import 'dart:io';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme.dart';
import '../../models/audio_quality.dart';
import '../../models/player_state.dart';
import '../../providers/lyrics_provider.dart';
import '../../providers/player_provider.dart';
import '../../services/lyrics_service.dart';
import '../audio_info/audio_chain_screen.dart';

class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen> {
  final ScrollController _lyricsScrollController = ScrollController();
  bool _isFullScreenLyrics = false;
  int _lastActiveIndex = -1;

  // Seek scrubber state — while dragging, use local value so the
  // 250ms position ticks don't snap the thumb back mid-drag.
  bool _isSeeking = false;
  double _seekValue = 0.0;

  // One GlobalKey per lyric line so ensureVisible() can read the actual
  // rendered position instead of guessing based on a fixed item height.
  final List<GlobalKey> _lyricKeys = [];

  @override
  void dispose() {
    _lyricsScrollController.dispose();
    super.dispose();
  }

  void _scrollToActiveLyric(int activeIndex) {
    if (activeIndex == _lastActiveIndex || activeIndex < 0) return;
    _lastActiveIndex = activeIndex;
    if (activeIndex >= _lyricKeys.length) return;
    final ctx = _lyricKeys[activeIndex].currentContext;
    if (ctx == null) return;
    // alignment: 0.3 → active line sits at ~30% from the top so several
    // upcoming lines are always visible below it.
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      alignment: 0.3,
    );
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(playerProvider);
    final lyricsAsync = ref.watch(fullLyricsProvider);
    final syncState = ref.watch(lyricsSyncProvider);
    final track = playerState.currentTrack;

