import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import '../models/audio_quality.dart';
import '../models/lyrics.dart';
import '../models/player_state.dart';
import '../models/track.dart';

// ─── Native typedefs ──────────────────────────────────────────────────────────
typedef NativeFreeString = Void Function(Pointer<Utf8>);
typedef DartFreeString = void Function(Pointer<Utf8>);

// 3-arg init (internal, sd, ytdlp)
typedef NativeInit = Pointer<Utf8> Function(
    Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);
typedef DartInit = Pointer<Utf8> Function(
    Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);

typedef NativeNoArgsString = Pointer<Utf8> Function();
typedef DartNoArgsString = Pointer<Utf8> Function();

typedef NativeStringArgString = Pointer<Utf8> Function(Pointer<Utf8>);
typedef DartStringArgString = Pointer<Utf8> Function(Pointer<Utf8>);

typedef NativeU64ArgString = Pointer<Utf8> Function(Uint64);
typedef DartU64ArgString = Pointer<Utf8> Function(int);

typedef NativeSetQueue = Pointer<Utf8> Function(Pointer<Utf8>, IntPtr);
typedef DartSetQueue = Pointer<Utf8> Function(Pointer<Utf8>, int);

typedef NativePagination = Pointer<Utf8> Function(IntPtr, IntPtr);
typedef DartPagination = Pointer<Utf8> Function(int, int);

typedef NativeTwoStringArgs = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef DartTwoStringArgs = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);

// ─── RustBridge ──────────────────────────────────────────────────────────────
class RustBridge {
  static final RustBridge instance = RustBridge._internal();
  late DynamicLibrary _dylib;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  late DartFreeString _freeString;
  late DartInit _init;
  late DartNoArgsString _getPlayerState;
  late DartStringArgString _loadTrack;
  late DartNoArgsString _play;
  late DartNoArgsString _pause;
  late DartU64ArgString _seek;
  late DartNoArgsString _next;
  late DartNoArgsString _previous;
  late DartSetQueue _setQueue;
  late DartU64ArgString _updatePosition;
  late DartStringArgString _updateOutputStatus;
  late DartStringArgString _getLyrics;
  late DartU64ArgString _syncLyrics;
  late DartPagination _listTracks;
  late DartStringArgString _searchTracks;
  late DartNoArgsString _listAlbums;
  late DartNoArgsString _listArtists;
  late DartNoArgsString _listPlaylists;
  late DartU64ArgString _getRecentlyPlayed;
  late DartNoArgsString _getFavorites;
  late DartStringArgString _toggleFavorite;
  late DartStringArgString _scanDirectory;
  late DartStringArgString _scanFile;
  // Playlists
  late DartStringArgString _createPlaylist;
  late DartTwoStringArgs _addTrackToPlaylist;
  // Downloader
  late DartStringArgString _downloadYt;
  late DartNoArgsString _getDownloadJobs;

  RustBridge._internal() {
    _loadLibrary();
    _bindFunctions();
  }

  void _loadLibrary() {
    if (Platform.isAndroid) {
      try {
        _dylib = DynamicLibrary.open('librust_core.so');
      } catch (_) {
        _dylib = DynamicLibrary.process();
      }
    } else if (Platform.isWindows) {
      try {
        _dylib = DynamicLibrary.open('../rust_core/target/debug/rust_core.dll');
      } catch (_) {
        try {
          _dylib = DynamicLibrary.open('rust_core.dll');
        } catch (_) {
          _dylib = DynamicLibrary.process();
        }
      }
    } else {
      _dylib = DynamicLibrary.process();
    }
  }

