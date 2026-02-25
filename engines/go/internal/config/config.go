package config

import (
	"bufio"
	"flag"
	"io"
	"os"
	"path/filepath"
	"strings"
)

type Config struct {
	ShowModel      bool
	ShowModelBars  bool
	ShowContext     bool
	ShowCost       bool
	ShowDuration   bool
	ShowGit        bool
	ShowDiff       bool
	Line2          bool
	ShowTokens     bool
	ShowSpeed      bool
	ShowCumulative bool
	NoColor        bool
	ShowVersion    bool
	ShowHelp       bool

	InternalRefreshModels  bool
	InternalSessionID      string
	InternalTranscriptPath string
}

var envKeys = []string{
	"STATUSLINE_SHOW_MODEL",
	"STATUSLINE_SHOW_MODEL_BARS",
	"STATUSLINE_SHOW_CONTEXT",
	"STATUSLINE_SHOW_COST",
	"STATUSLINE_SHOW_DURATION",
	"STATUSLINE_SHOW_GIT",
	"STATUSLINE_SHOW_DIFF",
	"STATUSLINE_LINE2",
	"STATUSLINE_SHOW_TOKENS",
	"STATUSLINE_SHOW_SPEED",
	"STATUSLINE_SHOW_CUMULATIVE",
}

func Load(args []string) Config {
	cfg := Config{
		ShowModel:      true,
		ShowModelBars:  true,
		ShowContext:     true,
		ShowCost:       true,
		ShowDuration:   true,
		ShowGit:        true,
		ShowDiff:       true,
		Line2:          true,
		ShowTokens:     true,
		ShowSpeed:      true,
		ShowCumulative: true,
	}

	// Save env overrides before loading config file
	envOverrides := map[string]string{}
	for _, k := range envKeys {
		if v, ok := os.LookupEnv(k); ok {
			envOverrides[k] = v
		}
	}

	// Load config file
	cfgPath := filepath.Join(os.Getenv("HOME"), ".claude", "statusline.env")
	fileVals := loadEnvFile(cfgPath)

	// Merge: file < env
	merged := make(map[string]string)
	for k, v := range fileVals {
		merged[k] = v
	}
	for k, v := range envOverrides {
		merged[k] = v
	}

	// Apply merged values
	applyBool(merged, "STATUSLINE_SHOW_MODEL", &cfg.ShowModel)
	applyBool(merged, "STATUSLINE_SHOW_MODEL_BARS", &cfg.ShowModelBars)
	applyBool(merged, "STATUSLINE_SHOW_CONTEXT", &cfg.ShowContext)
	applyBool(merged, "STATUSLINE_SHOW_COST", &cfg.ShowCost)
	applyBool(merged, "STATUSLINE_SHOW_DURATION", &cfg.ShowDuration)
	applyBool(merged, "STATUSLINE_SHOW_GIT", &cfg.ShowGit)
	applyBool(merged, "STATUSLINE_SHOW_DIFF", &cfg.ShowDiff)
	applyBool(merged, "STATUSLINE_LINE2", &cfg.Line2)
	applyBool(merged, "STATUSLINE_SHOW_TOKENS", &cfg.ShowTokens)
	applyBool(merged, "STATUSLINE_SHOW_SPEED", &cfg.ShowSpeed)
	applyBool(merged, "STATUSLINE_SHOW_CUMULATIVE", &cfg.ShowCumulative)

	// CLI args (highest priority)
	fs := flag.NewFlagSet("statusline", flag.ContinueOnError)
	fs.SetOutput(io.Discard)

	noModel := fs.Bool("no-model", false, "")
	noModelBars := fs.Bool("no-model-bars", false, "")
	noContext := fs.Bool("no-context", false, "")
	noCost := fs.Bool("no-cost", false, "")
	noDuration := fs.Bool("no-duration", false, "")
	noGit := fs.Bool("no-git", false, "")
	noDiff := fs.Bool("no-diff", false, "")
	noLine2 := fs.Bool("no-line2", false, "")
	noTokens := fs.Bool("no-tokens", false, "")
	noSpeed := fs.Bool("no-speed", false, "")
	noCumulative := fs.Bool("no-cumulative", false, "")
	noColor := fs.Bool("no-color", false, "")
	version := fs.Bool("version", false, "")
	help := fs.Bool("help", false, "")
	internalRefresh := fs.Bool("internal-refresh-models", false, "")
	sessionID := fs.String("session-id", "", "")
	transcriptPath := fs.String("transcript-path", "", "")

	_ = fs.Parse(args)

	if *noModel {
		cfg.ShowModel = false
	}
	if *noModelBars {
		cfg.ShowModelBars = false
	}
	if *noContext {
		cfg.ShowContext = false
	}
	if *noCost {
		cfg.ShowCost = false
	}
	if *noDuration {
		cfg.ShowDuration = false
	}
	if *noGit {
		cfg.ShowGit = false
	}
	if *noDiff {
		cfg.ShowDiff = false
	}
	if *noLine2 {
		cfg.Line2 = false
	}
	if *noTokens {
		cfg.ShowTokens = false
	}
	if *noSpeed {
		cfg.ShowSpeed = false
	}
	if *noCumulative {
		cfg.ShowCumulative = false
	}
	if *noColor {
		cfg.NoColor = true
	}
	if *version {
		cfg.ShowVersion = true
	}
	if *help {
		cfg.ShowHelp = true
	}
	if *internalRefresh {
		cfg.InternalRefreshModels = true
	}
	cfg.InternalSessionID = *sessionID
	cfg.InternalTranscriptPath = *transcriptPath

	// NO_COLOR env
	if _, ok := os.LookupEnv("NO_COLOR"); ok {
		cfg.NoColor = true
	}
	if _, ok := os.LookupEnv("STATUSLINE_NO_COLOR"); ok {
		cfg.NoColor = true
	}

	return cfg
}

func applyBool(m map[string]string, key string, target *bool) {
	if v, ok := m[key]; ok && v == "false" {
		*target = false
	}
}

func loadEnvFile(path string) map[string]string {
	vals := make(map[string]string)
	f, err := os.Open(path)
	if err != nil {
		return vals
	}
	defer func() { _ = f.Close() }()

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		idx := strings.Index(line, "=")
		if idx < 0 {
			continue
		}
		k := strings.TrimSpace(line[:idx])
		v := strings.TrimSpace(line[idx+1:])
		vals[k] = v
	}
	return vals
}
