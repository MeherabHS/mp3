/// yt-dlp subprocess wrapper.
/// Invokes the bundled yt-dlp binary to acquire the highest-quality audio stream.
use crate::error::{CoreError, Result};
use std::path::{Path, PathBuf};
use std::process::Command;

pub struct YtDlp {
    /// Path to the yt-dlp binary (copied from assets to filesDir on first launch).
    binary_path: PathBuf,
}

impl YtDlp {
    pub fn new(binary_path: impl AsRef<Path>) -> Self {
        Self {
            binary_path: binary_path.as_ref().to_path_buf(),
        }
    }

    /// Download the best audio stream for a given YouTube URL.
    /// Returns the path to the downloaded file.
    pub fn download_audio(&self, url: &str, output_dir: &str) -> Result<PathBuf> {
        let output_template = format!("{}/%(title)s.%(ext)s", output_dir);

        // Use yt-dlp best audio format: prefer opus > aac > mp4a
        let output = Command::new(&self.binary_path)
            .args([
                "--no-playlist",
                "--format",
                "bestaudio[ext=opus]/bestaudio[ext=m4a]/bestaudio",
                "--audio-quality",
                "0",
                "--output",
                &output_template,
                "--print",
                "after_move:filepath",
                "--no-warnings",
                "--quiet",
                url,
            ])
            .output()
            .map_err(|e| CoreError::Audio(format!("yt-dlp launch failed: {}", e)))?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(CoreError::Audio(format!("yt-dlp error: {}", stderr.trim())));
        }

        let stdout = String::from_utf8_lossy(&output.stdout);
        let file_path = stdout.trim();

        if file_path.is_empty() {
            return Err(CoreError::Audio("yt-dlp produced no output path".to_string()));
        }

        Ok(PathBuf::from(file_path))
    }

    /// Fetch just the video metadata (title, uploader, duration, thumbnail URL)
    /// without downloading the audio. Used for "preview before download".
    pub fn get_metadata(&self, url: &str) -> Result<VideoMetadata> {
        let output = Command::new(&self.binary_path)
            .args([
                "--no-playlist",
                "--dump-single-json",
                "--no-warnings",
                "--quiet",
                url,
            ])
            .output()
            .map_err(|e| CoreError::Audio(format!("yt-dlp metadata failed: {}", e)))?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(CoreError::Audio(format!("yt-dlp error: {}", stderr.trim())));
        }

        let json_str = String::from_utf8_lossy(&output.stdout);
        let meta: VideoMetadata = serde_json::from_str(&json_str)
            .map_err(|e| CoreError::Metadata(format!("yt-dlp JSON parse error: {}", e)))?;

        Ok(meta)
    }
}

#[derive(Debug, serde::Serialize, serde::Deserialize)]
pub struct VideoMetadata {
    pub id: String,
    pub title: String,
    #[serde(default)]
    pub uploader: String,
    #[serde(default)]
    pub artist: Option<String>,
    #[serde(default)]
    pub album: Option<String>,
    #[serde(default)]
    pub track: Option<String>,
    #[serde(default)]
    pub duration: Option<f64>,
    #[serde(default)]
    pub thumbnail: Option<String>,
    #[serde(default)]
    pub description: Option<String>,
}

impl VideoMetadata {
    pub fn display_title(&self) -> &str {
        self.track.as_deref().unwrap_or(&self.title)
    }

    pub fn display_artist(&self) -> &str {
        self.artist.as_deref().unwrap_or(&self.uploader)
    }

    pub fn duration_ms(&self) -> u64 {
        self.duration.map(|d| (d * 1000.0) as u64).unwrap_or(0)
    }
}
