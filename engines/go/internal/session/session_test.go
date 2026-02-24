package session

import (
	"strings"
	"testing"
)

func TestParse(t *testing.T) {
	input := `{
		"cwd": "/tmp/test",
		"session_id": "sess-123",
		"model": {"id": "claude-opus-4-6", "display_name": "Claude Opus 4.6"},
		"context_window": {
			"used_percentage": 38,
			"total_input_tokens": 287500,
			"total_output_tokens": 41200
		},
		"cost": {
			"total_cost_usd": 8.42,
			"total_duration_ms": 900000,
			"total_api_duration_ms": 600000,
			"total_lines_added": 127,
			"total_lines_removed": 34
		},
		"workspace": {"project_dir": "/tmp/test", "current_dir": "/tmp/test"},
		"transcript_path": "/tmp/sess-123.jsonl"
	}`

	s := Parse(strings.NewReader(input))

	if s.Model.DisplayName != "Claude Opus 4.6" {
		t.Errorf("DisplayName = %q, want %q", s.Model.DisplayName, "Claude Opus 4.6")
	}
	if s.ContextWindow.UsedPercentage != 38 {
		t.Errorf("UsedPercentage = %v, want 38", s.ContextWindow.UsedPercentage)
	}
	if s.Cost.TotalCostUSD != 8.42 {
		t.Errorf("TotalCostUSD = %v, want 8.42", s.Cost.TotalCostUSD)
	}
	if int(s.ContextWindow.TotalInputTokens) != 287500 {
		t.Errorf("TotalInputTokens = %v, want 287500", s.ContextWindow.TotalInputTokens)
	}
	if int(s.Cost.TotalLinesAdded) != 127 {
		t.Errorf("TotalLinesAdded = %v, want 127", s.Cost.TotalLinesAdded)
	}
	if s.TranscriptPath != "/tmp/sess-123.jsonl" {
		t.Errorf("TranscriptPath = %q, want %q", s.TranscriptPath, "/tmp/sess-123.jsonl")
	}
	if s.Workspace.ProjectDir != "/tmp/test" {
		t.Errorf("ProjectDir = %q, want %q", s.Workspace.ProjectDir, "/tmp/test")
	}
}

func TestParseEmpty(t *testing.T) {
	s := Parse(strings.NewReader(""))
	if s.Model.DisplayName != "" {
		t.Errorf("empty input should give zero session, got DisplayName=%q", s.Model.DisplayName)
	}
}

func TestParseInvalidJSON(t *testing.T) {
	s := Parse(strings.NewReader("{invalid"))
	if s.Cost.TotalCostUSD != 0 {
		t.Errorf("invalid JSON should give zero session, got cost=%v", s.Cost.TotalCostUSD)
	}
}

func TestParseMinimal(t *testing.T) {
	input := `{"model":{"display_name":"Claude Sonnet 4.5"},"context_window":{"used_percentage":1}}`
	s := Parse(strings.NewReader(input))

	if s.Model.DisplayName != "Claude Sonnet 4.5" {
		t.Errorf("DisplayName = %q", s.Model.DisplayName)
	}
	if s.Cost.TotalCostUSD != 0 {
		t.Errorf("missing cost should be 0, got %v", s.Cost.TotalCostUSD)
	}
	if s.Workspace.ProjectDir != "" {
		t.Errorf("missing workspace should be empty, got %q", s.Workspace.ProjectDir)
	}
}
