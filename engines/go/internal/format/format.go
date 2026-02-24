package format

import (
	"fmt"
	"strings"
)

// FmtK formats token counts: 1234567->"1.2M", 45231->"45k", 1234->"1.2k", 523->"523".
func FmtK(n int) string {
	if n >= 1000000 {
		return fmt.Sprintf("%.1fM", float64(n)/1000000)
	}
	if n >= 10000 {
		return fmt.Sprintf("%.0fk", float64(n)/1000)
	}
	if n >= 1000 {
		return fmt.Sprintf("%.1fk", float64(n)/1000)
	}
	return fmt.Sprintf("%d", n)
}

// FmtCost formats cost: >=1000->"$1.8k", >=100->"$374", >=10->"$14", >=1->"$8.4", <1->"$0.12".
func FmtCost(c float64) string {
	if c >= 1000 {
		return fmt.Sprintf("$%.1fk", c/1000)
	}
	if c >= 100 {
		return fmt.Sprintf("$%.0f", c)
	}
	if c >= 10 {
		return fmt.Sprintf("$%.0f", c)
	}
	if c >= 1 {
		return fmt.Sprintf("$%.1f", c)
	}
	return fmt.Sprintf("$%.2f", c)
}

// FmtDuration formats milliseconds: >=60min->"4h0m", <60min->"15m".
func FmtDuration(ms int) string {
	min := ms / 60000
	if min >= 60 {
		return fmt.Sprintf("%dh%dm", min/60, min%60)
	}
	return fmt.Sprintf("%dm", min)
}

var bars = []string{"\u2581", "\u2582", "\u2583", "\u2584", "\u2585", "\u2586", "\u2587", "\u2588"}

// BarChar returns a bar character proportional to val/max (8 levels).
func BarChar(val, max int) string {
	if val <= 0 || max <= 0 {
		return ""
	}
	level := (val*8 + max/2) / max
	if level < 1 {
		level = 1
	}
	if level > 8 {
		level = 8
	}
	return bars[level-1]
}

var branchPrefixes = []struct {
	prefix string
	icon   string
}{
	{"feature/", "\u2605"},
	{"feat/", "\u2605"},
	{"fix/", "\u2726"},
	{"chore/", "\u2699"},
	{"refactor/", "\u21bb"},
	{"docs/", "\u00a7"},
}

// ShortenBranch replaces known prefixes with icons.
func ShortenBranch(name string) string {
	for _, p := range branchPrefixes {
		if strings.HasPrefix(name, p.prefix) {
			return p.icon + name[len(p.prefix):]
		}
	}
	return name
}

// Truncate truncates to maxLen runes with ellipsis.
func Truncate(s string, maxLen int) string {
	runes := []rune(s)
	if len(runes) > maxLen {
		return string(runes[:maxLen-1]) + "\u2026"
	}
	return s
}
