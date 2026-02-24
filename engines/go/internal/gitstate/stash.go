package gitstate

import (
	"bufio"
	"os"
	"path/filepath"
	"strings"
)

// countStash counts stash entries by reading the reflog file directly.
// go-git has no reflog API, so we read .git/logs/refs/stash.
func countStash(cwd string) int {
	commonDir := findCommonDir(cwd)
	if commonDir == "" {
		return 0
	}

	stashLog := filepath.Join(commonDir, "logs", "refs", "stash")
	f, err := os.Open(stashLog)
	if err != nil {
		return 0
	}
	defer func() { _ = f.Close() }()

	count := 0
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		if strings.TrimSpace(scanner.Text()) != "" {
			count++
		}
	}
	return count
}

// findCommonDir returns the main .git directory (handling worktrees).
func findCommonDir(cwd string) string {
	gitPath := findDotGit(cwd)
	if gitPath == "" {
		return ""
	}

	info, err := os.Stat(gitPath)
	if err != nil {
		return ""
	}

	if info.IsDir() {
		return gitPath
	}

	// .git is a file → worktree, parse gitdir pointer
	data, err := os.ReadFile(gitPath)
	if err != nil {
		return ""
	}
	content := strings.TrimSpace(string(data))
	if !strings.HasPrefix(content, "gitdir: ") {
		return ""
	}
	gitdir := strings.TrimPrefix(content, "gitdir: ")
	if !filepath.IsAbs(gitdir) {
		gitdir = filepath.Join(filepath.Dir(gitPath), gitdir)
	}
	// gitdir is .git/worktrees/<name>, common dir is .git
	return filepath.Dir(filepath.Dir(gitdir))
}
