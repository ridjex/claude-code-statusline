#!/usr/bin/env python3
"""Claude Code Status Line — Python engine.

Reads JSON session data from stdin, outputs formatted status bar.
Drop-in replacement for the bash engine with identical output.

Line 1: model | context bar | cost | duration | git branch | lines
Line 2: per-model tokens | speed | proj cumulative | all cumulative
"""
import sys
import json
import os
import subprocess
import math
import hashlib
import argparse
import re

# --- ANSI codes ---
DIM = "\033[2m"
RST = "\033[0m"
SEP = f"{DIM}|{RST}"  # will be replaced with │ in output
CYAN = "\033[36m"
GREEN = "\033[32m"
YELLOW = "\033[33m"
RED = "\033[31m"
MAGENTA = "\033[35m"


def parse_args():
    """Parse CLI arguments (same flags as bash engine)."""
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--no-model", action="store_true")
    parser.add_argument("--no-model-bars", action="store_true")
    parser.add_argument("--no-context", action="store_true")
    parser.add_argument("--no-cost", action="store_true")
    parser.add_argument("--no-duration", action="store_true")
    parser.add_argument("--no-git", action="store_true")
    parser.add_argument("--no-diff", action="store_true")
    parser.add_argument("--no-line2", action="store_true")
    parser.add_argument("--no-tokens", action="store_true")
    parser.add_argument("--no-speed", action="store_true")
    parser.add_argument("--no-cumulative", action="store_true")
    parser.add_argument("--no-color", action="store_true")
    parser.add_argument("--help", action="store_true")
    return parser.parse_args()


def print_help():
    """Print usage to stderr (same as bash engine)."""
    sys.stderr.write("""Usage: statusline.py [OPTIONS]
Reads JSON from stdin, outputs formatted status bar.

Options:
  --no-model       Hide model name
  --no-model-bars  Hide model mix bars
  --no-context     Hide context window bar
  --no-cost        Hide session cost
  --no-duration    Hide duration
  --no-git         Hide git branch/status
  --no-diff        Hide lines added/removed
  --no-line2       Hide entire second line
  --no-tokens      Hide token counts
  --no-speed       Hide throughput (tok/s)
  --no-cumulative  Hide cumulative costs
  --no-color       Disable ANSI colors
  --help           Show this help

Config precedence: CLI args > env vars > ~/.claude/statusline.env > defaults (all on)
""")
    sys.exit(0)


def load_config(args):
    """Load config from env file + env vars + CLI args. Returns dict of bools."""
    keys = [
        "STATUSLINE_SHOW_MODEL", "STATUSLINE_SHOW_MODEL_BARS",
        "STATUSLINE_SHOW_CONTEXT", "STATUSLINE_SHOW_COST",
        "STATUSLINE_SHOW_DURATION", "STATUSLINE_SHOW_GIT",
        "STATUSLINE_SHOW_DIFF", "STATUSLINE_LINE2",
        "STATUSLINE_SHOW_TOKENS", "STATUSLINE_SHOW_SPEED",
        "STATUSLINE_SHOW_CUMULATIVE",
    ]

    # Save env overrides before loading config file
    env_overrides = {}
    for k in keys:
        v = os.environ.get(k)
        if v is not None:
            env_overrides[k] = v

    # Load config file
    cfg_path = os.path.expanduser("~/.claude/statusline.env")
    file_vals = {}
    if os.path.isfile(cfg_path):
        with open(cfg_path) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if "=" in line:
                    k, v = line.split("=", 1)
                    file_vals[k.strip()] = v.strip()

    # Merge: file < env < CLI args
    cfg = {}
    for k in keys:
        val = file_vals.get(k, "true")
        if k in env_overrides:
            val = env_overrides[k]
        cfg[k] = val != "false"

    # CLI args override everything
    arg_map = {
        "--no-model": "STATUSLINE_SHOW_MODEL",
        "--no-model-bars": "STATUSLINE_SHOW_MODEL_BARS",
        "--no-context": "STATUSLINE_SHOW_CONTEXT",
        "--no-cost": "STATUSLINE_SHOW_COST",
        "--no-duration": "STATUSLINE_SHOW_DURATION",
        "--no-git": "STATUSLINE_SHOW_GIT",
        "--no-diff": "STATUSLINE_SHOW_DIFF",
        "--no-line2": "STATUSLINE_LINE2",
        "--no-tokens": "STATUSLINE_SHOW_TOKENS",
        "--no-speed": "STATUSLINE_SHOW_SPEED",
        "--no-cumulative": "STATUSLINE_SHOW_CUMULATIVE",
    }
    for flag, key in arg_map.items():
        attr = flag.lstrip("-").replace("-", "_")
        if getattr(args, attr, False):
            cfg[key] = False

    # NO_COLOR support
    no_color = (
        args.no_color
        or os.environ.get("NO_COLOR", "") != ""
        or os.environ.get("STATUSLINE_NO_COLOR", "") != ""
    )
    cfg["no_color"] = no_color
    return cfg


