import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../bridge/rust_bridge.dart';
import '../models/track.dart';
import 'lyrics_service.dart';

// ─── MethodChannel to Kotlin YtDlpHelper ──────────────────────────────────────
const _ytdlpChannel = MethodChannel('com.hifi.musicplayer/ytdlp');

// Piped instances (open-source YouTube proxies) — tried in order
const _pipedInstances = [
  'https://pipedapi.kavin.rocks',
  'https://piped-api.privacy.com.de',
  'https://api.piped.projectsegfau.lt',
  'https://pipedapi.in.projectsegfau.lt',
];

// Invidious instances — tried in order
const _invidiousInstances = [
  'https://invidious.io.lol',
  'https://inv.nadeko.net',
  'https://y.com.sb',
  'https://invidious.nerdvpn.de',
];

const _browserUA =
    'Mozilla/5.0 (Linux; Android 13; Pixel 7) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/124.0.6367.82 Mobile Safari/537.36';

// ─── Progress model ────────────────────────────────────────────────────────────
class YtDownloadProgress {
  final String stage;
  final double progressPct;
  final String title;
  final String artist;
  final String? error;
  final String? filePath;

  const YtDownloadProgress({
    required this.stage,
    required this.progressPct,
    required this.title,
    required this.artist,
    this.error,
    this.filePath,
  });
}

// ─── Service ───────────────────────────────────────────────────────────────────
class YouTubeDownloaderService {
  static final YouTubeDownloaderService instance = YouTubeDownloaderService._();
  YouTubeDownloaderService._();

  // ── ID extraction ────────────────────────────────────────────────────────────

  String? parseVideoId(String input) {
    final re = RegExp(
      r'(?:https?://)?(?:www\.|m\.|music\.)?'
      r'(?:youtube\.com/(?:watch\?(?:.*&)?v=|v/|embed/|shorts/)|youtu\.be/)'
      r'([a-zA-Z0-9_-]{11})',
      caseSensitive: false,
    );
    return re.firstMatch(input.trim())?.group(1);
  }

  // ── Main download flow ────────────────────────────────────────────────────────

