import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../bridge/rust_bridge.dart';
import '../models/audio_quality.dart';
import '../models/player_state.dart';
import '../models/track.dart';

// ─── Playback MethodChannel (Dart → Android ExoPlayer) ───────────────────────
const _playbackChannel = MethodChannel('com.hifi.musicplayer/playback');

final playerProvider =
    StateNotifierProvider<PlayerNotifier, PlayerState>((ref) {
  return PlayerNotifier();
});

class PlayerNotifier extends StateNotifier<PlayerState> {
  PlayerNotifier() : super(const PlayerState()) {
    _setupAndroidCallbacks();
    _refreshState();
  }

  // ─── Android callbacks ────────────────────────────────────────────────────

  void _setupAndroidCallbacks() {
    _playbackChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onPlaybackStateChanged':
          final map = call.arguments as Map?;
          if (map != null) {
            _onAndroidStateChanged(
              isPlaying: map['isPlaying'] as bool? ?? false,
              positionMs: (map['positionMs'] as num?)?.toInt() ?? 0,
              durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
            );
          }
          break;
        case 'onPositionChanged':
          _onPositionTick(call.arguments);
          break;
        // ExoPlayer auto-advanced to a new item in its queue.
        // Update currentTrack + reset position so the UI syncs immediately.
        case 'onTrackChanged':
          final map = call.arguments as Map?;
          final idx = (map?['queueIndex'] as num?)?.toInt() ?? 0;
          final durMs = (map?['durationMs'] as num?)?.toInt() ?? 0;
          _onExoPlayerTrackChanged(idx, durMs);
          break;
        // Entire queue finished playing.
        case 'onQueueEnded':
        case 'onTrackEnded': // keep old name for backward compat
          _onQueueEnded();
          break;
      }
    });
  }

  void _onAndroidStateChanged({
    required bool isPlaying,
    required int positionMs,
    required int durationMs,
  }) {
    state = state.copyWith(
      isPlaying: isPlaying,
      positionMs: positionMs,
      durationMs: durationMs > 0
          ? durationMs
          : (state.currentTrack?.durationMs.toInt() ?? state.durationMs),
    );
    // Keep Rust state in sync
    RustBridge.instance.updatePosition(positionMs);
  }

  void _onPositionTick(dynamic args) {
    if (args is Map) {
      final posMs = (args['positionMs'] as num?)?.toInt() ?? 0;
      final durMs = (args['durationMs'] as num?)?.toInt() ?? 0;
      state = state.copyWith(
        positionMs: posMs,
        durationMs: durMs > 0
            ? durMs
            : (state.durationMs > 0
                ? state.durationMs
                : (state.currentTrack?.durationMs.toInt() ?? 0)),
      );
      RustBridge.instance.updatePosition(posMs);
    } else if (args is num) {
      final posMs = args.toInt();
      state = state.copyWith(positionMs: posMs);
      RustBridge.instance.updatePosition(posMs);
    }
  }

  /// ExoPlayer moved to the next item in its internal queue.
  /// Update Dart state without telling ExoPlayer to play again.
  void _onExoPlayerTrackChanged(int newIndex, int durationMs) {
    final queue = state.queue;
    if (newIndex >= 0 && newIndex < queue.length) {
      final newTrack = queue[newIndex];
      state = state.copyWith(
        currentTrack: newTrack,
        positionMs: 0,
        durationMs: durationMs > 0 ? durationMs : newTrack.durationMs,
        isPlaying: true,
      );
      // Keep Rust engine in sync with the new track
      RustBridge.instance.loadTrack(newTrack.id);
    }
  }

  /// The entire ExoPlayer queue has finished — stop playback.
  void _onQueueEnded() {
    state = state.copyWith(isPlaying: false, positionMs: 0);
  }

  // ─── State sync ──────────────────────────────────────────────────────────

  void _refreshState() {
    state = RustBridge.instance.getPlayerState();
  }

  // ─── Playback controls ────────────────────────────────────────────────────

  /// Play a specific track. Rust updates queue state; Android ExoPlayer
  /// actually plays the audio file.
  Future<void> playTrack(Track track) async {
    // 1. Tell Rust to load the track into its state/queue
    final rustState = RustBridge.instance.loadTrack(track.id);
    state = rustState.copyWith(isPlaying: true);

    // 2. Tell Android ExoPlayer to play the file
    try {
      await _playbackChannel.invokeMethod('playFile', {
        'path': track.filePath,
        'title': track.title,
        'artist': track.artist,
        'album': track.album,
        'artworkPath': track.artworkPath,
      });
    } catch (e) {
      // ExoPlayer not available — state still updates in Rust
    }
  }

  /// Play an ordered queue starting at [startIndex].
  Future<void> playQueue(List<Track> tracks, int startIndex) async {
    final rustState = RustBridge.instance.setQueue(tracks, startIndex);
    state = rustState.copyWith(isPlaying: true);

    final paths = tracks.map((t) => t.filePath).toList();
    try {
      await _playbackChannel.invokeMethod('setQueueAndPlay', {
        'paths': paths,
        'startIndex': startIndex,
      });
    } catch (_) {}
  }

  /// Alias for playQueue for backward compatibility with UI
  Future<void> setQueue(List<Track> tracks, int startIndex) =>
      playQueue(tracks, startIndex);

  /// Load track by ID and play it
  Future<void> loadTrack(String trackId) async {
    final rustState = RustBridge.instance.loadTrack(trackId);
    state = rustState.copyWith(isPlaying: true);
    final filePath = state.currentTrack?.filePath;
    if (filePath != null) {
      try {
        await _playbackChannel.invokeMethod('playFile', {'path': filePath});
      } catch (_) {}
    }
  }

  Future<void> play() async {
    final rustState = RustBridge.instance.play();
    state = rustState.copyWith(isPlaying: true);
    try {
      await _playbackChannel.invokeMethod('resume');
    } catch (_) {}
  }

  Future<void> pause() async {
    final rustState = RustBridge.instance.pause();
    state = rustState.copyWith(isPlaying: false);
    try {
      await _playbackChannel.invokeMethod('pause');
    } catch (_) {}
  }

  Future<void> togglePlay() async {
    if (state.isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> seek(int positionMs) async {
    RustBridge.instance.seek(positionMs);
    state = state.copyWith(positionMs: positionMs);
    try {
      await _playbackChannel.invokeMethod('seekTo', {'positionMs': positionMs});
    } catch (_) {}
  }

  Future<void> next() async {
    // Advance Rust's queue index so its state stays in sync.
    // ExoPlayer's seekToNextMediaItem() triggers onMediaItemTransition
    // which calls _onExoPlayerTrackChanged() → updates currentTrack.
    RustBridge.instance.next();
    try {
      await _playbackChannel.invokeMethod('next');
    } catch (_) {}
  }

  Future<void> previous() async {
    // If more than 3 s into the track, restart it; otherwise go back.
    if (state.positionMs > 3000) {
      await seek(0);
      return;
    }
    RustBridge.instance.previous();
    try {
      await _playbackChannel.invokeMethod('previous');
    } catch (_) {}
  }

  void toggleShuffle() {
    state = state.copyWith(shuffle: !state.shuffle);
  }

  void toggleRepeat() {
    final nextMode = switch (state.repeatMode) {
      RepeatMode.off => RepeatMode.all,
      RepeatMode.all => RepeatMode.one,
      RepeatMode.one => RepeatMode.off,
    };
    state = state.copyWith(repeatMode: nextMode);
  }

  void updateOutputStatus(OutputStatus status) {
    state = state.copyWith(outputStatus: status);
  }

  void toggleFavorite(String trackId) {
    final isFav = RustBridge.instance.toggleFavorite(trackId);
    final current = state.currentTrack;
    if (current?.id == trackId) {
      state = state.copyWith(
        currentTrack: current!.copyWith(isFavorite: isFav),
      );
    }
  }

  @override
  void dispose() {
    _playbackChannel.setMethodCallHandler(null);
    super.dispose();
  }
}
