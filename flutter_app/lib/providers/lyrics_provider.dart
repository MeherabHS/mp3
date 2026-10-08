import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../bridge/rust_bridge.dart';
import '../models/lyrics.dart';
import '../services/lyrics_service.dart';
import 'player_provider.dart';
import 'settings_provider.dart';

// ─── fullLyricsProvider ───────────────────────────────────────────────────────
// Re-fetches only when the current track changes (not on every position tick).
final fullLyricsProvider = FutureProvider.autoDispose<SyncedLyrics>((ref) async {
  final currentTrack = ref.watch(
    playerProvider.select((s) => s.currentTrack),
  );

  // Keep Musixmatch token in sync with settings (re-runs when token changes)
  final mxmToken = ref.watch(
    settingsProvider.select((s) => s.musixmatchToken),
  );
  LyricsService.setMusixmatchToken(mxmToken);

  if (currentTrack == null) {
    return const SyncedLyrics(
      trackId: '',
      isSynchronized: false,
      isWordSynced: false,
      offsetMs: 0,
      lines: [],
    );
  }

  // 1. Try Rust bridge for an already-indexed .lrc (works once .so is built)
  final localLyrics = RustBridge.instance.getLyrics(currentTrack.id);
  if (localLyrics.lines.isNotEmpty) {
    return localLyrics;
  }

  // 2. Fetch from all sources (LRCLIB → NetEase → lyrics.ovh → Musixmatch)
  return LyricsService.fetchLyrics(currentTrack);
});

// ─── lyricsSyncProvider ───────────────────────────────────────────────────────
// Pure-Dart sync: reads the already-loaded SyncedLyrics and the current
// playback position, then binary-searches for the active line and word.
// No Rust dependency — works immediately even before the .so is compiled.
final lyricsSyncProvider = Provider<LyricsSyncState>((ref) {
  final positionMs = ref.watch(playerProvider.select((s) => s.positionMs));
  final trackId   = ref.watch(playerProvider.select((s) => s.currentTrack?.id));

  if (trackId == null) return const LyricsSyncState(trackId: '');

  final lyricsAsync = ref.watch(fullLyricsProvider);
  final lyrics = lyricsAsync.valueOrNull;

  // Primary path: Dart-side sync using the loaded lyrics object
  if (lyrics != null && lyrics.isSynchronized && lyrics.lines.isNotEmpty) {
    return _syncDart(lyrics, positionMs, trackId);
  }

  // Fallback: Rust sync (used after .so is compiled and Rust is initialized)
  if (RustBridge.instance.isInitialized) {
    return RustBridge.instance.updatePosition(positionMs);
  }

  return LyricsSyncState(trackId: trackId);
});

// ─── Pure-Dart sync implementation ───────────────────────────────────────────

LyricsSyncState _syncDart(SyncedLyrics lyrics, int positionMs, String trackId) {
  final lines = lyrics.lines;

  // Binary search: last line whose startMs ≤ positionMs
  int? activeLineIndex;
  int lo = 0, hi = lines.length - 1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (lines[mid].startMs <= positionMs) {
      activeLineIndex = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }

  // Word-level sync within the active line
  int? activeWordIndex;
  if (activeLineIndex != null) {
    final words = lines[activeLineIndex].words;
    for (int i = words.length - 1; i >= 0; i--) {
      if (positionMs >= words[i].startMs) {
        activeWordIndex = i;
        break;
      }
    }
  }

  // Progress ratio within the active line (0.0 → 1.0)
  double lineProgress = 0.0;
  if (activeLineIndex != null) {
    final start = lines[activeLineIndex].startMs;
    final end = activeLineIndex < lines.length - 1
        ? lines[activeLineIndex + 1].startMs
        : start + 5000;
    if (end > start) {
      lineProgress = ((positionMs - start) / (end - start)).clamp(0.0, 1.0);
    }
  }

  return LyricsSyncState(
    trackId: trackId,
    activeLineIndex: activeLineIndex,
    activeWordIndex: activeWordIndex,
    lineProgress: lineProgress,
    activeLineText:
        activeLineIndex != null ? lines[activeLineIndex].text : null,
    previousLineText:
        (activeLineIndex != null && activeLineIndex > 0)
            ? lines[activeLineIndex - 1].text
            : null,
    nextLineText:
        (activeLineIndex != null && activeLineIndex < lines.length - 1)
            ? lines[activeLineIndex + 1].text
            : null,
  );
}
