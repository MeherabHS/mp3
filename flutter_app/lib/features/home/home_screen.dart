import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme.dart';
import '../../models/track.dart';
import '../../providers/library_provider.dart';
import '../../providers/player_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/output_status_badge.dart';
import '../audio_info/audio_chain_screen.dart';
import '../settings/settings_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerProvider);
    final userName = ref.watch(settingsProvider.select((s) => s.userName));
    final recentlyPlayedAsync = ref.watch(recentlyPlayedProvider);
    final allTracksAsync = ref.watch(tracksProvider);

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: AppTheme.accentPurple,
          backgroundColor: AppTheme.surfaceElevated,
          onRefresh: () async {
            ref.invalidate(recentlyPlayedProvider);
            ref.invalidate(tracksProvider);
            ref.invalidate(albumsProvider);
            ref.invalidate(artistsProvider);
          },
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // Top Bar: Avatar, Greeting & Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.surfaceElevated,
                          border: Border.all(color: AppTheme.accentPurple.withValues(alpha: 0.6), width: 1.5),
                        ),
                        child: const Icon(Icons.person_rounded, color: AppTheme.neonPurple, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _greeting(),
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            userName,
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.notifications_none_rounded),
                        color: AppTheme.textSecondary,
                        onPressed: () {},
                      ),
                      IconButton(
                        icon: const Icon(Icons.settings_outlined),
                        color: AppTheme.textSecondary,
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const SettingsScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Search Bar Pill
              Container(
                height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(21),
                  border: Border.all(color: AppTheme.border),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    const Icon(Icons.search_rounded, color: AppTheme.textTertiary, size: 18),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Search songs, albums, artists...',
                        style: TextStyle(color: AppTheme.textTertiary, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Live Output Card (Hi-Fi Chain)
              OutputStatusBadge(
                outputStatus: playerState.outputStatus,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AudioChainScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 22),

              // ─── Section: Recently Played ────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Recently Played',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton(
                    onPressed: () {},
                    child: const Text('See all', style: TextStyle(color: AppTheme.accentPurple, fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              recentlyPlayedAsync.when(
                data: (tracks) {
                  final displayTracks = tracks.isNotEmpty
                      ? tracks
                      : allTracksAsync.value?.take(6).toList() ?? [];

                  if (displayTracks.isEmpty) {
                    return _buildEmptyHomeCard('No recent plays', 'Scan or download tracks to begin listening');
                  }

                  return SizedBox(
                    height: 175,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: displayTracks.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 14),
                      itemBuilder: (ctx, idx) {
                        final t = displayTracks[idx];
                        return _buildRecentlyPlayedCard(context, ref, t, displayTracks, idx);
                      },
                    ),
                  );
                },
                loading: () => const SizedBox(
                  height: 175,
                  child: Center(child: CircularProgressIndicator(color: AppTheme.accentPurple)),
                ),
                error: (err, _) => const SizedBox.shrink(),
              ),

              const SizedBox(height: 24),

              // ─── Section: Recently Added ────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Recently Added',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton(
                    onPressed: () {},
                    child: const Text('See all', style: TextStyle(color: AppTheme.accentPurple, fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              allTracksAsync.when(
                data: (tracks) {
                  if (tracks.isEmpty) {
                    return _buildEmptyHomeCard('Library is empty', 'Tap Library tab to import or auto-scan your music');
                  }

                  final recentList = tracks.take(6).toList();
                  return ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: recentList.length,
                    separatorBuilder: (_, _) => const Divider(color: AppTheme.border, height: 1),
                    itemBuilder: (ctx, idx) {
                      final t = recentList[idx];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceElevated,
                            borderRadius: BorderRadius.circular(8),
                            image: t.artworkPath != null && File(t.artworkPath!).existsSync()
                                ? DecorationImage(image: FileImage(File(t.artworkPath!)), fit: BoxFit.cover)
                                : null,
                          ),
                          child: t.artworkPath == null || !File(t.artworkPath!).existsSync()
                              ? const Icon(Icons.music_note_rounded, color: AppTheme.neonPurple, size: 20)
                              : null,
                        ),
                        title: Text(
                          t.title,
                          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Row(
                          children: [
                            Expanded(
                              child: Text(
                                t.artist,
                                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
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
                                t.codec,
                                style: const TextStyle(color: AppTheme.neonPurple, fontSize: 9, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        trailing: const Icon(Icons.more_vert_rounded, color: AppTheme.textTertiary, size: 18),
                        onTap: () {
                          ref.read(playerProvider.notifier).setQueue(tracks, idx);
                        },
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.accentPurple)),
                error: (err, _) => const SizedBox.shrink(),
              ),

              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning,';
    if (hour < 17) return 'Good afternoon,';
    return 'Good evening,';
  }

  Widget _buildRecentlyPlayedCard(
    BuildContext context,
    WidgetRef ref,
    Track track,
    List<Track> queue,
    int index,
  ) {
    return GestureDetector(
      onTap: () {
        ref.read(playerProvider.notifier).setQueue(queue, index);
      },
      child: SizedBox(
        width: 120,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: AppTheme.surfaceElevated,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.accentPurple.withValues(alpha: 0.25)),
                image: track.artworkPath != null && File(track.artworkPath!).existsSync()
                    ? DecorationImage(image: FileImage(File(track.artworkPath!)), fit: BoxFit.cover)
                    : null,
              ),
              child: track.artworkPath == null || !File(track.artworkPath!).existsSync()
                  ? const Center(child: Icon(Icons.album_rounded, color: AppTheme.neonPurple, size: 40))
                  : null,
            ),
            const SizedBox(height: 8),
            Text(
              track.title,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 1),
            Text(
              track.artist,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyHomeCard(String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: AppTheme.textTertiary, fontSize: 12)),
        ],
      ),
    );
  }
}
