import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app/theme.dart';
import '../features/player/now_playing_screen.dart';
import '../providers/player_provider.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerProvider);
    final track = playerState.currentTrack;

    if (track == null) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          PageRouteBuilder(
            pageBuilder: (context, anim1, anim2) => const NowPlayingScreen(),
            transitionsBuilder: (context, anim1, anim2, child) {
              return SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 1),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(
                    parent: anim1,
                    curve: Curves.easeOutCubic,
                  ),
                ),
                child: child,
              );
            },
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                // Artwork thumbnail with purple glow border
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.accentPurple.withValues(alpha: 0.3)),
                    image: track.artworkPath != null &&
                            File(track.artworkPath!).existsSync()
                        ? DecorationImage(
                            image: FileImage(File(track.artworkPath!)),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: track.artworkPath == null ||
                          !File(track.artworkPath!).existsSync()
                      ? const Icon(
                          Icons.music_note_rounded,
                          color: AppTheme.neonPurple,
                          size: 22,
                        )
                      : null,
                ),
                const SizedBox(width: 12),

                // Title and Artist
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        track.title,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: playerState.outputStatus.isConnected
                                  ? AppTheme.connectedGreen
                                  : AppTheme.textTertiary,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${track.artist} · ${playerState.outputStatus.deviceName.isNotEmpty ? playerState.outputStatus.deviceName : "Phone Speaker"}',
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 11,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Play / Pause Button
                IconButton(
                  icon: Icon(
                    playerState.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: AppTheme.accentPurple,
                    size: 28,
                  ),
                  onPressed: () {
                    ref.read(playerProvider.notifier).togglePlay();
                  },
                ),
                // Next Button
                IconButton(
                  icon: const Icon(
                    Icons.skip_next_rounded,
                    color: AppTheme.textPrimary,
                    size: 22,
                  ),
                  onPressed: () {
                    ref.read(playerProvider.notifier).next();
                  },
                ),
              ],
            ),

            // Mini progress indicator bar
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: playerState.progress,
                backgroundColor: AppTheme.border,
                valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.accentPurple),
                minHeight: 2.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
