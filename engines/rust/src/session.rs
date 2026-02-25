use serde::Deserialize;
use std::io::Read;

#[allow(dead_code)]
#[derive(Deserialize, Default)]
pub struct Model {
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub display_name: String,
}

#[allow(dead_code)]
#[derive(Deserialize, Default)]
pub struct ContextWindow {
    #[serde(default)]
    pub used_percentage: f64,
    #[serde(default)]
    pub context_window_size: f64,
    #[serde(default)]
    pub total_input_tokens: f64,
    #[serde(default)]
    pub total_output_tokens: f64,
}

#[derive(Deserialize, Default)]
pub struct Cost {
    #[serde(default)]
    pub total_cost_usd: f64,
    #[serde(default)]
    pub total_duration_ms: f64,
    #[serde(default)]
    pub total_api_duration_ms: f64,
    #[serde(default)]
    pub total_lines_added: f64,
    #[serde(default)]
    pub total_lines_removed: f64,
}

#[allow(dead_code)]
#[derive(Deserialize, Default)]
pub struct Workspace {
    #[serde(default)]
    pub project_dir: String,
    #[serde(default)]
    pub current_dir: String,
}

#[allow(dead_code)]
#[derive(Deserialize, Default)]
pub struct Session {
    #[serde(default)]
    pub cwd: String,
    #[serde(default)]
    pub session_id: String,
    #[serde(default)]
    pub model: Model,
    #[serde(default)]
    pub context_window: ContextWindow,
    #[serde(default)]
    pub cost: Cost,
    #[serde(default)]
    pub version: String,
    #[serde(default)]
    pub workspace: Workspace,
    #[serde(default)]
    pub transcript_path: String,
}

pub fn parse(mut reader: impl Read) -> Session {
    let mut buf = Vec::new();
    if reader.read_to_end(&mut buf).is_err() {
        return Session::default();
    }
    serde_json::from_slice(&buf).unwrap_or_default()
}
