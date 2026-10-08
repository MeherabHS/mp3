import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme.dart';
import '../../bridge/rust_bridge.dart';
import '../../models/track.dart';
import '../../providers/library_provider.dart';
import '../../providers/player_provider.dart';
import 'album_detail_screen.dart';

const _permChannel = MethodChannel('com.hifi.musicplayer/permissions');

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  bool _isScanning = false;
  String _scanStatusText = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() => setState(() {}));
  }

  Future<void> _showCreatePlaylistDialog() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceElevated,
        title: const Text('New Playlist', style: TextStyle(color: AppTheme.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(
            hintText: 'Playlist name',
            hintStyle: TextStyle(color: AppTheme.textTertiary),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.border)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.accentPurple)),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Create', style: TextStyle(color: AppTheme.accentPurple, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      RustBridge.instance.createPlaylist(name);
      ref.invalidate(playlistsProvider);
    }
  }

  Future<void> _showAddToPlaylistDialog(Track track) async {
    final playlists = RustBridge.instance.listPlaylists();
    if (!mounted) return;
    if (playlists.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No playlists yet — create one in the Playlists tab'),
          backgroundColor: AppTheme.surfaceElevated,
          action: SnackBarAction(label: 'Create', textColor: AppTheme.accentPurple, onPressed: () {
            _tabController.animateTo(3);
            _showCreatePlaylistDialog();
          }),
        ),
      );
      return;
    }
    await showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceElevated,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text('Add to Playlist', style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          const Divider(color: AppTheme.border),
          ...playlists.map((p) => ListTile(
            leading: const Icon(Icons.playlist_add_rounded, color: AppTheme.accentPurple),
            title: Text(p.name, style: const TextStyle(color: AppTheme.textPrimary)),
            subtitle: Text('${p.trackCount} tracks', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            onTap: () {
              RustBridge.instance.addTrackToPlaylist(p.id, track.id);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Added to ${p.name}'),
                  backgroundColor: AppTheme.surfaceElevated,
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          )),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Future<void> _requestPermissions() async {
    try {
      await _permChannel.invokeMethod('requestStoragePermissions');
    } catch (_) {}
  }

  void _refreshLibrary() {
    ref.invalidate(tracksProvider);
    ref.invalidate(albumsProvider);
    ref.invalidate(artistsProvider);
    ref.invalidate(playlistsProvider);
  }

  /// Converts Android SAF content URIs (e.g. content://.../tree/6130-6364%3AMusic)
  /// into physical POSIX paths (/storage/6130-6364/Music)
  String _resolveSafUriToPath(String raw) {
    if (!raw.startsWith('content://')) return raw;
    try {
      final decoded = Uri.decodeComponent(raw);
      final match = RegExp(r'(?:tree|document)/([^:]+):?(.*)$').firstMatch(decoded);
      if (match != null) {
        final volume = match.group(1);
        final subpath = match.group(2) ?? '';
        if (volume == 'primary') {
          return '/storage/emulated/0${subpath.isNotEmpty ? '/$subpath' : ''}';
        } else if (volume != null && volume.isNotEmpty) {
          return '/storage/$volume${subpath.isNotEmpty ? '/$subpath' : ''}';
        }
      }
    } catch (_) {}
    return raw;
  }

  /// Import audio files selected by user
  Future<void> _pickAudioFiles() async {
    await _requestPermissions();

    try {
      final result = await FilePickerPlatform.instance.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['flac', 'wav', 'mp3', 'm4a', 'opus', 'ogg', 'alac', 'aac'],
      );

      if (result.isNotEmpty) {
        setState(() {
          _isScanning = true;
          _scanStatusText = 'Importing ${result.length} selected tracks...';
        });

        int indexed = 0;
        for (final file in result) {
          if (file.path != null && file.path!.isNotEmpty) {
            final track = RustBridge.instance.scanFile(file.path!);
            if (track != null) {
              indexed++;
            }
          }
        }

        setState(() {
          _isScanning = false;
          _scanStatusText = '';
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppTheme.surfaceElevated,
              content: Text(
                indexed > 0
                    ? 'Successfully imported $indexed tracks!'
                    : 'No audio tracks could be indexed.',
                style: TextStyle(
                  color: indexed > 0 ? AppTheme.accentPurple : Colors.redAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
          _refreshLibrary();
        }
      }
    } catch (e) {
      setState(() => _isScanning = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.surfaceElevated,
            content: Text('Import error: $e', style: const TextStyle(color: Colors.redAccent)),
          ),
        );
      }
    }
  }

  /// Scan a specific directory selected by the user
  Future<void> _scanDirectoryPath(String rawPath) async {
    final dirPath = _resolveSafUriToPath(rawPath);

    setState(() {
      _isScanning = true;
      _scanStatusText = 'Scanning $dirPath...';
    });

    final count = RustBridge.instance.scanDirectory(dirPath);

    setState(() {
      _isScanning = false;
      _scanStatusText = '';
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.surfaceElevated,
          content: Text(
            count > 0
                ? 'Indexed $count tracks from $dirPath'
                : 'No audio files found in $dirPath',
            style: TextStyle(
              color: count > 0 ? AppTheme.accentPurple : Colors.white70,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
      _refreshLibrary();
    }
  }

  /// Automatically scan all music across phone storage AND external SD cards
  Future<void> _autoScanDeviceAndSdCard() async {
    await _requestPermissions();

    setState(() {
      _isScanning = true;
      _scanStatusText = 'Discovering audio across device & SD card...';
    });

    int totalIndexed = 0;

    // 1. Instant scan via Android MediaStore (indexes both internal + SD card)
    try {
      final List<dynamic>? mediaStorePaths =
          await _permChannel.invokeMethod('getMediaStoreAudioPaths');
      if (mediaStorePaths != null && mediaStorePaths.isNotEmpty) {
        int processed = 0;
        for (final p in mediaStorePaths) {
          if (p is String && p.isNotEmpty) {
            final track = RustBridge.instance.scanFile(p);
            if (track != null) totalIndexed++;
            processed++;
            // Yield to the event loop every 3 tracks so Rust's artwork
            // processing doesn't block the UI thread for too long.
            if (processed % 3 == 0) {
              if (mounted) {
                setState(() {
                  _scanStatusText = 'Indexing $processed / ${mediaStorePaths.length} tracks...';
                });
              }
              await Future.delayed(const Duration(milliseconds: 8));
            }
          }
        }
      }
    } catch (_) {}

    // 2. Discover external SD card roots and scan dedicated music folders
    try {
      final List<dynamic>? volumes =
          await _permChannel.invokeMethod('getMountedStoragePaths');
      final volumeRoots = (volumes ?? ['/storage/emulated/0']).cast<String>();

      for (final root in volumeRoots) {
        final subfolders = [
          '$root/Music',
          '$root/Download',
          '$root/Downloads',
          '$root/Audio',
          '$root/Audiobooks',
          '$root/Podcasts',
        ];
        for (final folder in subfolders) {
          if (Directory(folder).existsSync()) {
            totalIndexed += RustBridge.instance.scanDirectory(folder);
            await Future.delayed(Duration.zero);
          }
        }
      }
    } catch (_) {}

    setState(() {
      _isScanning = false;
      _scanStatusText = '';
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.surfaceElevated,
          content: Text(
            totalIndexed > 0
                ? 'Scan complete: $totalIndexed tracks ready in library!'
                : 'No new audio tracks found on storage.',
            style: TextStyle(
              color: totalIndexed > 0 ? AppTheme.connectedGreen : Colors.white70,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
      _refreshLibrary();
    }
  }

  void _showScanOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Text(
                  'Import & Scan Audio',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.accentPurple.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.autorenew_rounded, color: AppTheme.accentPurple),
                ),
                title: const Text('Auto-Scan Device & SD Card (Recommended)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                subtitle: const Text('Scans all music from Phone and SD Card storage automatically', style: TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  _autoScanDeviceAndSdCard();
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.accentGold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.file_open_rounded, color: AppTheme.accentGold),
                ),
                title: const Text('Select Audio Files', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Pick individual MP3, FLAC, M4A, Opus files', style: TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAudioFiles();
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.accentCyan.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.folder_open_rounded, color: AppTheme.accentCyan),
                ),
                title: const Text('Pick Custom Folder / SD Card', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Choose a specific SD card folder', style: TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _requestPermissions();
                  final selected = await FilePickerPlatform.instance.getDirectoryPath();
                  if (selected != null) {
                    _scanDirectoryPath(selected);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tracksAsync = ref.watch(tracksProvider);
    final albumsAsync = ref.watch(albumsProvider);
    final artistsAsync = ref.watch(artistsProvider);
    final playlistsAsync = ref.watch(playlistsProvider);
    final searchQuery = ref.watch(searchQueryProvider);
    final searchResultsAsync = ref.watch(searchResultsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded, color: AppTheme.accentPurple),
            tooltip: 'Import Audio Files',
            onPressed: _pickAudioFiles,
          ),
          IconButton(
            icon: const Icon(Icons.folder_open_rounded, color: AppTheme.accentPurple),
            tooltip: 'Scan Options',
            onPressed: _showScanOptions,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(106),
          child: Column(
            children: [
              // Search Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Container(
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) {
                      ref.read(searchQueryProvider.notifier).state = val;
                    },
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Search songs, artists, albums...',
                      hintStyle: const TextStyle(color: AppTheme.textTertiary, fontSize: 13),
                      prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textTertiary, size: 18),
                      suffixIcon: searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, color: AppTheme.textTertiary, size: 16),
                              onPressed: () {
                                _searchController.clear();
                                ref.read(searchQueryProvider.notifier).state = '';
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 11),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              // Category Filter Tabs
              TabBar(
                controller: _tabController,
                indicatorColor: AppTheme.accentPurple,
                indicatorWeight: 3,
                labelColor: AppTheme.accentPurple,
                unselectedLabelColor: AppTheme.textSecondary,
                labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                tabs: const [
                  Tab(text: 'Songs'),
                  Tab(text: 'Albums'),
                  Tab(text: 'Artists'),
                  Tab(text: 'Playlists'),
                ],
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: _tabController.index == 3
          ? FloatingActionButton(
              onPressed: _showCreatePlaylistDialog,
              backgroundColor: AppTheme.accentPurple,
              child: const Icon(Icons.add_rounded, color: Colors.white),
            )
          : null,
      body: _isScanning
          ? _buildScanningLoader()
          : searchQuery.isNotEmpty
              ? _buildSearchResults(searchResultsAsync)
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildTracksTab(tracksAsync),
                    _buildAlbumsTab(albumsAsync),
                    _buildArtistsTab(artistsAsync),
                    _buildPlaylistsTab(playlistsAsync),
                  ],
                ),
    );
  }

  Widget _buildScanningLoader() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: AppTheme.accentPurple,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            _scanStatusText.isNotEmpty ? _scanStatusText : 'Scanning library...',
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Reading tags & caching artwork...',
            style: TextStyle(color: AppTheme.textTertiary, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults(AsyncValue<List<Track>> searchResultsAsync) {
    return searchResultsAsync.when(
      data: (tracks) {
        if (tracks.isEmpty) {
          return const Center(
            child: Text(
              'No matching tracks found',
              style: TextStyle(color: AppTheme.textTertiary),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: tracks.length,
          separatorBuilder: (context, index) => const Divider(color: AppTheme.border, height: 1),
          itemBuilder: (context, index) {
            final t = tracks[index];
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.music_note_rounded, color: AppTheme.accentPurple, size: 20),
              ),
              title: Text(t.title, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14)),
              subtitle: Text('${t.artist} · ${t.codec}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              onTap: () {
                ref.read(playerProvider.notifier).setQueue(tracks, index);
              },
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.accentPurple)),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  Widget _buildTracksTab(AsyncValue<List<Track>> tracksAsync) {
    return tracksAsync.when(
      data: (tracks) {
        if (tracks.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: const BoxDecoration(
                      color: AppTheme.surfaceElevated,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.library_music_rounded, color: AppTheme.accentPurple, size: 48),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No tracks in library',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Auto-scan all music from your Phone and SD card, or import individual audio files.',
                    style: TextStyle(color: AppTheme.textTertiary, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accentPurple,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.autorenew_rounded, size: 18),
                        label: const Text('Auto-Scan SD & Phone', style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: _autoScanDeviceAndSdCard,
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.accentPurple,
                          side: const BorderSide(color: AppTheme.accentPurple),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.file_open_rounded, size: 18),
                        label: const Text('Pick Files'),
                        onPressed: _pickAudioFiles,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }

        return Column(
          children: [
            // Header: Track count & Sort
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${tracks.length} tracks',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  Row(
                    children: [
                      const Text(
                        'Sort by: Recently Added',
                        style: TextStyle(color: AppTheme.textTertiary, fontSize: 12),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded, color: AppTheme.accentPurple, size: 18),
                        onPressed: _autoScanDeviceAndSdCard,
                        tooltip: 'Rescan Storage',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.only(left: 16, right: 16, top: 4, bottom: 80),
                itemCount: tracks.length,
                separatorBuilder: (context, index) => const Divider(color: AppTheme.border, height: 1),
                itemBuilder: (context, index) {
                  final t = tracks[index];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 4),
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceElevated,
                        borderRadius: BorderRadius.circular(10),
                        image: t.artworkPath != null && File(t.artworkPath!).existsSync()
                            ? DecorationImage(image: FileImage(File(t.artworkPath!)), fit: BoxFit.cover)
                            : null,
                      ),
                      child: t.artworkPath == null || !File(t.artworkPath!).existsSync()
                          ? const Icon(Icons.music_note_rounded, color: AppTheme.accentPurple, size: 22)
                          : null,
                    ),
                    title: Text(
                      t.title,
                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Row(
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
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceElevated,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: AppTheme.border),
                            ),
                            child: Text(
                              t.hiFiBadgeText,
                              style: const TextStyle(color: AppTheme.neonPurple, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                    trailing: Text(t.formattedDuration, style: const TextStyle(color: AppTheme.textTertiary, fontSize: 12)),
                    onTap: () {
                      ref.read(playerProvider.notifier).setQueue(tracks, index);
                    },
                    onLongPress: () => _showAddToPlaylistDialog(t),
                  );
                },
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.accentPurple)),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  Widget _buildAlbumsTab(AsyncValue<List<Album>> albumsAsync) {
    return albumsAsync.when(
      data: (albums) {
        if (albums.isEmpty) {
          return const Center(child: Text('No albums found', style: TextStyle(color: AppTheme.textTertiary)));
        }
        return GridView.builder(
          padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 80),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: 0.82,
          ),
          itemCount: albums.length,
          itemBuilder: (context, index) {
            final a = albums[index];
            return GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AlbumDetailScreen(album: a),
                  ),
                );
              },
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceElevated,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                          image: a.artworkPath != null && File(a.artworkPath!).existsSync()
                              ? DecorationImage(image: FileImage(File(a.artworkPath!)), fit: BoxFit.cover)
                              : null,
                        ),
                        child: a.artworkPath == null || !File(a.artworkPath!).existsSync()
                            ? const Center(child: Icon(Icons.album_rounded, color: AppTheme.accentPurple, size: 40))
                            : null,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            a.title,
                            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${a.artist} · ${a.trackCount} tracks',
                            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.accentPurple)),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  Widget _buildArtistsTab(AsyncValue<List<Artist>> artistsAsync) {
    return artistsAsync.when(
      data: (artists) {
        if (artists.isEmpty) {
          return const Center(child: Text('No artists found', style: TextStyle(color: AppTheme.textTertiary)));
        }
        return ListView.separated(
          padding: const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 80),
          itemCount: artists.length,
          separatorBuilder: (context, index) => const Divider(color: AppTheme.border, height: 1),
          itemBuilder: (context, index) {
            final ar = artists[index];
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
              leading: CircleAvatar(
                radius: 22,
                backgroundColor: AppTheme.surfaceElevated,
                child: const Icon(Icons.person_rounded, color: AppTheme.accentPurple, size: 22),
              ),
              title: Text(ar.name, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: Text('${ar.albumCount} albums · ${ar.trackCount} tracks', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.accentPurple)),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  Widget _buildPlaylistsTab(AsyncValue<List<Playlist>> playlistsAsync) {
    return playlistsAsync.when(
      data: (playlists) {
        if (playlists.isEmpty) {
          return const Center(child: Text('No playlists created', style: TextStyle(color: AppTheme.textTertiary)));
        }
        return ListView.separated(
          padding: const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 80),
          itemCount: playlists.length,
          separatorBuilder: (context, index) => const Divider(color: AppTheme.border, height: 1),
          itemBuilder: (context, index) {
            final p = playlists[index];
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.playlist_play_rounded, color: AppTheme.accentPurple, size: 24),
              ),
              title: Text(p.name, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: Text('${p.trackCount} tracks', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.accentPurple)),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }
}
