use crate::audio::AudioEngineCore;
use crate::database::Database;
use crate::downloader::DownloadPipeline;
use crate::library::LibraryScanner;
use crate::models::quality::OutputStatus;
use crate::models::track::Track;
use crate::storage::StorageManager;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::sync::{Arc, OnceLock};

static CORE_INSTANCE: OnceLock<Arc<AudioEngineCore>> = OnceLock::new();
static DB_INSTANCE: OnceLock<Arc<Database>> = OnceLock::new();
static STORAGE_INSTANCE: OnceLock<Arc<StorageManager>> = OnceLock::new();
static PIPELINE_INSTANCE: OnceLock<Arc<DownloadPipeline>> = OnceLock::new();

fn string_to_c_char(s: String) -> *mut c_char {
    let clean = s.replace('\0', "");
    CString::new(clean).unwrap_or_default().into_raw()
}

fn c_char_to_str<'a>(ptr: *const c_char) -> &'a str {
    if ptr.is_null() {
        return "";
    }
    unsafe { CStr::from_ptr(ptr).to_str().unwrap_or("") }
}

#[no_mangle]
pub extern "C" fn core_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            let _ = CString::from_raw(ptr);
        }
    }
}

#[no_mangle]
pub extern "C" fn core_init(
    internal_path: *const c_char,
    sd_card_path: *const c_char,
    ytdlp_path: *const c_char,
) -> *mut c_char {
    let internal = c_char_to_str(internal_path);
    let sd = c_char_to_str(sd_card_path);
    let ytdlp = c_char_to_str(ytdlp_path);

    let storage_res = StorageManager::new(internal, sd);
    let storage = match storage_res {
        Ok(s) => Arc::new(s),
        Err(e) => return string_to_c_char(format!("{{\"error\":\"{}\"}}", e)),
    };

    let db_res = Database::new(storage.get_database_path());
    let db = match db_res {
        Ok(d) => Arc::new(d),
        Err(e) => return string_to_c_char(format!("{{\"error\":\"{}\"}}", e)),
    };

    let engine = Arc::new(AudioEngineCore::new(db.clone(), storage.clone()));
    let pipeline = Arc::new(DownloadPipeline::new(ytdlp, db.clone(), storage.clone()));

    let _ = STORAGE_INSTANCE.set(storage);
    let _ = DB_INSTANCE.set(db);
    let _ = CORE_INSTANCE.set(engine);
    let _ = PIPELINE_INSTANCE.set(pipeline);

    string_to_c_char("{\"success\":true}".to_string())
}

#[no_mangle]
pub extern "C" fn core_get_player_state() -> *mut c_char {
    if let Some(engine) = CORE_INSTANCE.get() {
        let state = engine.get_state();
        let json = serde_json::to_string(&state).unwrap_or_else(|e| format!("{{\"error\":\"{}\"}}", e));
        string_to_c_char(json)
    } else {
        string_to_c_char("{\"error\":\"Core not initialized\"}".to_string())
    }
}

#[no_mangle]
pub extern "C" fn core_load_track(track_id: *const c_char) -> *mut c_char {
    let id = c_char_to_str(track_id);
    if let Some(engine) = CORE_INSTANCE.get() {
        match engine.load_track(id) {
            Ok(state) => string_to_c_char(serde_json::to_string(&state).unwrap_or_default()),
            Err(e) => string_to_c_char(format!("{{\"error\":\"{}\"}}", e)),
        }
    } else {
        string_to_c_char("{\"error\":\"Core not initialized\"}".to_string())
    }
}

#[no_mangle]
pub extern "C" fn core_play() -> *mut c_char {
    if let Some(engine) = CORE_INSTANCE.get() {
        match engine.play() {
            Ok(state) => string_to_c_char(serde_json::to_string(&state).unwrap_or_default()),
            Err(e) => string_to_c_char(format!("{{\"error\":\"{}\"}}", e)),
        }
    } else {
        string_to_c_char("{\"error\":\"Core not initialized\"}".to_string())
    }
}

#[no_mangle]
pub extern "C" fn core_pause() -> *mut c_char {
    if let Some(engine) = CORE_INSTANCE.get() {
        match engine.pause() {
            Ok(state) => string_to_c_char(serde_json::to_string(&state).unwrap_or_default()),
            Err(e) => string_to_c_char(format!("{{\"error\":\"{}\"}}", e)),
        }
    } else {
        string_to_c_char("{\"error\":\"Core not initialized\"}".to_string())
    }
}

