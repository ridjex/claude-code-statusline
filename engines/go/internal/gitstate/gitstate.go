package gitstate

import (
	"errors"
	"os"
	"path/filepath"
	"strings"

	"github.com/go-git/go-git/v5"
	"github.com/go-git/go-git/v5/plumbing"
	"github.com/go-git/go-git/v5/plumbing/object"
)

var errStop = errors.New("stop")

type GitState struct {
	Branch       string
	Dirty        bool
	Ahead        int
	Behind       int
	Stash        int
	InWorktree   bool
	WorktreeName string
}

// Get returns the git state for the given working directory, or nil if not in a repo.
func Get(cwd string) *GitState {
	repo, err := git.PlainOpenWithOptions(cwd, &git.PlainOpenOptions{
		DetectDotGit:          true,
		EnableDotGitCommonDir: true,
	})
	if err != nil {
		return nil
	}

	state := &GitState{}

	head, err := repo.Head()
	if err != nil || !head.Name().IsBranch() {
		return nil
	}
	state.Branch = head.Name().Short()

	// Dirty
	wt, err := repo.Worktree()
	if err == nil {
		status, err := wt.Status()
		if err == nil {
			state.Dirty = !status.IsClean()
		}
	}

	// Ahead/behind
	state.Ahead, state.Behind = getAheadBehind(repo, head)

	// Worktree detection + stash (filesystem-based)
	detectWorktree(cwd, state)
	state.Stash = countStash(cwd)

	return state
}

func getAheadBehind(repo *git.Repository, head *plumbing.Reference) (int, int) {
	cfg, err := repo.Config()
	if err != nil {
		return 0, 0
	}

	branchName := head.Name().Short()
	branchCfg, ok := cfg.Branches[branchName]
	if !ok {
		return 0, 0
	}

	upstreamRef := plumbing.NewRemoteReferenceName(branchCfg.Remote, branchCfg.Merge.Short())
	upstream, err := repo.Reference(upstreamRef, true)
	if err != nil {
		return 0, 0
	}

	if head.Hash() == upstream.Hash() {
		return 0, 0
	}

	const limit = 1000

	// Collect upstream commits
	upstreamSet := collectCommitHashes(repo, upstream.Hash(), limit)

	// Count ahead: commits from HEAD not in upstream set
	ahead := 0
	total := 0
	headIter, err := repo.Log(&git.LogOptions{From: head.Hash()})
	if err != nil {
		return 0, 0
	}
	_ = headIter.ForEach(func(c *object.Commit) error {
		total++
		if total > limit {
			return errStop
		}
		if !upstreamSet[c.Hash] {
			ahead++
		}
		return nil
	})

	// Collect HEAD commits
	headSet := collectCommitHashes(repo, head.Hash(), limit)

	// Count behind: commits from upstream not in HEAD set
	behind := 0
	total = 0
	upIter, err := repo.Log(&git.LogOptions{From: upstream.Hash()})
	if err != nil {
		return ahead, 0
	}
	_ = upIter.ForEach(func(c *object.Commit) error {
		total++
		if total > limit {
			return errStop
		}
		if !headSet[c.Hash] {
			behind++
		}
		return nil
	})

	return ahead, behind
}

func collectCommitHashes(repo *git.Repository, from plumbing.Hash, limit int) map[plumbing.Hash]bool {
	set := make(map[plumbing.Hash]bool)
	iter, err := repo.Log(&git.LogOptions{From: from})
	if err != nil {
		return set
	}
	count := 0
	_ = iter.ForEach(func(c *object.Commit) error {
		set[c.Hash] = true
		count++
		if count >= limit {
			return errStop
		}
		return nil
	})
	return set
}

func detectWorktree(cwd string, state *GitState) {
	gitPath := findDotGit(cwd)
	if gitPath == "" {
		return
	}

	info, err := os.Stat(gitPath)
	if err != nil {
		return
	}

	if info.IsDir() {
		return // regular repo, not a worktree
	}

	// .git is a file → worktree
	data, err := os.ReadFile(gitPath)
	if err != nil {
		return
	}
	content := strings.TrimSpace(string(data))
	if !strings.HasPrefix(content, "gitdir: ") {
		return
	}

	gitdir := strings.TrimPrefix(content, "gitdir: ")
	if !filepath.IsAbs(gitdir) {
		gitdir = filepath.Join(filepath.Dir(gitPath), gitdir)
	}

	state.InWorktree = true

	// Extract worktree name from path
	toplevel := filepath.Dir(gitPath)
	commonDir := filepath.Dir(filepath.Dir(gitdir)) // up from worktrees/<name>
	mainToplevel := filepath.Dir(commonDir)

	wtPrefix := mainToplevel + "/.worktrees/"
	if strings.HasPrefix(toplevel, wtPrefix) {
		state.WorktreeName = toplevel[len(wtPrefix):]
	} else {
		state.WorktreeName = toplevel
	}
}

func findDotGit(cwd string) string {
	dir := cwd
	for {
		gitPath := filepath.Join(dir, ".git")
		if _, err := os.Stat(gitPath); err == nil {
			return gitPath
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return ""
		}
		dir = parent
	}
}
