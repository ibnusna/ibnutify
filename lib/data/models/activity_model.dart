import 'dart:convert';

/// Model untuk tabel activities (Workout Mode)
class ActivityModel {
  final int? id;
  final String sportMode;   // 'Berlari', 'Sepeda', 'Berjalan', 'Mendaki'
  final int duration;       // detik
  final double distance;    // KM
  final String routePoints; // JSON: [{"lat":.,"lng":..}]
  final String createdAt;   // ISO8601

  // ── Sensor Fusion Fields (DB version 7) ──
  final int stepCount;
  final double elevationGainM;
  final double estimatedCalories;
  final int avgHeartRateBpm;

  const ActivityModel({
    this.id,
    required this.sportMode,
    required this.duration,
    required this.distance,
    required this.routePoints,
    required this.createdAt,
    this.stepCount = 0,
    this.elevationGainM = 0.0,
    this.estimatedCalories = 0.0,
    this.avgHeartRateBpm = 0,
  });

  /// Pace rata-rata dalam format "MM'SS\"/km"
  String get avgPace {
    if (distance <= 0) return '--\'--"/km';
    final secondsPerKm = (duration / distance).round();
    final mins = secondsPerKm ~/ 60;
    final secs = secondsPerKm % 60;
    return "$mins'${secs.toString().padLeft(2, '0')}\"/km";
  }

  /// Durasi dalam format HH:MM:SS
  String get formattedDuration {
    final h = duration ~/ 3600;
    final m = (duration % 3600) ~/ 60;
    final s = duration % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// Jarak dengan 2 desimal
  String get formattedDistance => '${distance.toStringAsFixed(2)} KM';

  /// Parse routePoints ke list of LatLng-like maps
  List<Map<String, double>> get parsedRoutePoints {
    try {
      final decoded = jsonDecode(routePoints) as List;
      return decoded.map((e) => {
        'lat': (e['lat'] as num).toDouble(),
        'lng': (e['lng'] as num).toDouble(),
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'sport_mode': sportMode,
    'duration': duration,
    'distance': distance,
    'route_points': routePoints,
    'created_at': createdAt,
    'step_count': stepCount,
    'elevation_gain_m': elevationGainM,
    'estimated_calories': estimatedCalories,
    'avg_heart_rate_bpm': avgHeartRateBpm,
  };

  factory ActivityModel.fromMap(Map<String, dynamic> map) => ActivityModel(
    id: map['id'] as int?,
    sportMode: map['sport_mode'] as String,
    duration: map['duration'] as int,
    distance: (map['distance'] as num).toDouble(),
    routePoints: map['route_points'] as String,
    createdAt: map['created_at'] as String,
    stepCount: (map['step_count'] as int?) ?? 0,
    elevationGainM: (map['elevation_gain_m'] as num?)?.toDouble() ?? 0.0,
    estimatedCalories: (map['estimated_calories'] as num?)?.toDouble() ?? 0.0,
    avgHeartRateBpm: (map['avg_heart_rate_bpm'] as int?) ?? 0,
  );

  ActivityModel copyWith({
    int? id,
    String? sportMode,
    int? duration,
    double? distance,
    String? routePoints,
    String? createdAt,
    int? stepCount,
    double? elevationGainM,
    double? estimatedCalories,
    int? avgHeartRateBpm,
  }) => ActivityModel(
    id: id ?? this.id,
    sportMode: sportMode ?? this.sportMode,
    duration: duration ?? this.duration,
    distance: distance ?? this.distance,
    routePoints: routePoints ?? this.routePoints,
    createdAt: createdAt ?? this.createdAt,
    stepCount: stepCount ?? this.stepCount,
    elevationGainM: elevationGainM ?? this.elevationGainM,
    estimatedCalories: estimatedCalories ?? this.estimatedCalories,
    avgHeartRateBpm: avgHeartRateBpm ?? this.avgHeartRateBpm,
  );
}