def show(cfg, key):
    return cfg.get(key, True)


# --- Formatting helpers ---

def fmt_k(n):
    """Format token count: 1234567→1.2M, 45231→45k, 1234→1.2k, 523→523."""
    n = int(n)
    if n >= 1000000:
        return f"{n / 1000000:.1f}M"
    elif n >= 10000:
        return f"{n / 1000:.0f}k"
    elif n >= 1000:
        return f"{n / 1000:.1f}k"
    else:
        return str(n)


def fmt_cost(c):
    """Format cost: >=1000→$12.0k, >=100→$374, >=10→$14, >=1→$8.4, <1→$0.12."""
    c = float(c)
    if c >= 1000:
        return f"${c / 1000:.1f}k"
    elif c >= 100:
        return f"${c:.0f}"
    elif c >= 10:
        return f"${c:.0f}"
    elif c >= 1:
        return f"${c:.1f}"
    else:
        return f"${c:.2f}"


# --- Git helpers ---

def git_cmd(*args):
    """Run a git command, return stdout or empty string on failure."""
    try:
        r = subprocess.run(
            ["git"] + list(args),
            capture_output=True, text=True, timeout=2,
        )
        return r.stdout.strip() if r.returncode == 0 else ""
    except Exception:
        return ""


def shorten_branch(name):
    """Shorten branch prefix to icon."""
    prefixes = {
        "feature/": "★", "feat/": "★", "fix/": "✦",
        "chore/": "⚙", "refactor/": "↻", "docs/": "§",
    }
    for prefix, icon in prefixes.items():
        if name.startswith(prefix):
            return icon + name[len(prefix):]
    return name


def trunc(name, max_len=20):
    """Truncate to max length with ellipsis."""
    if len(name) > max_len:
        return name[: max_len - 1] + "…"
    return name


# --- Bar chart helpers ---

BARS = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]


