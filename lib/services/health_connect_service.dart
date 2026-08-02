import 'package:health/health.dart';
import '../data/models/activity_model.dart';

/// Service untuk integrasi Android Health Connect.
/// Menulis sesi olahraga ke Health Connect setelah workout selesai.
class HealthConnectService {
  static final HealthConnectService instance = HealthConnectService._();
  HealthConnectService._();

  final Health _health = Health();

  // Data types yang dibutuhkan
  static const _writeTypes = [
    HealthDataType.WORKOUT,
    HealthDataType.DISTANCE_DELTA,
    HealthDataType.ACTIVE_ENERGY_BURNED,
  ];

  /// Minta permission Health Connect. Returns true jika granted.
  Future<bool> requestPermission() async {
    try {
      await _health.configure();
      final perms = _writeTypes.map((_) => HealthDataAccess.READ_WRITE).toList();
      final granted = await _health.requestAuthorization(
        _writeTypes,
        permissions: perms,
      );
      return granted;
    } catch (e) {
      return false;
    }
  }

  /// Tulis sesi olahraga ke Health Connect.
  /// Dipanggil setelah [saveActivity] berhasil.
  Future<bool> writeWorkout(ActivityModel activity) async {
    try {
      await _health.configure();

      final start = DateTime.parse(activity.createdAt);
      final end = start.add(Duration(seconds: activity.duration));

      // Mapping sport mode ke HealthWorkoutActivityType
      final workoutType = _mapSportMode(activity.sportMode);

      // Tulis sesi olahraga
      final workoutOk = await _health.writeWorkoutData(
        activityType: workoutType,
        start: start,
        end: end,
        totalDistance: (activity.distance * 1000).round(), // km → meter
        totalEnergyBurned: _estimateCalories(activity).round(),
      );

      // Tulis jarak sebagai DISTANCE_DELTA
      if (activity.distance > 0) {
        await _health.writeHealthData(
          value: activity.distance * 1000, // km → meter
          type: HealthDataType.DISTANCE_DELTA,
          startTime: start,
          endTime: end,
        );
      }

      return workoutOk;
    } catch (e) {
      // Health Connect tidak tersedia atau permission ditolak — silent fail
      return false;
    }
  }

  /// Estimasi kalori terbakar (METs formula)
  double _estimateCalories(ActivityModel activity) {
    // Asumsi berat badan 70kg. MET values:
    // Berlari ~8 MET, Bersepeda ~6 MET, Berjalan ~3.5 MET, Mendaki ~5 MET
    const weight = 70.0;
    double met;
    switch (activity.sportMode) {
      case 'Berlari':
        met = 8.0;
        break;
      case 'Sepeda':
        met = 6.0;
        break;
      case 'Berjalan':
        met = 3.5;
        break;
      case 'Mendaki':
        met = 5.0;
        break;
      default:
        met = 5.0;
    }
    final hours = activity.duration / 3600.0;
    return met * weight * hours;
  }

  HealthWorkoutActivityType _mapSportMode(String mode) {
    switch (mode) {
      case 'Berlari':
        return HealthWorkoutActivityType.RUNNING;
      case 'Sepeda':
        return HealthWorkoutActivityType.BIKING;
      case 'Berjalan':
        return HealthWorkoutActivityType.WALKING;
      case 'Mendaki':
        return HealthWorkoutActivityType.HIKING;
      default:
        return HealthWorkoutActivityType.OTHER;
    }
  }
}
