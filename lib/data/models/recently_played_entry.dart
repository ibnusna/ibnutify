class PlayLogEntry {
  int? id;
  int songId;
  int timestamp;
  int durationPlayed;

  PlayLogEntry({
    this.id,
    required this.songId,
    required this.timestamp,
    required this.durationPlayed,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'song_id': songId,
      'timestamp': timestamp,
      'duration_played': durationPlayed,
    };
  }

  factory PlayLogEntry.fromMap(Map<String, dynamic> map) {
    return PlayLogEntry(
      id: map['id'],
      songId: map['song_id'],
      timestamp: map['timestamp'],
      durationPlayed: map['duration_played'],
    );
  }
}
