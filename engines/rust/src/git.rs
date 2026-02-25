use std::fs;

pub struct GitState {
    pub branch: String,
    pub dirty: bool,
    pub ahead: i32,
    pub behind: i32,
    pub stash: i32,
    pub in_worktree: bool,
    pub worktree_name: String,
}

/// Get the git state for the given working directory, or None if not in a repo.
pub fn get(cwd: &str) -> Option<GitState> {
    let repo = gix::discover(cwd).ok()?;

    let mut state = GitState {
        branch: String::new(),
        dirty: false,
        ahead: 0,
        behind: 0,
        stash: 0,
        in_worktree: false,
        worktree_name: String::new(),
    };

    // Branch name — get the symbolic ref name from HEAD
    let mut head = repo.head().ok()?;
    let referent = head.referent_name()?;
    if !referent.as_bstr().starts_with(b"refs/heads/") {
        return None; // not a branch
    }
    state.branch = referent.shorten().to_string();

    // Dirty check via index stat comparison
    state.dirty = check_dirty(&repo);

    // Ahead/behind
    let head_commit = head.peel_to_commit_in_place().ok()?;
    let head_id = head_commit.id;
    let (ahead, behind) = get_ahead_behind(&repo, head_id, &state.branch);
    state.ahead = ahead;
    state.behind = behind;

    // Worktree detection
    detect_worktree(&repo, &mut state);

    // Stash count (file-based, same as Go)
    state.stash = count_stash(&repo);

    Some(state)
}

fn check_dirty(repo: &gix::Repository) -> bool {
    // Use gix status platform for a proper dirty check
    let status = match repo.status(gix::progress::Discard) {
        Ok(s) => s,
        Err(_) => return false,
    };

    let iter = match status.into_index_worktree_iter(None) {
        Ok(iter) => iter,
        Err(_) => return false,
    };

    // If there's any entry, the repo is dirty
    for item in iter {
        match item {
            Ok(_) => return true,
            Err(_) => continue,
        }
    }

    false
}

fn get_ahead_behind(
    repo: &gix::Repository,
    head_id: gix::ObjectId,
    branch_name: &str,
) -> (i32, i32) {
    // Read branch config for upstream
    let config = repo.config_snapshot();

    let remote_key = format!("branch.{}.remote", branch_name);
    let merge_key = format!("branch.{}.merge", branch_name);

    let remote: String = match config.string(&remote_key) {
        Some(v) => v.to_string(),
        None => return (0, 0),
    };
    let merge_ref: String = match config.string(&merge_key) {
        Some(v) => v.to_string(),
        None => return (0, 0),
    };

    // Convert merge ref (refs/heads/main) to remote tracking ref (refs/remotes/origin/main)
    let short_name = merge_ref.strip_prefix("refs/heads/").unwrap_or(&merge_ref);
    let upstream_ref = format!("refs/remotes/{}/{}", remote, short_name);

    let upstream_id = match repo.find_reference(&upstream_ref) {
        Ok(r) => match r.into_fully_peeled_id() {
            Ok(id) => id.detach(),
            Err(_) => return (0, 0),
        },
        Err(_) => return (0, 0),
    };

    if head_id == upstream_id {
        return (0, 0);
    }

    // Find merge base and count ahead/behind
    let merge_base = match repo.merge_base(head_id, upstream_id) {
        Ok(mb) => mb.into(),
        Err(_) => return (0, 0),
    };

    // Count ahead: commits from HEAD to merge base
    let ahead = count_commits(repo, head_id, merge_base);
    // Count behind: commits from upstream to merge base
    let behind = count_commits(repo, upstream_id, merge_base);

    (ahead, behind)
}

fn count_commits(repo: &gix::Repository, from: gix::ObjectId, to: gix::ObjectId) -> i32 {
    let platform = repo.rev_walk([from]);
    let iter = match platform.all() {
        Ok(iter) => iter,
        Err(_) => return 0,
    };

    let mut count = 0;
    let limit = 1000;
    for info in iter {
        let info = match info {
            Ok(i) => i,
            Err(_) => break,
        };
        if info.id == to {
            break;
        }
        count += 1;
        if count >= limit {
            break;
        }
    }
    count
}

fn detect_worktree(repo: &gix::Repository, state: &mut GitState) {
    // Check if this is a linked worktree
    let kind = repo.kind();
    let is_linked = matches!(kind, gix::repository::Kind::WorkTree { is_linked: true });

    if is_linked {
        state.in_worktree = true;

        // Try to extract worktree name from the worktree path
        if let Some(work_dir) = repo.work_dir() {
            let toplevel = work_dir.to_string_lossy().to_string();
            let toplevel = toplevel.trim_end_matches('/');

            // Check if path contains /.worktrees/
            if let Some(idx) = toplevel.find("/.worktrees/") {
                state.worktree_name = toplevel[idx + "/.worktrees/".len()..].to_string();
            } else {
                state.worktree_name = toplevel.to_string();
            }
        }
    }
}

fn count_stash(repo: &gix::Repository) -> i32 {
    let common_dir = repo.common_dir().to_path_buf();
    let stash_log = common_dir.join("logs").join("refs").join("stash");

    let content = match fs::read_to_string(&stash_log) {
        Ok(c) => c,
        Err(_) => return 0,
    };

    content.lines().filter(|l| !l.trim().is_empty()).count() as i32
}
