package cache

import (
	"crypto/md5"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// CacheDir returns the statusline cache directory.
func CacheDir() string {
	if xdg := os.Getenv("XDG_CACHE_HOME"); xdg != "" {
		return filepath.Join(xdg, "claude-code-statusline")
	}
	return filepath.Join(os.Getenv("HOME"), ".cache", "claude-code-statusline")
}

// ProjectHash computes the 8-char hex hash for a project directory.
// Matches bash: echo "$slug" | md5 (note: newline included).
func ProjectHash(dir string) string {
	slug := strings.TrimPrefix(dir, "/")
	slug = strings.ReplaceAll(slug, "/", "-")
	h := md5.Sum([]byte(slug + "\n"))
	return fmt.Sprintf("%x", h)[:8]
}

type ModelEntry struct {
	Model string `json:"model"`
	In    int    `json:"in"`
	Out   int    `json:"out"`
}

type ModelsCache struct {
	Models []ModelEntry `json:"models"`
}

type ModelStats struct {
	OpusIn    int
	OpusOut   int
	SonnetIn  int
	SonnetOut int
	HaikuIn   int
	HaikuOut  int
}

// ReadModels reads the per-session model cache and aggregates by model family.
func ReadModels(sessionID string) *ModelStats {
	if sessionID == "" {
		return nil
	}
	cacheFile := filepath.Join(CacheDir(), fmt.Sprintf("models-%s.json", sessionID))
	data, err := os.ReadFile(cacheFile)
	if err != nil {
		return nil
	}
	var mc ModelsCache
	if err := json.Unmarshal(data, &mc); err != nil {
		return nil
	}

	stats := &ModelStats{}
	for _, m := range mc.Models {
		name := strings.ToLower(m.Model)
		if strings.Contains(name, "opus") {
			stats.OpusIn += m.In
			stats.OpusOut += m.Out
		} else if strings.Contains(name, "sonnet") {
			stats.SonnetIn += m.In
			stats.SonnetOut += m.Out
		} else if strings.Contains(name, "haiku") {
			stats.HaikuIn += m.In
			stats.HaikuOut += m.Out
		}
	}
	return stats
}

type cumulativePeriod struct {
	Cost float64 `json:"cost"`
}

type cumulativeCache struct {
	D1  cumulativePeriod `json:"d1"`
	D7  cumulativePeriod `json:"d7"`
	D30 cumulativePeriod `json:"d30"`
}

type CumulativeStats struct {
	D1  float64
	D7  float64
	D30 float64
}

// ReadCumulative reads project and global cumulative caches.
func ReadCumulative(projectDir string) (*CumulativeStats, *CumulativeStats) {
	cacheDir := CacheDir()
	var proj *CumulativeStats

	if projectDir != "" {
		hash := ProjectHash(projectDir)
		projFile := filepath.Join(cacheDir, fmt.Sprintf("proj-%s.json", hash))
		proj = readCumulativeFile(projFile)
	}

	allFile := filepath.Join(cacheDir, "all.json")
	all := readCumulativeFile(allFile)

	return proj, all
}

func readCumulativeFile(path string) *CumulativeStats {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil
	}
	var cc cumulativeCache
	if err := json.Unmarshal(data, &cc); err != nil {
		return nil
	}
	if cc.D1.Cost == 0 && cc.D7.Cost == 0 && cc.D30.Cost == 0 {
		return nil
	}
	return &CumulativeStats{
		D1:  cc.D1.Cost,
		D7:  cc.D7.Cost,
		D30: cc.D30.Cost,
	}
}
