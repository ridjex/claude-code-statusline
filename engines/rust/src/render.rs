use crate::cache;
use crate::config::Config;
use crate::format;
use crate::session::Session;
use std::path::Path;

const DIM: &str = "\x1b[2m";
const RST: &str = "\x1b[0m";
const CYAN: &str = "\x1b[36m";
const GREEN: &str = "\x1b[32m";
const YELLOW: &str = "\x1b[33m";
const RED: &str = "\x1b[31m";
const MAGENTA: &str = "\x1b[35m";

pub fn render(sess: &Session, cfg: &Config) -> String {
    let sep = format!(" {}\u{2502}{} ", DIM, RST);

    // Session ID from transcript path
    let session_id = if !sess.transcript_path.is_empty() {
        let base = Path::new(&sess.transcript_path)
            .file_name()
            .map(|f| f.to_string_lossy().to_string())
            .unwrap_or_default();
        base.strip_suffix(".jsonl").unwrap_or(&base).to_string()
    } else {
        String::new()
    };

    // --- Model ---
    let model = if cfg.show_model {
        let m = if sess.model.display_name.is_empty() {
            "?".to_string()
        } else {
            sess.model.display_name.clone()
        };
        m.strip_prefix("Claude ").unwrap_or(&m).to_string()
    } else {
        String::new()
    };

    // --- Context bar ---
    let mut pct = 0i32;
    let mut bar = String::new();
    let mut warn = "";
    let mut clr = GREEN;
    if cfg.show_context {
        pct = sess.context_window.used_percentage as i32;
        let filled = (pct / 10).clamp(0, 10) as usize;
        let empty = 10 - filled;
        bar = "\u{2593}".repeat(filled) + &"\u{2591}".repeat(empty);
        if pct >= 90 {
            clr = RED;
            warn = " \u{26a0}";
        } else if pct >= 70 {
            clr = YELLOW;
            warn = " \u{26a0}";
        }
    }

    // --- Cost ---
    let cost_fmt = if cfg.show_cost {
        format::fmt_cost(sess.cost.total_cost_usd)
    } else {
        String::new()
    };

    // --- Duration ---
    let dur_fmt = if cfg.show_duration {
        format::fmt_duration(sess.cost.total_duration_ms as i64)
    } else {
        String::new()
    };

    // --- Git ---
    let mut git_display = String::new();
    let mut dirty = "";
    let mut git_extra = String::new();
    if cfg.show_git {
        if let Ok(cwd) = std::env::current_dir() {
            if let Some(gs) = crate::git::get(&cwd.to_string_lossy()) {
                if !gs.branch.is_empty() {
                    let sb = format::truncate(&format::shorten_branch(&gs.branch), 20);
                    if gs.in_worktree {
                        let sw = format::truncate(&format::shorten_branch(&gs.worktree_name), 20);
                        if sw == sb {
                            git_display = format!("\u{2295} {}", sb);
                        } else {
                            git_display = format!("\u{2295}{} {}", sw, sb);
                        }
                    } else {
                        git_display = sb;
                    }
                    if gs.dirty {
                        dirty = "\u{25cf}";
                    }
                    let mut parts = Vec::new();
                    if gs.ahead > 0 {
                        parts.push(format!("\u{2191}{}", gs.ahead));
                    }
                    if gs.behind > 0 {
                        parts.push(format!("\u{2193}{}", gs.behind));
                    }
                    if gs.stash > 0 {
                        parts.push(format!("stash:{}", gs.stash));
                    }
                    git_extra = parts.join(" ");
                }
            }
        }
    }

    // --- Lines added/removed ---
    let lines_fmt = if cfg.show_diff {
        let added = sess.cost.total_lines_added as i64;
        let removed = sess.cost.total_lines_removed as i64;
        if added > 0 || removed > 0 {
            format!("{}+{}{} {}-{}{}", GREEN, added, RST, RED, removed, RST)
        } else {
            String::new()
        }
    } else {
        String::new()
    };

    // --- Token data ---
    let in_tok = sess.context_window.total_input_tokens as i64;
    let out_tok = sess.context_window.total_output_tokens as i64;
    let in_fmt = format::fmt_k(in_tok);
    let out_fmt = format::fmt_k(out_tok);

    // --- Per-model stats ---
    let model_stats = if !session_id.is_empty() {
        cache::read_models(&session_id)
    } else {
        None
    };

    let model_mix = if let Some(ref ms) = model_stats {
        let max_out = ms.opus_out.max(ms.sonnet_out).max(ms.haiku_out);
        if cfg.show_model_bars && max_out > 0 {
            let o_bar = format::bar_char(ms.opus_out, max_out);
            let s_bar = format::bar_char(ms.sonnet_out, max_out);
            let h_bar = format::bar_char(ms.haiku_out, max_out);
            let o_c = if o_bar.is_empty() {
                format!("{}\u{00b7}", DIM)
            } else {
                format!("{}{}", MAGENTA, o_bar)
            };
            let s_c = if s_bar.is_empty() {
                format!("{}\u{00b7}", DIM)
            } else {
                format!("{}{}", CYAN, s_bar)
            };
            let h_c = if h_bar.is_empty() {
                format!("{}\u{00b7}", DIM)
            } else {
                format!("{}{}", GREEN, h_bar)
            };
            format!("{}{}{}{}", o_c, s_c, h_c, RST)
        } else {
            String::new()
        }
    } else {
        String::new()
    };

    // --- Speed ---
    let speed_fmt = if cfg.show_speed {
        let api_ms = sess.cost.total_api_duration_ms as i64;
        if api_ms > 0 && out_tok > 0 {
            let speed = out_tok as f64 * 1000.0 / api_ms as f64;
            let speed_int = format::round_to_even(speed);
            let speed_clr = if speed_int > 30 {
                GREEN
            } else if speed_int >= 15 {
                YELLOW
            } else {
                RED
            };
            format!("{}{} tok/s{}", speed_clr, speed_int, RST)
        } else {
            String::new()
        }
    } else {
        String::new()
    };

    // --- Cumulative stats ---
    let mut cum_proj = String::new();
    let mut cum_all = String::new();
    if cfg.show_cumulative {
        let (proj_stats, all_stats) = cache::read_cumulative(&sess.workspace.project_dir);
        if let Some(ps) = proj_stats {
            cum_proj = format!(
                "\u{2302} {}/{}/{}",
                format::fmt_cost(ps.d1),
                format::fmt_cost(ps.d7),
                format::fmt_cost(ps.d30)
            );
        }
        if let Some(als) = all_stats {
            cum_all = format!(
                "\u{03a3} {}/{}/{}",
                format::fmt_cost(als.d1),
                format::fmt_cost(als.d7),
                format::fmt_cost(als.d30)
            );
        }
    }

    // ======== ASSEMBLE LINE 1 ========
    let mut l1_parts: Vec<String> = Vec::new();

    if !model.is_empty() {
        let mut part = format!("{}{}{}", CYAN, model, RST);
        if !model_mix.is_empty() {
            part = format!("{} {}", part, model_mix);
        }
        l1_parts.push(part);
    } else if !model_mix.is_empty() {
        l1_parts.push(model_mix.clone());
    }

    if !bar.is_empty() {
        l1_parts.push(format!("{}{} {}%{}{}", clr, bar, pct, warn, RST));
    }
    if !cost_fmt.is_empty() {
        l1_parts.push(cost_fmt);
    }
    if !dur_fmt.is_empty() {
        l1_parts.push(dur_fmt);
    }
    if !git_display.is_empty() {
        let mut git_part = format!("{}{}{}", MAGENTA, git_display, RST);
        if !dirty.is_empty() {
            git_part = format!("{} {}{}{}", git_part, YELLOW, dirty, RST);
        }
        if !git_extra.is_empty() {
            git_part = format!("{} {}{}{}", git_part, CYAN, git_extra, RST);
        }
        l1_parts.push(git_part);
    }
    if !lines_fmt.is_empty() {
        l1_parts.push(lines_fmt);
    }

    let l1 = l1_parts.join(&sep);

    // ======== ASSEMBLE LINE 2 ========
    let l2 = if cfg.line2 {
        let mut l2_parts: Vec<String> = Vec::new();

        if cfg.show_tokens {
            let mut tok_parts: Vec<String> = Vec::new();
            if let Some(ref ms) = model_stats {
                if ms.opus_out > 0 || ms.opus_in > 0 {
                    tok_parts.push(format!(
                        "{}O{}:{}/{}",
                        MAGENTA,
                        RST,
                        format::fmt_k(ms.opus_in),
                        format::fmt_k(ms.opus_out)
                    ));
                }
                if ms.sonnet_out > 0 || ms.sonnet_in > 0 {
                    tok_parts.push(format!(
                        "{}S{}:{}/{}",
                        CYAN,
                        RST,
                        format::fmt_k(ms.sonnet_in),
                        format::fmt_k(ms.sonnet_out)
                    ));
                }
                if ms.haiku_out > 0 || ms.haiku_in > 0 {
                    tok_parts.push(format!(
                        "{}H{}:{}/{}",
                        GREEN,
                        RST,
                        format::fmt_k(ms.haiku_in),
                        format::fmt_k(ms.haiku_out)
                    ));
                }
            }
            if !tok_parts.is_empty() {
                l2_parts.push(tok_parts.join(" "));
            } else {
                l2_parts.push(format!(
                    "{}in:{}{} {}out:{}{}",
                    DIM, RST, in_fmt, DIM, RST, out_fmt
                ));
            }
        }

        if !speed_fmt.is_empty() {
            l2_parts.push(speed_fmt);
        }
        if !cum_proj.is_empty() {
            l2_parts.push(cum_proj);
        }
        if !cum_all.is_empty() {
            l2_parts.push(cum_all);
        }

        l2_parts.join(&sep)
    } else {
        String::new()
    };

    // --- NO_COLOR ---
    let (l1, l2) = if cfg.no_color {
        (strip_ansi(&l1), strip_ansi(&l2))
    } else {
        (l1, l2)
    };

    if !l2.is_empty() {
        format!("{}\n{}\n", l1, l2)
    } else {
        format!("{}\n\n", l1)
    }
}

/// Strip ANSI escape sequences manually (no regex dep).
fn strip_ansi(s: &str) -> String {
    let bytes = s.as_bytes();
    let mut result = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == 0x1b && i + 1 < bytes.len() && bytes[i + 1] == b'[' {
            // Skip until 'm'
            i += 2;
            while i < bytes.len() && bytes[i] != b'm' {
                i += 1;
            }
            if i < bytes.len() {
                i += 1; // skip 'm'
            }
        } else {
            result.push(bytes[i]);
            i += 1;
        }
    }
    String::from_utf8(result).unwrap_or_default()
}
