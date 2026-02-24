package session

import (
	"encoding/json"
	"io"
)

type Model struct {
	ID          string `json:"id"`
	DisplayName string `json:"display_name"`
}

type ContextWindow struct {
	UsedPercentage    float64 `json:"used_percentage"`
	ContextWindowSize float64 `json:"context_window_size"`
	TotalInputTokens  float64 `json:"total_input_tokens"`
	TotalOutputTokens float64 `json:"total_output_tokens"`
}

type Cost struct {
	TotalCostUSD       float64 `json:"total_cost_usd"`
	TotalDurationMs    float64 `json:"total_duration_ms"`
	TotalAPIDurationMs float64 `json:"total_api_duration_ms"`
	TotalLinesAdded    float64 `json:"total_lines_added"`
	TotalLinesRemoved  float64 `json:"total_lines_removed"`
}

type Workspace struct {
	ProjectDir string `json:"project_dir"`
	CurrentDir string `json:"current_dir"`
}

type Session struct {
	Cwd            string        `json:"cwd"`
	SessionID      string        `json:"session_id"`
	Model          Model         `json:"model"`
	ContextWindow  ContextWindow `json:"context_window"`
	Cost           Cost          `json:"cost"`
	Version        string        `json:"version"`
	Workspace      Workspace     `json:"workspace"`
	TranscriptPath string        `json:"transcript_path"`
}

func Parse(r io.Reader) Session {
	var s Session
	data, err := io.ReadAll(r)
	if err != nil {
		return s
	}
	_ = json.Unmarshal(data, &s)
	return s
}
