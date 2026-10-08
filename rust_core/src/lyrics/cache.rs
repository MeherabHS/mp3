use crate::error::{CoreError, Result};
use crate::lyrics::parser::LrcParser;
use crate::models::lyrics::SyncedLyrics;
use std::fs;
use std::path::Path;

pub struct LyricsCache;

impl LyricsCache {
    pub fn load_from_file<P: AsRef<Path>>(track_id: &str, file_path: P) -> Result<SyncedLyrics> {
        let content = fs::read_to_string(file_path).map_err(CoreError::Io)?;
        LrcParser::parse(track_id, &content)
    }

    pub fn save_to_file<P: AsRef<Path>>(file_path: P, content: &str) -> Result<()> {
        if let Some(parent) = file_path.as_ref().parent() {
            fs::create_dir_all(parent).map_err(CoreError::Io)?;
        }
        fs::write(file_path, content).map_err(CoreError::Io)
    }
}