def bar_char(val, max_val):
    """Return a bar character proportional to val/max_val."""
    if val <= 0 or max_val <= 0:
        return ""
    level = (val * 8 + max_val // 2) // max_val
    level = max(1, min(8, level))
    return BARS[level - 1]


def strip_ansi(text):
    return re.sub(r"\033\[[0-9;]*m", "", text)


def main():
    args = parse_args()
    if args.help:
        print_help()

    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        data = {}

    cfg = load_config(args)

    # --- Session transcript (for per-model stats) ---
    transcript_path = data.get("transcript_path", "")
    session_id = ""
    if transcript_path:
        session_id = os.path.basename(transcript_path).replace(".jsonl", "")

    # --- Model ---
    model = ""
    if show(cfg, "STATUSLINE_SHOW_MODEL"):
        model = data.get("model", {}).get("display_name", "?")
        if model.startswith("Claude "):
            model = model[7:]

    # --- Context bar ---
    pct = 0
    bar = ""
    warn = ""
    clr = GREEN
    if show(cfg, "STATUSLINE_SHOW_CONTEXT"):
        pct = int(data.get("context_window", {}).get("used_percentage", 0))
        filled = min(pct // 10, 10)
        empty = 10 - filled
        bar = "▓" * filled + "░" * empty
        if pct >= 90:
            clr = RED
            warn = " ⚠"
        elif pct >= 70:
            clr = YELLOW
            warn = " ⚠"

    # --- Cost ---
    cost_fmt = ""
    if show(cfg, "STATUSLINE_SHOW_COST"):
        cost = float(data.get("cost", {}).get("total_cost_usd", 0))
        cost_fmt = fmt_cost(cost)

    # --- Duration ---
    dur_fmt = ""
    if show(cfg, "STATUSLINE_SHOW_DURATION"):
        dur_ms = int(float(data.get("cost", {}).get("total_duration_ms", 0)))
        dur_min = dur_ms // 60000
        if dur_min >= 60:
            dur_fmt = f"{dur_min // 60}h{dur_min % 60}m"
        else:
            dur_fmt = f"{dur_min}m"

    # --- Git ---
    branch = ""
    git_display = ""
    dirty = ""
    git_extra = ""
    if show(cfg, "STATUSLINE_SHOW_GIT"):
        branch = git_cmd("branch", "--show-current")

    if branch:
        # Worktree detection
        toplevel = git_cmd("rev-parse", "--show-toplevel")
        common = git_cmd("rev-parse", "--git-common-dir")
        in_wt = False
        wt_name = ""
        if toplevel and common:
            try:
                resolved_common = os.path.realpath(os.path.join(toplevel, common))
                if resolved_common != os.path.join(toplevel, ".git"):
                    in_wt = True
                    main_toplevel = os.path.dirname(resolved_common)
                    wt_prefix = main_toplevel + "/.worktrees/"
                    if toplevel.startswith(wt_prefix):
                        wt_name = toplevel[len(wt_prefix):]
                    else:
                        wt_name = toplevel
            except Exception:
                pass

        sb = trunc(shorten_branch(branch))
        if in_wt:
            sw = trunc(shorten_branch(wt_name))
            if sw == sb:
                git_display = f"⊕ {sb}"
            else:
                git_display = f"⊕{sw} {sb}"
        else:
            git_display = sb

        # Dirty indicator
        porcelain = git_cmd("status", "--porcelain")
        if porcelain:
            dirty = "●"

        # Ahead/behind/stash
        ahead = git_cmd("rev-list", "--count", "@{u}..HEAD") or "0"
        behind = git_cmd("rev-list", "--count", "HEAD..@{u}") or "0"
        stash_list = git_cmd("stash", "list")
        stash_count = len(stash_list.splitlines()) if stash_list else 0

        parts = []
        if int(ahead) > 0:
            parts.append(f"↑{ahead}")
        if int(behind) > 0:
            parts.append(f"↓{behind}")
        if stash_count > 0:
            parts.append(f"stash:{stash_count}")
        git_extra = " ".join(parts) if parts else ""

    # --- Lines added/removed ---
    lines_fmt = ""
    if show(cfg, "STATUSLINE_SHOW_DIFF"):
        added = int(data.get("cost", {}).get("total_lines_added", 0))
        removed = int(data.get("cost", {}).get("total_lines_removed", 0))
        if added > 0 or removed > 0:
            lines_fmt = f"{GREEN}+{added}{RST} {RED}-{removed}{RST}"

    # ============================================================
    # LINE 2 DATA
    # ============================================================
    in_tok = int(data.get("context_window", {}).get("total_input_tokens", 0))
    out_tok = int(data.get("context_window", {}).get("total_output_tokens", 0))
    in_fmt = fmt_k(in_tok)
    out_fmt = fmt_k(out_tok)

    # --- Speed ---
    speed_fmt = ""
    if show(cfg, "STATUSLINE_SHOW_SPEED"):
        api_ms = int(float(data.get("cost", {}).get("total_api_duration_ms", 0)))
        if api_ms > 0 and out_tok > 0:
            speed = out_tok * 1000 / api_ms
            speed_int = int(round(speed))
            if speed_int > 30:
                speed_clr = GREEN
            elif speed_int >= 15:
                speed_clr = YELLOW
            else:
                speed_clr = RED
            speed_fmt = f"{speed_clr}{speed_int} tok/s{RST}"

    # --- Cumulative stats ---
    cache_dir = os.path.join(
        os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")),
        "claude-code-statusline",
    )
    project_dir = data.get("workspace", {}).get("project_dir", "")
    cum_proj = ""
    cum_all = ""

    if show(cfg, "STATUSLINE_SHOW_CUMULATIVE") and project_dir:
        slug = project_dir.lstrip("/").replace("/", "-")
        proj_hash = hashlib.md5(
            (slug + "\n").encode()
        ).hexdigest()[:8]
        proj_cache = os.path.join(cache_dir, f"proj-{proj_hash}.json")

        if os.path.isfile(proj_cache):
            try:
                with open(proj_cache) as f:
                    pc = json.load(f)
                p1 = float(pc.get("d1", {}).get("cost", 0))
                p7 = float(pc.get("d7", {}).get("cost", 0))
                p30 = float(pc.get("d30", {}).get("cost", 0))
                if p1 > 0 or p7 > 0 or p30 > 0:
                    cum_proj = f"⌂ {fmt_cost(p1)}/{fmt_cost(p7)}/{fmt_cost(p30)}"
            except Exception:
                pass

    if show(cfg, "STATUSLINE_SHOW_CUMULATIVE"):
        all_cache = os.path.join(cache_dir, "all.json")
        if os.path.isfile(all_cache):
            try:
                with open(all_cache) as f:
                    ac = json.load(f)
                a1 = float(ac.get("d1", {}).get("cost", 0))
                a7 = float(ac.get("d7", {}).get("cost", 0))
                a30 = float(ac.get("d30", {}).get("cost", 0))
                if a1 > 0 or a7 > 0 or a30 > 0:
                    cum_all = f"Σ {fmt_cost(a1)}/{fmt_cost(a7)}/{fmt_cost(a30)}"
            except Exception:
                pass

    # --- Per-model stats ---
    opus_in = opus_out = 0
    sonnet_in = sonnet_out = 0
    haiku_in = haiku_out = 0
    model_mix = ""

    if session_id:
        model_cache = os.path.join(cache_dir, f"models-{session_id}.json")
        if os.path.isfile(model_cache):
            try:
                with open(model_cache) as f:
                    mc = json.load(f)
                for m in mc.get("models", []):
                    name = m.get("model", "")
                    if "opus" in name:
                        opus_in += int(m.get("in", 0))
                        opus_out += int(m.get("out", 0))
                    elif "sonnet" in name:
                        sonnet_in += int(m.get("in", 0))
                        sonnet_out += int(m.get("out", 0))
                    elif "haiku" in name:
                        haiku_in += int(m.get("in", 0))
                        haiku_out += int(m.get("out", 0))
            except Exception:
                pass

        max_out = max(opus_out, sonnet_out, haiku_out)
        if show(cfg, "STATUSLINE_SHOW_MODEL_BARS") and max_out > 0:
            o_bar = bar_char(opus_out, max_out)
            s_bar = bar_char(sonnet_out, max_out)
            h_bar = bar_char(haiku_out, max_out)
            o_c = f"\033[35m{o_bar}" if o_bar else "\033[2m·"
            s_c = f"\033[36m{s_bar}" if s_bar else "\033[2m·"
            h_c = f"\033[32m{h_bar}" if h_bar else "\033[2m·"
            model_mix = f"{o_c}{s_c}{h_c}{RST}"

    # --- Kick off background jobs ---
    self_dir = os.path.dirname(os.path.abspath(__file__))
    # Try engines/bash/ location first, then fall back to same-dir
    cum_script = os.path.join(self_dir, "..", "bash", "cumulative-stats.sh")
    if not os.path.isfile(cum_script):
        cum_script = os.path.join(
            os.path.expanduser("~/.claude"), "cumulative-stats.sh"
        )
    if project_dir and os.path.isfile(cum_script) and os.access(cum_script, os.X_OK):
        try:
            subprocess.Popen(
                [cum_script, project_dir],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
        except Exception:
            pass

    # Background: refresh model stats cache (same logic as bash)
    if session_id and transcript_path:
        _refresh_model_cache(session_id, transcript_path, cache_dir)

    # ============================================================
    # ASSEMBLE OUTPUT
    # ============================================================
    sep = f" {DIM}\u2502{RST} "

    # --- Line 1 ---
    l1_parts = []
    if model:
        part = f"{CYAN}{model}{RST}"
        if model_mix:
            part += f" {model_mix}"
        l1_parts.append(part)
    elif model_mix:
        l1_parts.append(model_mix)

    if bar:
        l1_parts.append(f"{clr}{bar} {pct}%{warn}{RST}")
    if cost_fmt:
        l1_parts.append(cost_fmt)
    if dur_fmt:
        l1_parts.append(dur_fmt)
    if git_display:
        git_part = f"{MAGENTA}{git_display}{RST}"
        if dirty:
            git_part += f" {YELLOW}{dirty}{RST}"
        if git_extra:
            git_part += f" {CYAN}{git_extra}{RST}"
        l1_parts.append(git_part)
    if lines_fmt:
        l1_parts.append(lines_fmt)

    l1 = sep.join(l1_parts)

    # --- Line 2 ---
    l2 = ""
    if show(cfg, "STATUSLINE_LINE2"):
        l2_parts = []

        if show(cfg, "STATUSLINE_SHOW_TOKENS"):
            tok_parts = []
            if opus_out > 0 or opus_in > 0:
                tok_parts.append(
                    f"\033[35mO{RST}:{fmt_k(opus_in)}/{fmt_k(opus_out)}"
                )
            if sonnet_out > 0 or sonnet_in > 0:
                tok_parts.append(
                    f"\033[36mS{RST}:{fmt_k(sonnet_in)}/{fmt_k(sonnet_out)}"
                )
            if haiku_out > 0 or haiku_in > 0:
                tok_parts.append(
                    f"\033[32mH{RST}:{fmt_k(haiku_in)}/{fmt_k(haiku_out)}"
                )
            if tok_parts:
                l2_parts.append(" ".join(tok_parts))
            else:
                l2_parts.append(f"{DIM}in:{RST}{in_fmt} {DIM}out:{RST}{out_fmt}")

        if speed_fmt:
            l2_parts.append(speed_fmt)
        if cum_proj:
            l2_parts.append(cum_proj)
        if cum_all:
            l2_parts.append(cum_all)

        l2 = sep.join(l2_parts)

    # --- Output ---
    no_color = cfg.get("no_color", False)
    if no_color:
        l1 = strip_ansi(l1)
        l2 = strip_ansi(l2)

    if l2:
        sys.stdout.write(l1 + "\n" + l2 + "\n")
    else:
        sys.stdout.write(l1 + "\n\n")


def _refresh_model_cache(session_id, transcript_path, cache_dir):
    """Spawn background model cache refresh (fire and forget)."""
    try:
        script = f"""
import json, os, sys, glob

transcript = {json.dumps(transcript_path)}
session_id = {json.dumps(session_id)}
cache_dir = {json.dumps(cache_dir)}

files = [transcript]
subagent_dir = os.path.join(os.path.dirname(transcript), session_id, "subagents")
if os.path.isdir(subagent_dir):
    files.extend(glob.glob(os.path.join(subagent_dir, "*.jsonl")))

models = {{}}
for fpath in files:
    if not os.path.isfile(fpath):
        continue
    with open(fpath) as f:
        for line in f:
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue
            if (entry.get("type") != "assistant" or
                "message" not in entry):
                continue
            msg = entry["message"]
            model_name = msg.get("model", "")
            usage = msg.get("usage")
            if not model_name or not usage or not model_name.startswith("claude-"):
                continue
            if model_name not in models:
                models[model_name] = {{"model": model_name, "in": 0, "out": 0}}
            models[model_name]["in"] += (
                usage.get("input_tokens", 0) +
                usage.get("cache_read_input_tokens", 0) +
                usage.get("cache_creation_input_tokens", 0)
            )
            models[model_name]["out"] += usage.get("output_tokens", 0)

os.makedirs(cache_dir, exist_ok=True)
cache_file = os.path.join(cache_dir, f"models-{{session_id}}.json")
tmp = cache_file + ".tmp"
with open(tmp, "w") as f:
    json.dump({{"models": list(models.values())}}, f)
os.rename(tmp, cache_file)
"""
        subprocess.Popen(
            [sys.executable, "-c", script],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except Exception:
        pass


if __name__ == "__main__":
    main()
