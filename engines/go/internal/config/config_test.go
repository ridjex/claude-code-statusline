package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLoadDefaults(t *testing.T) {
	cfg := Load(nil)
	if !cfg.ShowModel {
		t.Error("ShowModel should default to true")
	}
	if !cfg.ShowCost {
		t.Error("ShowCost should default to true")
	}
	if !cfg.Line2 {
		t.Error("Line2 should default to true")
	}
	if !cfg.ShowGit {
		t.Error("ShowGit should default to true")
	}
	if cfg.NoColor {
		t.Error("NoColor should default to false")
	}
}

func TestLoadCLIArgs(t *testing.T) {
	cfg := Load([]string{"--no-cost", "--no-git", "--no-line2"})
	if cfg.ShowCost {
		t.Error("--no-cost should disable ShowCost")
	}
	if cfg.ShowGit {
		t.Error("--no-git should disable ShowGit")
	}
	if cfg.Line2 {
		t.Error("--no-line2 should disable Line2")
	}
	// Others still on
	if !cfg.ShowModel {
		t.Error("ShowModel should still be true")
	}
	if !cfg.ShowDiff {
		t.Error("ShowDiff should still be true")
	}
}

func TestLoadNoColor(t *testing.T) {
	cfg := Load([]string{"--no-color"})
	if !cfg.NoColor {
		t.Error("--no-color should enable NoColor")
	}
}

func TestLoadNoColorEnv(t *testing.T) {
	t.Setenv("NO_COLOR", "1")
	cfg := Load(nil)
	if !cfg.NoColor {
		t.Error("NO_COLOR env should enable NoColor")
	}
}

func TestLoadEnvOverride(t *testing.T) {
	t.Setenv("STATUSLINE_SHOW_COST", "false")
	cfg := Load(nil)
	if cfg.ShowCost {
		t.Error("STATUSLINE_SHOW_COST=false should disable ShowCost")
	}
	if !cfg.ShowModel {
		t.Error("other settings should remain true")
	}
}

func TestLoadCLIOverridesEnv(t *testing.T) {
	t.Setenv("STATUSLINE_SHOW_COST", "true")
	cfg := Load([]string{"--no-cost"})
	if cfg.ShowCost {
		t.Error("CLI --no-cost should override env STATUSLINE_SHOW_COST=true")
	}
}

func TestLoadEnvFile(t *testing.T) {
	dir := t.TempDir()
	envFile := filepath.Join(dir, "statusline.env")
	_ = os.WriteFile(envFile, []byte("STATUSLINE_SHOW_DIFF=false\n# comment\nSTATUSLINE_SHOW_SPEED=false\n"), 0o644)

	// Point HOME to temp dir so config is found at ~/.claude/statusline.env
	claudeDir := filepath.Join(dir, ".claude")
	_ = os.MkdirAll(claudeDir, 0o755)
	_ = os.WriteFile(filepath.Join(claudeDir, "statusline.env"),
		[]byte("STATUSLINE_SHOW_DIFF=false\nSTATUSLINE_SHOW_SPEED=false\n"), 0o644)

	t.Setenv("HOME", dir)
	cfg := Load(nil)
	if cfg.ShowDiff {
		t.Error("config file should disable ShowDiff")
	}
	if cfg.ShowSpeed {
		t.Error("config file should disable ShowSpeed")
	}
	if !cfg.ShowModel {
		t.Error("unset config should stay true")
	}
}

func TestLoadEnvFileOverriddenByEnv(t *testing.T) {
	dir := t.TempDir()
	claudeDir := filepath.Join(dir, ".claude")
	_ = os.MkdirAll(claudeDir, 0o755)
	_ = os.WriteFile(filepath.Join(claudeDir, "statusline.env"),
		[]byte("STATUSLINE_SHOW_COST=false\n"), 0o644)

	t.Setenv("HOME", dir)
	t.Setenv("STATUSLINE_SHOW_COST", "true")
	cfg := Load(nil)
	if !cfg.ShowCost {
		t.Error("env var should override config file (true > false)")
	}
}

func TestLoadHelp(t *testing.T) {
	cfg := Load([]string{"--help"})
	if !cfg.ShowHelp {
		t.Error("--help should set ShowHelp")
	}
}

func TestLoadInternalRefresh(t *testing.T) {
	cfg := Load([]string{"--internal-refresh-models", "--session-id", "abc", "--transcript-path", "/tmp/x.jsonl"})
	if !cfg.InternalRefreshModels {
		t.Error("should set InternalRefreshModels")
	}
	if cfg.InternalSessionID != "abc" {
		t.Errorf("session-id = %q", cfg.InternalSessionID)
	}
	if cfg.InternalTranscriptPath != "/tmp/x.jsonl" {
		t.Errorf("transcript-path = %q", cfg.InternalTranscriptPath)
	}
}
