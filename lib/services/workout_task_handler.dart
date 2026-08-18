import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';

/// Entry point untuk task isolate yang dijalankan oleh Android Foreground Service.
/// WAJIB top-level function (bukan method class) dan annotasi @pragma.
@pragma('vm:entry-point')
void workoutTaskEntryPoint() {
  FlutterForegroundTask.setTaskHandler(WorkoutTaskHandler());
}

/// WorkoutTaskHandler — berjalan di isolate terpisah, dilindungi Android Foreground Service.
///
/// Tanggung jawab:
/// - Menjalankan `Timer.periodic` (1 detik) untuk increment elapsed time
/// - Melisten GPS stream via Geolocator
/// - Kirim state update ke main isolate setiap detik via `FlutterForegroundTask.sendDataToMain`
/// - Update notification text secara realtime (waktu + jarak)
/// - Terima command pause/resume/stop dari main isolate via `onReceiveData`
class WorkoutTaskHandler extends TaskHandler {
  // ── Internal state ─────────────────────────────────────────────────────────
  bool _isPaused = false;
  int _elapsedSeconds = 0;
  double _distanceKm = 0;
  double _currentSpeedMs = 0;
  double _gpsAccuracy = 0;
  String _sportMode = '';

  // Route points sebagai List<Map> untuk serialisasi
  final List<Map<String, double>> _routePoints = [];

  // GPS tracking
  StreamSubscription<Position>? _gpsSub;
  _LatLng? _lastPoint;

  // Timer
  Timer? _timer;

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // Baca initial data yang dikirim dari main isolate saat startService
    _sportMode = (await FlutterForegroundTask.getData<String>(key: 'sportMode')) ?? '';
    _elapsedSeconds = (await FlutterForegroundTask.getData<int>(key: 'elapsedSeconds')) ?? 0;
    _distanceKm = (await FlutterForegroundTask.getData<double>(key: 'distanceKm')) ?? 0.0;
    _isPaused = (await FlutterForegroundTask.getData<bool>(key: 'isPaused')) ?? false;

