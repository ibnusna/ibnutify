class PlaylistModel {
  String id;
  String name;
  String? description;
  List<int> songIds; // list of on_audio_query song IDs
  bool isCustom; // user-created vs auto-playlist
  int createdAt;

  // Cover Generator Template Fields
  String? coverTemplateType; // 'minimal', 'dailymix', 'collage'
  String? coverColor; // Hex or gradient preset ID
  String? coverIcon; // Vector icon key/identifier
  String? coverTitle; // Custom text overlay for cover

  PlaylistModel({
    required this.id,
    required this.name,
    this.description,
    required this.songIds,
    required this.isCustom,
    required this.createdAt,
    this.coverTemplateType,
    this.coverColor,
    this.coverIcon,
    this.coverTitle,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'isCustom': isCustom ? 1 : 0,
      'createdAt': createdAt,
      'coverTemplateType': coverTemplateType,
      'coverColor': coverColor,
      'coverIcon': coverIcon,
      'coverTitle': coverTitle,
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
      coverTemplateType: map['coverTemplateType'] as String?,
      coverColor: map['coverColor'] as String?,
      coverIcon: map['coverIcon'] as String?,
      coverTitle: map['coverTitle'] as String?,
    );
  }

  PlaylistModel copyWith({
    String? id,
    String? name,
    String? description,
    List<int>? songIds,
    bool? isCustom,
    int? createdAt,
    String? coverTemplateType,
    String? coverColor,
    String? coverIcon,
    String? coverTitle,
  }) {
    return PlaylistModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      songIds: songIds ?? List.from(this.songIds),
      isCustom: isCustom ?? this.isCustom,
      createdAt: createdAt ?? this.createdAt,
      coverTemplateType: coverTemplateType ?? this.coverTemplateType,
      coverColor: coverColor ?? this.coverColor,
      coverIcon: coverIcon ?? this.coverIcon,
      coverTitle: coverTitle ?? this.coverTitle,
    );
  }
}