#[no_mangle]
pub extern "C" fn core_seek(position_ms: u64) -> *mut c_char {
    if let Some(engine) = CORE_INSTANCE.get() {
        match engine.seek(position_ms) {
            Ok(sync) => string_to_c_char(serde_json::to_string(&sync).unwrap_or_default()),
            Err(e) => string_to_c_char(format!("{{\"error\":\"{}\"}}", e)),
        }
    } else {
        string_to_c_char("{\"error\":\"Core not initialized\"}".to_string())
    }
}

#[no_mangle]
pub extern "C" fn core_next() -> *mut c_char {
    if let Some(engine) = CORE_INSTANCE.get() {
        match engine.next() {
            Ok(Some(state)) => string_to_c_char(serde_json::to_string(&state).unwrap_or_default()),
            Ok(None) => string_to_c_char("{\"end_of_queue\":true}".to_string()),
            Err(e) => string_to_c_char(format!("{{\"error\":\"{}\"}}", e)),
        }
    } else {
        string_to_c_char("{\"error\":\"Core not initialized\"}".to_string())
    }
}

#[no_mangle]
pub extern "C" fn core_previous() -> *mut c_char {
    if let Some(engine) = CORE_INSTANCE.get() {
        match engine.previous() {
            Ok(Some(state)) => string_to_c_char(serde_json::to_string(&state).unwrap_or_default()),
            Ok(None) => string_to_c_char("{\"beginning_of_queue\":true}".to_string()),
            Err(e) => string_to_c_char(format!("{{\"error\":\"{}\"}}", e)),
        }
    } else {
        string_to_c_char("{\"error\":\"Core not initialized\"}".to_string())
    }
}

#[no_mangle]
pub extern "C" fn core_set_queue(tracks_json: *const c_char, start_index: usize) -> *mut c_char {
    let json_str = c_char_to_str(tracks_json);
    let tracks: Vec<Track> = match serde_json::from_str(json_str) {
        Ok(t) => t,
        Err(e) => return string_to_c_char(format!("{{\"error\":\"{}\"}}", e)),
    };

    if let Some(engine) = CORE_INSTANCE.get() {
        match engine.set_queue(tracks, start_index) {
            Ok(state) => string_to_c_char(serde_json::to_string(&state).unwrap_or_default()),
            Err(e) => string_to_c_char(format!("{{\"error\":\"{}\"}}", e)),
        }
    } else {
        string_to_c_char("{\"error\":\"Core not initialized\"}".to_string())
    }
}

#[no_mangle]
pub extern "C" fn core_update_position(position_ms: u64) -> *mut c_char {
    if let Some(engine) = CORE_INSTANCE.get() {
        let sync = engine.update_position(position_ms);
        string_to_c_char(serde_json::to_string(&sync).unwrap_or_default())
    } else {
        string_to_c_char("{\"error\":\"Core not initialized\"}".to_string())
    }
}

#[no_mangle]
pub extern "C" fn core_update_output_status(status_json: *const c_char) -> *mut c_char {
    let json_str = c_char_to_str(status_json);
    let status: OutputStatus = match serde_json::from_str(json_str) {
        Ok(s) => s,
        Err(e) => return string_to_c_char(format!("{{\"error\":\"{}\"}}", e)),
    };

    if let Some(engine) = CORE_INSTANCE.get() {
        match engine.update_output_status(status) {
            Ok(state) => string_to_c_char(serde_json::to_string(&state).unwrap_or_default()),
            Err(e) => string_to_c_char(format!("{{\"error\":\"{}\"}}", e)),
        }
    } else {
        string_to_c_char("{\"error\":\"Core not initialized\"}".to_string())
    }
}

#[no_mangle]
pub extern "C" fn core_get_lyrics(track_id: *const c_char) -> *mut c_char {
    let id = c_char_to_str(track_id);
    if let Some(engine) = CORE_INSTANCE.get() {
        match engine.get_lyrics(id) {
            Ok(lyrics) => string_to_c_char(serde_json::to_string(&lyrics).unwrap_or_default()),
            Err(e) => string_to_c_char(format!("{{\"error\":\"{}\"}}", e)),
        }
    } else {
        string_to_c_char("{\"error\":\"Core not initialized\"}".to_string())
    }
}

