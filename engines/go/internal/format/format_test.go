package format

import "testing"

func TestFmtK(t *testing.T) {
	tests := []struct {
		input int
		want  string
	}{
		{0, "0"},
		{1, "1"},
		{340, "340"},
		{999, "999"},
		{1000, "1.0k"},
		{1200, "1.2k"},
		{1250, "1.2k"}, // banker's rounding: 1.25 -> 1.2
		{9999, "10.0k"},
		{10000, "10k"},
		{45231, "45k"},
		{287500, "288k"}, // 287.5 rounds to 288 (even)
		{549000, "549k"},
		{999999, "1000k"},
		{1000000, "1.0M"},
		{1250000, "1.2M"}, // 1.25 -> 1.2 (banker's)
		{1500000, "1.5M"},
	}
	for _, tt := range tests {
		got := FmtK(tt.input)
		if got != tt.want {
			t.Errorf("FmtK(%d) = %q, want %q", tt.input, got, tt.want)
		}
	}
}

func TestFmtCost(t *testing.T) {
	tests := []struct {
		input float64
		want  string
	}{
		{0, "$0.00"},
		{0.03, "$0.03"},
		{0.125, "$0.12"}, // banker's: 0.125 -> 0.12
		{0.99, "$0.99"},
		{1.0, "$1.0"},
		{8.42, "$8.4"},
		{9.95, "$9.9"}, // IEEE 754: 9.95 stored as 9.9499..., stays in >=1 bucket
		{10.0, "$10"},
		{14.3, "$14"},
		{99.5, "$100"}, // rounds up to 100 -> $100
		{100.0, "$100"},
		{374.0, "$374"},
		{552.0, "$552"},
		{999.0, "$999"},
		{1000.0, "$1.0k"},
		{1842.50, "$1.8k"},
		{3964.0, "$4.0k"},
		{4690.0, "$4.7k"},
		{7144.0, "$7.1k"},
		{12025.0, "$12.0k"},
	}
	for _, tt := range tests {
		got := FmtCost(tt.input)
		if got != tt.want {
			t.Errorf("FmtCost(%g) = %q, want %q", tt.input, got, tt.want)
		}
	}
}

func TestFmtDuration(t *testing.T) {
	tests := []struct {
		ms   int
		want string
	}{
		{0, "0m"},
		{15000, "0m"},
		{59999, "0m"},
		{60000, "1m"},
		{900000, "15m"},
		{3540000, "59m"},
		{3600000, "1h0m"},
		{14400000, "4h0m"},
		{5580000, "1h33m"},
	}
	for _, tt := range tests {
		got := FmtDuration(tt.ms)
		if got != tt.want {
			t.Errorf("FmtDuration(%d) = %q, want %q", tt.ms, got, tt.want)
		}
	}
}

func TestBarChar(t *testing.T) {
	tests := []struct {
		val, max int
		want     string
	}{
		{0, 100, ""},
		{-1, 100, ""},
		{100, 0, ""},
		{100, 100, "\u2588"}, // full bar
		{1, 100, "\u2581"},   // lowest bar
		{50, 100, "\u2584"},  // mid bar
	}
	for _, tt := range tests {
		got := BarChar(tt.val, tt.max)
		if got != tt.want {
			t.Errorf("BarChar(%d, %d) = %q, want %q", tt.val, tt.max, got, tt.want)
		}
	}

	// Self-max always returns full bar
	if got := BarChar(42, 42); got != "\u2588" {
		t.Errorf("BarChar(42, 42) = %q, want full bar", got)
	}
}

func TestShortenBranch(t *testing.T) {
	tests := []struct {
		input, want string
	}{
		{"main", "main"},
		{"feature/auth", "\u2605auth"},
		{"feat/login", "\u2605login"},
		{"fix/typo", "\u2726typo"},
		{"chore/deps", "\u2699deps"},
		{"refactor/api", "\u21bbapi"},
		{"docs/readme", "\u00a7readme"},
		{"release/v1", "release/v1"},
	}
	for _, tt := range tests {
		got := ShortenBranch(tt.input)
		if got != tt.want {
			t.Errorf("ShortenBranch(%q) = %q, want %q", tt.input, got, tt.want)
		}
	}
}

func TestTruncate(t *testing.T) {
	tests := []struct {
		input  string
		maxLen int
		want   string
	}{
		{"short", 20, "short"},
		{"exactly-twenty-chars", 20, "exactly-twenty-chars"},
		{"this-is-a-very-long-branch-name", 20, "this-is-a-very-long\u2026"},
		{"ab", 2, "ab"},
		{"abc", 2, "a\u2026"},
	}
	for _, tt := range tests {
		got := Truncate(tt.input, tt.maxLen)
		if got != tt.want {
			t.Errorf("Truncate(%q, %d) = %q, want %q", tt.input, tt.maxLen, got, tt.want)
		}
	}
}
