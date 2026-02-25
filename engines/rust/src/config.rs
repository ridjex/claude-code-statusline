use std::collections::HashMap;
use std::env;
use std::fs;
use std::path::PathBuf;

pub struct Config {
    pub show_model: bool,
    pub show_model_bars: bool,
    pub show_context: bool,
    pub show_cost: bool,
    pub show_duration: bool,
    pub show_git: bool,
    pub show_diff: bool,
    pub line2: bool,
    pub show_tokens: bool,
    pub show_speed: bool,
    pub show_cumulative: bool,
    pub no_color: bool,
    pub show_help: bool,
    pub internal_refresh_models: bool,
    pub internal_session_id: String,
    pub internal_transcript_path: String,
}

const ENV_KEYS: &[&str] = &[
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
];

pub fn load(args: &[String]) -> Config {
    let mut cfg = Config {
        show_model: true,
        show_model_bars: true,
        show_context: true,
        show_cost: true,
        show_duration: true,
        show_git: true,
        show_diff: true,
        line2: true,
        show_tokens: true,
        show_speed: true,
        show_cumulative: true,
        no_color: false,
        show_help: false,
        internal_refresh_models: false,
        internal_session_id: String::new(),
        internal_transcript_path: String::new(),
    };

    // Save env overrides before loading config file
    let mut env_overrides: HashMap<String, String> = HashMap::new();
    for &key in ENV_KEYS {
        if let Ok(val) = env::var(key) {
            env_overrides.insert(key.to_string(), val);
        }
    }

    // Load config file
    let cfg_path = env::var("HOME")
        .map(|h| PathBuf::from(h).join(".claude").join("statusline.env"))
        .unwrap_or_default();
    let file_vals = load_env_file(&cfg_path);

    // Merge: file < env
    let mut merged: HashMap<String, String> = HashMap::new();
    for (k, v) in &file_vals {
        merged.insert(k.clone(), v.clone());
    }
    for (k, v) in &env_overrides {
        merged.insert(k.clone(), v.clone());
    }

    // Apply merged values
    apply_bool(&merged, "STATUSLINE_SHOW_MODEL", &mut cfg.show_model);
    apply_bool(
        &merged,
        "STATUSLINE_SHOW_MODEL_BARS",
        &mut cfg.show_model_bars,
    );
    apply_bool(&merged, "STATUSLINE_SHOW_CONTEXT", &mut cfg.show_context);
    apply_bool(&merged, "STATUSLINE_SHOW_COST", &mut cfg.show_cost);
    apply_bool(&merged, "STATUSLINE_SHOW_DURATION", &mut cfg.show_duration);
    apply_bool(&merged, "STATUSLINE_SHOW_GIT", &mut cfg.show_git);
    apply_bool(&merged, "STATUSLINE_SHOW_DIFF", &mut cfg.show_diff);
    apply_bool(&merged, "STATUSLINE_LINE2", &mut cfg.line2);
    apply_bool(&merged, "STATUSLINE_SHOW_TOKENS", &mut cfg.show_tokens);
    apply_bool(&merged, "STATUSLINE_SHOW_SPEED", &mut cfg.show_speed);
    apply_bool(
        &merged,
        "STATUSLINE_SHOW_CUMULATIVE",
        &mut cfg.show_cumulative,
    );

    // CLI args (highest priority) — manual parsing, no clap
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--no-model" => cfg.show_model = false,
            "--no-model-bars" => cfg.show_model_bars = false,
            "--no-context" => cfg.show_context = false,
            "--no-cost" => cfg.show_cost = false,
            "--no-duration" => cfg.show_duration = false,
            "--no-git" => cfg.show_git = false,
            "--no-diff" => cfg.show_diff = false,
            "--no-line2" => cfg.line2 = false,
            "--no-tokens" => cfg.show_tokens = false,
            "--no-speed" => cfg.show_speed = false,
            "--no-cumulative" => cfg.show_cumulative = false,
            "--no-color" => cfg.no_color = true,
            "--help" => cfg.show_help = true,
            "--internal-refresh-models" => cfg.internal_refresh_models = true,
            "--session-id" => {
                i += 1;
                if i < args.len() {
                    cfg.internal_session_id = args[i].clone();
                }
            }
            "--transcript-path" => {
                i += 1;
                if i < args.len() {
                    cfg.internal_transcript_path = args[i].clone();
                }
            }
            _ => {}
        }
        i += 1;
    }

    // NO_COLOR env
    if env::var("NO_COLOR").is_ok() {
        cfg.no_color = true;
    }
    if env::var("STATUSLINE_NO_COLOR").is_ok() {
        cfg.no_color = true;
    }

    cfg
}

fn apply_bool(m: &HashMap<String, String>, key: &str, target: &mut bool) {
    if let Some(v) = m.get(key) {
        if v == "false" {
            *target = false;
        }
    }
}

fn load_env_file(path: &PathBuf) -> HashMap<String, String> {
    let mut vals = HashMap::new();
    let content = match fs::read_to_string(path) {
        Ok(c) => c,
        Err(_) => return vals,
    };
    for line in content.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if let Some(idx) = line.find('=') {
            let k = line[..idx].trim().to_string();
            let v = line[idx + 1..].trim().to_string();
            vals.insert(k, v);
        }
    }
    vals
}