#[no_mangle]
pub extern "C" fn core_sync_lyrics(position_ms: u64) -> *mut c_char {
    if let Some(engine) = CORE_INSTANCE.get() {
        let sync = engine.sync_lyrics_at_position(position_ms);
        string_to_c_char(serde_json::to_string(&sync).unwrap_or_default())
    } else {
        string_to_c_char("{\"error\":\"Core not initialized\"}".to_string())
    }
}

#[no_mangle]
pub extern "C" fn core_list_tracks(limit: usize, offset: usize) -> *mut c_char {
    if let Some(db) = DB_INSTANCE.get() {
        match db.list_tracks(limit, offset) {
            Ok(tracks) => string_to_c_char(serde_json::to_string(&tracks).unwrap_or_default()),
            Err(e) => string_to_c_char(format!("{{\"error\":\"{}\"}}", e)),
        }
    } else {
        string_to_c_char("{\"error\":\"DB not initialized\"}".to_string())
    }
}

#[no_mangle]
pub extern "C" fn core_search_tracks(query: *const c_char) -> *mut c_char {
    let q = c_char_to_str(query);
    if let Some(db) = DB_INSTANCE.get() {
        match db.search_tracks(q) {
            Ok(tracks) => string_to_c_char(serde_json::to_string(&tracks).unwrap_or_default()),
            Err(e) => string_to_c_char(format!("{{\"error\":\"{}\"}}", e)),
        }
    } else {
        string_to_c_char("{\"error\":\"DB not initialized\"}".to_string())
    }
}

#[no_mangle]
pub extern "C" fn core_list_albums() -> *mut c_char {
    if let Some(db) = DB_INSTANCE.get() {
        match db.list_albums() {
            Ok(albums) => string_to_c_char(serde_json::to_string(&albums).unwrap_or_default()),
            Err(e) => string_to_c_char(format!("{{\"error\":\"{}\"}}", e)),
        }
    } else {
        string_to_c_char("{\"error\":\"DB not initialized\"}".to_string())
    }
}

#[no_mangle]
pub extern "C" fn core_list_artists() -> *mut c_char {
    if let Some(db) = DB_INSTANCE.get() {
        match db.list_artists() {
            Ok(artists) => string_to_c_char(serde_json::to_string(&artists).unwrap_or_default()),
            Err(e) => string_to_c_char(format!("{{\"error\":\"{}\"}}", e)),
        }
    } else {
        string_to_c_char("{\"error\":\"DB not initialized\"}".to_string())
    }
}

#[no_mangle]
pub extern "C" fn core_list_playlists() -> *mut c_char {
    if let Some(db) = DB_INSTANCE.get() {
        match db.list_playlists() {
            Ok(playlists) => string_to_c_char(serde_json::to_string(&playlists).unwrap_or_default()),
            Err(e) => string_to_c_char(format!("{{\"error\":\"{}\"}}", e)),
        }
    } else {
        string_to_c_char("{\"error\":\"DB not initialized\"}".to_string())
    }
}

#[no_mangle]
pub extern "C" fn core_get_recently_played(limit: usize) -> *mut c_char {
    if let Some(db) = DB_INSTANCE.get() {
        match db.get_recently_played(limit) {
            Ok(tracks) => string_to_c_char(serde_json::to_string(&tracks).unwrap_or_default()),
            Err(e) => string_to_c_char(format!("{{\"error\":\"{}\"}}", e)),
        }
    } else {
        string_to_c_char("{\"error\":\"DB not initialized\"}".to_string())
    }
}

#[no_mangle]
pub extern "C" fn core_get_favorites() -> *mut c_char {
    if let Some(db) = DB_INSTANCE.get() {
        match db.get_favorites() {
            Ok(tracks) => string_to_c_char(serde_json::to_string(&tracks).unwrap_or_default()),
            Err(e) => string_to_c_char(format!("{{\"error\":\"{}\"}}", e)),
        }
    } else {
        string_to_c_char("{\"error\":\"DB not initialized\"}".to_string())
    }
}

