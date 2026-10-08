/// Download pipeline: orchestrates URL resolution → yt-dlp audio download →
/// metadata extraction → artwork thumbnailing → lyrics fetch → DB insert.
use crate::database::Database;
use crate::downloader::{resolve_yt_url, ytdlp::YtDlp};
use crate::error::{CoreError, Result};
use crate::metadata::{ArtworkProcessor, MetadataParser};
use crate::models::track::Track;
use crate::storage::StorageManager;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::sync::{Arc, Mutex};

/// Stages of the download pipeline for progress reporting.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum DownloadStage {
    Queued,
    ResolvingUrl,
    FetchingMetadata,
    DownloadingAudio,
    ExtractingMetadata,
    ProcessingArtwork,
    FetchingLyrics,
    IndexingLibrary,
    Completed,
    Failed,
}

/// A single job tracked through the pipeline.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DownloadJob {
    pub id: String,
    pub url: String,
    pub stage: DownloadStage,
    pub progress_pct: f32,
    pub title: String,
    pub artist: String,
    pub error: Option<String>,
    pub output_path: Option<String>,
    pub track_id: Option<String>,
}

impl DownloadJob {
    pub fn new(id: String, url: String) -> Self {
        Self {
            id,
            url,
            stage: DownloadStage::Queued,
            progress_pct: 0.0,
            title: "Resolving...".to_string(),
            artist: String::new(),
            error: None,
            output_path: None,
            track_id: None,
        }
    }
}

/// Progress update emitted after each pipeline stage.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DownloadProgress {
    pub job_id: String,
    pub stage: DownloadStage,
    pub progress_pct: f32,
    pub title: String,
    pub artist: String,
    pub error: Option<String>,
}

/// Manages the active download job queue.
pub struct DownloadPipeline {
    jobs: Mutex<Vec<DownloadJob>>,
    ytdlp: YtDlp,
    db: Arc<Database>,
    storage: Arc<StorageManager>,
}

impl DownloadPipeline {
    pub fn new(ytdlp_path: impl AsRef<std::path::Path>, db: Arc<Database>, storage: Arc<StorageManager>) -> Self {
        Self {
            jobs: Mutex::new(Vec::new()),
            ytdlp: YtDlp::new(ytdlp_path),
            db,
            storage,
        }
    }

    pub fn list_jobs(&self) -> Vec<DownloadJob> {
        self.jobs.lock().unwrap().clone()
    }

    pub fn get_job(&self, id: &str) -> Option<DownloadJob> {
        self.jobs.lock().unwrap().iter().find(|j| j.id == id).cloned()
    }

    fn update_job(&self, id: &str, f: impl FnOnce(&mut DownloadJob)) {
        if let Ok(mut jobs) = self.jobs.lock() {
            if let Some(job) = jobs.iter_mut().find(|j| j.id == id) {
                f(job);
            }
        }
    }

