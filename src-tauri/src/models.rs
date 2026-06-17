// Serde models mirroring the TypeScript contracts (src/app/bridge.ts). Kept in
// lockstep so `invoke` round-trips cleanly between the web UI and the Rust core.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModelSettings {
    pub kind: String,
    pub model: String,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub base_url: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppSettings {
    pub model: ModelSettings,
    #[serde(rename = "briefTime")]
    pub brief_time: String,
    pub onboarded: bool,
}

impl Default for AppSettings {
    fn default() -> Self {
        AppSettings {
            model: ModelSettings {
                kind: "openrouter".into(),
                model: "anthropic/claude-sonnet-4-6".into(),
                base_url: None,
            },
            brief_time: "07:00".into(),
            onboarded: false,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Account {
    pub id: String,
    pub label: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Connection {
    pub id: String,
    #[serde(rename = "connectorId")]
    pub connector_id: String,
    pub account: Account,
    pub space: String,
    pub enabled: bool,
    #[serde(rename = "createdAt")]
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StoredBrief {
    pub date: String,
    #[serde(rename = "generatedAt")]
    pub generated_at: String,
    pub html: String,
    pub json: String,
}
