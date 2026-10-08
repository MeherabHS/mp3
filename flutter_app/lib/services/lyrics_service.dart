import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../models/lyrics.dart';
import '../models/track.dart';

class LyricsService {
  static final Map<String, SyncedLyrics> _memoryCache = {};

  static const _baseUrl    = 'https://lrclib.net';
  static const _ovhBaseUrl = 'https://api.lyrics.ovh/v1';
  static const _headers    = {'User-Agent': 'PersonalHiFi/2.0 (https://github.com)'};
  static const _timeout    = Duration(seconds: 10);

  /// Set by the lyrics provider whenever the Musixmatch token changes in settings.
  /// Empty string = Musixmatch tier is silently skipped.
  static String _musixmatchToken = '';
  static void setMusixmatchToken(String token) => _musixmatchToken = token.trim();

  /// Fetch lyrics for [track].
  ///
  /// Strategy (each step only runs if the previous found nothing):
  ///   1. Local .lrc sidecar
  ///   2. /api/get  — exact match without duration (most permissive)
  ///   3. /api/get  — exact match WITH duration (if durationMs > 0), matches ±3 s
  ///   4. /api/search?track_name=&artist_name= — structured search (precise)
  ///   5. /api/search?q= — free-text search (broadest fallback)
  static Future<SyncedLyrics> fetchLyrics(Track track) async {
    if (_memoryCache.containsKey(track.id)) return _memoryCache[track.id]!;

    // ── 1. Local sidecar ─────────────────────────────────────────────────────
    try {
      final sidecar =
          File(track.filePath.replaceAll(RegExp(r'\.[^.]+$'), '.lrc'));
      if (sidecar.existsSync()) {
        final content = await sidecar.readAsString();
        final parsed = parseLrc(track.id, content);
        if (parsed.lines.isNotEmpty) {
          _memoryCache[track.id] = parsed;
          return parsed;
        }
      }
    } catch (_) {}

    // ── Normalise ─────────────────────────────────────────────────────────────
    final rawTitle  = track.title;
    final rawArtist = track.artist;

    String cleanTitle = _stripTitleJunk(rawTitle);
    String cleanArtist = _primaryArtist(rawArtist);

    // "Artist - Title" style (common in YouTube rips)
    if (cleanTitle.contains(' - ')) {
      final parts = cleanTitle.split(' - ');
      final possibleArtist = parts.first.trim();
      if (cleanArtist.isEmpty ||
          cleanArtist.toLowerCase() == 'unknown artist' ||
          _looksGenericChannel(cleanArtist)) {
        cleanArtist = possibleArtist;
      }
      cleanTitle = parts.sublist(1).join(' - ').trim();
    }

    final durationSec    = track.durationMs > 0 ? track.durationMs ~/ 1000 : 0;
    final artistVariants = _artistVariants(cleanArtist, rawArtist);
    final titleVariants  = _dedupe([cleanTitle, rawTitle]);

    // ── 2. /api/get — no duration (best match by name alone) ─────────────────
    for (final artist in artistVariants) {
      for (final title in titleVariants) {
        final lrc = await _apiGet(artist, title, duration: null);
        if (lrc != null) return _cache(track, lrc);
      }
    }

    // ── 3. /api/get — with duration (±3 s tolerance, more precise) ───────────
    if (durationSec > 0) {
      for (final artist in artistVariants) {
        for (final title in titleVariants) {
          final lrc = await _apiGet(artist, title, duration: durationSec);
          if (lrc != null) return _cache(track, lrc);
        }
      }
    }

    // ── 4. Structured search: ?track_name=&artist_name= ──────────────────────
    for (final artist in artistVariants) {
      for (final title in titleVariants) {
        final lrc = await _structuredSearch(artist, title);
        if (lrc != null) return _cache(track, lrc);
      }
    }

    // ── 5–7. Parallel fallback race ───────────────────────────────────────────
    // Fire LRCLIB free-text, lyrics.ovh, and NetEase simultaneously.
    // Total wait = max(individual), not sum — adding more sources costs nothing.
    final freeQueries = _dedupe([
      '$cleanArtist $cleanTitle',
      '$cleanArtist $rawTitle',
      '$rawArtist $cleanTitle',
      cleanTitle,
      _removeDiacritics('$cleanArtist $cleanTitle'),
    ]);

    // Build all tasks that run in parallel.
    final parallelTasks = <Future<String?> Function()>[
      // 5a. LRCLIB free-text (multiple queries, try first that hits)
      () async {
        for (final q in freeQueries) {
          final r = await _freeSearch(q, cleanTitle, cleanArtist);
          if (r != null) return r;
        }
        return null;
      },
      // 5b. lyrics.ovh — huge plain-lyrics catalogue
      () async {
        final artists = _dedupe([
          cleanArtist, _removeDiacritics(cleanArtist), ..._artistVariants(cleanArtist, rawArtist),
        ]);
        final titles = _dedupe([cleanTitle, _removeDiacritics(cleanTitle), rawTitle]);
        for (final a in artists) {
          for (final t in titles) {
            final r = await _lyricsOvh(a, t);
            if (r != null) return r;
          }
        }
        return null;
      },
      // 5c. NetEase Cloud Music — synced LRC, excellent mainstream coverage
      () => _neteaseLrc('$cleanArtist $cleanTitle'),
      // 5d. JioSaavn — plain lyrics, best coverage for Indian/Bangla/Hindi songs
      () => _jioSaavnLyrics('$cleanArtist $cleanTitle'),
      // 5e. Musixmatch unofficial API — synced LRC, world's largest catalogue
      //     Only runs when user has set a token in Settings → Lyrics.
      if (_musixmatchToken.isNotEmpty)
        () => _musixmatchLrc(cleanArtist, cleanTitle,
            durationSec: durationSec),
    ];

    // Race: return first non-null result, prefer synced over plain.
    final lrc = await _raceFirst(parallelTasks);
    if (lrc != null) return _cache(track, lrc);

    // Nothing found
    return SyncedLyrics(
        trackId: track.id,
        isSynchronized: false,
        isWordSynced: false,
        offsetMs: 0,
        lines: []);
  }

