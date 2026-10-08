import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme.dart';
import '../../models/track.dart';
import '../../providers/library_provider.dart';
import '../../providers/player_provider.dart';

class AlbumDetailScreen extends ConsumerWidget {
  final Album album;

  const AlbumDetailScreen({super.key, required this.album});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allTracksAsync = ref.watch(tracksProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: CustomScrollView(
        slivers: [
          // Collapsible App Bar with Album Artwork Hero
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            backgroundColor: AppTheme.surfaceElevated,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (album.artworkPath != null && File(album.artworkPath!).existsSync())
                    Image.file(File(album.artworkPath!), fit: BoxFit.cover)
                  else
                    Container(
                      color: AppTheme.surfaceElevated,
                      child: const Center(
                        child: Icon(Icons.album_rounded, size: 80, color: AppTheme.accentPurple),
                      ),
                    ),
                  // Dark gradient overlay
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          AppTheme.background.withValues(alpha: 0.8),
                          AppTheme.background,
                        ],
                        stops: const [0.3, 0.75, 1.0],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Album Info Header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    album.title,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${album.artist} · ${album.year != null ? "${album.year} · " : ""}${album.trackCount} tracks',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 16),

                  // Action Buttons: Play All & Shuffle
                  allTracksAsync.when(
                    data: (allTracks) {
                      final albumTracks = allTracks.where((t) {
                        return t.album.toLowerCase() == album.title.toLowerCase() ||
                            t.artist.toLowerCase() == album.artist.toLowerCase();
                      }).toList();

                      if (albumTracks.isEmpty) return const SizedBox.shrink();

                      return Row(
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.accentPurple,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.play_arrow_rounded, size: 22),
                            label: const Text('Play All', style: TextStyle(fontWeight: FontWeight.bold)),
                            onPressed: () {
                              ref.read(playerProvider.notifier).setQueue(albumTracks, 0);
                            },
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.neonPurple,
                              side: const BorderSide(color: AppTheme.accentPurple),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.shuffle_rounded, size: 20),
                            label: const Text('Shuffle'),
                            onPressed: () {
                              final shuffled = List<Track>.from(albumTracks)..shuffle();
                              ref.read(playerProvider.notifier).setQueue(shuffled, 0);
                            },
                          ),
                        ],
                      );
                    },
                    loading: () => const SizedBox.shrink(),
                    error: (_, _) => const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: AppTheme.border),
                ],
              ),
            ),
          ),

          // Track List
          allTracksAsync.when(
            data: (allTracks) {
              final albumTracks = allTracks.where((t) {
                return t.album.toLowerCase() == album.title.toLowerCase() ||
                    (album.title.toLowerCase() == 'unknown album' &&
                        t.artist.toLowerCase() == album.artist.toLowerCase());
              }).toList();

              if (albumTracks.isEmpty) {
                return const SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('No tracks found for this album', style: TextStyle(color: AppTheme.textTertiary)),
                    ),
                  ),
                );
              }

              return SliverPadding(
                padding: const EdgeInsets.only(left: 16, right: 16, bottom: 80),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final t = albumTracks[index];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(vertical: 4),
                        leading: Container(
                          width: 32,
                          alignment: Alignment.center,
                          child: Text(
                            t.trackNumber != null ? '${t.trackNumber}' : '${index + 1}',
                            style: const TextStyle(color: AppTheme.textTertiary, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(
                          t.title,
                          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Row(
                          children: [
                            Expanded(
                              child: Text(
                                t.artist,
                                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceElevated,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: AppTheme.border),
                              ),
                              child: Text(
                                t.hiFiBadgeText,
                                style: const TextStyle(color: AppTheme.neonPurple, fontSize: 9, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        trailing: Text(t.formattedDuration, style: const TextStyle(color: AppTheme.textTertiary, fontSize: 12)),
                        onTap: () {
                          ref.read(playerProvider.notifier).setQueue(albumTracks, index);
                        },
                      );
                    },
                    childCount: albumTracks.length,
                  ),
                ),
              );
            },
            loading: () => const SliverToBoxAdapter(
              child: Center(child: CircularProgressIndicator(color: AppTheme.accentPurple)),
            ),
            error: (e, _) => SliverToBoxAdapter(
              child: Center(child: Text('Error: $e', style: const TextStyle(color: Colors.redAccent))),
            ),
          ),
        ],
      ),
    );
  }
}
