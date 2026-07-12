class PlaylistModel {
  String id;
  String name;
  String? description;
  List<int> songIds; // list of on_audio_query song IDs
  bool isCustom; // user-created vs auto-playlist
  int createdAt;

  PlaylistModel({
    required this.id,
    required this.name,
    this.description,
    required this.songIds,
    required this.isCustom,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'isCustom': isCustom ? 1 : 0,
      'createdAt': createdAt,
    };
  }

  factory PlaylistModel.fromMap(Map<String, dynamic> map, {List<int> songIds = const []}) {
    return PlaylistModel(
      id: map['id'],
      name: map['name'],
      description: map['description'],
      isCustom: (map['isCustom'] ?? 1) == 1,
      createdAt: map['createdAt'] ?? 0,
      songIds: songIds,
    );
  }

  PlaylistModel copyWith({
    String? id,
    String? name,
    String? description,
    List<int>? songIds,
    bool? isCustom,
    int? createdAt,
  }) {
    return PlaylistModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      songIds: songIds ?? List.from(this.songIds),
      isCustom: isCustom ?? this.isCustom,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
