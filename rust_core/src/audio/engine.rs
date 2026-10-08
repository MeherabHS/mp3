use crate::database::Database;
use crate::error::{CoreError, Result};
use crate::lyrics::{LyricsCache, LyricsSynchronizer};
use crate::models::lyrics::{LyricsSyncState, SyncedLyrics};
use crate::models::player::{PlaybackState, PlayerState, RepeatMode};
use crate::models::quality::OutputStatus;
use crate::models::track::Track;
use crate::queue::QueueManager;
use crate::storage::StorageManager;
use parking_lot::Mutex;
use std::sync::Arc;

pub struct AudioEngineCore {
    db: Arc<Database>,
    storage: Arc<StorageManager>,
    queue: Mutex<QueueManager>,
    state: Mutex<PlayerState>,
    current_lyrics: Mutex<Option<SyncedLyrics>>,
}

impl AudioEngineCore {
    pub fn new(db: Arc<Database>, storage: Arc<StorageManager>) -> Self {
        Self {
            db,
            storage,
            queue: Mutex::new(QueueManager::new()),
            state: Mutex::new(PlayerState::default()),
            current_lyrics: Mutex::new(None),
        }
    }

    pub fn set_queue(&self, tracks: Vec<Track>, start_index: usize) -> Result<PlayerState> {
        let current_track = {
            let mut q = self.queue.lock();
            q.set_queue(tracks, start_index);
            q.current_track().cloned()
        };

        if let Some(track) = current_track {
            self.load_track_internal(&track)?;
        }
        Ok(self.get_state())
    }

    pub fn load_track(&self, track_id: &str) -> Result<PlayerState> {
        let track = self
            .db
            .get_track(track_id)?
            .ok_or_else(|| CoreError::NotFound(format!("Track not found: {}", track_id)))?;

        self.load_track_internal(&track)?;
        Ok(self.get_state())
    }

    fn load_track_internal(&self, track: &Track) -> Result<()> {
        let (q_tracks, q_index) = {
            let q = self.queue.lock();
            (q.tracks().to_vec(), q.current_index())
        };

        let lyrics_path = track
            .lyrics_path
            .clone()
            .unwrap_or_else(|| self.storage.get_lyrics_path_for_track(&track.id).to_string_lossy().to_string());

        let loaded_lyrics = if std::path::Path::new(&lyrics_path).exists() {
            LyricsCache::load_from_file(&track.id, &lyrics_path).ok()
        } else {
            None
        };

        {
            let mut state = self.state.lock();
            state.current_track = Some(track.clone());
            state.position_ms = 0;
            state.duration_ms = track.duration_ms;
            state.playback_state = PlaybackState::Paused;
            state.is_playing = false;

            // Update AudioQuality model
            state.audio_quality.container = Some(track.container.clone());
            state.audio_quality.codec = Some(track.codec.clone());
            state.audio_quality.bitrate_kbps = track.bitrate_kbps;
            state.audio_quality.sample_rate_hz = track.sample_rate_hz;
            state.audio_quality.bit_depth = track.bit_depth;
            state.audio_quality.channels = track.channels;
            state.audio_quality.lossless = Some(track.lossless);
            state.audio_quality.pcm_sample_rate_hz = track.sample_rate_hz;
            state.audio_quality.pcm_bit_depth = track.bit_depth;

            // Sync queue current state
            state.queue = q_tracks;
            state.queue_index = q_index;
        }

        *self.current_lyrics.lock() = loaded_lyrics;

        Ok(())
    }

    pub fn play(&self) -> Result<PlayerState> {
        let mut state = self.state.lock();
        if state.current_track.is_some() {
            state.is_playing = true;
            state.playback_state = PlaybackState::Playing;
        }
        Ok(state.clone())
    }

    pub fn pause(&self) -> Result<PlayerState> {
        let mut state = self.state.lock();
        state.is_playing = false;
        state.playback_state = PlaybackState::Paused;
        Ok(state.clone())
    }

    pub fn seek(&self, position_ms: u64) -> Result<LyricsSyncState> {
        {
            let mut state = self.state.lock();
            state.position_ms = position_ms;
        }
        Ok(self.sync_lyrics_at_position(position_ms))
    }

    pub fn next(&self) -> Result<Option<PlayerState>> {
        let next_track = {
            let mut q = self.queue.lock();
            q.next().cloned()
        };

        if let Some(track) = next_track {
            self.load_track_internal(&track)?;
            self.play()?;
            Ok(Some(self.get_state()))
        } else {
            let mut state = self.state.lock();
            state.is_playing = false;
            state.playback_state = PlaybackState::Stopped;
            Ok(None)
        }
    }

    pub fn previous(&self) -> Result<Option<PlayerState>> {
        let prev_track = {
            let mut q = self.queue.lock();
            q.previous().cloned()
        };

        if let Some(track) = prev_track {
            self.load_track_internal(&track)?;
            self.play()?;
            Ok(Some(self.get_state()))
        } else {
            Ok(None)
        }
    }