  void _bindFunctions() {
    try {
      _freeString = _dylib
          .lookup<NativeFunction<NativeFreeString>>('core_free_string')
          .asFunction();
      _init = _dylib
          .lookup<NativeFunction<NativeInit>>('core_init')
          .asFunction();
      _getPlayerState = _dylib
          .lookup<NativeFunction<NativeNoArgsString>>('core_get_player_state')
          .asFunction();
      _loadTrack = _dylib
          .lookup<NativeFunction<NativeStringArgString>>('core_load_track')
          .asFunction();
      _play =
          _dylib.lookup<NativeFunction<NativeNoArgsString>>('core_play').asFunction();
      _pause =
          _dylib.lookup<NativeFunction<NativeNoArgsString>>('core_pause').asFunction();
      _seek =
          _dylib.lookup<NativeFunction<NativeU64ArgString>>('core_seek').asFunction();
      _next =
          _dylib.lookup<NativeFunction<NativeNoArgsString>>('core_next').asFunction();
      _previous = _dylib
          .lookup<NativeFunction<NativeNoArgsString>>('core_previous')
          .asFunction();
      _setQueue = _dylib
          .lookup<NativeFunction<NativeSetQueue>>('core_set_queue')
          .asFunction();
      _updatePosition = _dylib
          .lookup<NativeFunction<NativeU64ArgString>>('core_update_position')
          .asFunction();
      _updateOutputStatus = _dylib
          .lookup<NativeFunction<NativeStringArgString>>(
              'core_update_output_status')
          .asFunction();
      _getLyrics = _dylib
          .lookup<NativeFunction<NativeStringArgString>>('core_get_lyrics')
          .asFunction();
      _syncLyrics = _dylib
          .lookup<NativeFunction<NativeU64ArgString>>('core_sync_lyrics')
          .asFunction();
      _listTracks = _dylib
          .lookup<NativeFunction<NativePagination>>('core_list_tracks')
          .asFunction();
      _searchTracks = _dylib
          .lookup<NativeFunction<NativeStringArgString>>('core_search_tracks')
          .asFunction();
      _listAlbums = _dylib
          .lookup<NativeFunction<NativeNoArgsString>>('core_list_albums')
          .asFunction();
      _listArtists = _dylib
          .lookup<NativeFunction<NativeNoArgsString>>('core_list_artists')
          .asFunction();
      _listPlaylists = _dylib
          .lookup<NativeFunction<NativeNoArgsString>>('core_list_playlists')
          .asFunction();
      _getRecentlyPlayed = _dylib
          .lookup<NativeFunction<NativeU64ArgString>>('core_get_recently_played')
          .asFunction();
      _getFavorites = _dylib
          .lookup<NativeFunction<NativeNoArgsString>>('core_get_favorites')
          .asFunction();
      _toggleFavorite = _dylib
          .lookup<NativeFunction<NativeStringArgString>>('core_toggle_favorite')
          .asFunction();
      _scanDirectory = _dylib
          .lookup<NativeFunction<NativeStringArgString>>('core_scan_directory')
          .asFunction();
      _scanFile = _dylib
          .lookup<NativeFunction<NativeStringArgString>>('core_scan_file')
          .asFunction();
      _createPlaylist = _dylib
          .lookup<NativeFunction<NativeStringArgString>>('core_create_playlist')
          .asFunction();
      _addTrackToPlaylist = _dylib
          .lookup<NativeFunction<NativeTwoStringArgs>>('core_add_track_to_playlist')
          .asFunction();
      _downloadYt = _dylib
          .lookup<NativeFunction<NativeStringArgString>>('core_download_yt')
          .asFunction();
      _getDownloadJobs = _dylib
          .lookup<NativeFunction<NativeNoArgsString>>('core_get_download_jobs')
          .asFunction();
    } catch (_) {
      // Stub fallback — native library not available in test environment
    }
  }

  String _callAndFree(Pointer<Utf8> Function() ffiCall) {
    try {
      final ptr = ffiCall();
      if (ptr == nullptr) return '{}';
      final str = ptr.toDartString();
      _freeString(ptr);
      return str;
    } catch (_) {
      return '{}';
    }
  }

  bool init(String internalPath, String sdCardPath, String ytdlpPath) {
    final internalPtr = internalPath.toNativeUtf8();
    final sdPtr = sdCardPath.toNativeUtf8();
    final ytdlpPtr = ytdlpPath.toNativeUtf8();
    final jsonStr = _callAndFree(() => _init(internalPtr, sdPtr, ytdlpPtr));
    calloc.free(internalPtr);
    calloc.free(sdPtr);
    calloc.free(ytdlpPtr);
    _isInitialized = true;
    return jsonStr.contains('"success":true');
  }

