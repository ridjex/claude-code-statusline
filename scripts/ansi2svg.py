#!/usr/bin/env python3
"""Convert ANSI-colored terminal output to SVG with terminal chrome."""
import re
import sys
from html import escape

# ANSI code → CSS class mapping
ANSI_MAP = {
    "0": "default",   # reset
    "2": "dim",        # dim/faint
    "31": "red",
    "32": "green",
    "33": "yellow",
    "35": "magenta",
    "36": "cyan",
}

# Theme definitions (Catppuccin Mocha / Latte)
THEMES = {
    "dark": {
        "bg": "#1e1e2e",
        "border": "#313244",
        "default": "#cdd6f4",
        "dim": "#6c7086",
        "cyan": "#89dceb",
        "magenta": "#cba6f7",
        "green": "#a6e3a1",
        "yellow": "#f9e2af",
        "red": "#f38ba8",
        "dot_red": "#f38ba8",
        "dot_yellow": "#f9e2af",
        "dot_green": "#a6e3a1",
        "prompt": "#6c7086",
        "label_bg": "#313244",
        "separator": "#45475a",
    },
    "light": {
        "bg": "#eff1f5",
        "border": "#ccd0da",
        "default": "#4c4f69",
        "dim": "#9ca0b0",
        "cyan": "#179299",
        "magenta": "#8839ef",
        "green": "#40a02b",
        "yellow": "#df8e1d",
        "red": "#d20f39",
        "dot_red": "#d20f39",
        "dot_yellow": "#df8e1d",
        "dot_green": "#40a02b",
        "prompt": "#9ca0b0",
        "label_bg": "#dce0e8",
        "separator": "#ccd0da",
    },
}

FONT = "'JetBrains Mono', 'Fira Code', 'SF Mono', Menlo, Consolas, monospace"
FONT_SIZE = 13
LINE_HEIGHT = 20
PADDING_X = 20
PADDING_TOP = 40  # space for title bar
CHAR_WIDTH = 7.8  # approximate monospace char width at 13px


def parse_ansi(text: str) -> list[tuple[str, str]]:
    """Parse ANSI text into [(css_class, text), ...] segments."""
    segments = []
    current_class = "default"
    pos = 0
    ansi_re = re.compile(r"\033\[([0-9;]*)m")

    for match in ansi_re.finditer(text):
        # Text before this escape
        before = text[pos : match.start()]
        if before:
            segments.append((current_class, before))

        # Parse the ANSI code
        codes = match.group(1).split(";")
        for code in codes:
            code = code.strip()
            if code in ANSI_MAP:
                current_class = ANSI_MAP[code]
            elif code == "0" or code == "":
                current_class = "default"

        pos = match.end()

    # Remaining text
    remaining = text[pos:]
    if remaining:
        segments.append((current_class, remaining))

    return segments


def segments_to_tspans(segments: list[tuple[str, str]]) -> str:
    """Convert parsed segments to SVG tspan elements."""
    parts = []
    for cls, text in segments:
        escaped = escape(text)
        parts.append(f'<tspan class="{cls}">{escaped}</tspan>')
    return "".join(parts)


