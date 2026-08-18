import 'dart:async';
import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart';

// ─── Kalman Filter (Altitude Smoothing) ───────────────────────────────────────

/// Simple 1-D Kalman filter optimized for GPS altitude noise (~3–5 m σ).
class AltitudeKalmanFilter {
  double _estimate = 0;
  double _errorCovariance = 10;
  bool _initialized = false;

  static const double _processNoise = 0.02;
  static const double _measurementNoise = 4.0; // GPS altitude std dev ≈ 4m

  double update(double measurement) {
    if (!_initialized) {
      _estimate = measurement;
      _initialized = true;
      return measurement;
    }
    // Prediction step
    _errorCovariance += _processNoise;
    // Update step
    final gain = _errorCovariance / (_errorCovariance + _measurementNoise);
    _estimate += gain * (measurement - _estimate);
    _errorCovariance *= (1 - gain);
    return _estimate;
  }

  void reset() {
    _estimate = 0;
    _errorCovariance = 10;
    _initialized = false;
  }
}

// ─── Step Detector ────────────────────────────────────────────────────────────

/// Detects footsteps from raw accelerometer data using:
/// 1. Low-pass filter to remove high-frequency noise
/// 2. Magnitude of gravity-removed acceleration
/// 3. Peak detection with adaptive threshold
class StepDetector {
  // Low-pass filter state
  double _filteredX = 0;
  double _filteredY = 0;
  double _filteredZ = 0;
  double _prevMagnitude = 0;
  bool _ascending = false;

  // Step count
  int _stepCount = 0;

  // Sliding window for cadence (last 10 seconds of timestamps)
  final List<int> _stepTimestamps = [];

  // Adaptive threshold (updated per sport mode)
  double _threshold = 11.8;
  bool _enabled = true; // disabled for Sepeda mode

  static const double _alpha = 0.8; // low-pass filter smoothing

  int get stepCount => _stepCount;

  /// Update threshold and enable/disable based on sport mode.
  void configureSportMode(String sportMode) {
    switch (sportMode) {
      case 'Berjalan':
        _threshold = 11.2;
        _enabled = true;
        break;
      case 'Berlari':
        _threshold = 12.2;
        _enabled = true;
        break;
      case 'Mendaki':
        _threshold = 10.8;
        _enabled = true;
        break;
      case 'Sepeda':
        _enabled = false; // cadence pedaling not tracked via accel
        break;
      default:
        _threshold = 11.5;
        _enabled = true;
    }
  }

  /// Process one accelerometer sample.
  /// Returns true if a step was detected.
  bool process(AccelerometerEvent event) {
    if (!_enabled) return false;

    // Low-pass filter (isolate gravity component)
    _filteredX = _alpha * _filteredX + (1 - _alpha) * event.x;
    _filteredY = _alpha * _filteredY + (1 - _alpha) * event.y;
    _filteredZ = _alpha * _filteredZ + (1 - _alpha) * event.z;

    // Magnitude of high-pass component (linear accel = raw - gravity estimate)
    final linX = event.x - _filteredX;
    final linY = event.y - _filteredY;
    final linZ = event.z - _filteredZ;
    final magnitude = math.sqrt(linX * linX + linY * linY + linZ * linZ);

    bool stepDetected = false;

    // Peak detection: detect transition from ascending to descending above threshold
    if (magnitude > _prevMagnitude) {
      _ascending = true;
    } else if (_ascending && _prevMagnitude > _threshold && magnitude < _prevMagnitude) {
      // Local peak above threshold — count as step
      _ascending = false;
      _stepCount++;
      _stepTimestamps.add(DateTime.now().millisecondsSinceEpoch);
      stepDetected = true;
    }

    _prevMagnitude = magnitude;
    return stepDetected;
  }

  /// Returns cadence in steps/minute over the last 10 seconds.
  double getCadenceSpm() {
    if (!_enabled) return 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final windowMs = 10000; // 10 second window
    _stepTimestamps.removeWhere((t) => now - t > windowMs);
    if (_stepTimestamps.isEmpty) return 0;
    // Extrapolate to spm: steps_in_10s / 10 * 60
    return (_stepTimestamps.length / 10.0) * 60;
  }

  void reset() {
    _stepCount = 0;
    _stepTimestamps.clear();
    _filteredX = 0;
    _filteredY = 0;
    _filteredZ = 0;
    _prevMagnitude = 0;
    _ascending = false;
  }
}

// ─── Activity Classifier ──────────────────────────────────────────────────────

/// Activity types recognized by the classifier.
enum DetectedActivity {
  still,
  walking,
  running,
  cycling,
  hiking,
}

