use crate::error::{CoreError, Result};
use crate::models::lyrics::{LyricLine, LyricWord, SyncedLyrics};
use regex::Regex;

pub struct LrcParser;

impl LrcParser {
    pub fn parse(track_id: &str, content: &str) -> Result<SyncedLyrics> {
        let mut lines: Vec<LyricLine> = Vec::new();
        let mut offset_ms: i64 = 0;
        let mut is_word_synced = false;

        // Regex for line timestamps: [mm:ss.xx] or [mm:ss.xxx]
        let time_tag_regex = Regex::new(r"\[(\d{1,2}):(\d{2})(?:\.(\d{2,3}))?\]")
            .map_err(|e| CoreError::Lyrics(e.to_string()))?;
        
        // Regex for enhanced word timestamps: <mm:ss.xx>word
        let word_tag_regex = Regex::new(r"<(\d{1,2}):(\d{2})(?:\.(\d{2,3}))?>([^<]*)")
            .map_err(|e| CoreError::Lyrics(e.to_string()))?;

        for raw_line in content.lines() {
            let trimmed = raw_line.trim();
            if trimmed.is_empty() {
                continue;
            }

            // Parse metadata tags e.g. [offset:+500]
            if trimmed.starts_with("[offset:") && trimmed.ends_with(']') {
                let offset_str = &trimmed[8..trimmed.len() - 1].trim();
                if let Ok(val) = offset_str.parse::<i64>() {
                    offset_ms = val;
                }
                continue;
            }

            // Check for standard timestamp headers e.g. [01:23.45]
            let mut timestamps: Vec<i64> = Vec::new();
            let mut last_match_end = 0;

            for mat in time_tag_regex.find_iter(trimmed) {
                if let Some(caps) = time_tag_regex.captures(mat.as_str()) {
                    let min: i64 = caps.get(1).map_or(0, |m| m.as_str().parse().unwrap_or(0));
                    let sec: i64 = caps.get(2).map_or(0, |m| m.as_str().parse().unwrap_or(0));
                    let ms: i64 = caps.get(3).map_or(0, |m| {
                        let ms_str = m.as_str();
                        if ms_str.len() == 2 {
                            ms_str.parse::<i64>().unwrap_or(0) * 10
                        } else {
                            ms_str.parse::<i64>().unwrap_or(0)
                        }
                    });

                    let total_ms = (min * 60 * 1000) + (sec * 1000) + ms;
                    timestamps.push(total_ms);
                    last_match_end = mat.end();
                }
            }

            if timestamps.is_empty() {
                continue;
            }

            let text_part = trimmed[last_match_end..].trim().to_string();

            // Check if this line has word-level timestamps e.g. <00:14.32>I <00:14.51>remember
            let mut words: Vec<LyricWord> = Vec::new();
            if word_tag_regex.is_match(&text_part) {
                is_word_synced = true;
                let mut prev_word_time: Option<i64> = None;
                let mut prev_word_text = String::new();

                for caps in word_tag_regex.captures_iter(&text_part) {
                    let min: i64 = caps.get(1).map_or(0, |m| m.as_str().parse().unwrap_or(0));
                    let sec: i64 = caps.get(2).map_or(0, |m| m.as_str().parse().unwrap_or(0));
                    let ms: i64 = caps.get(3).map_or(0, |m| {
                        let ms_str = m.as_str();
                        if ms_str.len() == 2 {
                            ms_str.parse::<i64>().unwrap_or(0) * 10
                        } else {
                            ms_str.parse::<i64>().unwrap_or(0)
                        }
                    });
                    let word_text = caps.get(4).map_or("", |m| m.as_str()).to_string();
                    let current_word_time = (min * 60 * 1000) + (sec * 1000) + ms;

                    if let Some(prev_start) = prev_word_time {
                        words.push(LyricWord {
                            start_ms: prev_start,
                            end_ms: current_word_time,
                            word: prev_word_text.clone(),
                        });
                    }

                    prev_word_time = Some(current_word_time);
                    prev_word_text = word_text;
                }

                if let Some(last_start) = prev_word_time {
                    // Default last word length 500ms
                    words.push(LyricWord {
                        start_ms: last_start,
                        end_ms: last_start + 500,
                        word: prev_word_text,
                    });
                }
            }

            // Strip word tags for clean text if needed
            let clean_text = if is_word_synced && !words.is_empty() {
                words.iter().map(|w| w.word.clone()).collect::<Vec<_>>().join("")
            } else {
                text_part
            };

            for &ts in &timestamps {
                lines.push(LyricLine {
                    start_ms: ts + offset_ms,
                    end_ms: None,
                    text: clean_text.clone(),
                    words: words.clone(),
                });
            }
        }

        // Sort lines chronologically
        lines.sort_by_key(|l| l.start_ms);

        // Fill end_ms based on next line's start_ms
        for i in 0..lines.len() {
            if i + 1 < lines.len() {
                lines[i].end_ms = Some(lines[i + 1].start_ms);
            }
        }

        let is_synchronized = !lines.is_empty();

        Ok(SyncedLyrics {
            track_id: track_id.to_string(),
            is_synchronized,
            is_word_synced,
            offset_ms,
            lines,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_standard_lrc() {
        let lrc_content = r#"
[ti:A Moment Apart]
[ar:ODESZA]
[00:14.32]I remember
[00:18.50]The way you looked at me that night
[00:24.00]I couldn't let go of you
"#;
        let parsed = LrcParser::parse("track_1", lrc_content).unwrap();
        assert!(parsed.is_synchronized);
        assert_eq!(parsed.lines.len(), 3);
        assert_eq!(parsed.lines[0].start_ms, 14320);
        assert_eq!(parsed.lines[0].text, "I remember");
        assert_eq!(parsed.lines[0].end_ms, Some(18500));
        assert_eq!(parsed.lines[1].start_ms, 18500);
        assert_eq!(parsed.lines[1].text, "The way you looked at me that night");
    }

    #[test]
    fn test_parse_enhanced_word_lrc() {
        let lrc_content = r#"
[00:10.00]<00:10.00>The <00:10.50>way <00:11.00>you <00:11.50>looked
"#;
        let parsed = LrcParser::parse("track_2", lrc_content).unwrap();
        assert!(parsed.is_synchronized);
        assert!(parsed.is_word_synced);
        assert_eq!(parsed.lines.len(), 1);
        assert_eq!(parsed.lines[0].words.len(), 4);
        assert_eq!(parsed.lines[0].words[0].word, "The ");
        assert_eq!(parsed.lines[0].words[0].start_ms, 10000);
        assert_eq!(parsed.lines[0].words[0].end_ms, 10500);
    }
}
