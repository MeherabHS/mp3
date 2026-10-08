use crate::error::{CoreError, Result};
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone)]
pub struct StorageManager {
    internal_app_dir: PathBuf,
    sd_card_dir: PathBuf,
}

impl StorageManager {
    pub fn new<P1: AsRef<Path>, P2: AsRef<Path>>(
        internal_app_dir: P1,
        sd_card_dir: P2,
    ) -> Result<Self> {
        let manager = Self {
            internal_app_dir: internal_app_dir.as_ref().to_path_buf(),
            sd_card_dir: sd_card_dir.as_ref().to_path_buf(),
        };
        manager.ensure_directories()?;
        Ok(manager)
    }

    pub fn ensure_directories(&self) -> Result<()> {
        // Internal directories (DB & private settings)
        fs::create_dir_all(&self.internal_app_dir).map_err(CoreError::Io)?;

        // SD-Card / External directories
        fs::create_dir_all(self.get_audio_dir()).map_err(CoreError::Io)?;
        fs::create_dir_all(self.get_artwork_dir(64)).map_err(CoreError::Io)?;
        fs::create_dir_all(self.get_artwork_dir(200)).map_err(CoreError::Io)?;
        fs::create_dir_all(self.get_artwork_dir(500)).map_err(CoreError::Io)?;
        fs::create_dir_all(self.get_lyrics_dir()).map_err(CoreError::Io)?;
        fs::create_dir_all(self.get_cache_dir()).map_err(CoreError::Io)?;

        Ok(())
    }

    pub fn get_database_path(&self) -> PathBuf {
        self.internal_app_dir.join("hifi_music.db")
    }

    pub fn get_audio_dir(&self) -> PathBuf {
        self.sd_card_dir.join("MusicPlayer").join("Audio")
    }

    pub fn get_artwork_dir(&self, size: u32) -> PathBuf {
        self.sd_card_dir
            .join("MusicPlayer")
            .join("Artwork")
            .join(size.to_string())
    }

    pub fn get_lyrics_dir(&self) -> PathBuf {
        self.sd_card_dir.join("MusicPlayer").join("Lyrics")
    }

    pub fn get_cache_dir(&self) -> PathBuf {
        self.sd_card_dir.join("MusicPlayer").join("Cache")
    }

    pub fn get_lyrics_path_for_track(&self, track_id: &str) -> PathBuf {
        self.get_lyrics_dir().join(format!("{}.lrc", track_id))
    }

    pub fn get_artwork_path_for_track(&self, track_id: &str, size: u32) -> PathBuf {
        self.get_artwork_dir(size).join(format!("{}.webp", track_id))
    }

    pub fn sanitize_filename(name: &str) -> String {
        let invalid_chars = ['/', '\\', '?', '%', '*', ':', '|', '"', '<', '>', '.', ' '];
        let mut clean: String = name
            .chars()
            .map(|c| if invalid_chars.contains(&c) { '_' } else { c })
            .collect();
        if clean.is_empty() {
            clean = "unknown".to_string();
        }
        clean
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn test_storage_manager_paths() {
        let internal = TempDir::new().unwrap();
        let sd = TempDir::new().unwrap();

        let manager = StorageManager::new(internal.path(), sd.path()).unwrap();

        assert!(manager.get_database_path().ends_with("hifi_music.db"));
        assert!(manager.get_audio_dir().exists());
        assert!(manager.get_artwork_dir(64).exists());
        assert!(manager.get_artwork_dir(200).exists());
        assert!(manager.get_artwork_dir(500).exists());
        assert!(manager.get_lyrics_dir().exists());

        let sanitized = StorageManager::sanitize_filename("ODESZA / A Moment Apart: Track * 1?");
        assert!(!sanitized.contains('/'));
        assert!(!sanitized.contains(':'));
        assert!(!sanitized.contains('*'));
    }
}
