class SongModel {
  final int id; // on_audio_query song ID
  String title;
  String artist;
  String album;
  int duration; // milliseconds
  String uri; // file:// URI
  String? albumArtPath; // cached artwork path
  int playCount;
  int? lastPlayedAt; // epoch ms
  int addedAt; // epoch ms
  bool isLiked;
  int listenThroughCount;
  
  // New properties for Smart ML Features
  int? releaseYear;
  int? clusterId;
  int score;
  double? bpm;
  double? brightness;
  double? percussiveness;
  String? youtubeUrl;
  int skipCount;
  int completionCount;

  SongModel({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.uri,
    this.albumArtPath,
    this.playCount = 0,
    this.lastPlayedAt,
    required this.addedAt,
    this.isLiked = false,
    this.listenThroughCount = 0,
    this.releaseYear,
    this.clusterId,
    this.score = 0,
    this.bpm,
    this.brightness,
    this.percussiveness,
    this.youtubeUrl,
    this.skipCount = 0,
    this.completionCount = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'album': album,
      'duration': duration,
      'uri': uri,
      'albumArtPath': albumArtPath,
      'playCount': playCount,
      'lastPlayedAt': lastPlayedAt,
      'addedAt': addedAt,
      'isLiked': isLiked ? 1 : 0,
      'listenThroughCount': listenThroughCount,
      'release_year': releaseYear,
      'cluster_id': clusterId,
      'score': score,
      'bpm': bpm,
      'brightness': brightness,
      'percussiveness': percussiveness,
      'youtube_url': youtubeUrl,
      'skip_count': skipCount,
      'completion_count': completionCount,
    };
  }

  factory SongModel.fromMap(Map<String, dynamic> map) {
    return SongModel(
      id: map['id'],
      title: map['title'],
      artist: map['artist'],
      album: map['album'] ?? 'Unknown Album',
      duration: map['duration'] ?? 0,
      uri: map['uri'],
      albumArtPath: map['albumArtPath'],
      playCount: map['playCount'] ?? 0,
      lastPlayedAt: map['lastPlayedAt'],
      addedAt: map['addedAt'] ?? 0,
      isLiked: (map['isLiked'] ?? 0) == 1,
      listenThroughCount: map['listenThroughCount'] ?? 0,
      releaseYear: map['release_year'],
      clusterId: map['cluster_id'],
      score: map['score'] ?? 0,
      bpm: map['bpm'] != null ? (map['bpm'] as num).toDouble() : null,
      brightness: map['brightness'] != null ? (map['brightness'] as num).toDouble() : null,
      percussiveness: map['percussiveness'] != null ? (map['percussiveness'] as num).toDouble() : null,
      youtubeUrl: map['youtube_url'],
      skipCount: map['skip_count'] ?? 0,
      completionCount: map['completion_count'] ?? 0,
    );
  }

  SongModel copyWith({
    int? id,
    String? title,
    String? artist,
    String? album,
    int? duration,
    String? uri,
    String? albumArtPath,
    int? playCount,
    int? lastPlayedAt,
    int? addedAt,
    bool? isLiked,
    int? listenThroughCount,
    int? releaseYear,
    int? clusterId,
    int? score,
    double? bpm,
    double? brightness,
    double? percussiveness,
    String? youtubeUrl,
    int? skipCount,
    int? completionCount,
  }) {
    return SongModel(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      duration: duration ?? this.duration,
      uri: uri ?? this.uri,
      albumArtPath: albumArtPath ?? this.albumArtPath,
      playCount: playCount ?? this.playCount,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
      addedAt: addedAt ?? this.addedAt,
      isLiked: isLiked ?? this.isLiked,
      listenThroughCount: listenThroughCount ?? this.listenThroughCount,
      releaseYear: releaseYear ?? this.releaseYear,
      clusterId: clusterId ?? this.clusterId,
      score: score ?? this.score,
      bpm: bpm ?? this.bpm,
      brightness: brightness ?? this.brightness,
      percussiveness: percussiveness ?? this.percussiveness,
      youtubeUrl: youtubeUrl ?? this.youtubeUrl,
      skipCount: skipCount ?? this.skipCount,
      completionCount: completionCount ?? this.completionCount,
    );
  }
}
