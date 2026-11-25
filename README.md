# Hi-Fi Music Player

A modern, high-performance music player built with **Flutter** for a sleek, responsive UI and **Rust (`rust_core`)** for the native backend engine.

---

## Features

- **High-Performance Audio Pipeline:** Native Rust core handling audio indexing, queue management, and metadata extraction.
- **Synced Lyrics:** Real-time lyric synchronization with caching and multi-source parsing.
- **Audio Quality & Chain Inspector:** Real-time audio chain visualization, sample rate, bit depth, and DAC output detection.
- **10-Band Equalizer:** Customizable EQ presets and sound enhancements.
- **YouTube Downloader Integration:** Integrated download pipeline for offline playback.
- **Rich Media Notification:** Custom Android media notification with dynamic waveform canvas.
- **Modern UI:** Built with Flutter, Riverpod state management, and modern dark-mode aesthetics.

---

## Architecture

- **Flutter UI** (`flutter_app/lib`): screens per feature, Riverpod providers for player, library, lyrics, output and settings state.
- **Rust core** (`rust_core`): library scanning and metadata parsing, SQLite storage, queue management, synced-lyrics parsing and caching, artwork cache, and the download pipeline. Compiled to `librust_core.so` for Android and called from Dart through FFI (`lib/bridge/rust_bridge.dart`).
- **Android host** (Kotlin): ExoPlayer-based `PlaybackService`, the custom media notification with a waveform, and audio-output (DAC) detection, reached from Dart through platform channels.

---

## Project status

Work in progress. Open items are tracked in [`TODO.md`](TODO.md), including wiring shuffle and repeat through to ExoPlayer and indexing downloaded tracks into the library automatically.

---

## Repository structure

```
mp3/
├── flutter_app/          # Flutter front-end application
│   ├── android/          # Native Android host & ExoPlayer playback service
│   │   └── app/src/main/jniLibs/ # Prebuilt librust_core.so binaries
│   ├── lib/              # Riverpod providers, UI screens, models & services
│   │   ├── bridge/       # FFI / Platform bridge to native core
│   │   ├── features/     # Player, Library, Equalizer, Downloads, Audio Info
│   │   └── providers/    # Reactive state management
│   └── pubspec.yaml
├── rust_core/            # Native Rust engine
│   ├── src/
│   │   ├── audio/        # Audio engine core
│   │   ├── database/     # SQLite database & repository
│   │   ├── downloader/   # Download pipeline & resolver
│   │   ├── library/      # High-speed file scanner & metadata parser
│   │   ├── lyrics/       # Synchronized lyric engine & cache
│   │   └── queue/        # Playback queue manager
│   └── Cargo.toml
├── build_rust_android.ps1# Script to compile rust_core for Android targets
└── TODO.md               # Roadmap and task tracking
```

---

## Getting started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.x+)
- [Rust & Cargo](https://rustup.rs/) (for building `rust_core`)
- Android NDK & `cargo ndk` (if recompiling native `.so` binaries)

### Building the Native Core (Android)

If you modify `rust_core`, rebuild the native libraries with:

```powershell
./build_rust_android.ps1
```

This compiles `librust_core.so` for:
- `aarch64-linux-android` (arm64-v8a)
- `armv7-linux-androideabi` (armeabi-v7a)
- `x86_64-linux-android` (x86_64)

### Running the Flutter App

```bash
cd flutter_app
flutter pub get
flutter run
```

---

## License

This project is licensed under the MIT License.
