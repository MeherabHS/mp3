class Track {
  final String id;
  final String filePath;
  final String title;
  final String artist;
  final String album;
  final String? albumArtist;
  final String? genre;
  final int? year;
  final int? trackNumber;
  final int? discNumber;
  final int durationMs;
  final String codec;
  final String container;
  final int? bitrateKbps;
  final int? sampleRateHz;
  final int? bitDepth;
  final int? channels;
  final bool lossless;
  final String? artworkPath;
  final String? lyricsPath;
  final bool isFavorite;
  final int playCount;
  final int? lastPlayedAt;
  final int createdAt;

  const Track({
    required this.id,
    required this.filePath,
    required this.title,
    required this.artist,
    required this.album,
    this.albumArtist,
    this.genre,
    this.year,
    this.trackNumber,
    this.discNumber,
    required this.durationMs,
    required this.codec,
    required this.container,
    this.bitrateKbps,
    this.sampleRateHz,
    this.bitDepth,
    this.channels,
    this.lossless = false,
    this.artworkPath,
    this.lyricsPath,
    this.isFavorite = false,
    this.playCount = 0,
    this.lastPlayedAt,
    required this.createdAt,
  });

  factory Track.fromJson(Map<String, dynamic> json) {
    return Track(
      id: json['id'] as String,
      filePath: json['file_path'] as String,
      title: json['title'] as String,
      artist: json['artist'] as String,
      album: json['album'] as String,
      albumArtist: json['album_artist'] as String?,
      genre: json['genre'] as String?,
      year: json['year'] as int?,
      trackNumber: json['track_number'] as int?,
      discNumber: json['disc_number'] as int?,
      durationMs: (json['duration_ms'] as num).toInt(),
      codec: json['codec'] as String,
      container: json['container'] as String,
      bitrateKbps: json['bitrate_kbps'] as int?,
      sampleRateHz: json['sample_rate_hz'] as int?,
      bitDepth: json['bit_depth'] as int?,
      channels: json['channels'] as int?,
      lossless: json['lossless'] as bool? ?? false,
      artworkPath: json['artwork_path'] as String?,
      lyricsPath: json['lyrics_path'] as String?,
      isFavorite: json['is_favorite'] as bool? ?? false,
      playCount: (json['play_count'] as num?)?.toInt() ?? 0,
      lastPlayedAt: json['last_played_at'] as int?,
      createdAt: (json['created_at'] as num).toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'file_path': filePath,
      'title': title,
      'artist': artist,
      'album': album,
      'album_artist': albumArtist,
      'genre': genre,
      'year': year,
      'track_number': trackNumber,
      'disc_number': discNumber,
      'duration_ms': durationMs,
      'codec': codec,
      'container': container,
      'bitrate_kbps': bitrateKbps,
      'sample_rate_hz': sampleRateHz,
      'bit_depth': bitDepth,
      'channels': channels,
      'lossless': lossless,
      'artwork_path': artworkPath,
      'lyrics_path': lyricsPath,
      'is_favorite': isFavorite,
      'play_count': playCount,
      'last_played_at': lastPlayedAt,
      'created_at': createdAt,
    };
  }

  String get formattedDuration {
    final totalSec = durationMs ~/ 1000;
    final min = totalSec ~/ 60;
    final sec = totalSec % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }

  String get hiFiBadgeText {
    final bits = bitDepth != null ? '$bitDepth-bit' : '';
    final rate = sampleRateHz != null ? '${sampleRateHz! ~/ 1000} kHz' : '';
    if (bits.isNotEmpty && rate.isNotEmpty) {
      return '$codec · $bits · $rate';
    }
    return codec;
  }

  Track copyWith({
    String? id,
    String? filePath,
    String? title,
    String? artist,
    String? album,
    String? albumArtist,
    String? genre,
    int? year,
    int? trackNumber,
    int? discNumber,
    int? durationMs,
    String? codec,
    String? container,
    int? bitrateKbps,
    int? sampleRateHz,
    int? bitDepth,
    int? channels,
    bool? lossless,
    String? artworkPath,
    String? lyricsPath,
    bool? isFavorite,
    int? playCount,
    int? lastPlayedAt,
    int? createdAt,
  }) {
    return Track(
      id: id ?? this.id,
      filePath: filePath ?? this.filePath,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      albumArtist: albumArtist ?? this.albumArtist,
      genre: genre ?? this.genre,
      year: year ?? this.year,
      trackNumber: trackNumber ?? this.trackNumber,
      discNumber: discNumber ?? this.discNumber,
      durationMs: durationMs ?? this.durationMs,
      codec: codec ?? this.codec,
      container: container ?? this.container,
      bitrateKbps: bitrateKbps ?? this.bitrateKbps,
      sampleRateHz: sampleRateHz ?? this.sampleRateHz,
      bitDepth: bitDepth ?? this.bitDepth,
      channels: channels ?? this.channels,
      lossless: lossless ?? this.lossless,
      artworkPath: artworkPath ?? this.artworkPath,
      lyricsPath: lyricsPath ?? this.lyricsPath,
      isFavorite: isFavorite ?? this.isFavorite,
      playCount: playCount ?? this.playCount,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class Album {
  final String id;
  final String title;
  final String artist;
  final String? artworkPath;
  final int? year;
  final int trackCount;

  const Album({
    required this.id,
    required this.title,
    required this.artist,
    this.artworkPath,
    this.year,
    required this.trackCount,
  });

  factory Album.fromJson(Map<String, dynamic> json) {
    return Album(
      id: json['id'] as String,
      title: json['title'] as String,
      artist: json['artist'] as String,
      artworkPath: json['artwork_path'] as String?,
      year: json['year'] as int?,
      trackCount: (json['track_count'] as num).toInt(),
    );
  }
}

class Artist {
  final String id;
  final String name;
  final int albumCount;
  final int trackCount;

  const Artist({
    required this.id,
    required this.name,
    required this.albumCount,
    required this.trackCount,
  });

  factory Artist.fromJson(Map<String, dynamic> json) {
    return Artist(
      id: json['id'] as String,
      name: json['name'] as String,
      albumCount: (json['album_count'] as num).toInt(),
      trackCount: (json['track_count'] as num).toInt(),
    );
  }
}

class Playlist {
  final String id;
  final String name;
  final int trackCount;
  final int createdAt;

  const Playlist({
    required this.id,
    required this.name,
    required this.trackCount,
    required this.createdAt,
  });

  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id'] as String,
      name: json['name'] as String,
      trackCount: (json['track_count'] as num).toInt(),
      createdAt: (json['created_at'] as num).toInt(),
    );
  }
}