def render_svg(scenes: list[tuple[str, str]], theme_name: str) -> str:
    """Render scenes into a complete SVG string."""
    theme = THEMES[theme_name]

    # Calculate dimensions
    content_lines = []
    for label, output in scenes:
        content_lines.append(("label", label))
        for line in output.strip().split("\n"):
            content_lines.append(("text", line))
        content_lines.append(("gap", ""))

    # Terminal prompt line + gap before scenes
    total_lines = 2 + len(content_lines)
    height = PADDING_TOP + total_lines * LINE_HEIGHT + 16
    width = 860

    svg_parts = []

    # Header
    svg_parts.append(
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
        f'viewBox="0 0 {width} {height}">'
    )

    # Styles
    svg_parts.append(f"""  <style>
    text, tspan {{ font-family: {FONT}; font-size: {FONT_SIZE}px; }}
    .default {{ fill: {theme["default"]}; }}
    .dim {{ fill: {theme["dim"]}; }}
    .cyan {{ fill: {theme["cyan"]}; }}
    .magenta {{ fill: {theme["magenta"]}; }}
    .green {{ fill: {theme["green"]}; }}
    .yellow {{ fill: {theme["yellow"]}; }}
    .red {{ fill: {theme["red"]}; }}
  </style>""")

    # Background
    svg_parts.append(
        f'  <rect fill="{theme["bg"]}" width="{width}" height="{height}" rx="10"/>'
    )
    svg_parts.append(
        f'  <rect fill="none" stroke="{theme["border"]}" stroke-width="1" '
        f'x="0.5" y="0.5" width="{width-1}" height="{height-1}" rx="10"/>'
    )

    # Title bar dots
    svg_parts.append(f'  <circle cx="20" cy="18" r="6" fill="{theme["dot_red"]}"/>')
    svg_parts.append(
        f'  <circle cx="38" cy="18" r="6" fill="{theme["dot_yellow"]}"/>'
    )
    svg_parts.append(f'  <circle cx="56" cy="18" r="6" fill="{theme["dot_green"]}"/>')

    # Title
    svg_parts.append(
        f'  <text x="{width // 2}" y="22" text-anchor="middle" '
        f'font-size="11" fill="{theme["dim"]}">claude — ~/projects/my-app</text>'
    )

    # Content
    y = PADDING_TOP + LINE_HEIGHT

    # Prompt line
    svg_parts.append(
        f'  <text x="{PADDING_X}" y="{y}">'
        f'<tspan fill="{theme["prompt"]}">❯ Implement the auth feature...</tspan>'
        f"</text>"
    )
    y += LINE_HEIGHT + 4

    for kind, content in content_lines:
        if kind == "label":
            # Separator line with label
            y += 6
            label_width = round(len(content) * CHAR_WIDTH + 16)
            svg_parts.append(
                f'  <line x1="{PADDING_X}" y1="{y - 4}" '
                f'x2="{width - PADDING_X}" y2="{y - 4}" '
                f'stroke="{theme["separator"]}" stroke-width="1"/>'
            )
            svg_parts.append(
                f'  <rect x="{PADDING_X + 8}" y="{y - 14}" '
                f'width="{label_width}" height="18" rx="4" '
                f'fill="{theme["label_bg"]}"/>'
            )
            svg_parts.append(
                f'  <text x="{PADDING_X + 16}" y="{y}" '
                f'font-size="11" fill="{theme["dim"]}">{escape(content)}</text>'
            )
            y += LINE_HEIGHT
        elif kind == "text":
            segments = parse_ansi(content)
            tspans = segments_to_tspans(segments)
            svg_parts.append(f'  <text x="{PADDING_X}" y="{y}">{tspans}</text>')
            y += LINE_HEIGHT
        elif kind == "gap":
            y += 4

    svg_parts.append("</svg>")
    return "\n".join(svg_parts)


def main():
    args = sys.argv[1:]
    scenes = []
    dark_path = None
    light_path = None

    i = 0
    while i < len(args):
        if args[i] == "--scene":
            label = args[i + 1]
            output = args[i + 2]
            scenes.append((label, output))
            i += 3
        elif args[i] == "--dark":
            dark_path = args[i + 1]
            i += 2
        elif args[i] == "--light":
            light_path = args[i + 1]
            i += 2
        else:
            i += 1

    if not scenes:
        print("Usage: ansi2svg.py --scene LABEL OUTPUT [--scene ...] --dark FILE --light FILE", file=sys.stderr)
        sys.exit(1)

    if dark_path:
        svg = render_svg(scenes, "dark")
        with open(dark_path, "w") as f:
            f.write(svg)

    if light_path:
        svg = render_svg(scenes, "light")
        with open(light_path, "w") as f:
            f.write(svg)


if __name__ == "__main__":
    main()