  Stream<YtDownloadProgress> downloadAudio(String url) async* {
    yield const YtDownloadProgress(
      stage: 'resolving_url', progressPct: 0.05,
      title: 'Validating URL…', artist: '',
    );

    final videoId = parseVideoId(url);
    if (videoId == null) {
      yield const YtDownloadProgress(
        stage: 'failed', progressPct: 0,
        title: 'Invalid URL', artist: '',
        error: 'Please enter a valid YouTube or YouTube Music link.',
      );
      return;
    }

    try {
      // ── Step 1: Metadata ──────────────────────────────────────────────────
      yield const YtDownloadProgress(
        stage: 'fetching_metadata', progressPct: 0.10,
        title: 'Fetching track info…', artist: '',
      );

      final meta = await _fetchMetadata(url, videoId);

      final rawTitle  = meta['title']  ?? 'Unknown Track';
      final rawArtist = (meta['artist']?.isNotEmpty == true
          ? meta['artist'] : meta['uploader']) ?? 'Unknown Artist';
      final durationSec = int.tryParse(meta['duration'] ?? '0') ?? 0;

      String displayTitle  = _cleanTitle(rawTitle);
      String displayArtist = _cleanArtist(rawArtist);

      // "Artist - Title" channel pattern
      if (displayTitle.contains(' - ') && _looksGenericChannel(rawArtist)) {
        final parts = displayTitle.split(' - ');
        displayArtist = parts.first.trim();
        displayTitle  = parts.sublist(1).join(' - ').trim();
      }

      yield YtDownloadProgress(
        stage: 'fetching_metadata', progressPct: 0.20,
        title: displayTitle, artist: displayArtist,
      );

      // ── Step 2: Resolve output dir ────────────────────────────────────────
      Directory? baseDir;
      try { baseDir = await getExternalStorageDirectory(); } catch (_) {}
      baseDir ??= await getApplicationDocumentsDirectory();
      final audioDir = '${baseDir.path}/MusicPlayer/Audio';
      Directory(audioDir).createSync(recursive: true);

      // ── Step 3: Resolve audio stream URL ─────────────────────────────────
      yield YtDownloadProgress(
        stage: 'resolving_stream', progressPct: 0.30,
        title: displayTitle, artist: displayArtist,
      );

      Map<String, String>? stream;

      // Try Piped → Invidious → yt-dlp
      stream = await _getPipedStream(videoId);
      if (stream == null) {
        debugPrint('[YT] Piped failed, trying Invidious…');
        stream = await _getInvidiousStream(videoId);
      }

      if (stream != null) {
        // ── Path A: Direct CDN download (fast) ──────────────────────────
        yield YtDownloadProgress(
          stage: 'downloading_audio', progressPct: 0.35,
          title: displayTitle, artist: displayArtist,
        );

        final ext      = stream['ext'] ?? 'm4a';
        final safeName = _sanitizeFilename('$displayArtist - $displayTitle');
        final filePath = '$audioDir/$safeName.$ext';

        await _streamDownload(stream['url']!, filePath);

        final f = File(filePath);
        if (!f.existsSync() || f.lengthSync() < 8192) {
          throw Exception('CDN file is empty after download');
        }

        yield YtDownloadProgress(
          stage: 'fetching_lyrics', progressPct: 0.90,
          title: displayTitle, artist: displayArtist,
        );

        await LyricsService.fetchLyrics(Track(
          id: filePath,
          filePath: filePath,
          title: displayTitle,
          artist: displayArtist,
          album: 'YouTube Music',
          durationMs: durationSec * 1000,
          codec: ext.toUpperCase(),
          container: ext,
          lossless: false,
          isFavorite: false,
          playCount: 0,
          createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        ));

        yield YtDownloadProgress(
          stage: 'indexing_library', progressPct: 0.95,
          title: displayTitle, artist: displayArtist,
        );
        RustBridge.instance.scanFile(filePath);

        yield YtDownloadProgress(
          stage: 'completed', progressPct: 1.0,
          title: displayTitle, artist: displayArtist,
          filePath: filePath,
        );
        return;
      }

      // ── Path B: yt-dlp fallback ───────────────────────────────────────
      debugPrint('[YT] Piped & Invidious failed — falling back to yt-dlp…');
      yield YtDownloadProgress(
        stage: 'downloading_audio', progressPct: 0.40,
        title: displayTitle, artist: displayArtist,
      );

      final filePath = await _ytdlpChannel.invokeMethod<String>(
        'downloadAudio',
        {'url': url, 'outputDir': audioDir},
      );

      if (filePath == null || filePath.isEmpty) {
        yield YtDownloadProgress(
          stage: 'failed', progressPct: 0,
          title: displayTitle, artist: displayArtist,
          error: 'All download methods failed. '
              'Check internet connection or try another video.',
        );
        return;
      }

      final f = File(filePath);
      if (!f.existsSync() || f.lengthSync() < 8192) {
        yield YtDownloadProgress(
          stage: 'failed', progressPct: 0,
          title: displayTitle, artist: displayArtist,
          error: 'Downloaded file is empty or missing.',
        );
        return;
      }

      yield YtDownloadProgress(
        stage: 'fetching_lyrics', progressPct: 0.90,
        title: displayTitle, artist: displayArtist,
      );

      await LyricsService.fetchLyrics(Track(
        id: filePath,
        filePath: filePath,
        title: displayTitle,
        artist: displayArtist,
        album: 'YouTube Music',
        durationMs: durationSec * 1000,
        codec: filePath.split('.').last.toUpperCase(),
        container: filePath.split('.').last,
        lossless: false,
        isFavorite: false,
        playCount: 0,
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      ));

      yield YtDownloadProgress(
        stage: 'indexing_library', progressPct: 0.95,
        title: displayTitle, artist: displayArtist,
      );
      RustBridge.instance.scanFile(filePath);

      yield YtDownloadProgress(
        stage: 'completed', progressPct: 1.0,
        title: displayTitle, artist: displayArtist,
        filePath: filePath,
      );

    } on PlatformException catch (e) {
      debugPrint('[YT] PlatformException: ${e.message}');
      yield YtDownloadProgress(
        stage: 'failed', progressPct: 0,
        title: 'Download failed', artist: '',
        error: e.message ?? 'Unknown platform error',
      );
    } catch (e, st) {
      debugPrint('[YT] Download error: $e\n$st');
      yield YtDownloadProgress(
        stage: 'failed', progressPct: 0,
        title: 'Download failed', artist: '',
        error: e.toString(),
      );
    }
  }

