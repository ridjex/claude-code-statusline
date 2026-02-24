package background

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"

	"statusline/internal/cache"
)

// SpawnCumulativeStats runs cumulative-stats.sh in the background (detached).
func SpawnCumulativeStats(projectDir string) {
	if projectDir == "" {
		return
	}

	exe, err := os.Executable()
	if err != nil {
		return
	}
	selfDir := filepath.Dir(exe)

	// Look for cumulative-stats.sh relative to binary, then fallback paths
	candidates := []string{
		filepath.Join(selfDir, "..", "bash", "cumulative-stats.sh"),
		filepath.Join(selfDir, "cumulative-stats.sh"),
		filepath.Join(os.Getenv("HOME"), ".claude", "cumulative-stats.sh"),
	}

	var script string
	for _, c := range candidates {
		abs, err := filepath.Abs(c)
		if err != nil {
			continue
		}
		if info, err := os.Stat(abs); err == nil && !info.IsDir() {
			script = abs
			break
		}
	}

	if script == "" {
		return
	}

	cmd := exec.Command(script, projectDir)
	cmd.Stdout = nil
	cmd.Stderr = nil
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	_ = cmd.Start()
}

// SpawnModelRefresh re-executes the binary with --internal-refresh-models to update the model cache.
func SpawnModelRefresh(sessionID, transcriptPath string) {
	if sessionID == "" || transcriptPath == "" {
		return
	}

	exe, err := os.Executable()
	if err != nil {
		return
	}

	cmd := exec.Command(exe,
		"--internal-refresh-models",
		"--session-id", sessionID,
		"--transcript-path", transcriptPath,
	)
	cmd.Stdin = strings.NewReader("{}")
	cmd.Stdout = nil
	cmd.Stderr = nil
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	_ = cmd.Start()
}

// RefreshModelCache is the internal mode that reads JSONL transcripts and writes the model cache.
func RefreshModelCache(sessionID, transcriptPath string) {
	if sessionID == "" || transcriptPath == "" {
		return
	}

	cacheDir := cache.CacheDir()
	_ = os.MkdirAll(cacheDir, 0o755)

	// Collect files to scan
	files := []string{transcriptPath}
	subagentDir := filepath.Join(filepath.Dir(transcriptPath), sessionID, "subagents")
	if entries, err := os.ReadDir(subagentDir); err == nil {
		for _, e := range entries {
			if strings.HasSuffix(e.Name(), ".jsonl") {
				files = append(files, filepath.Join(subagentDir, e.Name()))
			}
		}
	}

	type modelAgg struct {
		Model string `json:"model"`
		In    int    `json:"in"`
		Out   int    `json:"out"`
	}

	models := map[string]*modelAgg{}

	for _, fpath := range files {
		data, err := os.ReadFile(fpath)
		if err != nil {
			continue
		}
		for _, line := range strings.Split(string(data), "\n") {
			line = strings.TrimSpace(line)
			if line == "" {
				continue
			}
			var entry struct {
				Type    string `json:"type"`
				Message struct {
					Model string `json:"model"`
					Usage struct {
						InputTokens             int `json:"input_tokens"`
						OutputTokens            int `json:"output_tokens"`
						CacheReadInputTokens    int `json:"cache_read_input_tokens"`
						CacheCreationInputTokens int `json:"cache_creation_input_tokens"`
					} `json:"usage"`
				} `json:"message"`
			}
			if err := json.Unmarshal([]byte(line), &entry); err != nil {
				continue
			}
			if entry.Type != "assistant" {
				continue
			}
			name := entry.Message.Model
			if name == "" || !strings.HasPrefix(name, "claude-") {
				continue
			}
			if _, ok := models[name]; !ok {
				models[name] = &modelAgg{Model: name}
			}
			models[name].In += entry.Message.Usage.InputTokens +
				entry.Message.Usage.CacheReadInputTokens +
				entry.Message.Usage.CacheCreationInputTokens
			models[name].Out += entry.Message.Usage.OutputTokens
		}
	}

	result := struct {
		Models []*modelAgg `json:"models"`
	}{}
	for _, m := range models {
		result.Models = append(result.Models, m)
	}

	data, err := json.Marshal(result)
	if err != nil {
		return
	}

	cacheFile := filepath.Join(cacheDir, fmt.Sprintf("models-%s.json", sessionID))
	tmp := cacheFile + ".tmp"
	if err := os.WriteFile(tmp, data, 0o644); err != nil {
		return
	}
	_ = os.Rename(tmp, cacheFile)
}
