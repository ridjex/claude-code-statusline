package render

import (
	"crypto/md5"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"

	"statusline/internal/config"
	"statusline/internal/session"
)

var stripRe = regexp.MustCompile(`\033\[[0-9;]*m`)

func strip(s string) string { return stripRe.ReplaceAllString(s, "") }

func basicSession() session.Session {
	return session.Session{
		Model:         session.Model{DisplayName: "Claude Opus 4.6"},
		ContextWindow: session.ContextWindow{UsedPercentage: 38, TotalInputTokens: 287500, TotalOutputTokens: 41200},
		Cost:          session.Cost{TotalCostUSD: 8.42, TotalDurationMs: 900000, TotalAPIDurationMs: 600000, TotalLinesAdded: 127, TotalLinesRemoved: 34},
		Workspace:     session.Workspace{ProjectDir: "/tmp/statusline-test-project"},
	}
}

func defaultCfg() config.Config {
	return config.Config{
		ShowModel: true, ShowModelBars: true, ShowContext: true,
		ShowCost: true, ShowDuration: true, ShowGit: false,
		ShowDiff: true, Line2: true, ShowTokens: true,
		ShowSpeed: true, ShowCumulative: true,
	}
}

// projectHash duplicates cache.ProjectHash to avoid import cycles.
func projectHash(dir string) string {
	slug := strings.TrimPrefix(dir, "/")
	slug = strings.ReplaceAll(slug, "/", "-")
	h := md5.Sum([]byte(slug + "\n"))
	return fmt.Sprintf("%x", h)[:8]
}

func TestRenderBasic(t *testing.T) {
	out := Render(basicSession(), defaultCfg())
	clean := strip(out)
	lines := strings.Split(strings.TrimRight(out, "\n"), "\n")

	if len(lines) != 2 {
		t.Errorf("expected 2 lines, got %d", len(lines))
	}

	checks := map[string]string{
		"model":   "Opus 4.6",
		"context": "38%",
		"cost":    "$8.4",
		"dur":     "15m",
		"added":   "+127",
		"removed": "-34",
		"in tok":  "288k",
		"out tok": "41k",
		"speed":   "tok/s",
	}
	for label, want := range checks {
		if !strings.Contains(clean, want) {
			t.Errorf("%s: output missing %q\ngot: %s", label, want, clean)
		}
	}
}

func TestRenderContextWarnings(t *testing.T) {
	cfg := defaultCfg()

	s := basicSession()
	s.ContextWindow.UsedPercentage = 78
	out := strip(Render(s, cfg))
	if !strings.Contains(out, "\u26a0") {
		t.Error("78% should show warning")
	}

	s.ContextWindow.UsedPercentage = 92
	out = strip(Render(s, cfg))
	if !strings.Contains(out, "\u26a0") {
		t.Error("92% should show warning")
	}

	s.ContextWindow.UsedPercentage = 38
	out = strip(Render(s, cfg))
	if strings.Contains(out, "\u26a0") {
		t.Error("38% should NOT show warning")
	}
}

func TestRenderCostFormatting(t *testing.T) {
	cfg := defaultCfg()
	s := basicSession()

	s.Cost.TotalCostUSD = 0.03
	out := strip(Render(s, cfg))
	if !strings.Contains(out, "$0.03") {
		t.Errorf("cheap cost: missing $0.03 in %q", out)
	}

	s.Cost.TotalCostUSD = 1842.50
	out = strip(Render(s, cfg))
	if !strings.Contains(out, "$1.8k") {
		t.Errorf("expensive cost: missing $1.8k in %q", out)
	}
}

func TestRenderTokenFormatting(t *testing.T) {
	cfg := defaultCfg()
	s := basicSession()

	s.ContextWindow.TotalInputTokens = 1200
	s.ContextWindow.TotalOutputTokens = 340
	out := strip(Render(s, cfg))
	if !strings.Contains(out, "1.2k") {
		t.Errorf("missing 1.2k in %q", out)
	}
	if !strings.Contains(out, "340") {
		t.Errorf("missing 340 in %q", out)
	}

	s.ContextWindow.TotalInputTokens = 1250000
	out = strip(Render(s, cfg))
	if !strings.Contains(out, "1.2M") {
		t.Errorf("missing 1.2M in %q", out)
	}
}

func TestRenderDuration(t *testing.T) {
	cfg := defaultCfg()
	s := basicSession()

	s.Cost.TotalDurationMs = 14400000
	out := strip(Render(s, cfg))
	if !strings.Contains(out, "4h0m") {
		t.Errorf("missing 4h0m in %q", out)
	}

	s.Cost.TotalDurationMs = 15000
	out = strip(Render(s, cfg))
	if !strings.Contains(out, "0m") {
		t.Errorf("missing 0m in %q", out)
	}
}

