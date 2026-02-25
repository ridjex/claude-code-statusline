/// Format token counts: 1234567->"1.2M", 45231->"45k", 1234->"1.2k", 523->"523".
pub fn fmt_k(n: i64) -> String {
    if n >= 1_000_000 {
        format!("{:.1}M", n as f64 / 1_000_000.0)
    } else if n >= 10_000 {
        format!("{:.0}k", n as f64 / 1_000.0)
    } else if n >= 1_000 {
        format!("{:.1}k", n as f64 / 1_000.0)
    } else {
        format!("{}", n)
    }
}

/// Format cost: >=1000->"$1.8k", >=100->"$374", >=10->"$14", >=1->"$8.4", <1->"$0.12".
pub fn fmt_cost(c: f64) -> String {
    if c >= 1000.0 {
        format!("${:.1}k", c / 1000.0)
    } else if c >= 10.0 {
        format!("${:.0}", c)
    } else if c >= 1.0 {
        format!("${:.1}", c)
    } else {
        format!("${:.2}", c)
    }
}

/// Format milliseconds: >=60min->"4h0m", <60min->"15m".
pub fn fmt_duration(ms: i64) -> String {
    let min = ms / 60_000;
    if min >= 60 {
        format!("{}h{}m", min / 60, min % 60)
    } else {
        format!("{}m", min)
    }
}

const BARS: [&str; 8] = [
    "\u{2581}", "\u{2582}", "\u{2583}", "\u{2584}", "\u{2585}", "\u{2586}", "\u{2587}", "\u{2588}",
];

/// Return a bar character proportional to val/max (8 levels).
pub fn bar_char(val: i64, max: i64) -> &'static str {
    if val <= 0 || max <= 0 {
        return "";
    }
    let level = ((val * 8 + max / 2) / max).clamp(1, 8);
    BARS[(level - 1) as usize]
}

const BRANCH_PREFIXES: &[(&str, &str)] = &[
    ("feature/", "\u{2605}"),
    ("feat/", "\u{2605}"),
    ("fix/", "\u{2726}"),
    ("chore/", "\u{2699}"),
    ("refactor/", "\u{21bb}"),
    ("docs/", "\u{00a7}"),
];

/// Replace known branch prefixes with icons.
pub fn shorten_branch(name: &str) -> String {
    for &(prefix, icon) in BRANCH_PREFIXES {
        if let Some(rest) = name.strip_prefix(prefix) {
            return format!("{}{}", icon, rest);
        }
    }
    name.to_string()
}

/// Truncate to max_len runes with ellipsis.
pub fn truncate(s: &str, max_len: usize) -> String {
    let chars: Vec<char> = s.chars().collect();
    if chars.len() > max_len {
        let mut result: String = chars[..max_len - 1].iter().collect();
        result.push('\u{2026}');
        result
    } else {
        s.to_string()
    }
}

/// Round to even (banker's rounding), matching Go's math.RoundToEven.
pub fn round_to_even(x: f64) -> i64 {
    let rounded = x.round();
    // Check if we're exactly at .5
    if (x - x.floor() - 0.5).abs() < f64::EPSILON {
        // Round to even
        let r = rounded as i64;
        if r % 2 != 0 {
            return r - 1;
        }
    }
    rounded as i64
}
