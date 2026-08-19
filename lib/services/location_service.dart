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

  /// Meminta permission GPS termasuk background location (ACCESS_BACKGROUND_LOCATION).
  /// Android mensyaratkan two-step dialog:
  ///   Step 1 → request "while in use" (whileInUse)
  ///   Step 2 → request "always" (background) — hanya bisa setelah step 1 granted.
  /// Returns true jika minimal "while in use" diberikan (app tetap bisa tracking
  /// saat di foreground). Background tracking memerlukan "always" permission.
  Future<bool> requestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();

    // Step 1: Request whileInUse jika belum granted
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }
    if (permission == LocationPermission.deniedForever) return false;

    // Step 2: Request background location ("always") jika masih whileInUse.
    // Ini diperlukan agar GPS tetap aktif saat layar dikunci (Doze Mode).
    // Pada Android 11+ user diarahkan ke Settings untuk pilih "Allow all the time".
    if (permission == LocationPermission.whileInUse) {
      permission = await Geolocator.requestPermission();
      // Jika background ditolak, kita tetap return true agar workout bisa dimulai
      // (tracking akan aktif selama app di foreground, GPS mungkin berhenti saat lock screen).
    }

    return true;
  }

  // ─── Streaming ─────────────────────────────────────────────────────────────

  /// Mulai stream posisi GPS. Callback [onPosition] dipanggil tiap update.
  /// Filter: distanceFilter 1m, interval 1 detik.
  StreamSubscription<Position> startTracking({
    required void Function(Position position) onPosition,
  }) {
    late final LocationSettings settings;
    try {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 1, // Update tiap 1 meter
        intervalDuration: const Duration(seconds: 1), // Update tiap 1 detik
        forceLocationManager: false,
      );
    } catch (_) {
      settings = const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 1,
      );
    }
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