    // Restore route points jika ada
    final routeJson = await FlutterForegroundTask.getData<String>(key: 'routePoints');
    if (routeJson != null && routeJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(routeJson) as List;
        for (final pt in decoded) {
          if (pt is Map) {
            final lat = (pt['lat'] as num?)?.toDouble();
            final lng = (pt['lng'] as num?)?.toDouble();
            if (lat != null && lng != null) {
              _routePoints.add({'lat': lat, 'lng': lng});
            }
          }
        }
        if (_routePoints.isNotEmpty) {
          final last = _routePoints.last;
          _lastPoint = _LatLng(last['lat']!, last['lng']!);
        }
      } catch (_) {}
    }

    // Mulai GPS stream
    _startGps();

    // Timer dikelola oleh onRepeatEvent (dipanggil setiap 1 detik oleh framework)
    // Tidak perlu Timer.periodic manual di sini.
  }

  /// Dipanggil setiap 1 detik oleh flutter_foreground_task framework.
  /// Ini yang menggantikan Timer.periodic di main isolate.
  @override
  void onRepeatEvent(DateTime timestamp) {
    if (!_isPaused) {
      _elapsedSeconds++;
    }

    // Kirim state update ke main isolate
    _sendStateToMain();

    // Update notification text setiap detik
    FlutterForegroundTask.updateService(
      notificationTitle: _notifTitle,
      notificationText: _notifText,
    );
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _gpsSub?.cancel();
    _timer?.cancel();
    // Kirim snapshot final sebelum destroy
    _sendStateToMain(isFinal: true);
  }

  /// Terima command dari main isolate (WorkoutNotifier).
  @override
  void onReceiveData(Object data) {
    if (data is! Map) return;
    final cmd = data['cmd'] as String?;
    switch (cmd) {
      case 'pause':
        _isPaused = true;
        FlutterForegroundTask.updateService(
          notificationTitle: _notifTitle,
          notificationText: 'Dijeda — ${_formatDuration(_elapsedSeconds)}',
        );
        break;
      case 'resume':
        _isPaused = false;
        break;
      case 'stop':
        // Main isolate minta stop — kirim final state lalu service akan di-stop dari main
        _sendStateToMain(isFinal: true);
        break;
    }
  }

  // ── GPS ─────────────────────────────────────────────────────────────────────

  void _startGps() {
    _gpsSub?.cancel();
    _gpsSub = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0, // Update setiap posisi baru tanpa filter jarak
        intervalDuration: const Duration(seconds: 2),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'IbnuTify Workout',
          notificationText: 'GPS aktif di latar belakang',
        ),
      ),
    ).listen(_onPosition);
  }

  void _onPosition(Position pos) {
    final accuracy = pos.accuracy;
    final speedMs = pos.speed < 0 ? 0.0 : pos.speed;

    _currentSpeedMs = speedMs;
    _gpsAccuracy = accuracy;

    // Skip distance update saat paused
    if (_isPaused) return;

    // Skip posisi akurasi sangat buruk (> 50m)
    if (accuracy > 50.0) return;

    final newPoint = _LatLng(pos.latitude, pos.longitude);

    if (_lastPoint != null) {
      final rawKm = _haversine(
        _lastPoint!.lat, _lastPoint!.lng,
        newPoint.lat, newPoint.lng,
      );
      // Tambah jarak jika > 1.5m (anti-jitter) dan < 500m (anti-teleport)
      if (rawKm >= 0.0015 && rawKm < 0.5) {
        _distanceKm += rawKm;
        _lastPoint = newPoint;
        _routePoints.add({'lat': newPoint.lat, 'lng': newPoint.lng});
      }
    } else {
      _lastPoint = newPoint;
      _routePoints.add({'lat': newPoint.lat, 'lng': newPoint.lng});
    }
  }

  // ── State Communication ──────────────────────────────────────────────────────

  void _sendStateToMain({bool isFinal = false}) {
    FlutterForegroundTask.sendDataToMain({
      'type': 'workoutUpdate',
      'isFinal': isFinal,
      'elapsedSeconds': _elapsedSeconds,
      'distanceKm': _distanceKm,
      'currentSpeedMs': _currentSpeedMs,
      'gpsAccuracy': _gpsAccuracy,
      'isPaused': _isPaused,
      // Kirim route points — hanya kirim titik terakhir untuk efisiensi bandwidth
      // Main isolate track sendiri full route; kita sync hanya delta
      'lastLat': _routePoints.isNotEmpty ? _routePoints.last['lat'] : null,
      'lastLng': _routePoints.isNotEmpty ? _routePoints.last['lng'] : null,
      'routeLength': _routePoints.length,
      // Kirim full route hanya saat final (untuk save ke DB)
      if (isFinal) 'routePoints': jsonEncode(_routePoints),
    });
  }

  // ── Notification helpers ─────────────────────────────────────────────────────

  String get _notifTitle {
    final icon = _sportIcon(_sportMode);
    return '$icon $_sportMode';
  }

  String get _notifText {
    final time = _formatDuration(_elapsedSeconds);
    final dist = _distanceKm.toStringAsFixed(2);
    return '$time • ${dist}km${_isPaused ? ' • Dijeda' : ''}';
  }

  static String _sportIcon(String mode) {
    switch (mode) {
      case 'Berlari':
        return '🏃';
      case 'Sepeda':
        return '🚴';
      case 'Berjalan':
        return '🚶';
      case 'Mendaki':
        return '🧗';
      default:
        return '💪';
    }
  }

  static String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '${h}j ${m.toString().padLeft(2, '0')}m';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // ── Haversine ────────────────────────────────────────────────────────────────

  static double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0; // Earth radius km
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  static double _toRad(double deg) => deg * math.pi / 180;
}

/// Minimal lat/lng pair untuk dipakai di dalam task isolate.
class _LatLng {
  final double lat, lng;
  const _LatLng(this.lat, this.lng);
}