extension DetectedActivityLabel on DetectedActivity {
  String get label {
    switch (this) {
      case DetectedActivity.still:
        return 'Diam';
      case DetectedActivity.walking:
        return 'Berjalan';
      case DetectedActivity.running:
        return 'Berlari';
      case DetectedActivity.cycling:
        return 'Sepeda';
      case DetectedActivity.hiking:
        return 'Mendaki';
    }
  }
}

/// Classifies the current activity using a decision tree combining:
/// - GPS speed (m/s)
/// - Step cadence (spm)
/// - Accelerometer variance
/// - Altitude delta rate (m/s)
class ActivityClassifier {
  // Rolling variance of acceleration magnitude (last 50 samples)
  final List<double> _accelWindow = [];
  static const int _windowSize = 50;

  DetectedActivity _currentActivity = DetectedActivity.still;

  // Hysteresis: don't flip modes too fast (require 3s of consistent signal)
  DetectedActivity _pendingActivity = DetectedActivity.still;
  int _pendingCount = 0;
  static const int _hysteresisThreshold = 3; // seconds (since called ~1/s from GPS)

  DetectedActivity get currentActivity => _currentActivity;

  void addAccelSample(double magnitude) {
    _accelWindow.add(magnitude);
    if (_accelWindow.length > _windowSize) _accelWindow.removeAt(0);
  }

  double get _accelVariance {
    if (_accelWindow.isEmpty) return 0;
    final mean = _accelWindow.reduce((a, b) => a + b) / _accelWindow.length;
    final variance = _accelWindow
        .map((v) => (v - mean) * (v - mean))
        .reduce((a, b) => a + b) / _accelWindow.length;
    return variance;
  }

  /// Classify based on current sensor snapshot.
  /// Call this once per second (from GPS update tick).
  DetectedActivity classify({
    required double gpsSpeedMs,
    required double cadenceSpm,
    required double altitudeDeltaMs, // meters per second altitude change
    required String userSelectedMode, // hint from manual selection
  }) {
    DetectedActivity candidate;

    if (gpsSpeedMs < 0.5) {
      candidate = DetectedActivity.still;
    } else if (userSelectedMode == 'Sepeda' || (gpsSpeedMs >= 4.0 && _accelVariance < 0.8)) {
      // Cycling: high speed but smooth (low accel variance)
      candidate = DetectedActivity.cycling;
    } else if (altitudeDeltaMs > 0.08 && gpsSpeedMs < 2.5 && cadenceSpm < 100) {
      // Hiking: significant vertical gain, moderate speed, low cadence
      candidate = DetectedActivity.hiking;
    } else if (gpsSpeedMs < 2.0 || cadenceSpm < 100) {
      candidate = DetectedActivity.walking;
    } else {
      candidate = DetectedActivity.running;
    }

    // Hysteresis: only switch after N consistent readings
    if (candidate == _pendingActivity) {
      _pendingCount++;
      if (_pendingCount >= _hysteresisThreshold) {
        _currentActivity = _pendingActivity;
      }
    } else {
      _pendingActivity = candidate;
      _pendingCount = 1;
    }

    return _currentActivity;
  }

  void reset() {
    _accelWindow.clear();
    _currentActivity = DetectedActivity.still;
    _pendingActivity = DetectedActivity.still;
    _pendingCount = 0;
  }
}

// ─── Elevation Tracker ────────────────────────────────────────────────────────

/// Tracks cumulative elevation gain/loss with Kalman filtering.
/// Min threshold of 0.5m to ignore GPS noise.
class ElevationTracker {
  final AltitudeKalmanFilter _kalman = AltitudeKalmanFilter();
  double? _lastSmoothedAlt;
  double _elevationGainM = 0;
  double _elevationLossM = 0;
  double _currentAltM = 0;

  static const double _minDeltaM = 0.5; // ignore < 0.5m delta (GPS noise)
  static const double _maxDeltaM = 20.0; // ignore > 20m jump (GPS glitch)

  double get elevationGainM => _elevationGainM;
  double get elevationLossM => _elevationLossM;
  double get currentAltitudeM => _currentAltM;

  void update(double rawAltitude) {
    final smoothed = _kalman.update(rawAltitude);
    _currentAltM = smoothed;

    if (_lastSmoothedAlt != null) {
      final delta = smoothed - _lastSmoothedAlt!;
      if (delta.abs() >= _minDeltaM && delta.abs() <= _maxDeltaM) {
        if (delta > 0) {
          _elevationGainM += delta;
        } else {
          _elevationLossM += delta.abs();
        }
        _lastSmoothedAlt = smoothed;
      }
    } else {
      _lastSmoothedAlt = smoothed;
    }
  }