    /// Run the full pipeline for a YouTube URL synchronously.
    pub fn run(&self, url: &str) -> Result<DownloadJob> {
        let job_id = uuid::Uuid::new_v4().to_string();
        let job = DownloadJob::new(job_id.clone(), url.to_string());
        self.jobs.lock().unwrap().push(job);

        // Stage 1: Resolve URL
        self.update_job(&job_id, |j| {
            j.stage = DownloadStage::ResolvingUrl;
            j.progress_pct = 0.05;
        });

        let canonical_url = resolve_yt_url(url).map_err(|e| {
            self.update_job(&job_id, |j| {
                j.stage = DownloadStage::Failed;
                j.error = Some(e.to_string());
            });
            e
        })?;

        // Stage 2: Fetch metadata preview
        self.update_job(&job_id, |j| {
            j.stage = DownloadStage::FetchingMetadata;
            j.progress_pct = 0.10;
        });

        let meta = self.ytdlp.get_metadata(&canonical_url).map_err(|e| {
            self.update_job(&job_id, |j| {
                j.stage = DownloadStage::Failed;
                j.error = Some(e.to_string());
            });
            e
        })?;

        self.update_job(&job_id, |j| {
            j.title = meta.display_title().to_string();
            j.artist = meta.display_artist().to_string();
            j.progress_pct = 0.20;
        });

        // Stage 3: Download audio
        self.update_job(&job_id, |j| {
            j.stage = DownloadStage::DownloadingAudio;
            j.progress_pct = 0.25;
        });

        let audio_dir = self.storage.get_audio_dir();
        let audio_path = self.ytdlp.download_audio(&canonical_url, &audio_dir.to_string_lossy()).map_err(|e| {
            self.update_job(&job_id, |j| {
                j.stage = DownloadStage::Failed;
                j.error = Some(e.to_string());
            });
            e
        })?;

        self.update_job(&job_id, |j| {
            j.progress_pct = 0.60;
            j.output_path = Some(audio_path.to_string_lossy().to_string());
        });

        // Stage 4: Extract embedded metadata
        self.update_job(&job_id, |j| {
            j.stage = DownloadStage::ExtractingMetadata;
            j.progress_pct = 0.65;
        });

        let parsed = MetadataParser::parse_file(&audio_path).ok();

        // Derive title/artist from parsed metadata → yt-dlp tags → title splitting
        let (mut title, mut artist) = {
            let t = parsed.as_ref()
                .map(|p| p.track.title.clone())
                .filter(|t| !t.is_empty())
                .unwrap_or_else(|| meta.display_title().to_string());
            let a = parsed.as_ref()
                .map(|p| p.track.artist.clone())
                .filter(|a| !a.is_empty())
                .unwrap_or_else(|| meta.display_artist().to_string());
            (t, a)
        };

        // If yt-dlp only had the channel/uploader as the artist (common for
        // non-music-tagged uploads), try to split "Artist - Title" from the video title.
        if artist == meta.uploader && meta.artist.is_none() {
            if let Some((split_artist, split_title)) = split_yt_title(&meta.title, &meta.uploader) {
                artist = split_artist;
                title = split_title;
            }
        }

        self.update_job(&job_id, |j| {
            j.title = title.clone();
            j.artist = artist.clone();
        });

        // Stage 5: Process artwork
        self.update_job(&job_id, |j| {
            j.stage = DownloadStage::ProcessingArtwork;
            j.progress_pct = 0.75;
        });

        let track_uuid = uuid::Uuid::new_v4().to_string();
        let artwork = if let Some(ref p) = parsed {
            if let Some(ref raw_bytes) = p.embedded_artwork {
                ArtworkProcessor::process_and_cache(&self.storage, &track_uuid, raw_bytes).ok()
            } else {
                fetch_thumbnail_fallback(meta.thumbnail.as_deref(), &self.storage, &track_uuid)
            }
        } else {
            fetch_thumbnail_fallback(meta.thumbnail.as_deref(), &self.storage, &track_uuid)
        };

        // Stage 6: Fetch lyrics
        self.update_job(&job_id, |j| {
            j.stage = DownloadStage::FetchingLyrics;
            j.progress_pct = 0.85;
        });

        let track_duration_ms = parsed.as_ref()
            .map(|p| p.track.duration_ms)
            .unwrap_or_else(|| meta.duration_ms());
        let lyrics_path = fetch_lyrics_lrclib(
            &title, &artist, track_duration_ms, &self.storage.get_lyrics_dir()
        ).ok();

        // Stage 7: Index into library DB
        self.update_job(&job_id, |j| {
            j.stage = DownloadStage::IndexingLibrary;
            j.progress_pct = 0.92;
        });

        let parsed_track = parsed.map(|p| p.track);
        let track = Track {
            id: track_uuid.clone(),
            file_path: audio_path.to_string_lossy().to_string(),
            title: title.clone(),
            artist: artist.clone(),
            album: parsed_track.as_ref().map(|t| t.album.clone())
                .filter(|a| !a.is_empty())
                .or_else(|| meta.album.clone())
                .unwrap_or_default(),
            album_artist: parsed_track.as_ref().and_then(|t| t.album_artist.clone()),
            genre: parsed_track.as_ref().and_then(|t| t.genre.clone()),
            year: parsed_track.as_ref().and_then(|t| t.year),
            track_number: parsed_track.as_ref().and_then(|t| t.track_number),
            disc_number: parsed_track.as_ref().and_then(|t| t.disc_number),
            duration_ms: parsed_track.as_ref().map(|t| t.duration_ms).unwrap_or_else(|| meta.duration_ms()),
            codec: parsed_track.as_ref().map(|t| t.codec.clone()).unwrap_or_else(|| "Opus".to_string()),
            container: parsed_track.as_ref().map(|t| t.container.clone())
                .filter(|c| !c.is_empty())
                .unwrap_or_else(|| audio_path.extension()
                    .and_then(|e| e.to_str()).unwrap_or("opus").to_uppercase()),
            bitrate_kbps: parsed_track.as_ref().and_then(|t| t.bitrate_kbps),
            sample_rate_hz: parsed_track.as_ref().and_then(|t| t.sample_rate_hz),
            bit_depth: parsed_track.as_ref().and_then(|t| t.bit_depth),
            channels: parsed_track.as_ref().and_then(|t| t.channels),
            lossless: parsed_track.as_ref().map(|t| t.lossless).unwrap_or(false),
            artwork_path: artwork.as_ref().map(|a| a.path_200.clone()),
            lyrics_path: lyrics_path.map(|p| p.to_string_lossy().to_string()),
            is_favorite: false,
            play_count: 0,
            last_played_at: None,
            created_at: chrono::Utc::now().timestamp(),
        };

        let track_id = track.id.clone();
        self.db.insert_or_update_track(&track)
            .map_err(|e| CoreError::Downloader(format!("DB insert failed: {}", e)))?;

        self.update_job(&job_id, |j| {
            j.stage = DownloadStage::Completed;
            j.progress_pct = 1.0;
            j.track_id = Some(track_id.clone());
        });

        Ok(self.get_job(&job_id).unwrap())
    }
}