  // ── Metadata fetchers ─────────────────────────────────────────────────────────

  /// YouTube oEmbed → yt-dlp fallback.
  Future<Map<String, String>> _fetchMetadata(
      String url, String videoId) async {
    // oEmbed: official, no auth, very fast
    try {
      final client = HttpClient()
        ..userAgent = _browserUA
        ..connectionTimeout = const Duration(seconds: 10);
      final req = await client
          .getUrl(Uri.parse(
            'https://www.youtube.com/oembed'
            '?url=https://www.youtube.com/watch?v=$videoId&format=json',
          ))
          .timeout(const Duration(seconds: 12));
      final res = await req.close();
      if (res.statusCode == 200) {
        final body = await res.transform(utf8.decoder).join();
        final data = jsonDecode(body) as Map;
        return {
          'title'     : data['title']?.toString() ?? '',
          'artist'    : data['author_name']?.toString() ?? '',
          'thumbnail' : data['thumbnail_url']?.toString() ?? '',
          'duration'  : '0',
        };
      }
    } catch (_) {}

    // yt-dlp --dump-json fallback (slower, sometimes blocked)
    try {
      final raw = await _ytdlpChannel
          .invokeMethod<Map>('fetchMetadata', {'url': url});
      if (raw != null && raw.isNotEmpty) {
        return raw.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
    } catch (_) {}

    return {};
  }

  // ── Stream-URL resolvers ──────────────────────────────────────────────────────

  /// Tries each Piped instance until one returns a valid audio stream URL.
  Future<Map<String, String>?> _getPipedStream(String videoId) async {
    for (final base in _pipedInstances) {
      try {
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 12);
        final req = await client
            .getUrl(Uri.parse('$base/streams/$videoId'))
            .timeout(const Duration(seconds: 15));
        req.headers.set('User-Agent', _browserUA);
        req.headers.set('Accept', 'application/json');

        final res = await req.close();
        if (res.statusCode != 200) continue;

        final body = await res.transform(utf8.decoder).join();
        final data = jsonDecode(body) as Map;

        final streams = (data['audioStreams'] as List?) ?? [];
        if (streams.isEmpty) continue;

        // Sort by bitrate descending
        final sorted = List.from(streams)
          ..sort((a, b) =>
              ((b['bitrate'] as num?) ?? 0)
                  .compareTo((a['bitrate'] as num?) ?? 0));

        for (final s in sorted) {
          final streamUrl = s['url'] as String?;
          if (streamUrl == null || streamUrl.isEmpty) continue;

          final mime = (s['mimeType'] as String? ?? '').toLowerCase();
          final ext  = mime.contains('opus') || mime.contains('webm')
              ? 'opus'
              : 'm4a';

          debugPrint('[YT] Piped OK — $base — $ext');
          return {'url': streamUrl, 'ext': ext};
        }
      } catch (e) {
        debugPrint('[YT] Piped $base failed: $e');
      }
    }
    return null;
  }

