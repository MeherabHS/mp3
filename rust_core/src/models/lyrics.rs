use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LyricWord {
    pub start_ms: i64,
    pub end_ms: i64,
    pub word: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LyricLine {
    pub start_ms: i64,
    pub end_ms: Option<i64>,
    pub text: String,
    pub words: Vec<LyricWord>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SyncedLyrics {
    pub track_id: String,
    pub is_synchronized: bool,
    pub is_word_synced: bool,
    pub offset_ms: i64,
    pub lines: Vec<LyricLine>,
}

impl SyncedLyrics {
    pub fn empty(track_id: &str) -> Self {
        Self {
            track_id: track_id.to_string(),
            is_synchronized: false,
            is_word_synced: false,
            offset_ms: 0,
            lines: Vec::new(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LyricsSyncState {
    pub track_id: String,
    pub active_line_index: Option<usize>,
    pub active_word_index: Option<usize>,
    pub line_progress: f32, // 0.0 to 1.0 within current line if duration is known
    pub active_line_text: Option<String>,
    pub previous_line_text: Option<String>,
    pub next_line_text: Option<String>,
}
