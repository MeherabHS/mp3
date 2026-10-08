use crate::database::schema::Schema;
use crate::error::Result;
use crate::models::track::{Album, Artist, Playlist, Track};
use parking_lot::Mutex;
use rusqlite::{params, Connection, OptionalExtension, Row};
use std::path::Path;
use std::sync::Arc;
use uuid::Uuid;

#[derive(Clone)]
pub struct Database {
    conn: Arc<Mutex<Connection>>,
}

impl Database {
    pub fn new<P: AsRef<Path>>(path: P) -> Result<Self> {
        let conn = Connection::open(path)?;
        // Enable WAL mode and busy timeout for high-concurrency safety
        let _ = conn.execute_batch("PRAGMA journal_mode = WAL; PRAGMA busy_timeout = 5000;");
        Schema::create_tables(&conn)?;
        Ok(Self {
            conn: Arc::new(Mutex::new(conn)),
        })
    }

    pub fn in_memory() -> Result<Self> {
        let conn = Connection::open_in_memory()?;
        Schema::create_tables(&conn)?;
        Ok(Self {
            conn: Arc::new(Mutex::new(conn)),
        })
    }

    fn row_to_track(row: &Row) -> rusqlite::Result<Track> {
        let id: String = row.get("id")?;
        let file_path: String = row.get::<_, Option<String>>("file_path")?.unwrap_or_default();
        let title: String = row.get::<_, Option<String>>("title")?.unwrap_or_else(|| "Unknown Track".to_string());
        let artist: String = row.get::<_, Option<String>>("artist")?.unwrap_or_else(|| "Unknown Artist".to_string());
        let album: String = row.get::<_, Option<String>>("album")?.unwrap_or_else(|| "Unknown Album".to_string());
        let album_artist: Option<String> = row.get("album_artist")?;
        let genre: Option<String> = row.get("genre")?;
        let year: Option<u32> = row.get::<_, Option<i64>>("year")?.map(|v| v as u32);
        let track_number: Option<u32> = row.get::<_, Option<i64>>("track_number")?.map(|v| v as u32);
        let disc_number: Option<u32> = row.get::<_, Option<i64>>("disc_number")?.map(|v| v as u32);
        let duration_ms: u64 = row.get::<_, Option<i64>>("duration_ms")?.unwrap_or(0) as u64;
        let codec: String = row.get::<_, Option<String>>("codec")?.unwrap_or_else(|| "MP3".to_string());
        let container: String = row.get::<_, Option<String>>("container")?.unwrap_or_else(|| "mp3".to_string());
        let bitrate_kbps: Option<u32> = row.get::<_, Option<i64>>("bitrate_kbps")?.map(|v| v as u32);
        let sample_rate_hz: Option<u32> = row.get::<_, Option<i64>>("sample_rate_hz")?.map(|v| v as u32);
        let bit_depth: Option<u8> = row.get::<_, Option<i64>>("bit_depth")?.map(|v| v as u8);
        let channels: Option<u8> = row.get::<_, Option<i64>>("channels")?.map(|v| v as u8);
        let lossless: bool = row.get::<_, Option<i64>>("lossless")?.unwrap_or(0) != 0;
        let artwork_path: Option<String> = row.get("artwork_path")?;
        let lyrics_path: Option<String> = row.get("lyrics_path")?;
        let is_favorite: bool = row.get::<_, Option<i64>>("is_favorite")?.unwrap_or(0) != 0;
        let play_count: u64 = row.get::<_, Option<i64>>("play_count")?.unwrap_or(0) as u64;
        let last_played_at: Option<i64> = row.get("last_played_at")?;
        let created_at: i64 = row.get::<_, Option<i64>>("created_at")?.unwrap_or(0);

        Ok(Track {
            id,
            file_path,
            title,
            artist,
            album,
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
            artwork_path,
            lyrics_path,
            is_favorite,
            play_count,
            last_played_at,
            created_at,
        })
    }