    if (track == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF14141E),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: const Center(
          child: Text('No track loaded', style: TextStyle(color: Colors.white54)),
        ),
      );
    }

    // Auto-scroll lyrics to active line
    if (syncState.activeLineIndex != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToActiveLyric(syncState.activeLineIndex!);
      });
    }

    final lyricsLines = lyricsAsync.value?.lines ?? [];

    return Scaffold(
      backgroundColor: const Color(0xFF14141E),
      body: SafeArea(
        // Do NOT wrap in SingleChildScrollView — the Slider needs to be
        // outside any scroll context or the scroll view's gesture recogniser
        // wins the arena and the thumb can't be dragged.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              // ─── Top Bar: Down Arrow, Album Title, Info Button ──────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(
                      track.album.isNotEmpty ? track.album.toUpperCase() : 'NOW PLAYING',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.more_vert_rounded, size: 24, color: Colors.white),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AudioChainScreen()),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ─── Big Rounded Album Artwork Hero ─────────────────────────
              // Cap height so the lyrics card always gets space below.
              // On a 900 dp screen → artwork ~220 dp; on 800 dp → ~220 dp.
              Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.27,
                    maxWidth:  MediaQuery.of(context).size.height * 0.27,
                  ),
                  child: AspectRatio(
                  aspectRatio: 1.0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF222233),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                      image: track.artworkPath != null && File(track.artworkPath!).existsSync()
                          ? DecorationImage(
                              image: FileImage(File(track.artworkPath!)),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: track.artworkPath == null || !File(track.artworkPath!).existsSync()
                        ? const Center(
                            child: Icon(Icons.music_note_rounded, color: AppTheme.neonPurple, size: 96),
                          )
                        : null,
                  ),
                ),
                ),
              ),
              const SizedBox(height: 16),

              // ─── Track Title, Artist, & Favorite Heart ──────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                track.artist,
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2B2B3D),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                track.hiFiBadgeText,
                                style: const TextStyle(
                                  color: AppTheme.neonPurple,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      track.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: track.isFavorite ? Colors.redAccent : Colors.white60,
                      size: 26,
                    ),
                    onPressed: () {
                      ref.read(playerProvider.notifier).toggleFavorite(track.id);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ─── Scrubber Bar & Timestamps ──────────────────────────────
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                  activeTrackColor: Colors.white,
                  inactiveTrackColor: Colors.white24,
                  thumbColor: Colors.white,
                ),
                child: Slider(
                  // While the user drags, use the local _seekValue so the
                  // 250ms position ticks don't snap the thumb back mid-drag.
                  value: _isSeeking
                      ? _seekValue
                      : playerState.progress.clamp(0.0, 1.0),
                  onChangeStart: (val) {
                    setState(() {
                      _isSeeking = true;
                      _seekValue = val;
                    });
                  },
                  onChanged: (val) {
                    setState(() => _seekValue = val);
                  },
                  onChangeEnd: (val) {
                    final dur = playerState.durationMs > 0
                        ? playerState.durationMs
                        : track.durationMs.toInt();
                    ref.read(playerProvider.notifier).seek((val * dur).toInt());
                    setState(() => _isSeeking = false);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      playerState.formattedPosition,
                      style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                    Text(
                      playerState.durationMs > 0 ? playerState.formattedDuration : track.formattedDuration,
                      style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // ─── Playback Controls: Shuffle, Prev, Play/Pause, Next, Repeat
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.shuffle_rounded,
                      color: playerState.shuffle ? AppTheme.neonPurple : Colors.white60,
                      size: 24,
                    ),
                    onPressed: () => ref.read(playerProvider.notifier).toggleShuffle(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 38),
                    onPressed: () => ref.read(playerProvider.notifier).previous(),
                  ),
                  // White Circular Play / Pause button
                  Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: Icon(
                        playerState.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: Colors.black,
                        size: 36,
                      ),
                      onPressed: () {
                        if (playerState.isPlaying) {
                          ref.read(playerProvider.notifier).pause();
                        } else {
                          ref.read(playerProvider.notifier).play();
                        }
                      },
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 38),
                    onPressed: () => ref.read(playerProvider.notifier).next(),
                  ),
                  IconButton(
                    icon: Icon(
                      playerState.repeatMode == RepeatMode.one
                          ? Icons.repeat_one_rounded
                          : Icons.repeat_rounded,
                      color: playerState.repeatMode != RepeatMode.off ? AppTheme.neonPurple : Colors.white60,
                      size: 24,
                    ),
                    onPressed: () => ref.read(playerProvider.notifier).toggleRepeat(),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ─── Connected Device Output Bar & Queue ────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AudioChainScreen()),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      child: Row(
                        children: [
                          Icon(
                            playerState.outputStatus.outputType == OutputType.bluetooth
                                ? Icons.headphones_rounded
                                : Icons.speaker_rounded,
                            size: 18,
                            color: AppTheme.connectedGreen,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            playerState.outputStatus.deviceName,
                            style: const TextStyle(color: AppTheme.connectedGreen, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.queue_music_rounded, color: Colors.white60, size: 22),
                    onPressed: () {
                      // Open queue sheet
                      _showQueueSheet(context, ref, playerState);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
                ],
              ),
            ),

            // ─── LYRICS CARD — Expanded so it fills remaining height ────
            // Kept outside the inner Padding so it can grow to fill space.
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 20, right: 20, bottom: 20),
                child: GestureDetector(
                onTap: () {
                  setState(() => _isFullScreenLyrics = !_isFullScreenLyrics);
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF28283E),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'LYRICS',
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                          Icon(
                            _isFullScreenLyrics ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                            size: 18,
                            color: Colors.white54,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: lyricsAsync.when(
                          data: (lyrics) {
                            if (lyricsLines.isEmpty) {
                              return Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.lyrics_rounded, color: Colors.white24, size: 36),
                                    const SizedBox(height: 8),
                                    const Text('No lyrics found for this track', style: TextStyle(color: Colors.white38, fontSize: 13)),
                                    const SizedBox(height: 8),
                                    TextButton.icon(
                                      icon: const Icon(Icons.refresh_rounded, size: 16),
                                      label: const Text('Search LRCLIB Online', style: TextStyle(fontSize: 12)),
                                      style: TextButton.styleFrom(foregroundColor: AppTheme.neonPurple),
                                      onPressed: () async {
                                        // 1. Wipe every layer of cache for this track
                                        await LyricsService.evict(track);
                                        // 2. Force provider to re-run immediately (refresh
                                        //    triggers a rebuild + re-fetch, unlike invalidate
                                        //    which only marks stale for the next read)
                                        if (mounted) {
                                          // ignore: unused_result
                                          ref.refresh(fullLyricsProvider.future);
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              );
                            }

                            // -1 means nothing is active yet (before lyrics start)
                            final activeIdx = syncState.activeLineIndex ?? -1;

                            // Rebuild key list when the number of lines changes
                            // (i.e. when a new track is loaded).
                            if (_lyricKeys.length != lyricsLines.length) {
                              _lyricKeys.clear();
                              for (int i = 0; i < lyricsLines.length; i++) {
                                _lyricKeys.add(GlobalKey());
                              }
                              _lastActiveIndex = -1;
                            }

                            return ListView.builder(
                              controller: _lyricsScrollController,
                              physics: const BouncingScrollPhysics(),
                              itemCount: lyricsLines.length,
                              itemBuilder: (ctx, idx) {
                                final line = lyricsLines[idx];
                                final isActive = idx == activeIdx && lyrics.isSynchronized && activeIdx >= 0;

                                return Padding(
                                  key: _lyricKeys[idx],
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                  child: GestureDetector(
                                    onTap: () {
                                      if (line.startMs > 0) {
                                        ref.read(playerProvider.notifier).seek(line.startMs);
                                      }
                                    },
                                    child: AnimatedDefaultTextStyle(
                                      duration: const Duration(milliseconds: 200),
                                      style: TextStyle(
                                        color: isActive ? Colors.white : Colors.white38,
                                        fontSize: isActive ? 19 : 15,
                                        fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                                        height: 1.3,
                                      ),
                                      child: Text(line.text),
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                          loading: () => const Center(
                            child: CircularProgressIndicator(color: AppTheme.accentPurple, strokeWidth: 2),
                          ),
                          error: (_, _) => const Center(
                            child: Text('Lyrics unavailable', style: TextStyle(color: Colors.white38)),
                          ),
                        ),
                      ),
                    ],
                  ),
              ),
            ),
          ),
        ),
          ],
        ),
      ),
    );
  }

  void _showQueueSheet(BuildContext context, WidgetRef ref, PlayerState playerState) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final queue = playerState.queue;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Current Queue',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                if (queue.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('Queue is empty', style: TextStyle(color: Colors.white38))),
                  )
                else
                  Expanded(
                    child: ListView.builder(
                      itemCount: queue.length,
                      itemBuilder: (context, index) {
                        final t = queue[index];
                        final isCur = t.id == playerState.currentTrack?.id;
                        return ListTile(
                          leading: Icon(
                            isCur ? Icons.play_arrow_rounded : Icons.music_note_rounded,
                            color: isCur ? AppTheme.neonPurple : Colors.white38,
                          ),
                          title: Text(
                            t.title,
                            style: TextStyle(
                              color: isCur ? AppTheme.neonPurple : Colors.white,
                              fontWeight: isCur ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          subtitle: Text(t.artist, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                          trailing: Text(t.formattedDuration, style: const TextStyle(color: Colors.white38, fontSize: 12)),
                          onTap: () {
                            Navigator.pop(ctx);
                            ref.read(playerProvider.notifier).playTrack(t);
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
