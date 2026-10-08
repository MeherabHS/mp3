use crate::models::lyrics::{LyricsSyncState, SyncedLyrics};

pub struct LyricsSynchronizer;

impl LyricsSynchronizer {
    pub fn find_sync_state(lyrics: &SyncedLyrics, position_ms: i64) -> LyricsSyncState {
        if !lyrics.is_synchronized || lyrics.lines.is_empty() {
            return LyricsSyncState {
                track_id: lyrics.track_id.clone(),
                active_line_index: None,
                active_word_index: None,
                line_progress: 0.0,
                active_line_text: None,
                previous_line_text: None,
                next_line_text: None,
            };
        }

        let lines = &lyrics.lines;
        let pos = position_ms + lyrics.offset_ms;

        // Binary search to find the active line
        let mut low = 0;
        let mut high = lines.len();
        let mut active_index = None;

        while low < high {
            let mid = low + (high - low) / 2;
            let line_start = lines[mid].start_ms;

            if line_start <= pos {
                active_index = Some(mid);
                low = mid + 1;
            } else {
                high = mid;
            }
        }

        let active_line_index = active_index;
        let mut active_word_index = None;
        let mut line_progress = 0.0;
        let mut active_line_text = None;
        let mut previous_line_text = None;
        let mut next_line_text = None;

        if let Some(idx) = active_line_index {
            let active_line = &lines[idx];
            active_line_text = Some(active_line.text.clone());

            if idx > 0 {
                previous_line_text = Some(lines[idx - 1].text.clone());
            }
            if idx + 1 < lines.len() {
                next_line_text = Some(lines[idx + 1].text.clone());
            }

            // Calculate line progress
            if let Some(end_ms) = active_line.end_ms {
                let duration = end_ms - active_line.start_ms;
                if duration > 0 {
                    let elapsed = pos - active_line.start_ms;
                    line_progress = (elapsed as f32 / duration as f32).clamp(0.0, 1.0);
                }
            }

            // If word-level synchronization is present, find active word
            if !active_line.words.is_empty() {
                for (w_idx, word) in active_line.words.iter().enumerate() {
                    if pos >= word.start_ms && pos < word.end_ms {
                        active_word_index = Some(w_idx);
                        break;
                    }
                }
            }
        } else {
            // Before the first line begins
            next_line_text = Some(lines[0].text.clone());
        }

        LyricsSyncState {
            track_id: lyrics.track_id.clone(),
            active_line_index,
            active_word_index,
            line_progress,
            active_line_text,
            previous_line_text,
            next_line_text,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::lyrics::parser::LrcParser;

    #[test]
    fn test_sync_lookup() {
        let lrc = r#"
[00:10.00]First line
[00:20.00]Second line
[00:30.00]Third line
"#;
        let parsed = LrcParser::parse("test_track", lrc).unwrap();

        // 5 seconds: before any line
        let sync_0 = LyricsSynchronizer::find_sync_state(&parsed, 5000);
        assert_eq!(sync_0.active_line_index, None);
        assert_eq!(sync_0.next_line_text, Some("First line".to_string()));

        // 15 seconds: on First line
        let sync_1 = LyricsSynchronizer::find_sync_state(&parsed, 15000);
        assert_eq!(sync_1.active_line_index, Some(0));
        assert_eq!(sync_1.active_line_text, Some("First line".to_string()));
        assert_eq!(sync_1.next_line_text, Some("Second line".to_string()));
        assert_eq!(sync_1.line_progress, 0.5);

        // 25 seconds: on Second line
        let sync_2 = LyricsSynchronizer::find_sync_state(&parsed, 25000);
        assert_eq!(sync_2.active_line_index, Some(1));
        assert_eq!(sync_2.previous_line_text, Some("First line".to_string()));
        assert_eq!(sync_2.active_line_text, Some("Second line".to_string()));
        assert_eq!(sync_2.next_line_text, Some("Third line".to_string()));
    }
}