  void reset() {
    _kalman.reset();
    _lastSmoothedAlt = null;
    _elevationGainM = 0;
    _elevationLossM = 0;
    _currentAltM = 0;
  }
}

// ─── Calorie Estimator ────────────────────────────────────────────────────────

/// Estimates calories burned using Keytel Formula (when HR is available)
/// or MET estimation (fallback without HR).
class CalorieEstimator {
  // Default body stats (used when user profile not configured)
  static const double _defaultWeightKg = 70.0;
  static const int _defaultAge = 25;

  /// Keytel Formula (with heart rate).
  /// [hrBpm] - current heart rate
  /// [durationSeconds] - total elapsed seconds
  /// [weightKg] - body weight in kg
  /// [age] - age in years
  /// [isMale] - true for male formula
  static double estimateWithHR({
    required double hrBpm,
    required int durationSeconds,
    double weightKg = _defaultWeightKg,
    int age = _defaultAge,
    bool isMale = true,
  }) {
    if (hrBpm <= 0 || durationSeconds <= 0) return 0;
    final durationMin = durationSeconds / 60.0;
    double calPerMin;
    if (isMale) {
      calPerMin = (-55.0969 + 0.6309 * hrBpm + 0.1988 * weightKg + 0.2017 * age) / 4.184;
    } else {
      calPerMin = (-20.4022 + 0.4472 * hrBpm - 0.1263 * weightKg + 0.074 * age) / 4.184;
    }
    return (calPerMin * durationMin).clamp(0, double.infinity);
  }

  /// MET-based estimation (fallback without heart rate).
  /// MET values: Walking 3.5, Running 8.3, Cycling 7.5, Hiking 6.0
  static double estimateWithMET({
    required String sportMode,
    required int durationSeconds,
    double weightKg = _defaultWeightKg,
  }) {
    if (durationSeconds <= 0) return 0;
    double met;
    switch (sportMode) {
      case 'Berlari':
        met = 8.3;
        break;
      case 'Sepeda':
        met = 7.5;
        break;
      case 'Mendaki':
        met = 6.0;
        break;
      case 'Berjalan':
      default:
        met = 3.5;
    }
    final hours = durationSeconds / 3600.0;
    return met * weightKg * hours;
  }
}

// ─── Heart Rate Zone ──────────────────────────────────────────────────────────

enum HrZone { rest, warmup, fatBurn, cardio, peak }

extension HrZoneLabel on HrZone {
  String get label {
    switch (this) {
      case HrZone.rest:
        return 'Istirahat';
      case HrZone.warmup:
        return 'Pemanasan';
      case HrZone.fatBurn:
        return 'Pembakaran Lemak';
      case HrZone.cardio:
        return 'Kardio';
      case HrZone.peak:
        return 'Puncak';
    }
  }

  /// Color code for UI indicator.
  int get colorValue {
    switch (this) {
      case HrZone.rest:
        return 0xFF78909C;
      case HrZone.warmup:
        return 0xFF42A5F5;
      case HrZone.fatBurn:
        return 0xFF66BB6A;
      case HrZone.cardio:
        return 0xFFFFA726;
      case HrZone.peak:
        return 0xFFEF5350;
    }
  }
}

/// Classify heart rate into training zones.
/// Uses age-predicted max HR: HRmax = 220 - age
HrZone classifyHrZone(int bpm, {int age = 25}) {
  if (bpm <= 0) return HrZone.rest;
  final maxHr = 220 - age;
  final pct = bpm / maxHr;
  if (pct < 0.50) return HrZone.rest;
  if (pct < 0.60) return HrZone.warmup;
  if (pct < 0.70) return HrZone.fatBurn;
  if (pct < 0.85) return HrZone.cardio;
  return HrZone.peak;
}

// ─── Sensor Fusion Engine ─────────────────────────────────────────────────────

/// Snapshot of sensor fusion output — sent every 1s to main isolate.
class SensorFusionSnapshot {
  final int stepCount;
  final double cadenceSpm;
  final String detectedActivity;
  final double elevationGainM;
  final double elevationLossM;
  final double currentAltitudeM;
  final double estimatedCalories;

  const SensorFusionSnapshot({
    this.stepCount = 0,
    this.cadenceSpm = 0,
    this.detectedActivity = 'Diam',
    this.elevationGainM = 0,
    this.elevationLossM = 0,
    this.currentAltitudeM = 0,
    this.estimatedCalories = 0,
  });
}