  // ── LRCLIB endpoints ─────────────────────────────────────────────────────────

  /// GET /api/get — exact lookup.
  /// [duration] = null → omit the parameter (most permissive).
  /// [duration] > 0    → LRCLIB matches within ±3 s.
  static Future<String?> _apiGet(
      String artist, String title, {required int? duration}) async {
    try {
      final params = {
        'artist_name': artist,
        'track_name': title,
        if (duration != null && duration > 0) 'duration': '$duration',
      };
      final uri =
          Uri.parse('$_baseUrl/api/get').replace(queryParameters: params);
      final resp =
          await http.get(uri, headers: _headers).timeout(_timeout);
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        return _extractLrc(data);
      }
    } catch (e) {
      debugPrint('LRCLIB /api/get error: $e');
    }
    return null;
  }

  /// GET /api/search?track_name=&artist_name= — structured search.
  static Future<String?> _structuredSearch(
      String artist, String title) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/search').replace(queryParameters: {
        'track_name': title,
        'artist_name': artist,
      });
      final resp =
          await http.get(uri, headers: _headers).timeout(_timeout);
      if (resp.statusCode == 200) {
        final list = jsonDecode(resp.body) as List<dynamic>;
        final titleLower = title.toLowerCase();
        for (final item in list) {
          if (item is! Map<String, dynamic>) continue;
          // Must at least partially match the title we searched for
          final rTitle =
              (item['trackName'] as String? ?? '').toLowerCase();
          final titleOk =
              rTitle.contains(titleLower) || titleLower.contains(rTitle);
          if (!titleOk) continue;
          final lrc = _extractLrc(item);
          if (lrc != null) return lrc;
        }
      }
    } catch (e) {
      debugPrint('LRCLIB structured search error: $e');
    }
    return null;
  }

  /// GET /api/search?q= — free-text fallback with loose relevance filter.
  static Future<String?> _freeSearch(
      String query, String cleanTitle, String cleanArtist) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/search')
          .replace(queryParameters: {'q': query.trim()});
      final resp =
          await http.get(uri, headers: _headers).timeout(_timeout);
      if (resp.statusCode != 200) return null;

      final list = jsonDecode(resp.body) as List<dynamic>;
      for (final item in list) {
        if (item is! Map<String, dynamic>) continue;

        // Loose relevance filter — skip only if clearly unrelated
        final rTitle = (item['trackName'] as String? ?? '').toLowerCase();
        final tClean = cleanTitle.toLowerCase();

        final titleOk = rTitle.contains(tClean) || tClean.contains(rTitle);
        // Accept if at least the title matches (artist can be wrong on compilations)
        if (!titleOk) continue;

        final lrc = _extractLrc(item);
        if (lrc != null) return lrc;
      }
    } catch (e) {
      debugPrint('LRCLIB free search error: $e');
    }
    return null;
  }

  /// GET https://api.lyrics.ovh/v1/{artist}/{title}
  /// Returns plain (unsynced) lyrics as an LRC-formatted string.
  /// Wide catalogue, no API key, good coverage for popular songs.
  static Future<String?> _lyricsOvh(String artist, String title) async {
    try {
      // lyrics.ovh uses path segments — encode each part separately
      final uri = Uri.parse(
          '$_ovhBaseUrl/${Uri.encodeComponent(artist)}/${Uri.encodeComponent(title)}');
      final resp = await http.get(uri, headers: _headers).timeout(_timeout);
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final lyrics = (data['lyrics'] as String?)?.trim();
        if (lyrics != null && lyrics.isNotEmpty) {
          // Return as plain text — parseLrc will treat lines with no timestamp
          // as unsynchronised plain lyrics.
          return lyrics;
        }
      }
    } catch (e) {
      debugPrint('lyrics.ovh error: $e');
    }
    return null;
  }

  /// Race multiple async tasks — returns the first non-null result.
  /// All tasks run concurrently; total latency ≈ fastest winner, not sum.
  /// Prefers synced lyrics (containing time-tags) over plain ones when
  /// multiple sources respond near-simultaneously.
  static Future<String?> _raceFirst(
      List<Future<String?> Function()> tasks) async {
    if (tasks.isEmpty) return null;

    final completer = Completer<String?>();
    int pending = tasks.length;
    String? bestPlain; // fallback if only plain results arrive

    void finish(String? result) {
      pending--;
      if (result != null) {
        // Immediately resolve on synced lyrics (has time tags)
        if (!completer.isCompleted && result.contains(RegExp(r'\[\d+:\d+'))) {
          completer.complete(result);
          return;
        }
        // Otherwise hold as best plain candidate
        bestPlain ??= result;
      }
      if (pending == 0 && !completer.isCompleted) {
        completer.complete(bestPlain);
      }
    }

    for (final task in tasks) {
      task().then(finish).catchError((_) => finish(null));
    }

    return completer.future;
  }

  /// Search NetEase Cloud Music for synced LRC lyrics.
  /// NetEase has a massive catalogue including Western pop — returns LRC format.
  static Future<String?> _neteaseLrc(String query) async {
    try {
      // Step 1: search for the song to get its ID
      final searchUri = Uri.parse(
              'https://music.163.com/api/search/get')
          .replace(queryParameters: {
        's': query,
        'type': '1',   // 1 = songs
        'limit': '5',
        'offset': '0',
      });
      final searchResp = await http
          .get(searchUri, headers: {
            ..._headers,
            'Referer': 'https://music.163.com',
          })
          .timeout(_timeout);

      if (searchResp.statusCode != 200) return null;

      final searchJson = jsonDecode(searchResp.body) as Map<String, dynamic>;
      final songs = ((searchJson['result'] as Map<String, dynamic>?)?['songs']
              as List<dynamic>?) ??
          [];
      if (songs.isEmpty) return null;

      final songId = (songs.first as Map<String, dynamic>)['id']?.toString();
      if (songId == null) return null;

      // Step 2: fetch LRC for that song ID
      final lrcUri = Uri.parse('https://music.163.com/api/song/lyric')
          .replace(queryParameters: {
        'id': songId,
        'lv': '1',  // line-synced LRC
        'kv': '1',
        'tv': '-1',
      });
      final lrcResp = await http
          .get(lrcUri, headers: {
            ..._headers,
            'Referer': 'https://music.163.com',
          })
          .timeout(_timeout);

      if (lrcResp.statusCode != 200) return null;

      final lrcJson  = jsonDecode(lrcResp.body) as Map<String, dynamic>;
      final lrcText  = (lrcJson['lrc'] as Map<String, dynamic>?)?['lyric']
          as String?;

      if (lrcText == null || lrcText.trim().isEmpty) return null;

      // NetEase sometimes returns metadata-only LRC with no actual lyrics
      final hasRealLines = lrcText
          .split('\n')
          .any((l) => RegExp(r'\[\d+:\d+\.\d+\]\s*\S').hasMatch(l));
      if (!hasRealLines) return null;

      return lrcText.trim();
    } catch (e) {
      debugPrint('NetEase lyrics error: $e');
      return null;
    }
  }

  /// JioSaavn internal API — plain lyrics, best free source for Indian and
  /// Bangla/Bengali songs. No API key required.
  ///
  /// Flow: search for song → pick first result with has_lyrics==true →
  ///       fetch lyrics via lyrics.getLyrics endpoint.
  static Future<String?> _jioSaavnLyrics(String query) async {
    const base = 'https://www.jiosaavn.com/api.php';
    const commonParams = {
      '_format': 'json',
      '_marker': '0',
      'ctx': 'web6dot0',
    };
    const saavnHeaders = {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      'Referer': 'https://www.jiosaavn.com/',
    };

    try {
      // Step 1 — search for the song
      final searchUri = Uri.parse(base).replace(queryParameters: {
        ...commonParams,
        '__call': 'search.getResults',
        'q': query,
        'p': '1',
        'n': '8',
      });
      final searchResp = await http
          .get(searchUri, headers: saavnHeaders)
          .timeout(_timeout);
      if (searchResp.statusCode != 200) return null;

      final searchData = jsonDecode(searchResp.body) as Map<String, dynamic>;
      final results = searchData['results'] as List<dynamic>? ?? [];

      // Find first song that has lyrics available
      String? songId;
      for (final item in results) {
        if (item is Map<String, dynamic> &&
            item['has_lyrics']?.toString() == 'true') {
          songId = item['id']?.toString();
          break;
        }
      }
      if (songId == null) return null;

      // Step 2 — fetch the actual lyrics text
      final lyricsUri = Uri.parse(base).replace(queryParameters: {
        ...commonParams,
        '__call': 'lyrics.getLyrics',
        'api_version': '4',
        'lyrics_id': songId,
      });
      final lyricsResp = await http
          .get(lyricsUri, headers: saavnHeaders)
          .timeout(_timeout);
      if (lyricsResp.statusCode != 200) return null;

      final lyricsData = jsonDecode(lyricsResp.body) as Map<String, dynamic>;
      final lyrics = (lyricsData['lyrics'] as String?)?.trim();
      if (lyrics == null || lyrics.isEmpty) return null;

      // JioSaavn uses <br> for newlines in some responses
      return lyrics.replaceAll(RegExp(r'<br\s*/?>',caseSensitive: false), '\n');
    } catch (e) {
      debugPrint('JioSaavn lyrics error: $e');
      return null;
    }
  }

  /// Musixmatch unofficial desktop-app API — returns synced LRC.
  /// Requires a `usertoken` extracted from the Musixmatch desktop app.
  ///
  /// How to get the token:
  ///   1. Install Musixmatch desktop (musixmatch.com/apps) and sign in.
  ///   2. Open DevTools (F12) → Network tab → filter "apic-desktop".
  ///   3. Copy the `usertoken=` query param from any request.
  ///   4. Paste into Settings → Lyrics → Musixmatch Token.
  static Future<String?> _musixmatchLrc(
    String artist,
    String title, {
    int durationSec = 0,
  }) async {
    if (_musixmatchToken.isEmpty) return null;
    try {
      final params = <String, String>{
        'format': 'json',
        'namespace': 'lyrics_richsynced',
        'subtitle_format': 'lrc',
        'app_id': 'web-desktop-app-v1.0',
        'usertoken': _musixmatchToken,
        'q_artist': artist,
        'q_track': title,
        'user_language': 'en',
        if (durationSec > 0) 'q_duration': '$durationSec',
      };
      final uri = Uri.parse(
              'https://apic-desktop.musixmatch.com/ws/1.1/macro.subtitles.get')
          .replace(queryParameters: params);

      final resp = await http.get(uri, headers: {
        ..._headers,
        'Cookie': 'MXMUID=${_musixmatchToken.substring(0, 8)}',
      }).timeout(_timeout);

      if (resp.statusCode != 200) return null;

      final root  = jsonDecode(resp.body) as Map<String, dynamic>;
      final body  = root['message']?['body'];
      if (body == null) return null;

      // Nested path: body → macro_calls → track.subtitles.get → message → body → subtitle_list
      final macroCalls = body['macro_calls'] as Map<String, dynamic>?;
      final subtitleCall = macroCalls?['track.subtitles.get']
          as Map<String, dynamic>?;
      final subtitleBody = subtitleCall?['message']?['body']
          as Map<String, dynamic>?;
      final subtitleList = subtitleBody?['subtitle_list'] as List<dynamic>?;

      if (subtitleList == null || subtitleList.isEmpty) return null;

      final lrc = (subtitleList.first as Map<String, dynamic>)['subtitle']
          ?['subtitle_body'] as String?;

      if (lrc == null || lrc.trim().isEmpty) return null;

      // Validate it's real synced content
      final hasTimeTags = lrc.contains(RegExp(r'\[\d+:\d+'));
      return hasTimeTags ? lrc.trim() : null;
    } catch (e) {
      debugPrint('Musixmatch lyrics error: $e');
      return null;
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  /// Pull the best lrc string out of a LRCLIB response map.
  /// Prefers synced, falls back to plain.
  static String? _extractLrc(Map<String, dynamic> data) {
    final synced = (data['syncedLyrics'] as String?)?.trim();
    if (synced != null && synced.isNotEmpty) return synced;
    final plain = (data['plainLyrics'] as String?)?.trim();
    if (plain != null && plain.isNotEmpty) return plain;
    return null;
  }

  static SyncedLyrics _cache(Track track, String lrcContent) {
    final parsed = parseLrc(track.id, lrcContent);
    if (parsed.lines.isNotEmpty) {
      _memoryCache[track.id] = parsed;
      _cacheLocally(track, lrcContent);
    }
    return parsed;
  }

  static String _stripTitleJunk(String raw) => raw
      .replaceAll(
          RegExp(
              r'\s*[\(\[]\s*(?:official\s+)?(?:lyric[s]?\s+)?(?:music\s+)?'
              r'(?:video|audio|mv|hd|4k|visualizer|vevo|live|performance|acoustic)\s*[\)\]]',
              caseSensitive: false),
          '')
      .replaceAll(
          RegExp(r'\s*[\(\[]\s*official[^\)\]]*[\)\]]',
              caseSensitive: false),
          '')
      .replaceAll(
          RegExp(r'\s*[\(\[]\s*from\s+[^\)\]]+[\)\]]',
              caseSensitive: false),
          '')
      .replaceAll(
          RegExp(r'\s*[\(\[]\s*feat\.?[^\)\]]*[\)\]]',
              caseSensitive: false),
          '')
      .replaceAll(RegExp(r'\s*\bfeat\..*$', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s*\bft\..*$',   caseSensitive: false), '')
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .trim();

  static String _primaryArtist(String raw) => raw
      .split(RegExp(
          r'\s*[,&]\s*|\s+feat\.?\s+|\s+ft\.?\s+',
          caseSensitive: false))
      .first
      .replaceAll(RegExp(r'\s*VEVO$',    caseSensitive: false), '')
      .replaceAll(RegExp(r'\s*- Topic$', caseSensitive: false), '')
      .trim();

  static List<String> _artistVariants(String clean, String raw) {
    final primary = _primaryArtist(raw);
    // Also try without leading "The " (e.g. "The Weeknd" → "Weeknd")
    final withoutThe = clean.startsWith('The ')
        ? clean.substring(4)
        : (primary.startsWith('The ') ? primary.substring(4) : null);
    // Diacritics-stripped version (e.g. "Beyoncé" → "Beyonce")
    final stripped = _removeDiacritics(clean);
    final seen = <String>{};
    return [clean, primary, raw, withoutThe, stripped]
        .whereType<String>()
        .where((a) => a.isNotEmpty && seen.add(a.toLowerCase()))
        .toList();
  }

  /// Remove common Latin diacritics so "Beyoncé" matches "Beyonce" in the DB.
  static String _removeDiacritics(String s) {
    const map = {
      'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a',
      'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
      'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
      'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o',
      'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
      'ý': 'y', 'ÿ': 'y', 'ñ': 'n', 'ç': 'c', 'ß': 'ss',
      'À': 'A', 'Á': 'A', 'Â': 'A', 'Ã': 'A', 'Ä': 'A', 'Å': 'A',
      'È': 'E', 'É': 'E', 'Ê': 'E', 'Ë': 'E',
      'Ì': 'I', 'Í': 'I', 'Î': 'I', 'Ï': 'I',
      'Ò': 'O', 'Ó': 'O', 'Ô': 'O', 'Õ': 'O', 'Ö': 'O', 'Ø': 'O',
      'Ù': 'U', 'Ú': 'U', 'Û': 'U', 'Ü': 'U',
      'Ý': 'Y', 'Ñ': 'N', 'Ç': 'C',
    };
    return s.split('').map((c) => map[c] ?? c).join('');
  }

  static bool _looksGenericChannel(String s) {
    final l = s.toLowerCase();
    return l.contains('vevo') || l.contains('topic') ||
        l.contains('official') || l.contains('records') ||
        l.contains('music') || l == 'unknown artist';
  }

  /// Remove duplicates while preserving order.
  static List<String> _dedupe(List<String> items) {
    final seen = <String>{};
    return items
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && seen.add(s.toLowerCase()))
        .toList();
  }

  // ── LRC parser ───────────────────────────────────────────────────────────────

  static SyncedLyrics parseLrc(String trackId, String lrcContent) {
    final timeTagRe = RegExp(r'\[(\d{1,2}):(\d{2})(?:\.(\d{2,3}))?\]');
    final parsedLines = <LyricLine>[];

    for (final rawLine in lrcContent.split('\n')) {
      final trimmed = rawLine.trim();
      if (trimmed.isEmpty) continue;

      final match = timeTagRe.firstMatch(trimmed);
      if (match != null) {
        final min    = int.tryParse(match.group(1) ?? '0') ?? 0;
        final sec    = int.tryParse(match.group(2) ?? '0') ?? 0;
        final fracStr = match.group(3) ?? '0';
        final msFrac  = fracStr.length == 2
            ? (int.tryParse(fracStr) ?? 0) * 10
            : (int.tryParse(fracStr) ?? 0);
        final startMs = min * 60 * 1000 + sec * 1000 + msFrac;
        final text    = trimmed.replaceFirst(timeTagRe, '').trim();

        // Empty-text lines (silence gaps) are silently skipped
        if (text.isNotEmpty) {
          parsedLines.add(LyricLine(startMs: startMs, text: text));
        }
      } else if (!trimmed.startsWith('[')) {
        // Plain (unsynced) line
        parsedLines.add(LyricLine(startMs: 0, text: trimmed));
      }
      // Lines starting with '[' but not matching the time tag (e.g. [ar:Artist])
      // are metadata tags — skip them silently.
    }

    // Assign end times
    for (int i = 0; i < parsedLines.length; i++) {
      final isLastOrUnsync = i == parsedLines.length - 1 ||
          parsedLines[i].startMs == 0;
      parsedLines[i] = LyricLine(
        startMs: parsedLines[i].startMs,
        endMs: isLastOrUnsync
            ? parsedLines[i].startMs + 5000
            : parsedLines[i + 1].startMs,
        text: parsedLines[i].text,
      );
    }

    final isSynced = parsedLines.any((l) => l.startMs > 0);
    return SyncedLyrics(
      trackId: trackId,
      isSynchronized: isSynced,
      isWordSynced: false,
      offsetMs: 0,
      lines: parsedLines,
    );
  }

  // ── Public cache control ─────────────────────────────────────────────────────

  /// Remove all cached data for [trackId] so the next [fetchLyrics] call
  /// performs a fresh network request. Called by the retry button.
  static Future<void> evict(Track track) async {
    _memoryCache.remove(track.id);
    // Also wipe any sidecar / app-dir cache file so the local-file check
    // in step 1 doesn't return stale data.
    try {
      final sidecar =
          File(track.filePath.replaceAll(RegExp(r'\.[^.]+$'), '.lrc'));
      if (sidecar.existsSync()) await sidecar.delete();
    } catch (_) {}
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final cached = File(
          '${appDir.path}/MusicPlayer/Lyrics/${track.id}.lrc');
      if (cached.existsSync()) await cached.delete();
    } catch (_) {}
  }

  // ── Local cache ──────────────────────────────────────────────────────────────

  static Future<void> _cacheLocally(Track track, String lrcContent) async {
    try {
      final sidecar =
          File(track.filePath.replaceAll(RegExp(r'\.[^.]+$'), '.lrc'));
      await sidecar.writeAsString(lrcContent);
    } catch (_) {
      try {
        final appDir = await getApplicationDocumentsDirectory();
        final dir    = Directory('${appDir.path}/MusicPlayer/Lyrics');
        if (!dir.existsSync()) dir.createSync(recursive: true);
        await File('${dir.path}/${track.id}.lrc').writeAsString(lrcContent);
      } catch (_) {}
    }
  }
}