  /// Tries each Invidious instance until one returns a valid adaptive audio URL.
  Future<Map<String, String>?> _getInvidiousStream(String videoId) async {
    for (final base in _invidiousInstances) {
      try {
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 12);
        final req = await client
            .getUrl(Uri.parse(
              '$base/api/v1/videos/$videoId'
              '?fields=adaptiveFormats,title,author,lengthSeconds',
            ))
            .timeout(const Duration(seconds: 15));
        req.headers.set('User-Agent', _browserUA);
        req.headers.set('Accept', 'application/json');

        final res = await req.close();
        if (res.statusCode != 200) continue;

        final body = await res.transform(utf8.decoder).join();
        final data = jsonDecode(body) as Map;

        final formats = (data['adaptiveFormats'] as List?) ?? [];
        final audioFormats = formats
            .where((f) =>
                (f['type'] as String? ?? '').startsWith('audio/'))
            .toList();

        if (audioFormats.isEmpty) continue;

        audioFormats.sort((a, b) =>
            ((b['bitrate'] as num?) ?? 0)
                .compareTo((a['bitrate'] as num?) ?? 0));

        for (final f in audioFormats) {
          final streamUrl = f['url'] as String?;
          if (streamUrl == null || streamUrl.isEmpty) continue;

          final container = (f['container'] as String? ?? '').toLowerCase();
          final ext = container == 'webm' ? 'opus' : 'm4a';

          debugPrint('[YT] Invidious OK — $base — $ext');
          return {'url': streamUrl, 'ext': ext};
        }
      } catch (e) {
        debugPrint('[YT] Invidious $base failed: $e');
      }
    }
    return null;
  }

  // ── Streaming download ────────────────────────────────────────────────────────

  /// Downloads [url] to [filePath] by streaming bytes directly to disk.
  Future<void> _streamDownload(String downloadUrl, String filePath) async {
    final client = HttpClient()
      ..userAgent = _browserUA
      ..connectionTimeout = const Duration(seconds: 30);

    final req = await client
        .getUrl(Uri.parse(downloadUrl))
        .timeout(const Duration(seconds: 35));
    req.headers.set('Referer', 'https://www.youtube.com/');
    req.headers.set('Origin', 'https://www.youtube.com');
    req.headers.set('Accept', '*/*');
    req.headers.set('Accept-Language', 'en-US,en;q=0.9');

    final res = await req.close().timeout(const Duration(minutes: 10));
    if (res.statusCode != 200 && res.statusCode != 206) {
      throw Exception('CDN returned HTTP ${res.statusCode}');
    }

    final sink = File(filePath).openWrite();
    await res.pipe(sink);
  }

  // ── String helpers ────────────────────────────────────────────────────────────

  String _cleanTitle(String raw) => raw
      .replaceAll(RegExp(
          r'\s*[\(\[]\s*(?:official\s+)?(?:lyric[s]?\s+)?(?:music\s+)?'
          r'(?:video|audio|mv|hd|4k|visualizer|vevo|live|performance|acoustic)\s*[\)\]]',
          caseSensitive: false), '')
      .replaceAll(RegExp(
          r'\s*[\(\[]\s*official[^\)\]]*[\)\]]', caseSensitive: false), '')
      .replaceAll(RegExp(
          r'\s*[\(\[]\s*from\s+[^\)\]]+[\)\]]', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s*\bfeat\..*$', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s*\bft\..*$',   caseSensitive: false), '')
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .trim();

  String _cleanArtist(String raw) => raw
      .split(RegExp(
          r'\s*[,&]\s*|\s+feat\.?\s+|\s+ft\.?\s+', caseSensitive: false))
      .first
      .replaceAll(RegExp(r'\s*VEVO$',    caseSensitive: false), '')
      .replaceAll(RegExp(r'\s*- Topic$', caseSensitive: false), '')
      .trim();

  bool _looksGenericChannel(String uploader) {
    final u = uploader.toLowerCase();
    return u.contains('vevo') || u.contains('topic') ||
        u.contains('official') || u.contains('records') ||
        u.contains('music');
  }

  String _sanitizeFilename(String name) => name
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .trim();
}