func TestRenderNoColor(t *testing.T) {
	cfg := defaultCfg()
	cfg.NoColor = true
	out := Render(basicSession(), cfg)

	if regexp.MustCompile(`\033\[`).MatchString(out) {
		t.Error("NO_COLOR output contains ANSI codes")
	}
	if !strings.Contains(out, "Opus 4.6") {
		t.Error("NO_COLOR should still have model name")
	}
	if !strings.Contains(out, "38%") {
		t.Error("NO_COLOR should still have context")
	}
}

func TestRenderSectionToggles(t *testing.T) {
	tests := []struct {
		name   string
		modify func(*config.Config)
		absent string
	}{
		{"no cost", func(c *config.Config) { c.ShowCost = false }, "$8.4"},
		{"no duration", func(c *config.Config) { c.ShowDuration = false }, "15m"},
		{"no context", func(c *config.Config) { c.ShowContext = false }, "38%"},
		{"no diff", func(c *config.Config) { c.ShowDiff = false }, "+127"},
		{"no speed", func(c *config.Config) { c.ShowSpeed = false }, "tok/s"},
		{"no line2", func(c *config.Config) { c.Line2 = false }, "tok/s"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			cfg := defaultCfg()
			tt.modify(&cfg)
			out := strip(Render(basicSession(), cfg))
			if strings.Contains(out, tt.absent) {
				t.Errorf("output should not contain %q when %s", tt.absent, tt.name)
			}
		})
	}
}

func TestRenderCumulative(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("XDG_CACHE_HOME", dir)
	cacheDir := filepath.Join(dir, "claude-code-statusline")
	_ = os.MkdirAll(cacheDir, 0o755)

	projData := `{"d1":{"cost":374},"d7":{"cost":3964},"d30":{"cost":7144}}`
	allData := `{"d1":{"cost":552},"d7":{"cost":4690},"d30":{"cost":12025}}`

	_ = os.WriteFile(filepath.Join(cacheDir, "proj-"+projectHash("/tmp/statusline-test-project")+".json"), []byte(projData), 0o644)
	_ = os.WriteFile(filepath.Join(cacheDir, "all.json"), []byte(allData), 0o644)

	cfg := defaultCfg()
	out := strip(Render(basicSession(), cfg))

	checks := map[string]string{
		"proj symbol": "\u2302",
		"all symbol":  "\u03a3",
		"proj day":    "$374",
		"proj week":   "$4.0k",
		"proj month":  "$7.1k",
		"all day":     "$552",
		"all month":   "$12.0k",
	}
	for label, want := range checks {
		if !strings.Contains(out, want) {
			t.Errorf("%s: missing %q", label, want)
		}
	}
}

func TestRenderPerModel(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("XDG_CACHE_HOME", dir)
	cacheDir := filepath.Join(dir, "claude-code-statusline")
	_ = os.MkdirAll(cacheDir, 0o755)

	mc := map[string]interface{}{
		"models": []map[string]interface{}{
			{"model": "claude-opus-4-6-20250514", "in": 549000, "out": 41200},
			{"model": "claude-sonnet-4-5-20250929", "in": 180000, "out": 25000},
			{"model": "claude-haiku-4-5-20251001", "in": 45000, "out": 15000},
		},
	}
	data, _ := json.Marshal(mc)
	_ = os.WriteFile(filepath.Join(cacheDir, "models-test-abc.json"), data, 0o644)

	s := basicSession()
	s.TranscriptPath = "/tmp/test-abc.jsonl"
	cfg := defaultCfg()
	out := strip(Render(s, cfg))

	checks := map[string]string{
		"O label":    "O:",
		"S label":    "S:",
		"H label":    "H:",
		"opus in":    "549k",
		"opus out":   "41k",
		"sonnet in":  "180k",
		"sonnet out": "25k",
		"haiku in":   "45k",
		"haiku out":  "15k",
	}
	for label, want := range checks {
		if !strings.Contains(out, want) {
			t.Errorf("%s: missing %q in:\n%s", label, want, out)
		}
	}
}

func TestRenderAlways2Lines(t *testing.T) {
	out := Render(basicSession(), defaultCfg())
	if strings.Count(out, "\n") != 2 {
		t.Errorf("expected exactly 2 newlines, got %d in: %q", strings.Count(out, "\n"), out)
	}
}

func TestRenderMinimal(t *testing.T) {
	s := session.Session{
		Model:         session.Model{DisplayName: "Claude Sonnet 4.5"},
		ContextWindow: session.ContextWindow{UsedPercentage: 1},
	}
	cfg := defaultCfg()
	out := Render(s, cfg)
	clean := strip(out)

	if strings.Count(out, "\n") != 2 {
		t.Errorf("minimal should still produce 2 lines")
	}
	if !strings.Contains(clean, "Sonnet 4.5") {
		t.Error("missing model name")
	}
	if !strings.Contains(clean, "1%") {
		t.Error("missing context")
	}
	if strings.Contains(clean, "\u26a0") {
		t.Error("1% should NOT show warning")
	}
}

func TestRenderEmptySession(t *testing.T) {
	out := Render(session.Session{}, defaultCfg())
	if strings.Count(out, "\n") != 2 {
		t.Error("empty session should still produce 2 lines")
	}
}