fn fetch_thumbnail_fallback(
    url: Option<&str>,
    storage: &StorageManager,
    id: &str,
) -> Option<crate::metadata::artwork::ProcessedArtwork> {
    let url = url?;
    let response = ureq::get(url).call().ok()?;
    let mut bytes = Vec::new();
    std::io::Read::read_to_end(&mut response.into_reader(), &mut bytes).ok()?;
    ArtworkProcessor::process_and_cache(storage, id, &bytes).ok()
}

/// Separates "Artist - Title" style YouTube video titles into (artist, title).
/// Returns `None` if the separator pattern isn't detected.
fn split_yt_title(raw_title: &str, uploader: &str) -> Option<(String, String)> {
    // Only attempt split when artist == uploader (yt-dlp didn't find a real artist tag)
    // and the title contains the classic " - " separator.
    if raw_title.contains(" - ") {
        let parts: Vec<&str> = raw_title.splitn(2, " - ").collect();
        if parts.len() == 2 {
            let left = parts[0].trim().to_string();
            let right = parts[1].trim().to_string();
            // Heuristic: if the left side looks like the uploader name, treat it as artist.
            // Also accept if neither part is empty.
            if !left.is_empty() && !right.is_empty() {
                return Some((left, right));
            }
        }
    }
    None
}

