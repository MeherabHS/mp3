use serde::{Deserialize, Serialize};
use super::quality::{AudioQuality, OutputStatus};
use super::track::Track;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RepeatMode {
    Off,
    All,
    One,
}

impl Default for RepeatMode {
    fn default() -> Self {
        RepeatMode::Off
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PlaybackState {
    Playing,
    Paused,
    Stopped,
    Buffering,
    Error,
}

impl Default for PlaybackState {
    fn default() -> Self {
        PlaybackState::Stopped
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PlayerState {
    pub current_track: Option<Track>,
    pub position_ms: u64,
    pub duration_ms: u64,
    pub is_playing: bool,
    pub playback_state: PlaybackState,
    pub queue: Vec<Track>,
    pub queue_index: Option<usize>,
    pub shuffle: bool,
    pub repeat_mode: RepeatMode,
    pub volume: f32,
    pub output_status: OutputStatus,
    pub audio_quality: AudioQuality,
}

impl Default for PlayerState {
    fn default() -> Self {
        Self {
            current_track: None,
            position_ms: 0,
            duration_ms: 0,
            is_playing: false,
            playback_state: PlaybackState::Stopped,
            queue: Vec::new(),
            queue_index: None,
            shuffle: false,
            repeat_mode: RepeatMode::Off,
            volume: 1.0,
            output_status: OutputStatus::default(),
            audio_quality: AudioQuality::default(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", content = "payload")]
pub enum CoreEvent {
    PlaybackChanged(PlayerState),
    PositionTick { position_ms: u64, duration_ms: u64 },
    OutputChanged(OutputStatus),
    LyricsChanged { track_id: String },
    LibraryChanged,
    DownloadProgress { job_id: String, progress: f32, status: String },
    DownloadCompleted { job_id: String, track_id: String },
    DownloadFailed { job_id: String, error: String },
}
