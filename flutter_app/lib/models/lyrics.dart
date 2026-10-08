class LyricWord {
  final int startMs;
  final int endMs;
  final String word;

  const LyricWord({
    required this.startMs,
    required this.endMs,
    required this.word,
  });

  factory LyricWord.fromJson(Map<String, dynamic> json) {
    return LyricWord(
      startMs: (json['start_ms'] as num).toInt(),
      endMs: (json['end_ms'] as num).toInt(),
      word: json['word'] as String,
    );
  }
}

class LyricLine {
  final int startMs;
  final int? endMs;
  final String text;
  final List<LyricWord> words;

  const LyricLine({
    required this.startMs,
    this.endMs,
    required this.text,
    this.words = const [],
  });

  factory LyricLine.fromJson(Map<String, dynamic> json) {
    return LyricLine(
      startMs: (json['start_ms'] as num).toInt(),
      endMs: (json['end_ms'] as num?)?.toInt(),
      text: json['text'] as String,
      words: (json['words'] as List<dynamic>?)
              ?.map((w) => LyricWord.fromJson(w as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class SyncedLyrics {
  final String trackId;
  final bool isSynchronized;
  final bool isWordSynced;
  final int offsetMs;
  final List<LyricLine> lines;

  const SyncedLyrics({
    this.trackId = '',
    this.isSynchronized = false,
    this.isWordSynced = false,
    this.offsetMs = 0,
    this.lines = const [],
  });

  factory SyncedLyrics.fromJson(Map<String, dynamic> json) {
    return SyncedLyrics(
      trackId: json['track_id'] as String? ?? '',
      isSynchronized: json['is_synchronized'] as bool? ?? false,
      isWordSynced: json['is_word_synced'] as bool? ?? false,
      offsetMs: (json['offset_ms'] as num?)?.toInt() ?? 0,
      lines: (json['lines'] as List<dynamic>?)
              ?.map((l) => LyricLine.fromJson(l as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class LyricsSyncState {
  final String trackId;
  final int? activeLineIndex;
  final int? activeWordIndex;
  final double lineProgress;
  final String? activeLineText;
  final String? previousLineText;
  final String? nextLineText;

  const LyricsSyncState({
    this.trackId = '',
    this.activeLineIndex,
    this.activeWordIndex,
    this.lineProgress = 0.0,
    this.activeLineText,
    this.previousLineText,
    this.nextLineText,
  });

  factory LyricsSyncState.fromJson(Map<String, dynamic> json) {
    return LyricsSyncState(
      trackId: (json['track_id'] as String?) ?? '',
      activeLineIndex: json['active_line_index'] as int?,
      activeWordIndex: json['active_word_index'] as int?,
      lineProgress: (json['line_progress'] as num?)?.toDouble() ?? 0.0,
      activeLineText: json['active_line_text'] as String?,
      previousLineText: json['previous_line_text'] as String?,
      nextLineText: json['next_line_text'] as String?,
    );
  }
}
