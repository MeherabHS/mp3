import 'audio_quality.dart';
import 'track.dart';

enum PlaybackState {
  playing,
  paused,
  stopped,
  buffering,
  error;

  static PlaybackState fromString(String? val) {
    switch (val?.toLowerCase()) {
      case 'playing':
        return PlaybackState.playing;
      case 'paused':
        return PlaybackState.paused;
      case 'stopped':
        return PlaybackState.stopped;
      case 'buffering':
        return PlaybackState.buffering;
      default:
        return PlaybackState.stopped;
    }
  }
}

enum RepeatMode {
  off,
  all,
  one;

  static RepeatMode fromString(String? val) {
    switch (val?.toLowerCase()) {
      case 'all':
        return RepeatMode.all;
      case 'one':
        return RepeatMode.one;
      default:
        return RepeatMode.off;
    }
  }
}

class PlayerState {
  final Track? currentTrack;
  final int positionMs;
  final int durationMs;
  final bool isPlaying;
  final PlaybackState playbackState;
  final List<Track> queue;
  final int? queueIndex;
  final bool shuffle;
  final RepeatMode repeatMode;
  final double volume;
  final OutputStatus outputStatus;
  final AudioQuality audioQuality;

  const PlayerState({
    this.currentTrack,
    this.positionMs = 0,
    this.durationMs = 0,
    this.isPlaying = false,
    this.playbackState = PlaybackState.stopped,
    this.queue = const [],
    this.queueIndex,
    this.shuffle = false,
    this.repeatMode = RepeatMode.off,
    this.volume = 1.0,
    this.outputStatus = const OutputStatus(),
    this.audioQuality = const AudioQuality(),
  });

  factory PlayerState.fromJson(Map<String, dynamic> json) {
    return PlayerState(
      currentTrack: json['current_track'] != null
          ? Track.fromJson(json['current_track'] as Map<String, dynamic>)
          : null,
      positionMs: (json['position_ms'] as num?)?.toInt() ?? 0,
      durationMs: (json['duration_ms'] as num?)?.toInt() ?? 0,
      isPlaying: json['is_playing'] as bool? ?? false,
      playbackState: PlaybackState.fromString(json['playback_state'] as String?),
      queue: (json['queue'] as List<dynamic>?)
              ?.map((t) => Track.fromJson(t as Map<String, dynamic>))
              .toList() ??
          [],
      queueIndex: json['queue_index'] as int?,
      shuffle: json['shuffle'] as bool? ?? false,
      repeatMode: RepeatMode.fromString(json['repeat_mode'] as String?),
      volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
      outputStatus: json['output_status'] != null
          ? OutputStatus.fromJson(json['output_status'] as Map<String, dynamic>)
          : const OutputStatus(),
      audioQuality: json['audio_quality'] != null
          ? AudioQuality.fromJson(json['audio_quality'] as Map<String, dynamic>)
          : const AudioQuality(),
    );
  }

  double get progress {
    if (durationMs <= 0) return 0.0;
    return (positionMs / durationMs).clamp(0.0, 1.0);
  }

  String get formattedPosition {
    final totalSec = positionMs ~/ 1000;
    final min = totalSec ~/ 60;
    final sec = totalSec % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }

  String get formattedDuration {
    final totalSec = durationMs ~/ 1000;
    final min = totalSec ~/ 60;
    final sec = totalSec % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }

  PlayerState copyWith({
    Track? currentTrack,
    int? positionMs,
    int? durationMs,
    bool? isPlaying,
    PlaybackState? playbackState,
    List<Track>? queue,
    int? queueIndex,
    bool? shuffle,
    RepeatMode? repeatMode,
    double? volume,
    OutputStatus? outputStatus,
    AudioQuality? audioQuality,
  }) {
    return PlayerState(
      currentTrack: currentTrack ?? this.currentTrack,
      positionMs: positionMs ?? this.positionMs,
      durationMs: durationMs ?? this.durationMs,
      isPlaying: isPlaying ?? this.isPlaying,
      playbackState: playbackState ?? this.playbackState,
      queue: queue ?? this.queue,
      queueIndex: queueIndex ?? this.queueIndex,
      shuffle: shuffle ?? this.shuffle,
      repeatMode: repeatMode ?? this.repeatMode,
      volume: volume ?? this.volume,
      outputStatus: outputStatus ?? this.outputStatus,
      audioQuality: audioQuality ?? this.audioQuality,
    );
  }
}
