import 'dart:async';
import 'dart:math' as math;
import 'package:geolocator/geolocator.dart';

/// Service untuk GPS tracking offline — digunakan oleh WorkoutNotifier.
/// Semua kalkulasi jarak menggunakan Haversine formula (no internet).
class LocationService {
  static final LocationService instance = LocationService._();
  LocationService._();

  StreamSubscription<Position>? _subscription;

  // ─── Permission ────────────────────────────────────────────────────────────

  /// Meminta permission GPS. Returns true jika granted.
  Future<bool> requestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }
    if (permission == LocationPermission.deniedForever) return false;
    return true;
  }

  // ─── Streaming ─────────────────────────────────────────────────────────────

  /// Mulai stream posisi GPS. Callback [onPosition] dipanggil tiap update.
  /// Filter: distanceFilter 5m, interval 3 detik.
  StreamSubscription<Position> startTracking({
    required void Function(Position position) onPosition,
  }) {
    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5, // minimum 5 meter movement sebelum update
    );
    _subscription = Geolocator.getPositionStream(locationSettings: settings)
        .listen(onPosition);
    return _subscription!;
  }

  /// Stop GPS tracking stream.
  Future<void> stopTracking() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  // ─── Haversine Formula ──────────────────────────────────────────────────────

  /// Menghitung jarak antara dua titik koordinat dalam KM.
  /// Formula: Haversine (100% offline, pure math).
  static double haversineDistance(
    double lat1, double lon1,
    double lat2, double lon2,
  ) {
    const double earthRadius = 6371.0; // km
    final double dLat = _toRad(lat2 - lat1);
    final double dLon = _toRad(lon2 - lon1);
    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  static double _toRad(double deg) => deg * math.pi / 180;
}