    pub fn insert_or_update_track(&self, track: &Track) -> Result<()> {
        let conn = self.conn.lock();
        conn.execute(
            r#"
            INSERT INTO songs (
                id, file_path, title, artist, album, album_artist, genre, year,
                track_number, disc_number, duration_ms, codec, container,
                bitrate_kbps, sample_rate_hz, bit_depth, channels, lossless,
                artwork_path, lyrics_path, is_favorite, play_count, last_played_at, created_at
            ) VALUES (
                ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8,
                ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18,
                ?19, ?20, ?21, ?22, ?23, ?24
            )
            ON CONFLICT(id) DO UPDATE SET
                file_path = excluded.file_path,
                title = excluded.title,
                artist = excluded.artist,
                album = excluded.album,
                album_artist = excluded.album_artist,
                genre = excluded.genre,
                year = excluded.year,
                track_number = excluded.track_number,
                disc_number = excluded.disc_number,
                duration_ms = excluded.duration_ms,
                codec = excluded.codec,
                container = excluded.container,
                bitrate_kbps = excluded.bitrate_kbps,
                sample_rate_hz = excluded.sample_rate_hz,
                bit_depth = excluded.bit_depth,
                channels = excluded.channels,
                lossless = excluded.lossless,
                artwork_path = excluded.artwork_path,
                lyrics_path = excluded.lyrics_path
            "#,
            params![
                track.id,
                track.file_path,
                track.title,
                track.artist,
                track.album,
                track.album_artist,
                track.genre,
                track.year.map(|v| v as i64),
                track.track_number.map(|v| v as i64),
                track.disc_number.map(|v| v as i64),
                track.duration_ms as i64,
                track.codec,
                track.container,
                track.bitrate_kbps.map(|v| v as i64),
                track.sample_rate_hz.map(|v| v as i64),
                track.bit_depth.map(|v| v as i64),
                track.channels.map(|v| v as i64),
                if track.lossless { 1i64 } else { 0i64 },
                track.artwork_path,
                track.lyrics_path,
                if track.is_favorite { 1i64 } else { 0i64 },
                track.play_count as i64,
                track.last_played_at,
                track.created_at,
            ],
        )?;
        Ok(())
    }

    pub fn get_track_by_id(&self, id: &str) -> Result<Option<Track>> {
        let conn = self.conn.lock();
        let mut stmt = conn.prepare("SELECT * FROM songs WHERE id = ?1")?;
        let track = stmt.query_row(params![id], Self::row_to_track).optional()?;
        Ok(track)
    }

    pub fn get_track(&self, id: &str) -> Result<Option<Track>> {
        self.get_track_by_id(id)
    }

    pub fn list_tracks(&self, limit: usize, offset: usize) -> Result<Vec<Track>> {
        let conn = self.conn.lock();
        let mut stmt = conn.prepare(
            "SELECT * FROM songs ORDER BY created_at DESC, title COLLATE NOCASE ASC LIMIT ?1 OFFSET ?2",
        )?;
        let rows = stmt.query_map(params![limit as i64, offset as i64], Self::row_to_track)?;
        let mut tracks = Vec::new();
        for r in rows.flatten() {
            tracks.push(r);
        }
        Ok(tracks)
    }

    pub fn search_tracks(&self, query: &str) -> Result<Vec<Track>> {
        let clean_query = query.trim();
        if clean_query.is_empty() {
            return self.list_tracks(50, 0);
        }
        let pattern = format!("%{}%", clean_query);
        let conn = self.conn.lock();
        let mut stmt = conn.prepare(
            r#"
            SELECT * FROM songs
            WHERE title LIKE ?1 OR artist LIKE ?1 OR album LIKE ?1 OR genre LIKE ?1
            ORDER BY title COLLATE NOCASE ASC LIMIT 50
            "#,
        )?;
        let rows = stmt.query_map(params![pattern], Self::row_to_track)?;
        let mut tracks = Vec::new();
        for r in rows.flatten() {
            tracks.push(r);
        }
        Ok(tracks)
    }

    pub fn list_albums(&self) -> Result<Vec<Album>> {
        let conn = self.conn.lock();
        let mut stmt = conn.prepare(
            r#"
            SELECT COALESCE(NULLIF(album, ''), 'Unknown Album') as title,
                   COALESCE(NULLIF(artist, ''), 'Unknown Artist') as artist,
                   artwork_path,
                   year,
                   COUNT(*) as track_count
            FROM songs
            GROUP BY COALESCE(NULLIF(album, ''), 'Unknown Album'), COALESCE(NULLIF(artist, ''), 'Unknown Artist')
            ORDER BY title COLLATE NOCASE ASC
            "#,
        )?;
        let rows = stmt.query_map([], |row| {
            let title: String = row.get::<_, Option<String>>("title")?.unwrap_or_else(|| "Unknown Album".to_string());
            let artist: String = row.get::<_, Option<String>>("artist")?.unwrap_or_else(|| "Unknown Artist".to_string());
            let id = format!("{}_{}", artist, title);
            let artwork_path: Option<String> = row.get("artwork_path")?;
            let year: Option<u32> = row.get::<_, Option<i64>>("year")?.map(|v| v as u32);
            let track_count: usize = row.get::<_, Option<i64>>("track_count")?.unwrap_or(1) as usize;
            Ok(Album {
                id,
                title,
                artist,
                artwork_path,
                year,
                track_count,
            })
        })?;
        let mut albums = Vec::new();
        for r in rows.flatten() {
            albums.push(r);
        }
        Ok(albums)
    }

