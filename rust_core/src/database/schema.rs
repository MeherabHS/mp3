use crate::error::Result;
use rusqlite::Connection;

pub struct Schema;

impl Schema {
    pub fn create_tables(conn: &Connection) -> Result<()> {
        conn.execute_batch(
            r#"
            PRAGMA journal_mode = WAL;
            PRAGMA synchronous = NORMAL;
            PRAGMA foreign_keys = ON;

            CREATE TABLE IF NOT EXISTS songs (
                id TEXT PRIMARY KEY,
                file_path TEXT NOT NULL UNIQUE,
                title TEXT NOT NULL,
                artist TEXT NOT NULL,
                album TEXT NOT NULL,
                album_artist TEXT,
                genre TEXT,
                year INTEGER,
                track_number INTEGER,
                disc_number INTEGER,
                duration_ms INTEGER NOT NULL,
                codec TEXT NOT NULL,
                container TEXT NOT NULL,
                bitrate_kbps INTEGER,
                sample_rate_hz INTEGER,
                bit_depth INTEGER,
                channels INTEGER,
                lossless INTEGER NOT NULL DEFAULT 0,
                artwork_path TEXT,
                lyrics_path TEXT,
                is_favorite INTEGER NOT NULL DEFAULT 0,
                play_count INTEGER NOT NULL DEFAULT 0,
                last_played_at INTEGER,
                created_at INTEGER NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_songs_title ON songs(title);
            CREATE INDEX IF NOT EXISTS idx_songs_artist ON songs(artist);
            CREATE INDEX IF NOT EXISTS idx_songs_album ON songs(album);
            CREATE INDEX IF NOT EXISTS idx_songs_favorite ON songs(is_favorite);
            CREATE INDEX IF NOT EXISTS idx_songs_last_played ON songs(last_played_at);
            CREATE INDEX IF NOT EXISTS idx_songs_created_at ON songs(created_at);

            CREATE TABLE IF NOT EXISTS playlists (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                created_at INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS playlist_tracks (
                playlist_id TEXT NOT NULL,
                track_id TEXT NOT NULL,
                position INTEGER NOT NULL,
                PRIMARY KEY (playlist_id, track_id),
                FOREIGN KEY(playlist_id) REFERENCES playlists(id) ON DELETE CASCADE,
                FOREIGN KEY(track_id) REFERENCES songs(id) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS play_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                track_id TEXT NOT NULL,
                played_at INTEGER NOT NULL,
                FOREIGN KEY(track_id) REFERENCES songs(id) ON DELETE CASCADE
            );

            CREATE INDEX IF NOT EXISTS idx_history_played ON play_history(played_at);

            CREATE TABLE IF NOT EXISTS downloads (
                id TEXT PRIMARY KEY,
                source_url TEXT NOT NULL,
                title TEXT NOT NULL,
                artist TEXT NOT NULL,
                state TEXT NOT NULL,
                progress REAL NOT NULL DEFAULT 0.0,
                error TEXT,
                created_at INTEGER NOT NULL,
                completed_at INTEGER
            );

            CREATE TABLE IF NOT EXISTS settings (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );
            "#,
        )?;

        Ok(())
    }
}