/// Orchestrates all sensor sub-systems.
/// Subscribes to sensors_plus streams and produces SensorFusionSnapshot.
class SensorFusionEngine {
  final StepDetector _stepDetector = StepDetector();
  final ActivityClassifier _activityClassifier = ActivityClassifier();
  final ElevationTracker _elevationTracker = ElevationTracker();

  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;

  String _sportMode = '';
  double _lastAltitude = 0;
  double _prevAltitude = 0;
  DateTime? _lastAltTime;

  bool _isRunning = false;

  // Public snapshot (updated each second by GPS tick)
  SensorFusionSnapshot _snapshot = const SensorFusionSnapshot();
  SensorFusionSnapshot get snapshot => _snapshot;

  void start(String sportMode) {
    _sportMode = sportMode;
    _isRunning = true;
    _stepDetector.configureSportMode(sportMode);

    // Subscribe to accelerometer at 50Hz (default)
    _accelSub = accelerometerEventStream(
      samplingPeriod: SensorInterval.uiInterval, // ~16ms ≈ 60Hz
    ).listen(_onAccel, onError: (_) {});

    // Gyroscope — currently collected for future use in motion smoothing
    _gyroSub = gyroscopeEventStream(
      samplingPeriod: SensorInterval.uiInterval,
    ).listen(_onGyro, onError: (_) {});
  }

  void stop() {
    _isRunning = false;
    _accelSub?.cancel();
    _gyroSub?.cancel();
    _accelSub = null;
    _gyroSub = null;
    _stepDetector.reset();
    _activityClassifier.reset();
    _elevationTracker.reset();
    _snapshot = const SensorFusionSnapshot();
  }

  void _onAccel(AccelerometerEvent event) {
    if (!_isRunning) return;
    _stepDetector.process(event);
    final magnitude = math.sqrt(
      event.x * event.x + event.y * event.y + event.z * event.z,
    );
    _activityClassifier.addAccelSample(magnitude);
  }

  void _onGyro(GyroscopeEvent event) {
    // Reserved for future orientation-based motion smoothing
  }

  /// Call this every time a GPS position arrives (≈1s).
  /// [altitude] — raw GPS altitude in meters
  /// [gpsSpeedMs] — GPS speed in m/s
  /// [isPaused] — skip counting during pause
  /// [elapsedSeconds] — total elapsed workout seconds
  /// [hrBpm] — current heart rate (0 if unavailable)
  SensorFusionSnapshot updateFromGps({
    required double altitude,
    required double gpsSpeedMs,
    required bool isPaused,
    required int elapsedSeconds,
    required String sportMode,
    double hrBpm = 0,
  }) {
    if (!_isRunning) return _snapshot;

    // Elevation
    _elevationTracker.update(altitude);

    // Altitude delta rate for classifier
    final now = DateTime.now();
    double altDeltaMs = 0;
    if (_lastAltTime != null) {
      final dt = now.difference(_lastAltTime!).inMilliseconds / 1000.0;
      if (dt > 0) {
        altDeltaMs = (altitude - _prevAltitude) / dt;
      }
    }
    _prevAltitude = altitude;
    _lastAltTime = now;
    _lastAltitude = altitude;

    // Activity classification
    final activity = _activityClassifier.classify(
      gpsSpeedMs: isPaused ? 0 : gpsSpeedMs,
      cadenceSpm: _stepDetector.getCadenceSpm(),
      altitudeDeltaMs: altDeltaMs,
      userSelectedMode: sportMode,
    );

    // Calorie estimation
    double calories;
    if (hrBpm > 40) {
      calories = CalorieEstimator.estimateWithHR(
        hrBpm: hrBpm,
        durationSeconds: elapsedSeconds,
      );
    } else {
      calories = CalorieEstimator.estimateWithMET(
        sportMode: sportMode,
        durationSeconds: elapsedSeconds,
      );
    }

    _snapshot = SensorFusionSnapshot(
      stepCount: _stepDetector.stepCount,
      cadenceSpm: _stepDetector.getCadenceSpm(),
      detectedActivity: activity.label,
      elevationGainM: _elevationTracker.elevationGainM,
      elevationLossM: _elevationTracker.elevationLossM,
      currentAltitudeM: _elevationTracker.currentAltitudeM,
      estimatedCalories: calories,
    );

    return _snapshot;
  }

  void reset() {
    _stepDetector.reset();
    _activityClassifier.reset();
    _elevationTracker.reset();
    _snapshot = const SensorFusionSnapshot();
    _lastAltitude = 0;
    _prevAltitude = 0;
    _lastAltTime = null;
  }
}
