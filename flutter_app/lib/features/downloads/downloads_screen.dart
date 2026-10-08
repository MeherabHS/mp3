import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme.dart';
import '../../bridge/rust_bridge.dart';
import '../../providers/library_provider.dart';
import '../../providers/player_provider.dart';
import '../../services/youtube_downloader_service.dart';

// ─── Download job model ───────────────────────────────────────────────────────
class DownloadJob {
  final String id;
  final String url;
  final String title;
  final String artist;
  final String stage;
  final double progressPct;
  final String? error;
  final String? filePath;
  final bool isComplete;

  const DownloadJob({
    required this.id,
    required this.url,
    required this.title,
    required this.artist,
    required this.stage,
    required this.progressPct,
    this.error,
    this.filePath,
    required this.isComplete,
  });

  DownloadJob copyWith({
    String? title,
    String? artist,
    String? stage,
    double? progressPct,
    String? error,
    String? filePath,
    bool? isComplete,
  }) {
    return DownloadJob(
      id: id,
      url: url,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      stage: stage ?? this.stage,
      progressPct: progressPct ?? this.progressPct,
      error: error ?? this.error,
      filePath: filePath ?? this.filePath,
      isComplete: isComplete ?? this.isComplete,
    );
  }
}

// ─── Provider ────────────────────────────────────────────────────────────────
final downloadJobsProvider =
    StateNotifierProvider<DownloadNotifier, List<DownloadJob>>((ref) {
  return DownloadNotifier(ref);
});

class DownloadNotifier extends StateNotifier<List<DownloadJob>> {
  final Ref _ref;

  DownloadNotifier(this._ref) : super([]);

  Future<void> startDownload(String url) async {
    final jobId = DateTime.now().millisecondsSinceEpoch.toString();
    final initialJob = DownloadJob(
      id: jobId,
      url: url,
      title: 'Resolving YouTube URL...',
      artist: '',
      stage: 'resolving_url',
      progressPct: 0.05,
      isComplete: false,
    );

    state = [initialJob, ...state];

    try {
      final stream = YouTubeDownloaderService.instance.downloadAudio(url);

      await for (final progress in stream) {
        state = state.map((job) {
          if (job.id == jobId) {
            return job.copyWith(
              title: progress.title.isNotEmpty ? progress.title : job.title,
              artist: progress.artist.isNotEmpty ? progress.artist : job.artist,
              stage: progress.stage,
              progressPct: progress.progressPct,
              error: progress.error,
              filePath: progress.filePath,
              isComplete: progress.stage == 'completed',
            );
          }
          return job;
        }).toList();

        if (progress.stage == 'completed') {
          _ref.invalidate(tracksProvider);
          _ref.invalidate(albumsProvider);
          _ref.invalidate(artistsProvider);
          _ref.invalidate(playlistsProvider);
        }
      }
    } catch (e) {
      state = state.map((job) {
        if (job.id == jobId) {
          return job.copyWith(
            stage: 'failed',
            error: e.toString(),
            isComplete: false,
          );
        }
        return job;
      }).toList();
    }
  }

  void clearCompleted() {
    state = state.where((j) => !j.isComplete && j.error == null).toList();
  }
}