    pub fn list_artists(&self) -> Result<Vec<Artist>> {
        let conn = self.conn.lock();
        let mut stmt = conn.prepare(
            r#"
            SELECT COALESCE(NULLIF(artist, ''), 'Unknown Artist') as name,
                   COUNT(DISTINCT COALESCE(NULLIF(album, ''), 'Unknown Album')) as album_count,
                   COUNT(*) as track_count
            FROM songs
            GROUP BY COALESCE(NULLIF(artist, ''), 'Unknown Artist')
            ORDER BY name COLLATE NOCASE ASC
            "#,
        )?;
        let rows = stmt.query_map([], |row| {
            let name: String = row.get::<_, Option<String>>("name")?.unwrap_or_else(|| "Unknown Artist".to_string());
            let album_count: usize = row.get::<_, Option<i64>>("album_count")?.unwrap_or(1) as usize;
            let track_count: usize = row.get::<_, Option<i64>>("track_count")?.unwrap_or(1) as usize;
            Ok(Artist {
                id: name.clone(),
                name,
                album_count,
                track_count,
            })
        })?;
        let mut artists = Vec::new();
        for r in rows.flatten() {
            artists.push(r);
        }
        Ok(artists)
    }

    pub fn get_recently_played(&self, limit: usize) -> Result<Vec<Track>> {
        let conn = self.conn.lock();
        let mut stmt = conn.prepare(
            r#"
            SELECT * FROM songs
            WHERE last_played_at IS NOT NULL
            ORDER BY last_played_at DESC
            LIMIT ?1
            "#,
        )?;
        let rows = stmt.query_map(params![limit as i64], Self::row_to_track)?;
        let mut tracks = Vec::new();
        for r in rows.flatten() {
            tracks.push(r);
        }
        Ok(tracks)
    }

    pub fn get_favorites(&self) -> Result<Vec<Track>> {
        let conn = self.conn.lock();
        let mut stmt = conn.prepare(
            r#"
            SELECT * FROM songs
            WHERE is_favorite = 1
            ORDER BY title COLLATE NOCASE ASC
            "#,
        )?;
        let rows = stmt.query_map([], Self::row_to_track)?;
        let mut tracks = Vec::new();
        for r in rows.flatten() {
            tracks.push(r);
        }
        Ok(tracks)
    }

    pub fn toggle_favorite(&self, id: &str) -> Result<bool> {
        let conn = self.conn.lock();
        let current_state: Option<i64> = conn
            .query_row(
                "SELECT is_favorite FROM songs WHERE id = ?1",
                params![id],
                |row| row.get(0),
            )
            .optional()?;

        let new_state = match current_state {
            Some(1) => 0i64,
            _ => 1i64,
        };

        conn.execute(
            "UPDATE songs SET is_favorite = ?1 WHERE id = ?2",
            params![new_state, id],
        )?;

        Ok(new_state == 1)
    }

    pub fn increment_play_count(&self, id: &str, timestamp: i64) -> Result<()> {
        let conn = self.conn.lock();
        conn.execute(
            r#"
            UPDATE songs
            SET play_count = play_count + 1, last_played_at = ?1
            WHERE id = ?2
            "#,
            params![timestamp, id],
        )?;
        Ok(())
    }

    pub fn list_playlists(&self) -> Result<Vec<Playlist>> {
        let conn = self.conn.lock();
        let mut stmt = conn.prepare(
            r#"
            SELECT p.id, p.name, p.created_at, COUNT(ps.song_id) as track_count
            FROM playlists p
            LEFT JOIN playlist_songs ps ON p.id = ps.playlist_id
            GROUP BY p.id
            ORDER BY p.name COLLATE NOCASE ASC
            "#,
        )?;
        let rows = stmt.query_map([], |row| {
            let id: String = row.get("id")?;
            let name: String = row.get::<_, Option<String>>("name")?.unwrap_or_else(|| "Untitled".to_string());
            let created_at: i64 = row.get::<_, Option<i64>>("created_at")?.unwrap_or(0);
            let track_count: usize = row.get::<_, Option<i64>>("track_count")?.unwrap_or(0) as usize;
            Ok(Playlist {
                id,
                name,
                created_at,
                track_count,
            })
        })?;
        let mut playlists = Vec::new();
        for r in rows.flatten() {
            playlists.push(r);
        }
        Ok(playlists)
    }

    pub fn create_playlist(&self, name: &str) -> Result<Playlist> {
        let id = Uuid::new_v4().to_string();
        let now = chrono::Utc::now().timestamp_millis();
        let conn = self.conn.lock();
        conn.execute(
            "INSERT INTO playlists (id, name, created_at) VALUES (?1, ?2, ?3)",
            params![id, name, now],
        )?;
        Ok(Playlist {
            id,
            name: name.to_string(),
            created_at: now,
            track_count: 0,
        })
    }

    pub fn add_track_to_playlist(&self, playlist_id: &str, track_id: &str) -> Result<()> {
        let conn = self.conn.lock();
        // Use the current max position + 1 so tracks are appended in order
        let pos: i64 = conn
            .query_row(
                "SELECT COALESCE(MAX(position), -1) + 1 FROM playlist_tracks WHERE playlist_id = ?1",
                params![playlist_id],
                |r| r.get(0),
            )
            .unwrap_or(0);
        conn.execute(
            "INSERT OR IGNORE INTO playlist_tracks (playlist_id, track_id, position) VALUES (?1, ?2, ?3)",
            params![playlist_id, track_id, pos],
        )?;
        Ok(())
    }
}
