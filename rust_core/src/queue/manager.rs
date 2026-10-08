use crate::models::player::RepeatMode;
use crate::models::track::Track;

#[derive(Debug, Clone, Default)]
pub struct QueueManager {
    tracks: Vec<Track>,
    current_index: Option<usize>,
    shuffle: bool,
    repeat_mode: RepeatMode,
}

impl QueueManager {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn set_queue(&mut self, tracks: Vec<Track>, start_index: usize) {
        self.tracks = tracks;
        if !self.tracks.is_empty() && start_index < self.tracks.len() {
            self.current_index = Some(start_index);
        } else if !self.tracks.is_empty() {
            self.current_index = Some(0);
        } else {
            self.current_index = None;
        }
    }

    pub fn add_to_queue(&mut self, track: Track) {
        self.tracks.push(track);
        if self.current_index.is_none() && !self.tracks.is_empty() {
            self.current_index = Some(0);
        }
    }

    pub fn play_next(&mut self, track: Track) {
        if let Some(idx) = self.current_index {
            self.tracks.insert(idx + 1, track);
        } else {
            self.tracks.push(track);
            self.current_index = Some(0);
        }
    }

    pub fn remove_at(&mut self, index: usize) -> Option<Track> {
        if index < self.tracks.len() {
            let removed = self.tracks.remove(index);
            if let Some(cur) = self.current_index {
                if cur == index {
                    if self.tracks.is_empty() {
                        self.current_index = None;
                    } else if cur >= self.tracks.len() {
                        self.current_index = Some(self.tracks.len() - 1);
                    }
                } else if cur > index {
                    self.current_index = Some(cur - 1);
                }
            }
            Some(removed)
        } else {
            None
        }
    }

    pub fn clear(&mut self) {
        self.tracks.clear();
        self.current_index = None;
    }

    pub fn current_track(&self) -> Option<&Track> {
        self.current_index.and_then(|idx| self.tracks.get(idx))
    }

    pub fn current_index(&self) -> Option<usize> {
        self.current_index
    }

    pub fn tracks(&self) -> &[Track] {
        &self.tracks
    }

    pub fn next(&mut self) -> Option<&Track> {
        if self.tracks.is_empty() {
            return None;
        }

        match self.repeat_mode {
            RepeatMode::One => self.current_track(),
            RepeatMode::All => {
                if let Some(idx) = self.current_index {
                    self.current_index = Some((idx + 1) % self.tracks.len());
                } else {
                    self.current_index = Some(0);
                }
                self.current_track()
            }
            RepeatMode::Off => {
                if let Some(idx) = self.current_index {
                    if idx + 1 < self.tracks.len() {
                        self.current_index = Some(idx + 1);
                        self.current_track()
                    } else {
                        None
                    }
                } else {
                    self.current_index = Some(0);
                    self.current_track()
                }
            }
        }
    }

    pub fn previous(&mut self) -> Option<&Track> {
        if self.tracks.is_empty() {
            return None;
        }

        match self.repeat_mode {
            RepeatMode::One => self.current_track(),
            RepeatMode::All => {
                if let Some(idx) = self.current_index {
                    if idx == 0 {
                        self.current_index = Some(self.tracks.len() - 1);
                    } else {
                        self.current_index = Some(idx - 1);
                    }
                } else {
                    self.current_index = Some(0);
                }
                self.current_track()
            }
            RepeatMode::Off => {
                if let Some(idx) = self.current_index {
                    if idx > 0 {
                        self.current_index = Some(idx - 1);
                        self.current_track()
                    } else {
                        self.current_track()
                    }
                } else {
                    self.current_index = Some(0);
                    self.current_track()
                }
            }
        }
    }

    pub fn set_shuffle(&mut self, shuffle: bool) {
        self.shuffle = shuffle;
    }

    pub fn is_shuffle(&self) -> bool {
        self.shuffle
    }

    pub fn set_repeat_mode(&mut self, mode: RepeatMode) {
        self.repeat_mode = mode;
    }

    pub fn repeat_mode(&self) -> RepeatMode {
        self.repeat_mode
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_track(id: &str) -> Track {
        Track {
            id: id.to_string(),
            file_path: format!("/{}.flac", id),
            title: format!("Track {}", id),
            artist: "Artist".to_string(),
            album: "Album".to_string(),
            album_artist: None,
            genre: None,
            year: None,
            track_number: None,
            disc_number: None,
            duration_ms: 180000,
            codec: "FLAC".to_string(),
            container: "FLAC".to_string(),
            bitrate_kbps: Some(1411),
            sample_rate_hz: Some(44100),
            bit_depth: Some(16),
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
    fn test_queue_navigation() {
        let mut q = QueueManager::new();
        q.set_queue(vec![make_track("1"), make_track("2"), make_track("3")], 0);

        assert_eq!(q.current_track().unwrap().id, "1");
        assert_eq!(q.next().unwrap().id, "2");
        assert_eq!(q.next().unwrap().id, "3");
        assert!(q.next().is_none()); // Repeat off

        q.set_repeat_mode(RepeatMode::All);
        assert_eq!(q.next().unwrap().id, "1"); // Wrap around

        assert_eq!(q.previous().unwrap().id, "3");
    }
}