// ─── Screen ──────────────────────────────────────────────────────────────────
class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen>
    with SingleTickerProviderStateMixin {
  final _urlController = TextEditingController();
  late TabController _filterTabController;
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    _filterTabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _filterTabController.dispose();
    super.dispose();
  }

  Future<void> _startDownload() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    if (YouTubeDownloaderService.instance.parseVideoId(url) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppTheme.surfaceElevated,
          content: Text(
            'Please enter a valid YouTube video or music link',
            style: TextStyle(color: Colors.redAccent),
          ),
        ),
      );
      return;
    }

    setState(() => _isDownloading = true);
    _urlController.clear();

    try {
      await ref.read(downloadJobsProvider.notifier).startDownload(url);
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final jobs = ref.watch(downloadJobsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: const Text('Downloads'),
        actions: [
          if (jobs.any((j) => j.isComplete || j.error != null))
            IconButton(
              icon: const Icon(Icons.clear_all_rounded, color: AppTheme.textSecondary),
              onPressed: () => ref.read(downloadJobsProvider.notifier).clearCompleted(),
              tooltip: 'Clear history',
            ),
        ],
      ),
      body: Column(
        children: [
          // ─── URL input ────────────────────────────────────────────────
          _buildUrlInput(theme),

          // ─── Filter Tabs: All | Downloading | Completed ───────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: TabBar(
                controller: _filterTabController,
                indicator: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: AppTheme.accentPurple,
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: Colors.white,
                unselectedLabelColor: AppTheme.textSecondary,
                labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                onTap: (_) => setState(() {}),
                tabs: const [
                  Tab(text: 'All'),
                  Tab(text: 'Downloading'),
                  Tab(text: 'Completed'),
                ],
              ),
            ),
          ),

          // ─── Job list ─────────────────────────────────────────────────
          Expanded(
            child: _buildFilteredJobList(jobs),
          ),
        ],
      ),
    );
  }

  Widget _buildFilteredJobList(List<DownloadJob> allJobs) {
    final filtered = switch (_filterTabController.index) {
      1 => allJobs.where((j) => !j.isComplete && j.error == null).toList(),
      2 => allJobs.where((j) => j.isComplete).toList(),
      _ => allJobs,
    };

    if (filtered.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filtered.length,
      itemBuilder: (ctx, i) => _buildJobCard(filtered[i]),
    );
  }

  Widget _buildUrlInput(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: AppTheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'YouTube / YouTube Music URL',
            style: theme.textTheme.labelMedium?.copyWith(
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _urlController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'https://youtube.com/watch?v=... or youtu.be/...',
                    hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
                    filled: true,
                    fillColor: AppTheme.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppTheme.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppTheme.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppTheme.accentPurple),
                    ),
                    prefixIcon: const Icon(Icons.link_rounded, color: AppTheme.accentPurple, size: 20),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  onSubmitted: (_) => _startDownload(),
                ),
              ),
              const SizedBox(width: 10),
              _isDownloading
                  ? const SizedBox(
                      width: 44,
                      height: 44,
                      child: Padding(
                        padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentPurple),
                      ),
                    )
                  : ElevatedButton(
                      onPressed: _startDownload,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accentPurple,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(48, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Icon(Icons.download_rounded, size: 22),
                    ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Extracts highest-quality audio stream (Opus 160kbps / AAC), artwork & synced lyrics.',
            style: TextStyle(color: AppTheme.textTertiary, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildJobCard(DownloadJob job) {
    final hasError = job.error != null;
    final isComplete = job.isComplete;
    final color = hasError
        ? Colors.redAccent
        : isComplete
            ? AppTheme.connectedGreen
            : AppTheme.accentPurple;

    final stageLabel = _stageLabel(job.stage, job.progressPct);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasError
                    ? Icons.error_outline_rounded
                    : isComplete
                        ? Icons.check_circle_rounded
                        : Icons.downloading_rounded,
                color: color,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  job.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (job.artist.isNotEmpty) ...[
            const SizedBox(height: 3),
            Padding(
              padding: const EdgeInsets.only(left: 30),
              child: Text(
                job.artist,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (!isComplete && !hasError) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: job.progressPct,
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation<Color>(color),
                minHeight: 4,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(stageLabel, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500)),
                Text('${(job.progressPct * 100).toInt()}%', style: TextStyle(color: color, fontSize: 11)),
              ],
            ),
          ] else if (hasError) ...[
            Text(
              job.error ?? 'Unknown error',
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              maxLines: 2,
            ),
          ] else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.check_rounded, color: AppTheme.connectedGreen, size: 16),
                    SizedBox(width: 4),
                    Text('Complete — Ready in Library', style: TextStyle(color: AppTheme.connectedGreen, fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
                if (job.filePath != null)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.neonPurple,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('Play Now', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    onPressed: () {
                      final tracks = ref.read(tracksProvider).value ?? [];
                      final match = tracks.where((t) => t.filePath == job.filePath).firstOrNull;
                      if (match != null) {
                        ref.read(playerProvider.notifier).playTrack(match);
                      } else if (job.filePath != null) {
                        final scanned = RustBridge.instance.scanFile(job.filePath!);
                        if (scanned != null) {
                          ref.read(playerProvider.notifier).playTrack(scanned);
                        }
                      }
                    },
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: AppTheme.surfaceElevated,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.cloud_download_rounded, size: 48, color: AppTheme.accentPurple),
          ),
          const SizedBox(height: 16),
          const Text(
            'No downloads yet',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Paste any YouTube or YouTube Music link above to download\nhigh-quality audio with synced lyrics & artwork.',
            style: TextStyle(color: AppTheme.textTertiary, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _stageLabel(String stage, double pct) {
    return switch (stage) {
      'resolving_url' => 'Resolving audio stream...',
      'fetching_metadata' => 'Fetching track metadata...',
      'downloading_audio' => 'Downloading audio stream (${(pct * 100).toInt()}%)...',
      'extracting_metadata' => 'Reading audio tags...',
      'processing_artwork' => 'Processing album art...',
      'fetching_lyrics' => 'Fetching synced lyrics from LRCLIB...',
      'indexing_library' => 'Indexing to Hi-Fi library...',
      'completed' => 'Download Complete',
      'failed' => 'Failed',
      _ => 'Queued...',
    };
  }
}
