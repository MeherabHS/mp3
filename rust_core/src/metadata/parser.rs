use crate::error::{CoreError, Result};
use crate::models::track::Track;
use lofty::file::{AudioFile, TaggedFileExt};
use lofty::probe::Probe;
use lofty::tag::{Accessor, ItemKey};
use std::path::Path;
use uuid::Uuid;

pub struct MetadataParser;

pub struct ParsedAudioMetadata {
    pub track: Track,
    pub embedded_artwork: Option<Vec<u8>>,
}

impl MetadataParser {
    pub fn parse_file<P: AsRef<Path>>(file_path: P) -> Result<ParsedAudioMetadata> {
        let path = file_path.as_ref();
        if !path.exists() {
            return Err(CoreError::NotFound(format!(
                "File does not exist: {:?}",
                path
            )));
        }

        let file_ext = path
            .extension()
            .and_then(|ext| ext.to_str())
            .unwrap_or("")
            .to_lowercase();

        let filename_stem = path
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("Unknown Track")
            .to_string();

        // Default fallbacks from filename
        let (mut fallback_artist, mut fallback_title) = if filename_stem.contains(" - ") {
            let parts: Vec<&str> = filename_stem.splitn(2, " - ").collect();
            (parts[0].trim().to_string(), parts[1].trim().to_string())
        } else {
            ("Unknown Artist".to_string(), filename_stem.clone())
        };

        // Try probing tags with lofty
        let probed = Probe::open(path).ok().and_then(|p| p.read().ok());

        let (duration_ms, bitrate_kbps, sample_rate_hz, bit_depth, channels, embedded_artwork, title, artist, album, album_artist, genre, year, track_number, disc_number) =
            if let Some(tagged_file) = probed {
                let props = tagged_file.properties();
                let dur = props.duration().as_millis() as u64;
                let br = props.audio_bitrate();
                let sr = props.sample_rate();
                let bd = props.bit_depth();
                let ch = props.channels();

                let mut t = None;
                let mut a = None;
                let mut alb = None;
                let mut aa = None;
                let mut g = None;
                let mut y = None;
                let mut tn = None;
                let mut dn = None;
                let mut art = None;

                if let Some(tag) = tagged_file.primary_tag().or_else(|| tagged_file.first_tag()) {
                    t = tag.title().as_deref().map(str::to_string);
                    a = tag.artist().as_deref().map(str::to_string);
                    alb = tag.album().as_deref().map(str::to_string);
                    g = tag.genre().as_deref().map(str::to_string);
                    y = tag.year();
                    tn = tag.track();
                    dn = tag.disk();

                    if let Some(item) = tag.get(&ItemKey::AlbumArtist) {
                        if let Some(val) = item.value().text() {
                            aa = Some(val.to_string());
                        }
                    }

                    if let Some(picture) = tag.pictures().first() {
                        art = Some(picture.data().to_vec());
                    }
                }

                (dur, br, sr, bd, ch, art, t, a, alb, aa, g, y, tn, dn)
            } else {
                (0, None, None, None, None, None, None, None, None, None, None, None, None, None)
            };

        let (container, codec, lossless) = match file_ext.as_str() {
            "flac" => ("FLAC".to_string(), "FLAC".to_string(), true),
            "wav" => ("WAV".to_string(), "PCM".to_string(), true),
            "alac" | "m4a" | "mp4" => {
                if bit_depth.unwrap_or(16) > 16 || bitrate_kbps.unwrap_or(0) > 500 {
                    ("M4A".to_string(), "ALAC".to_string(), true)
                } else {
                    ("M4A".to_string(), "AAC".to_string(), false)
                }
            }
            "mp3" => ("MP3".to_string(), "MP3".to_string(), false),
            "opus" => ("Ogg".to_string(), "Opus".to_string(), false),
            "ogg" => ("Ogg".to_string(), "Vorbis".to_string(), false),
            "webm" => ("WebM".to_string(), "Opus".to_string(), false),
            "aac" => ("AAC".to_string(), "AAC".to_string(), false),
            _ => (file_ext.to_uppercase(), "Audio".to_string(), false),
        };

        let track_title = title.unwrap_or(fallback_title);
        let track_artist = artist.unwrap_or(fallback_artist);
        let track_album = album.unwrap_or_else(|| "Unknown Album".to_string());

        // Deterministic stable ID based on absolute path
        let track_id = Uuid::new_v5(&Uuid::NAMESPACE_URL, path.to_string_lossy().as_bytes()).to_string();
        let now = chrono::Utc::now().timestamp();

        let track = Track {
            id: track_id,
            file_path: path.to_string_lossy().to_string(),
            title: track_title,
            artist: track_artist,
            album: track_album,
            album_artist,
            genre,
            year,
            track_number,
            disc_number,
            duration_ms,
            codec,
            container,
            bitrate_kbps,
            sample_rate_hz,
            bit_depth,
            channels,
            lossless,
            artwork_path: None,
            lyrics_path: None,
            is_favorite: false,
            play_count: 0,
            last_played_at: None,
            created_at: now,
        };

        Ok(ParsedAudioMetadata {
            track,
            embedded_artwork,
        })
    }
}
