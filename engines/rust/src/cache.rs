use md5::{Digest, Md5};
use serde::Deserialize;
use std::env;
use std::fs;
use std::path::PathBuf;

/// Return the statusline cache directory.
pub fn cache_dir() -> PathBuf {
    if let Ok(xdg) = env::var("XDG_CACHE_HOME") {
        PathBuf::from(xdg).join("claude-code-statusline")
    } else {
        let home = env::var("HOME").unwrap_or_default();
        PathBuf::from(home)
            .join(".cache")
            .join("claude-code-statusline")
    }
}

/// Compute the 8-char hex hash for a project directory.
/// Matches bash: echo "$slug" | md5 (note: newline included).
pub fn project_hash(dir: &str) -> String {
    let slug = dir.strip_prefix('/').unwrap_or(dir).replace('/', "-");
    let mut hasher = Md5::new();
    hasher.update(slug.as_bytes());
    hasher.update(b"\n");
    let result = hasher.finalize();
    format!("{:x}", result)[..8].to_string()
}

#[derive(Deserialize)]
struct ModelEntry {
    model: String,
    #[serde(rename = "in")]
    in_tokens: i64,
    out: i64,
}

#[derive(Deserialize)]
struct ModelsCache {
    models: Vec<ModelEntry>,
}

pub struct ModelStats {
    pub opus_in: i64,
    pub opus_out: i64,
    pub sonnet_in: i64,
    pub sonnet_out: i64,
    pub haiku_in: i64,
    pub haiku_out: i64,
}

/// Read the per-session model cache and aggregate by model family.
pub fn read_models(session_id: &str) -> Option<ModelStats> {
    if session_id.is_empty() {
        return None;
    }
    let cache_file = cache_dir().join(format!("models-{}.json", session_id));
    let data = fs::read_to_string(cache_file).ok()?;
    let mc: ModelsCache = serde_json::from_str(&data).ok()?;

    let mut stats = ModelStats {
        opus_in: 0,
        opus_out: 0,
        sonnet_in: 0,
        sonnet_out: 0,
        haiku_in: 0,
        haiku_out: 0,
    };

    for m in &mc.models {
        let name = m.model.to_lowercase();
        if name.contains("opus") {
            stats.opus_in += m.in_tokens;
            stats.opus_out += m.out;
        } else if name.contains("sonnet") {
            stats.sonnet_in += m.in_tokens;
            stats.sonnet_out += m.out;
        } else if name.contains("haiku") {
            stats.haiku_in += m.in_tokens;
            stats.haiku_out += m.out;
        }
    }

    Some(stats)
}

#[derive(Deserialize)]
struct CumulativePeriod {
    cost: f64,
}

#[derive(Deserialize)]
struct CumulativeCache {
    d1: CumulativePeriod,
    d7: CumulativePeriod,
    d30: CumulativePeriod,
}

pub struct CumulativeStats {
    pub d1: f64,
    pub d7: f64,
    pub d30: f64,
}

/// Read project and global cumulative caches.
pub fn read_cumulative(project_dir: &str) -> (Option<CumulativeStats>, Option<CumulativeStats>) {
    let cd = cache_dir();
    let proj = if !project_dir.is_empty() {
        let hash = project_hash(project_dir);
        let proj_file = cd.join(format!("proj-{}.json", hash));
        read_cumulative_file(&proj_file)
    } else {
        None
    };

    let all_file = cd.join("all.json");
    let all = read_cumulative_file(&all_file);

    (proj, all)
}

fn read_cumulative_file(path: &PathBuf) -> Option<CumulativeStats> {
    let data = fs::read_to_string(path).ok()?;
    let cc: CumulativeCache = serde_json::from_str(&data).ok()?;
    if cc.d1.cost == 0.0 && cc.d7.cost == 0.0 && cc.d30.cost == 0.0 {
        return None;
    }
    Some(CumulativeStats {
        d1: cc.d1.cost,
        d7: cc.d7.cost,
        d30: cc.d30.cost,
    })
}
