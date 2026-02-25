use crate::cache;
use std::env;
use std::fs;
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

/// Run cumulative-stats.sh in the background (detached).
pub fn spawn_cumulative_stats(project_dir: &str) {
    if project_dir.is_empty() {
        return;
    }

    let exe = match env::current_exe() {
        Ok(e) => e,
        Err(_) => return,
    };
    let self_dir = match exe.parent() {
        Some(d) => d.to_path_buf(),
        None => return,
    };

    let candidates = [
        self_dir.join("..").join("bash").join("cumulative-stats.sh"),
        self_dir.join("cumulative-stats.sh"),
        PathBuf::from(env::var("HOME").unwrap_or_default())
            .join(".claude")
            .join("cumulative-stats.sh"),
    ];

    let mut script = None;
    for c in &candidates {
        if let Ok(abs) = fs::canonicalize(c) {
            if abs.is_file() {
                script = Some(abs);
                break;
            }
        }
    }

    let script = match script {
        Some(s) => s,
        None => return,
    };

    let mut cmd = Command::new(&script);
    cmd.arg(project_dir);
    cmd.stdout(Stdio::null());
    cmd.stderr(Stdio::null());
    cmd.stdin(Stdio::null());
    unsafe {
        cmd.pre_exec(|| {
            libc::setpgid(0, 0);
            Ok(())
        });
    }
    let _ = cmd.spawn();
}

/// Re-execute the binary with --internal-refresh-models to update the model cache.
pub fn spawn_model_refresh(session_id: &str, transcript_path: &str) {
    if session_id.is_empty() || transcript_path.is_empty() {
        return;
    }

    let exe = match env::current_exe() {
        Ok(e) => e,
        Err(_) => return,
    };

    let mut cmd = Command::new(&exe);
    cmd.args([
        "--internal-refresh-models",
        "--session-id",
        session_id,
        "--transcript-path",
        transcript_path,
    ]);
    cmd.stdin(Stdio::null());
    cmd.stdout(Stdio::null());
    cmd.stderr(Stdio::null());
    unsafe {
        cmd.pre_exec(|| {
            libc::setpgid(0, 0);
            Ok(())
        });
    }
    let _ = cmd.spawn();
}

/// Parse JSONL transcripts and write the model cache (internal mode).
pub fn refresh_model_cache(session_id: &str, transcript_path: &str) {
    if session_id.is_empty() || transcript_path.is_empty() {
        return;
    }

    let cache_dir = cache::cache_dir();
    let _ = fs::create_dir_all(&cache_dir);

    // Collect files to scan
    let mut files = vec![PathBuf::from(transcript_path)];
    let subagent_dir = Path::new(transcript_path)
        .parent()
        .map(|p| p.join(session_id).join("subagents"))
        .unwrap_or_default();

    if let Ok(entries) = fs::read_dir(&subagent_dir) {
        for entry in entries.flatten() {
            let name = entry.file_name();
            if name.to_string_lossy().ends_with(".jsonl") {
                files.push(entry.path());
            }
        }
    }

    #[derive(serde::Serialize)]
    struct ModelAgg {
        model: String,
        #[serde(rename = "in")]
        in_tokens: i64,
        out: i64,
    }

    let mut models: std::collections::HashMap<String, ModelAgg> = std::collections::HashMap::new();

    for fpath in &files {
        let data = match fs::read_to_string(fpath) {
            Ok(d) => d,
            Err(_) => continue,
        };
        for line in data.lines() {
            let line = line.trim();
            if line.is_empty() {
                continue;
            }
            let entry: serde_json::Value = match serde_json::from_str(line) {
                Ok(v) => v,
                Err(_) => continue,
            };
            if entry.get("type").and_then(|t| t.as_str()) != Some("assistant") {
                continue;
            }
            let msg = match entry.get("message") {
                Some(m) => m,
                None => continue,
            };
            let name = match msg.get("model").and_then(|m| m.as_str()) {
                Some(n) if n.starts_with("claude-") => n.to_string(),
                _ => continue,
            };
            let usage = match msg.get("usage") {
                Some(u) => u,
                None => continue,
            };
            let input = usage
                .get("input_tokens")
                .and_then(|v| v.as_i64())
                .unwrap_or(0)
                + usage
                    .get("cache_read_input_tokens")
                    .and_then(|v| v.as_i64())
                    .unwrap_or(0)
                + usage
                    .get("cache_creation_input_tokens")
                    .and_then(|v| v.as_i64())
                    .unwrap_or(0);
            let output = usage
                .get("output_tokens")
                .and_then(|v| v.as_i64())
                .unwrap_or(0);

            let agg = models.entry(name.clone()).or_insert(ModelAgg {
                model: name,
                in_tokens: 0,
                out: 0,
            });
            agg.in_tokens += input;
            agg.out += output;
        }
    }

    #[derive(serde::Serialize)]
    struct Result {
        models: Vec<ModelAgg>,
    }

    let result = Result {
        models: models.into_values().collect(),
    };

    let data = match serde_json::to_vec(&result) {
        Ok(d) => d,
        Err(_) => return,
    };

    let cache_file = cache_dir.join(format!("models-{}.json", session_id));
    let tmp = cache_file.with_extension("json.tmp");
    if fs::write(&tmp, &data).is_ok() {
        let _ = fs::rename(&tmp, &cache_file);
    }
}
