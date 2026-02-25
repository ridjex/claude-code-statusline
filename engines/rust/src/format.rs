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
    if max_len == 0 {
        return String::new();
    }
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

#[cfg(test)]
mod tests {
    use super::*;

    // --- fmt_k ---
    #[test]
    fn fmt_k_zero() {
        assert_eq!(fmt_k(0), "0");
    }
    #[test]
    fn fmt_k_small() {
        assert_eq!(fmt_k(523), "523");
        assert_eq!(fmt_k(999), "999");
    }
    #[test]
    fn fmt_k_thousands() {
        assert_eq!(fmt_k(1000), "1.0k");
        assert_eq!(fmt_k(1234), "1.2k");
        assert_eq!(fmt_k(9999), "10.0k");
    }
    #[test]
    fn fmt_k_ten_thousands() {
        assert_eq!(fmt_k(10000), "10k");
        assert_eq!(fmt_k(45231), "45k");
        assert_eq!(fmt_k(999999), "1000k");
    }
    #[test]
    fn fmt_k_millions() {
        assert_eq!(fmt_k(1000000), "1.0M");
        assert_eq!(fmt_k(1234567), "1.2M");
        assert_eq!(fmt_k(15_000_000), "15.0M");
    }
    #[test]
    fn fmt_k_negative() {
        assert_eq!(fmt_k(-100), "-100");
    }

    // --- fmt_cost ---
    #[test]
    fn fmt_cost_zero() {
        assert_eq!(fmt_cost(0.0), "$0.00");
    }
    #[test]
    fn fmt_cost_cents() {
        assert_eq!(fmt_cost(0.12), "$0.12");
        assert_eq!(fmt_cost(0.99), "$0.99");
    }
    #[test]
    fn fmt_cost_dollars() {
        assert_eq!(fmt_cost(1.0), "$1.0");
        assert_eq!(fmt_cost(8.42), "$8.4");
        assert_eq!(fmt_cost(9.99), "$10.0");
    }
    #[test]
    fn fmt_cost_tens() {
        assert_eq!(fmt_cost(10.0), "$10");
        assert_eq!(fmt_cost(14.3), "$14");
        assert_eq!(fmt_cost(374.0), "$374");
    }
    #[test]
    fn fmt_cost_thousands() {
        assert_eq!(fmt_cost(1000.0), "$1.0k");
        assert_eq!(fmt_cost(1800.0), "$1.8k");
    }

    // --- fmt_duration ---
    #[test]
    fn fmt_duration_zero() {
        assert_eq!(fmt_duration(0), "0m");
    }
    #[test]
    fn fmt_duration_minutes() {
        assert_eq!(fmt_duration(60_000), "1m");
        assert_eq!(fmt_duration(900_000), "15m");
        assert_eq!(fmt_duration(3_540_000), "59m");
    }
    #[test]
    fn fmt_duration_hours() {
        assert_eq!(fmt_duration(3_600_000), "1h0m");
        assert_eq!(fmt_duration(14_400_000), "4h0m");
        assert_eq!(fmt_duration(5_400_000), "1h30m");
    }

    // --- bar_char ---
    #[test]
    fn bar_char_zero() {
        assert_eq!(bar_char(0, 100), "");
    }
    #[test]
    fn bar_char_negative() {
        assert_eq!(bar_char(-1, 100), "");
        assert_eq!(bar_char(50, -1), "");
    }
    #[test]
    fn bar_char_full() {
        assert_eq!(bar_char(100, 100), "\u{2588}");
    }
    #[test]
    fn bar_char_half() {
        assert_eq!(bar_char(50, 100), "\u{2584}");
    }
    #[test]
    fn bar_char_min() {
        assert_eq!(bar_char(1, 100), "\u{2581}");
    }
    #[test]
    fn bar_char_over_max() {
        // val > max should clamp to full bar
        assert_eq!(bar_char(200, 100), "\u{2588}");
    }

    // --- shorten_branch ---
    #[test]
    fn shorten_branch_feature() {
        assert_eq!(shorten_branch("feature/login"), "\u{2605}login");
        assert_eq!(shorten_branch("feat/auth"), "\u{2605}auth");
    }
    #[test]
    fn shorten_branch_fix() {
        assert_eq!(shorten_branch("fix/crash"), "\u{2726}crash");
    }
    #[test]
    fn shorten_branch_no_prefix() {
        assert_eq!(shorten_branch("main"), "main");
        assert_eq!(shorten_branch("develop"), "develop");
    }
    #[test]
    fn shorten_branch_empty() {
        assert_eq!(shorten_branch(""), "");
    }

    // --- truncate ---
    #[test]
    fn truncate_short_string() {
        assert_eq!(truncate("hello", 10), "hello");
    }
    #[test]
    fn truncate_exact_length() {
        assert_eq!(truncate("hello", 5), "hello");
    }
    #[test]
    fn truncate_long_string() {
        assert_eq!(truncate("hello world", 5), "hell\u{2026}");
    }
    #[test]
    fn truncate_zero_max() {
        assert_eq!(truncate("hello", 0), "");
        assert_eq!(truncate("", 0), "");
    }
    #[test]
    fn truncate_one_max() {
        assert_eq!(truncate("hello", 1), "\u{2026}");
    }
    #[test]
    fn truncate_empty_string() {
        assert_eq!(truncate("", 5), "");
    }
    #[test]
    fn truncate_unicode() {
        // Unicode chars should be counted by char, not byte
        assert_eq!(truncate("日本語テスト", 4), "日本語\u{2026}");
    }

    // --- round_to_even ---
    #[test]
    fn round_to_even_basic() {
        assert_eq!(round_to_even(1.3), 1);
        assert_eq!(round_to_even(1.7), 2);
        assert_eq!(round_to_even(2.0), 2);
    }
    #[test]
    fn round_to_even_half_to_even() {
        assert_eq!(round_to_even(0.5), 0);
        assert_eq!(round_to_even(1.5), 2);
        assert_eq!(round_to_even(2.5), 2);
        assert_eq!(round_to_even(3.5), 4);
    }
    #[test]
    fn round_to_even_negative() {
        assert_eq!(round_to_even(-0.5), 0);
        assert_eq!(round_to_even(-1.5), -2);
    }
}
