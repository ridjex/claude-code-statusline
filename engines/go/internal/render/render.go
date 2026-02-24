package render

import (
	"fmt"
	"math"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"statusline/internal/cache"
	"statusline/internal/config"
	"statusline/internal/format"
	"statusline/internal/gitstate"
	"statusline/internal/session"
)

const (
	dim     = "\033[2m"
	rst     = "\033[0m"
	cyan    = "\033[36m"
	green   = "\033[32m"
	yellow  = "\033[33m"
	red     = "\033[31m"
	magenta = "\033[35m"
)

var ansiRe = regexp.MustCompile(`\033\[[0-9;]*m`)

// Render produces the 2-line statusline output from session data and config.
func Render(sess session.Session, cfg config.Config) string {
	sep := " " + dim + "\u2502" + rst + " "

	// Session ID from transcript path
	sessionID := ""
	if sess.TranscriptPath != "" {
		base := filepath.Base(sess.TranscriptPath)
		sessionID = strings.TrimSuffix(base, ".jsonl")
	}

	// --- Model ---
	model := ""
	if cfg.ShowModel {
		model = sess.Model.DisplayName
		if model == "" {
			model = "?"
		}
		model = strings.TrimPrefix(model, "Claude ")
	}

	// --- Context bar ---
	pct := 0
	bar := ""
	warn := ""
	clr := green
	if cfg.ShowContext {
		pct = int(sess.ContextWindow.UsedPercentage)
		filled := pct / 10
		if filled > 10 {
			filled = 10
		}
		empty := 10 - filled
		bar = strings.Repeat("\u2593", filled) + strings.Repeat("\u2591", empty)
		if pct >= 90 {
			clr = red
			warn = " \u26a0"
		} else if pct >= 70 {
			clr = yellow
			warn = " \u26a0"
		}
	}

	// --- Cost ---
	costFmt := ""
	if cfg.ShowCost {
		costFmt = format.FmtCost(sess.Cost.TotalCostUSD)
	}

	// --- Duration ---
	durFmt := ""
	if cfg.ShowDuration {
		durFmt = format.FmtDuration(int(sess.Cost.TotalDurationMs))
	}

	// --- Git ---
	var gitDisplay, dirty, gitExtra string
	if cfg.ShowGit {
		cwd, err := os.Getwd()
		if err == nil {
			gs := gitstate.Get(cwd)
			if gs != nil && gs.Branch != "" {
				sb := format.Truncate(format.ShortenBranch(gs.Branch), 20)
				if gs.InWorktree {
					sw := format.Truncate(format.ShortenBranch(gs.WorktreeName), 20)
					if sw == sb {
						gitDisplay = "\u2295 " + sb
					} else {
						gitDisplay = "\u2295" + sw + " " + sb
					}
				} else {
					gitDisplay = sb
				}
				if gs.Dirty {
					dirty = "\u25cf"
				}
				var parts []string
				if gs.Ahead > 0 {
					parts = append(parts, fmt.Sprintf("\u2191%d", gs.Ahead))
				}
				if gs.Behind > 0 {
					parts = append(parts, fmt.Sprintf("\u2193%d", gs.Behind))
				}
				if gs.Stash > 0 {
					parts = append(parts, fmt.Sprintf("stash:%d", gs.Stash))
				}
				gitExtra = strings.Join(parts, " ")
			}
		}
	}

	// --- Lines added/removed ---
	linesFmt := ""
	if cfg.ShowDiff {
		added := int(sess.Cost.TotalLinesAdded)
		removed := int(sess.Cost.TotalLinesRemoved)
		if added > 0 || removed > 0 {
			linesFmt = fmt.Sprintf("%s+%d%s %s-%d%s", green, added, rst, red, removed, rst)
		}
	}

	// --- Token data ---
	inTok := int(sess.ContextWindow.TotalInputTokens)
	outTok := int(sess.ContextWindow.TotalOutputTokens)
	inFmt := format.FmtK(inTok)
	outFmt := format.FmtK(outTok)

	// --- Per-model stats ---
	var modelStats *cache.ModelStats
	modelMix := ""
	if sessionID != "" {
		modelStats = cache.ReadModels(sessionID)
	}

	if modelStats != nil {
		maxOut := modelStats.OpusOut
		if modelStats.SonnetOut > maxOut {
			maxOut = modelStats.SonnetOut
		}
		if modelStats.HaikuOut > maxOut {
			maxOut = modelStats.HaikuOut
		}
		if cfg.ShowModelBars && maxOut > 0 {
			oBar := format.BarChar(modelStats.OpusOut, maxOut)
			sBar := format.BarChar(modelStats.SonnetOut, maxOut)
			hBar := format.BarChar(modelStats.HaikuOut, maxOut)
			oC := dim + "·"
			if oBar != "" {
				oC = magenta + oBar
			}
			sC := dim + "·"
			if sBar != "" {
				sC = cyan + sBar
			}
			hC := dim + "·"
			if hBar != "" {
				hC = green + hBar
			}
			modelMix = oC + sC + hC + rst
		}
	}

	// --- Speed ---
	speedFmt := ""
	if cfg.ShowSpeed {
		apiMs := int(sess.Cost.TotalAPIDurationMs)
		if apiMs > 0 && outTok > 0 {
			speed := float64(outTok) * 1000 / float64(apiMs)
			speedInt := int(math.RoundToEven(speed))
			speedClr := red
			if speedInt > 30 {
				speedClr = green
			} else if speedInt >= 15 {
				speedClr = yellow
			}
			speedFmt = fmt.Sprintf("%s%d tok/s%s", speedClr, speedInt, rst)
		}
	}

	// --- Cumulative stats ---
	cumProj := ""
	cumAll := ""
	if cfg.ShowCumulative {
		projStats, allStats := cache.ReadCumulative(sess.Workspace.ProjectDir)
		if projStats != nil {
			cumProj = fmt.Sprintf("\u2302 %s/%s/%s",
				format.FmtCost(projStats.D1),
				format.FmtCost(projStats.D7),
				format.FmtCost(projStats.D30))
		}
		if allStats != nil {
			cumAll = fmt.Sprintf("\u03a3 %s/%s/%s",
				format.FmtCost(allStats.D1),
				format.FmtCost(allStats.D7),
				format.FmtCost(allStats.D30))
		}
	}

	// ======== ASSEMBLE LINE 1 ========
	var l1Parts []string

	if model != "" {
		part := cyan + model + rst
		if modelMix != "" {
			part += " " + modelMix
		}
		l1Parts = append(l1Parts, part)
	} else if modelMix != "" {
		l1Parts = append(l1Parts, modelMix)
	}

	if bar != "" {
		l1Parts = append(l1Parts, fmt.Sprintf("%s%s %d%%%s%s", clr, bar, pct, warn, rst))
	}
	if costFmt != "" {
		l1Parts = append(l1Parts, costFmt)
	}
	if durFmt != "" {
		l1Parts = append(l1Parts, durFmt)
	}
	if gitDisplay != "" {
		gitPart := magenta + gitDisplay + rst
		if dirty != "" {
			gitPart += " " + yellow + dirty + rst
		}
		if gitExtra != "" {
			gitPart += " " + cyan + gitExtra + rst
		}
		l1Parts = append(l1Parts, gitPart)
	}
	if linesFmt != "" {
		l1Parts = append(l1Parts, linesFmt)
	}

	l1 := strings.Join(l1Parts, sep)

	// ======== ASSEMBLE LINE 2 ========
	l2 := ""
	if cfg.Line2 {
		var l2Parts []string

		if cfg.ShowTokens {
			var tokParts []string
			if modelStats != nil && (modelStats.OpusOut > 0 || modelStats.OpusIn > 0) {
				tokParts = append(tokParts, fmt.Sprintf("%sO%s:%s/%s",
					magenta, rst, format.FmtK(modelStats.OpusIn), format.FmtK(modelStats.OpusOut)))
			}
			if modelStats != nil && (modelStats.SonnetOut > 0 || modelStats.SonnetIn > 0) {
				tokParts = append(tokParts, fmt.Sprintf("%sS%s:%s/%s",
					cyan, rst, format.FmtK(modelStats.SonnetIn), format.FmtK(modelStats.SonnetOut)))
			}
			if modelStats != nil && (modelStats.HaikuOut > 0 || modelStats.HaikuIn > 0) {
				tokParts = append(tokParts, fmt.Sprintf("%sH%s:%s/%s",
					green, rst, format.FmtK(modelStats.HaikuIn), format.FmtK(modelStats.HaikuOut)))
			}
			if len(tokParts) > 0 {
				l2Parts = append(l2Parts, strings.Join(tokParts, " "))
			} else {
				l2Parts = append(l2Parts, fmt.Sprintf("%sin:%s%s %sout:%s%s",
					dim, rst, inFmt, dim, rst, outFmt))
			}
		}

		if speedFmt != "" {
			l2Parts = append(l2Parts, speedFmt)
		}
		if cumProj != "" {
			l2Parts = append(l2Parts, cumProj)
		}
		if cumAll != "" {
			l2Parts = append(l2Parts, cumAll)
		}

		l2 = strings.Join(l2Parts, sep)
	}

	// --- NO_COLOR ---
	if cfg.NoColor {
		l1 = ansiRe.ReplaceAllString(l1, "")
		l2 = ansiRe.ReplaceAllString(l2, "")
	}

	if l2 != "" {
		return l1 + "\n" + l2 + "\n"
	}
	return l1 + "\n\n"
}
