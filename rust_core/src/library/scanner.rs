use crate::database::Database;
use crate::error::Result;
use crate::metadata::{ArtworkProcessor, MetadataParser};
use crate::models::track::Track;
use crate::storage::StorageManager;
use std::fs;
use std::path::Path;

pub struct LibraryScanner;

impl LibraryScanner {
    pub const SUPPORTED_EXTENSIONS: &'static [&'static str] =
        &["flac", "wav", "mp3", "m4a", "mp4", "alac", "opus", "ogg", "aac", "webm"];

    /// Scan a single audio file and index it into the database safely.
    pub fn scan_file<P: AsRef<Path>>(
        db: &Database,
        storage: &StorageManager,
        file_path: P,
    ) -> Result<Option<Track>> {
        let path = file_path.as_ref();
        if !path.exists() || !path.is_file() {
            return Ok(None);
        }

        // Safety catch around file metadata parsing
        let parse_result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            MetadataParser::parse_file(path)
        }));

        let mut parsed = match parse_result {
            Ok(Ok(p)) => p,
            _ => return Ok(None),
        };

        // If artwork is embedded, process and cache it safely
        if let Some(art_bytes) = parsed.embedded_artwork {
            let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                if let Ok(processed_art) =
                    ArtworkProcessor::process_and_cache(storage, &parsed.track.id, &art_bytes)
                {
                    parsed.track.artwork_path = Some(processed_art.path_500);
                }
            }));
        }

        // Check for sidecar lyrics (.lrc next to audio or in central lyrics dir)
        let sidecar_lrc = path.with_extension("lrc");
        let central_lrc = storage.get_lyrics_path_for_track(&parsed.track.id);

        if sidecar_lrc.exists() {
            parsed.track.lyrics_path = Some(sidecar_lrc.to_string_lossy().to_string());
        } else if central_lrc.exists() {
            parsed.track.lyrics_path = Some(central_lrc.to_string_lossy().to_string());
        }

        let _ = db.insert_or_update_track(&parsed.track);
        Ok(Some(parsed.track))
    }

    /// Scan a directory recursively and index all discovered audio files.
    pub fn scan_directory<P: AsRef<Path>>(
        db: &Database,
        storage: &StorageManager,
        dir_path: P,
    ) -> Result<usize> {
        let mut count = 0;
        let mut audio_files = Vec::new();
        Self::collect_audio_files_safe(dir_path.as_ref(), &mut audio_files, 0)?;

        for file_path in audio_files {
            if let Ok(Some(_)) = Self::scan_file(db, storage, &file_path) {
                count += 1;
            }
        }

        Ok(count)
    }

    fn collect_audio_files_safe(
        dir: &Path,
        files: &mut Vec<std::path::PathBuf>,
        depth: usize,
    ) -> Result<()> {
        if depth > 6 || !dir.exists() || !dir.is_dir() {
            return Ok(());
        }

        let entries = match fs::read_dir(dir) {
            Ok(e) => e,
            Err(_) => return Ok(()),
        };

        for entry in entries.flatten() {
            let path = entry.path();
            let file_name = path
                .file_name()
                .and_then(|n| n.to_str())
                .unwrap_or("");

            // Skip hidden directories, Android system directories, and trash
            if file_name.starts_with('.')
                || file_name.eq_ignore_ascii_case("Android")
                || file_name.eq_ignore_ascii_case("LOST.DIR")
                || file_name.eq_ignore_ascii_case(".thumbnails")
            {
                continue;
            }

            if path.is_dir() {
                let _ = Self::collect_audio_files_safe(&path, files, depth + 1);
            } else if path.is_file() {
                if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
                    if Self::SUPPORTED_EXTENSIONS.contains(&ext.to_lowercase().as_str()) {
                        files.push(path);
                    }
                }
            }
        }

        Ok(())
    }
}
