/// Validates and normalizes YouTube URLs.
/// Returns the canonical video URL if valid, or an error string.
use crate::error::{CoreError, Result};
use regex::Regex;

static YT_PATTERN: std::sync::OnceLock<Regex> = std::sync::OnceLock::new();

fn yt_regex() -> &'static Regex {
    YT_PATTERN.get_or_init(|| {
        Regex::new(
            r"(?x)
            (?:https?://)?
            (?:www\.)?
            (?:
                youtube\.com/watch\?(?:[^&]*&)*v=([a-zA-Z0-9_-]{11})
                | youtu\.be/([a-zA-Z0-9_-]{11})
                | youtube\.com/shorts/([a-zA-Z0-9_-]{11})
                | m\.youtube\.com/watch\?(?:[^&]*&)*v=([a-zA-Z0-9_-]{11})
            )
            ",
        )
        .expect("YouTube regex is valid")
    })
}

/// Extract the 11-character YouTube video ID from a URL.
pub fn extract_video_id(url: &str) -> Option<String> {
    let re = yt_regex();
    let caps = re.captures(url)?;
    // Try each capture group
    for i in 1..=4 {
        if let Some(m) = caps.get(i) {
            return Some(m.as_str().to_string());
        }
    }
    None
}

/// Normalize a YouTube URL to its canonical form.
pub fn resolve_yt_url(url: &str) -> Result<String> {
    let video_id = extract_video_id(url)
        .ok_or_else(|| CoreError::Metadata(format!("Not a valid YouTube URL: {}", url)))?;

    Ok(format!("https://www.youtube.com/watch?v={}", video_id))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_resolve_standard_url() {
        let url = "https://www.youtube.com/watch?v=dQw4w9WgXcQ";
        assert_eq!(resolve_yt_url(url).unwrap(), "https://www.youtube.com/watch?v=dQw4w9WgXcQ");
    }

    #[test]
    fn test_resolve_short_url() {
        let url = "https://youtu.be/dQw4w9WgXcQ";
        assert_eq!(resolve_yt_url(url).unwrap(), "https://www.youtube.com/watch?v=dQw4w9WgXcQ");
    }

    #[test]
    fn test_resolve_shorts_url() {
        let url = "https://www.youtube.com/shorts/dQw4w9WgXcQ";
        assert_eq!(resolve_yt_url(url).unwrap(), "https://www.youtube.com/watch?v=dQw4w9WgXcQ");
    }

    #[test]
    fn test_invalid_url() {
        let url = "https://spotify.com/track/abc";
        assert!(resolve_yt_url(url).is_err());
    }
}
