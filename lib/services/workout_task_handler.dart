import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart'; // defaultTargetPlatform, debugPrint
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';

import 'sensor_fusion_engine.dart';

/// Entry point untuk task isolate yang dijalankan oleh Android Foreground Service.
/// WAJIB top-level function (bukan method class) dan annotasi @pragma.
@pragma('vm:entry-point')
void workoutTaskEntryPoint() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.setTaskHandler(WorkoutTaskHandler());
}

/// WorkoutTaskHandler — berjalan di isolate terpisah, dilindungi Android Foreground Service.
/// Sekarang mengintegrasikan SensorFusionEngine untuk step count, cadence, dan elevasi.
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

  // ── Sensor Fusion ──────────────────────────────────────────────────────────
  final SensorFusionEngine _sensorFusion = SensorFusionEngine();

  // Heart rate (diterima dari main isolate via BLE)
  int _heartRateBpm = 0;

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    WidgetsFlutterBinding.ensureInitialized();

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

    // Mulai SensorFusionEngine (akselerometer + giroskop)
    _sensorFusion.start(_sportMode);

    // Explicit 1-second Dart Timer untuk menjamin kelancaran penambahan durasi
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
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
    });

    // Mulai GPS stream
    _startGps();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Timer.periodic di onStart menangani update 1 detik secara presisi
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _gpsSub?.cancel();
    _timer?.cancel();
    _sensorFusion.stop();
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
        _sendStateToMain();
        break;
      case 'resume':
        _isPaused = false;
        _sendStateToMain();
        break;
      case 'stop':
        _sendStateToMain(isFinal: true);
        break;
      case 'heartRate':
        // Update HR dari main isolate (diterima dari BLE WatchService)
        final bpm = data['bpm'];
        if (bpm is int) _heartRateBpm = bpm;
        break;
    }
  }

  // ── GPS ─────────────────────────────────────────────────────────────────────

  void _startGps() {
    _gpsSub?.cancel();
    try {
      // [FIX-BUG-TRK-001-H1] Gunakan AndroidSettings agar Android tahu GPS
      // diminta dari Foreground Service. intervalDuration 1s memaksa update reguler,
      // enableWakeLock mencegah CPU sleep saat layar mati (kritis untuk Samsung OneUI).
      final settings = defaultTargetPlatform == TargetPlatform.android
          ? AndroidSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 0,
              intervalDuration: const Duration(seconds: 1),
              foregroundNotificationConfig: const ForegroundNotificationConfig(
                notificationText: 'GPS tracking aktif',
                notificationTitle: 'IbnuTify Workout',
                enableWakeLock: true,
              ),
            )
          : const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 0,
            );

      _gpsSub = Geolocator.getPositionStream(
        locationSettings: settings,
      ).listen(_onPosition, onError: (err) {
        debugPrint('[WorkoutTaskHandler] GPS error: $err');
      });
    } catch (_) {}
  }

  void _onPosition(Position pos) {
    final accuracy = pos.accuracy;
    final speedMs = pos.speed < 0 ? 0.0 : pos.speed;

    _currentSpeedMs = speedMs;
    _gpsAccuracy = accuracy;

    // Trigger sensor fusion update dari setiap posisi GPS
    _sensorFusion.updateFromGps(
      altitude: pos.altitude,
      gpsSpeedMs: speedMs,
      isPaused: _isPaused,
      elapsedSeconds: _elapsedSeconds,
      sportMode: _sportMode,
      hrBpm: _heartRateBpm.toDouble(),
    );

    // Skip distance update saat paused
    if (_isPaused) {
      _sendStateToMain();
      return;
    }

    // [FIX-BUG-TRK-001-H5] Longgarkan threshold dari 50m ke 100m.
    // Threshold 50m terlalu ketat: GPS awal sering memiliki akurasi 50-80m (cold start,
    // area padat). Dengan 100m, update GPS tetap masuk meski sinyal belum sempurna.
    // Anti-jitter 1.5m di bawah tetap menjaga kualitas data.
    if (accuracy > 100.0) {
      _sendStateToMain();
      return;
    }

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

    _sendStateToMain();
  }

  // ── State Communication ──────────────────────────────────────────────────────

  void _sendStateToMain({bool isFinal = false}) {
    final fusion = _sensorFusion.snapshot;
    FlutterForegroundTask.sendDataToMain({
      'type': 'workoutUpdate',
      'isFinal': isFinal,
      'elapsedSeconds': _elapsedSeconds,
      'distanceKm': _distanceKm,
      'currentSpeedMs': _currentSpeedMs,
      'gpsAccuracy': _gpsAccuracy,
      'isPaused': _isPaused,
      'lastLat': _routePoints.isNotEmpty ? _routePoints.last['lat'] : null,
      'lastLng': _routePoints.isNotEmpty ? _routePoints.last['lng'] : null,
      'routeLength': _routePoints.length,
      // Sensor fusion data
      'stepCount': fusion.stepCount,
      'cadenceSpm': fusion.cadenceSpm,
      'detectedActivity': fusion.detectedActivity,
      'elevationGainM': fusion.elevationGainM,
      'elevationLossM': fusion.elevationLossM,
      'currentAltitudeM': fusion.currentAltitudeM,
      'estimatedCalories': fusion.estimatedCalories,
      if (isFinal) 'routePoints': jsonEncode(_routePoints),
    });
  }

  // ── Notification helpers ─────────────────────────────────────────────────────

  String get _notifTitle {
    final icon = _sportIcon(_sportMode);
    final hr = _heartRateBpm > 0 ? '  ❤️ ${_heartRateBpm}bpm' : '';
    return '$icon $_sportMode$hr';
  }

  String get _notifText {
    final time = _formatDuration(_elapsedSeconds);
    final dist = _distanceKm.toStringAsFixed(2);
    final steps = _sensorFusion.snapshot.stepCount;
    final stepsStr = steps > 0 && _sportMode != 'Sepeda' ? ' • ${steps}lk' : '';
    return '$time • ${dist}km$stepsStr${_isPaused ? ' • Dijeda' : ''}';
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