    pub fn update_position(&self, position_ms: u64) -> LyricsSyncState {
        {
            let mut state = self.state.lock();
            state.position_ms = position_ms;
        }
        self.sync_lyrics_at_position(position_ms)
    }

    pub fn update_output_status(&self, output_status: OutputStatus) -> Result<PlayerState> {
        let mut state = self.state.lock();
        state.output_status = output_status.clone();

        state.audio_quality.output_type = output_status.output_type;
        state.audio_quality.output_device_name = Some(output_status.device_name);
        state.audio_quality.output_codec = output_status.codec;
        state.audio_quality.output_bitrate_kbps = output_status.bitrate_kbps;
        state.audio_quality.output_sample_rate_hz = output_status.sample_rate_hz;
        state.audio_quality.output_bit_depth = output_status.bit_depth;

        Ok(state.clone())
    }

    pub fn get_state(&self) -> PlayerState {
        self.state.lock().clone()
    }

    pub fn set_shuffle(&self, shuffle: bool) -> PlayerState {
        self.queue.lock().set_shuffle(shuffle);
        let mut state = self.state.lock();
        state.shuffle = shuffle;
        state.clone()
    }

    pub fn set_repeat_mode(&self, mode: RepeatMode) -> PlayerState {
        self.queue.lock().set_repeat_mode(mode);
        let mut state = self.state.lock();
        state.repeat_mode = mode;
        state.clone()
    }

    pub fn get_lyrics(&self, track_id: &str) -> Result<SyncedLyrics> {
        if let Some(ref lyrics) = *self.current_lyrics.lock() {
            if lyrics.track_id == track_id {
                return Ok(lyrics.clone());
            }
        }
        let lyrics_path = self.storage.get_lyrics_path_for_track(track_id);
        if lyrics_path.exists() {
            LyricsCache::load_from_file(track_id, lyrics_path)
        } else {
            Ok(SyncedLyrics::empty(track_id))
        }
    }

    pub fn sync_lyrics_at_position(&self, position_ms: u64) -> LyricsSyncState {
        let lyrics_guard = self.current_lyrics.lock();
        if let Some(ref lyrics) = *lyrics_guard {
            LyricsSynchronizer::find_sync_state(lyrics, position_ms as i64)
        } else {
            LyricsSyncState {
                track_id: String::new(),
                active_line_index: None,
                active_word_index: None,
                line_progress: 0.0,
                active_line_text: None,
                previous_line_text: None,
                next_line_text: None,
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn create_sample_track() -> Track {
        Track {
            id: "track_sample".to_string(),
            file_path: "/sdcard/ODESZA.flac".to_string(),
            title: "A Moment Apart".to_string(),
            artist: "ODESZA".to_string(),
            album: "A Moment Apart".to_string(),
            album_artist: Some("ODESZA".to_string()),
            genre: Some("Electronic".to_string()),
            year: Some(2017),
            track_number: Some(1),
            disc_number: Some(1),
            duration_ms: 257000,
            codec: "FLAC".to_string(),
            container: "FLAC".to_string(),
            bitrate_kbps: Some(1411),
            sample_rate_hz: Some(48000),
            bit_depth: Some(24),
            channels: Some(2),
            lossless: true,
            artwork_path: None,
            lyrics_path: None,
            is_favorite: false,
            play_count: 0,
            last_played_at: None,
            created_at: 0,
        }
    }

    #[test]
    fn test_engine_state_and_output_update() {
        let internal = TempDir::new().unwrap();
        let sd = TempDir::new().unwrap();
        let db = Arc::new(Database::in_memory().unwrap());
        let storage = Arc::new(StorageManager::new(internal.path(), sd.path()).unwrap());

        let engine = AudioEngineCore::new(db.clone(), storage);
        let track = create_sample_track();
        db.insert_or_update_track(&track).unwrap();

        let state = engine.set_queue(vec![track], 0).unwrap();
        assert_eq!(state.current_track.unwrap().title, "A Moment Apart");
        assert_eq!(state.audio_quality.codec, Some("FLAC".to_string()));
        assert_eq!(state.audio_quality.bit_depth, Some(24));

        let output = OutputStatus {
            output_type: crate::models::quality::OutputType::Bluetooth,
            device_name: "WH-1000XM5".to_string(),
            codec: Some("LDAC".to_string()),
            bitrate_kbps: Some(990),
            sample_rate_hz: Some(48000),
            bit_depth: Some(24),
            is_connected: true,
        };

        let updated_state = engine.update_output_status(output).unwrap();
        assert_eq!(
            updated_state.output_status.device_name,
            "WH-1000XM5"
        );
        assert_eq!(
            updated_state.audio_quality.output_codec,
            Some("LDAC".to_string())
        );
        assert_eq!(
            updated_state.audio_quality.output_bitrate_kbps,
            Some(990)
        );
    }
}
