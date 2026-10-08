# Music Player — TODO

Last updated: Aug 25, 2026

---

## Priority 1 — Core Engine (Blockers)

- [ ] **Run Rust build**
  - Execute `build_rust_android.ps1` with `cargo ndk`
  - Targets: `aarch64-linux-android`, `armv7-linux-androideabi`, `x86_64-linux-android`
  - Output `.so` files must land in `android/app/src/main/jniLibs/`
  - Until this runs: DB, library scanner, queue persistence, artwork cache are all silent

---

## Priority 2 — Quick Fixes (Each under 30 min)

- [ ] **Wire shuffle/repeat to ExoPlayer**
  - `PlayerNotifier.toggleShuffle()` updates Dart state but never calls ExoPlayer
  - Fix: `_playbackChannel.invokeMethod('setShuffle', {'enabled': state.shuffle})`
  - Same for repeat: map `RepeatMode` → ExoPlayer `REPEAT_MODE_OFF / ALL / ONE`
  - Android side: handle in `PlaybackService.kt`

- [ ] **Auto-index track after YouTube download**
  - After `YtDlpHelper.downloadAudio()` completes, the downloaded file is not added to the library
  - Fix: call `RustBridge.instance.scanFile(filePath)` or trigger a lightweight rescan
  - User currently has to manually pull-to-refresh the library

---

## Priority 3 — Audio & Notification

- [ ] **Real waveform amplitude pipeline**
  - Currently notification waveform draws placeholder/dummy bars
  - Plan: at import time, compute 64 RMS amplitude floats across the track duration
  - Store as a `BLOB` column in the tracks DB table
  - On playback start, send the 64 floats to `PlaybackService` via MethodChannel
  - `PlaybackService` draws the real waveform on the `RemoteViews` canvas

- [ ] **Dominant-colour gradient in notification**
  - Album art is set as `largeIcon` but fades flat
  - Plan: use Android `Palette.from(bitmap)` to extract dominant dark colour
  - Apply as a left→right gradient behind the waveform `RemoteViews`

---

## Priority 4 — Lyrics Improvements

- [ ] **Genius fallback for missing lyrics**
  - Songs not in LRCLIB (regional, niche, very new releases) have no fallback
  - Genius has plain lyrics for nearly everything
  - Option A: unofficial scrape (against ToS, but common in OSS players)
  - Option B: use a community mirror / proxy API
  - Plain lyrics only — no timestamps, so sync won't work, but text will show

- [ ] **MusicBrainz ID tag lookup**
  - Files tagged with `MUSICBRAINZ_TRACKID` can use LRCLIB's `/api/get?mbid=` endpoint
  - This bypasses all title/artist guessing — 100% accurate match
  - Fix: in `LyricsService.fetchLyrics`, check `track.mbid` before step 2

- [ ] **Local `.lrc` file import UI**
  - The sidecar logic already reads a `.lrc` next to the audio file
  - Missing: a file picker in the Now Playing screen to let user assign a `.lrc` manually
  - Good for Bangla / regional songs not in any online database

---

## Priority 5 — App Completeness

- [ ] **Backup / restore**
  - Settings screen has the placeholder UI
  - Plan: export DB + settings JSON to a zip in the selected storage path
  - Import: pick zip, restore DB, re-scan artwork

- [ ] **File integrity verification**
  - Planned in architecture doc, never started
  - On import: compute and store SHA-256 of each audio file
  - Periodic check: compare stored hash vs current file — flag moved/corrupted files

- [ ] **Word-level lyrics**
  - `LyricWord` model + `lyrics_display.dart` rendering already exist
  - LRCLIB only provides line-level `.lrc` — no word timestamps
  - Would need Musixmatch Enhanced LRC or similar source
  - Low priority until a reliable free source is identified

---

## Done (reference)

- [x] Library scan — proper MediaStore filters, no crash on 87+ tracks
- [x] Lyrics fetch — 5-tier LRCLIB strategy with sidecar caching
- [x] Lyrics sync — pure-Dart binary search on position ticks
- [x] Lyrics scroll — smooth `Scrollable.ensureVisible`, no overshoot
- [x] Retry button — evicts all cache layers, forces immediate re-fetch
- [x] Seek slider — `_isSeeking` flag, no slider fight
- [x] Track change UI sync — `onMediaItemTransition` → Dart `currentTrack` update
- [x] Equalizer — 7-band EQ + BassBoost + Virtualizer + LoudnessEnhancer → Android AudioEffect
- [x] YouTube download — `youtubedl-android` (yt-dlp) + metadata embedding
- [x] Playlist create/add UI
- [x] Settings screen — name, performance mode, storage path, persisted
- [x] Audio output badge — Bluetooth codec detection
- [x] Artwork processing — size guards, fast resize, no OOM
- [x] Media notification — waveform RemoteViews layout