#[no_mangle]
pub extern "C" fn core_toggle_favorite(track_id: *const c_char) -> *mut c_char {
    let id = c_char_to_str(track_id);
    if let Some(db) = DB_INSTANCE.get() {
        match db.toggle_favorite(id) {
            Ok(is_fav) => string_to_c_char(format!("{{\"is_favorite\":{}}}", is_fav)),
            Err(e) => string_to_c_char(format!("{{\"error\":\"{}\"}}", e)),
        }
    } else {
        string_to_c_char("{\"error\":\"DB not initialized\"}".to_string())
    }
}

#[no_mangle]
pub extern "C" fn core_scan_directory(dir_path: *const c_char) -> *mut c_char {
    let dir = c_char_to_str(dir_path);
    if let (Some(db), Some(storage)) = (DB_INSTANCE.get(), STORAGE_INSTANCE.get()) {
        match LibraryScanner::scan_directory(db, storage, dir) {
            Ok(count) => string_to_c_char(format!("{{\"indexed_count\":{}}}", count)),
            Err(e) => string_to_c_char(format!("{{\"error\":\"{}\"}}", e)),
        }
    } else {
        string_to_c_char("{\"error\":\"Core not initialized\"}".to_string())
    }
}

#[no_mangle]
pub extern "C" fn core_scan_file(file_path: *const c_char) -> *mut c_char {
    let path = c_char_to_str(file_path);
    if let (Some(db), Some(storage)) = (DB_INSTANCE.get(), STORAGE_INSTANCE.get()) {
        match LibraryScanner::scan_file(db, storage, path) {
            Ok(Some(track)) => string_to_c_char(serde_json::to_string(&track).unwrap_or_default()),
            Ok(None) => string_to_c_char("{\"error\":\"File not found or unreadable\"}".to_string()),
            Err(e) => string_to_c_char(format!("{{\"error\":\"{}\"}}", e)),
        }
    } else {
        string_to_c_char("{\"error\":\"Core not initialized\"}".to_string())
    }
}

/// Start a YouTube download job.
/// Returns a JSON DownloadJob immediately (stage = queued) then processes synchronously.
/// For background use, the caller should invoke this on a background thread.
#[no_mangle]
pub extern "C" fn core_download_yt(url: *const c_char) -> *mut c_char {
    let url_str = c_char_to_str(url);
    if let Some(pipeline) = PIPELINE_INSTANCE.get() {
        match pipeline.run(url_str) {
            Ok(job) => string_to_c_char(serde_json::to_string(&job).unwrap_or_default()),
            Err(e) => string_to_c_char(format!("{{\"error\":\"{}\"}}", e)),
        }
    } else {
        string_to_c_char("{\"error\":\"Downloader not initialized\"}".to_string())
    }
}

/// Create a new named playlist. Returns the Playlist as JSON.
#[no_mangle]
pub extern "C" fn core_create_playlist(name: *const c_char) -> *mut c_char {
    let name_str = c_char_to_str(name);
    if let Some(db) = DB_INSTANCE.get() {
        match db.create_playlist(name_str) {
            Ok(pl) => string_to_c_char(serde_json::to_string(&pl).unwrap_or_default()),
            Err(e) => string_to_c_char(format!("{{\"error\":\"{}\"}}", e)),
        }
    } else {
        string_to_c_char("{\"error\":\"DB not initialized\"}".to_string())
    }
}

/// Add a track to an existing playlist. Returns `{"ok":true}` on success.
#[no_mangle]
pub extern "C" fn core_add_track_to_playlist(
    playlist_id: *const c_char,
    track_id: *const c_char,
) -> *mut c_char {
    let pid = c_char_to_str(playlist_id);
    let tid = c_char_to_str(track_id);
    if let Some(db) = DB_INSTANCE.get() {
        match db.add_track_to_playlist(pid, tid) {
            Ok(()) => string_to_c_char("{\"ok\":true}".to_string()),
            Err(e) => string_to_c_char(format!("{{\"error\":\"{}\"}}", e)),
        }
    } else {
        string_to_c_char("{\"error\":\"DB not initialized\"}".to_string())
    }
}

/// List all download jobs (completed + in progress).
#[no_mangle]
pub extern "C" fn core_get_download_jobs() -> *mut c_char {
    if let Some(pipeline) = PIPELINE_INSTANCE.get() {
        let jobs = pipeline.list_jobs();
        string_to_c_char(serde_json::to_string(&jobs).unwrap_or_default())
    } else {
        string_to_c_char("[]".to_string())
    }
}