  PlayerState getPlayerState() {
    final jsonStr = _callAndFree(() => _getPlayerState());
    if (jsonStr.isEmpty || jsonStr == '{}') return const PlayerState();
    return PlayerState.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
  }

  PlayerState loadTrack(String trackId) {
    final idPtr = trackId.toNativeUtf8();
    final jsonStr = _callAndFree(() => _loadTrack(idPtr));
    calloc.free(idPtr);
    try {
      return PlayerState.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
    } catch (_) {
      return const PlayerState();
    }
  }

  PlayerState play() {
    final jsonStr = _callAndFree(() => _play());
    try {
      return PlayerState.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
    } catch (_) {
      return const PlayerState();
    }
  }

  PlayerState pause() {
    final jsonStr = _callAndFree(() => _pause());
    try {
      return PlayerState.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
    } catch (_) {
      return const PlayerState();
    }
  }

  LyricsSyncState seek(int positionMs) {
    final jsonStr = _callAndFree(() => _seek(positionMs));
    try {
      return LyricsSyncState.fromJson(
          jsonDecode(jsonStr) as Map<String, dynamic>);
    } catch (_) {
      return const LyricsSyncState();
    }
  }

  PlayerState? next() {
    final jsonStr = _callAndFree(() => _next());
    if (jsonStr.contains('end_of_queue')) return null;
    try {
      return PlayerState.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  PlayerState? previous() {
    final jsonStr = _callAndFree(() => _previous());
    if (jsonStr.contains('beginning_of_queue')) return null;
    try {
      return PlayerState.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  PlayerState setQueue(List<Track> tracks, int startIndex) {
    final jsonPayload = jsonEncode(tracks.map((t) => t.toJson()).toList());
    final tracksPtr = jsonPayload.toNativeUtf8();
    final jsonStr = _callAndFree(() => _setQueue(tracksPtr, startIndex));
    calloc.free(tracksPtr);
    try {
      return PlayerState.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
    } catch (_) {
      return const PlayerState();
    }
  }

  LyricsSyncState updatePosition(int positionMs) {
    final jsonStr = _callAndFree(() => _updatePosition(positionMs));
    try {
      return LyricsSyncState.fromJson(
          jsonDecode(jsonStr) as Map<String, dynamic>);
    } catch (_) {
      return const LyricsSyncState();
    }
  }

  PlayerState updateOutputStatus(OutputStatus status) {
    final jsonPayload = jsonEncode({
      'output_type': status.outputType.name,
      'device_name': status.deviceName,
      'codec': status.codec,
      'bitrate_kbps': status.bitrateKbps,
      'sample_rate_hz': status.sampleRateHz,
      'bit_depth': status.bitDepth,
      'is_connected': status.isConnected,
    });
    final statusPtr = jsonPayload.toNativeUtf8();
    final jsonStr = _callAndFree(() => _updateOutputStatus(statusPtr));
    calloc.free(statusPtr);
    try {
      return PlayerState.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
    } catch (_) {
      return const PlayerState();
    }
  }

  SyncedLyrics getLyrics(String trackId) {
    final idPtr = trackId.toNativeUtf8();
    final jsonStr = _callAndFree(() => _getLyrics(idPtr));
    calloc.free(idPtr);
    try {
      return SyncedLyrics.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
    } catch (_) {
      return const SyncedLyrics();
    }
  }

  LyricsSyncState syncLyrics(int positionMs) {
    final jsonStr = _callAndFree(() => _syncLyrics(positionMs));
    try {
      return LyricsSyncState.fromJson(
          jsonDecode(jsonStr) as Map<String, dynamic>);
    } catch (_) {
      return const LyricsSyncState();
    }
  }

  List<T> _safeDecodeList<T>(
    String jsonStr,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (jsonStr.isEmpty || jsonStr == '{}' || jsonStr.startsWith('{"error"')) {
      return [];
    }
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is! List) return [];
      final result = <T>[];
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          try {
            result.add(fromJson(item));
          } catch (_) {}
        }
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  List<Track> listTracks({int limit = 100, int offset = 0}) {
    final jsonStr = _callAndFree(() => _listTracks(limit, offset));
    return _safeDecodeList(jsonStr, Track.fromJson);
  }

  List<Track> searchTracks(String query) {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];
    final qPtr = cleanQuery.toNativeUtf8();
    final jsonStr = _callAndFree(() => _searchTracks(qPtr));
    calloc.free(qPtr);
    return _safeDecodeList(jsonStr, Track.fromJson);
  }

  List<Album> listAlbums() {
    final jsonStr = _callAndFree(() => _listAlbums());
    return _safeDecodeList(jsonStr, Album.fromJson);
  }

  List<Artist> listArtists() {
    final jsonStr = _callAndFree(() => _listArtists());
    return _safeDecodeList(jsonStr, Artist.fromJson);
  }

  List<Playlist> listPlaylists() {
    final jsonStr = _callAndFree(() => _listPlaylists());
    return _safeDecodeList(jsonStr, Playlist.fromJson);
  }

  List<Track> getRecentlyPlayed({int limit = 20}) {
    final jsonStr = _callAndFree(() => _getRecentlyPlayed(limit));
    return _safeDecodeList(jsonStr, Track.fromJson);
  }

  List<Track> getFavorites() {
    final jsonStr = _callAndFree(() => _getFavorites());
    return _safeDecodeList(jsonStr, Track.fromJson);
  }

  bool toggleFavorite(String trackId) {
    final idPtr = trackId.toNativeUtf8();
    final jsonStr = _callAndFree(() => _toggleFavorite(idPtr));
    calloc.free(idPtr);
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return map['is_favorite'] as bool? ?? false;
    } catch (_) {
      return false;
    }
  }

  int scanDirectory(String dirPath) {
    final dirPtr = dirPath.toNativeUtf8();
    final jsonStr = _callAndFree(() => _scanDirectory(dirPtr));
    calloc.free(dirPtr);
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return (map['indexed_count'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Track? scanFile(String filePath) {
    final filePtr = filePath.toNativeUtf8();
    final jsonStr = _callAndFree(() => _scanFile(filePtr));
    calloc.free(filePtr);
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      if (map.containsKey('error')) return null;
      return Track.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  // ─── Playlists ─────────────────────────────────────────────────────────────

  /// Create a playlist and return it, or null on error.
  Playlist? createPlaylist(String name) {
    final ptr = name.toNativeUtf8();
    final jsonStr = _callAndFree(() => _createPlaylist(ptr));
    calloc.free(ptr);
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      if (map.containsKey('error')) return null;
      return Playlist.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  /// Add a track to a playlist. Returns true on success.
  bool addTrackToPlaylist(String playlistId, String trackId) {
    final pidPtr = playlistId.toNativeUtf8();
    final tidPtr = trackId.toNativeUtf8();
    final jsonStr = _callAndFree(() => _addTrackToPlaylist(pidPtr, tidPtr));
    calloc.free(pidPtr);
    calloc.free(tidPtr);
    return jsonStr.contains('"ok":true');
  }

  // ─── Downloader ────────────────────────────────────────────────────────────

  /// Start a YouTube download. Returns a DownloadJob map when done.
  Map<String, dynamic> downloadYt(String url) {
    final urlPtr = url.toNativeUtf8();
    final jsonStr = _callAndFree(() => _downloadYt(urlPtr));
    calloc.free(urlPtr);
    try {
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (_) {
      return {'error': 'parse error'};
    }
  }

  /// List all download jobs (completed + failed).
  List<Map<String, dynamic>> getDownloadJobs() {
    final jsonStr = _callAndFree(() => _getDownloadJobs());
    try {
      final list = jsonDecode(jsonStr) as List<dynamic>;
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }
}
