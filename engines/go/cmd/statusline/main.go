package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"statusline/internal/background"
	"statusline/internal/config"
	"statusline/internal/render"
	"statusline/internal/session"
)

func main() {
	defer func() {
		if r := recover(); r != nil {
			// Never crash the render cycle
			_, _ = fmt.Fprint(os.Stdout, "\n\n")
		}
	}()

	cfg := config.Load(os.Args[1:])

	if cfg.ShowHelp {
		printHelp()
		return
	}

	// Internal mode: refresh model cache
	if cfg.InternalRefreshModels {
		background.RefreshModelCache(cfg.InternalSessionID, cfg.InternalTranscriptPath)
		return
	}

	sess := session.Parse(os.Stdin)

	// Render output
	output := render.Render(sess, cfg)
	_, _ = fmt.Fprint(os.Stdout, output)

	// Fire-and-forget background jobs
	sessionID := ""
	if sess.TranscriptPath != "" {
		base := filepath.Base(sess.TranscriptPath)
		sessionID = strings.TrimSuffix(base, ".jsonl")
	}

	background.SpawnCumulativeStats(sess.Workspace.ProjectDir)
	if sessionID != "" && sess.TranscriptPath != "" {
		background.SpawnModelRefresh(sessionID, sess.TranscriptPath)
	}
}

func printHelp() {
	_, _ = fmt.Fprint(os.Stderr, `Usage: statusline [OPTIONS]
Reads JSON from stdin, outputs formatted status bar.

Options:
  --no-model       Hide model name
  --no-model-bars  Hide model mix bars
  --no-context     Hide context window bar
  --no-cost        Hide session cost
  --no-duration    Hide duration
  --no-git         Hide git branch/status
  --no-diff        Hide lines added/removed
  --no-line2       Hide entire second line
  --no-tokens      Hide token counts
  --no-speed       Hide throughput (tok/s)
  --no-cumulative  Hide cumulative costs
  --no-color       Disable ANSI colors
  --help           Show this help

Config precedence: CLI args > env vars > ~/.claude/statusline.env > defaults (all on)
`)
}