/// Fetch lyrics from LRCLIB using a three-tier strategy:
///   1. `/api/get?track_name=…&artist_name=…&duration=…`  — exact match (best)
///   2. `/api/search?track_name=…&artist_name=…`          — pick closest duration match
///   3. Same search but prefer `plainLyrics` if no synced lyrics found anywhere
///
/// Writes `.lrc` (synced) or `.txt` (plain) to `lyrics_dir` and returns the path.
fn fetch_lyrics_lrclib(
    title: &str,
    artist: &str,
    duration_ms: u64,
    lyrics_dir: &std::path::Path,
) -> Result<PathBuf> {
    let duration_s = duration_ms / 1000;

    // ── Strategy 1: exact /api/get lookup with duration ───────────────────────
    if duration_s > 0 {
        let exact_url = format!(
            "https://lrclib.net/api/get?track_name={}&artist_name={}&duration={}",
            urlencoding(title),
            urlencoding(artist),
            duration_s
        );
        if let Ok(resp) = ureq::get(&exact_url)
            .set("User-Agent", "HiFiMusicPlayer/1.0")
            .call()
        {
            if let Ok(json) = resp.into_json::<serde_json::Value>() {
                if let Some(path) = save_lrclib_entry(&json, title, lyrics_dir) {
                    return Ok(path);
                }
            }
        }
    }

    // ── Strategy 2: /api/search — pick best duration match ────────────────────
    let search_url = format!(
        "https://lrclib.net/api/search?track_name={}&artist_name={}",
        urlencoding(title),
        urlencoding(artist)
    );

    let resp = ureq::get(&search_url)
        .set("User-Agent", "HiFiMusicPlayer/1.0")
        .call()
        .map_err(|e| CoreError::Lyrics(format!("lrclib search failed: {}", e)))?;

    let results: serde_json::Value = resp.into_json()
        .map_err(|e| CoreError::Lyrics(format!("lrclib JSON parse failed: {}", e)))?;

    let arr = results.as_array()
        .ok_or_else(|| CoreError::Lyrics("lrclib returned non-array".to_string()))?;

    if arr.is_empty() {
        return Err(CoreError::Lyrics("No lyrics found on lrclib.net".to_string()));
    }

    // Pick the result whose duration is closest to the actual track duration.
    // Fall back to the first result if duration is unknown.
    let best = if duration_s > 0 {
        arr.iter().min_by_key(|item| {
            let d = item.get("duration")
                .and_then(|v| v.as_f64())
                .unwrap_or(0.0) as i64;
            (d - duration_s as i64).abs()
        })
    } else {
        arr.first()
    };

    if let Some(entry) = best {
        if let Some(path) = save_lrclib_entry(entry, title, lyrics_dir) {
            return Ok(path);
        }
    }

    Err(CoreError::Lyrics("No usable lyrics in lrclib results".to_string()))
}

/// Extract synced or plain lyrics from a single LRCLIB JSON entry and write to disk.
/// Returns the saved path, or `None` if neither lyrics field is present.
fn save_lrclib_entry(entry: &serde_json::Value, title: &str, lyrics_dir: &std::path::Path) -> Option<PathBuf> {
    let safe_name: String = title.chars()
        .map(|c| if c.is_alphanumeric() || c == ' ' { c } else { '_' })
        .collect();
    let base = safe_name.trim().to_string();

    // Prefer synced (.lrc) over plain (.txt)
    let synced = entry.get("syncedLyrics")
        .and_then(|v| v.as_str())
        .filter(|s| !s.trim().is_empty());

    if let Some(lrc) = synced {
        let path = lyrics_dir.join(format!("{}.lrc", base));
        std::fs::write(&path, lrc).ok()?;
        return Some(path);
    }

    let plain = entry.get("plainLyrics")
        .and_then(|v| v.as_str())
        .filter(|s| !s.trim().is_empty());

    if let Some(txt) = plain {
        let path = lyrics_dir.join(format!("{}.txt", base));
        std::fs::write(&path, txt).ok()?;
        return Some(path);
    }

    None
}

fn urlencoding(s: &str) -> String {
    s.chars()
        .flat_map(|c| {
            if c.is_alphanumeric() || c == '-' || c == '_' || c == '.' || c == '~' {
                vec![c]
            } else if c == ' ' {
                vec!['+']
            } else {
                format!("%{:02X}", c as u32).chars().collect()
            }
        })
        .collect()
}
