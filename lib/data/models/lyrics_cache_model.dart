class LyricsCacheModel {
  int songId;
  String title;
  String artist;
  String lyrics;
  String source;
  int createdAt;

  LyricsCacheModel({
    required this.songId,
    required this.title,
    required this.artist,
    required this.lyrics,
    required this.source,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'songId': songId,
      'title': title,
      'artist': artist,
      'lyrics': lyrics,
      'source': source,
      'createdAt': createdAt,
    };
  }

  factory LyricsCacheModel.fromMap(Map<String, dynamic> map) {
    return LyricsCacheModel(
      songId: map['songId'],
      title: map['title'],
      artist: map['artist'],
      lyrics: map['lyrics'],
      source: map['source'],
      createdAt: map['createdAt'],
    );
  }
}
