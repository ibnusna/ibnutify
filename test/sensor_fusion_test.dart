import 'package:flutter_test/flutter_test.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:ibnutify/services/sensor_fusion_engine.dart';
import 'package:ibnutify/services/location_service.dart';

void main() {
  group('StepDetector Tests', () {
    late StepDetector detector;

    setUp(() {
      detector = StepDetector();
      detector.configureSportMode('Berlari');
    });

    test('Micro-jitter/noise does NOT trigger step counter', () {
      // Simulate rapid 60Hz hand jitter around zero/low magnitude
      for (int i = 0; i < 100; i++) {
        // High frequency oscillation between 0.2 and 0.8 m/s^2
        final val = (i % 2 == 0) ? 0.8 : 0.2;
        detector.process(AccelerometerEvent(val, val, 9.8 + val, DateTime.now()));
      }
      expect(detector.stepCount, equals(0),
          reason: 'Sub-threshold micro-vibrations must not increment step count');
    });

    test('Single footfall peak does NOT multi-trigger within 240ms debounce', () {
      final now = DateTime.now();
      // Establish baseline gravity
      for (int i = 0; i < 20; i++) {
        detector.process(AccelerometerEvent(0, 0, 9.8, now));
      }

      // Simulate a footstep peak: ascending to 4.0 m/s^2
      detector.process(AccelerometerEvent(2.0, 2.0, 9.8 + 3.0, now));
      detector.process(AccelerometerEvent(2.5, 2.5, 9.8 + 4.0, now));
      // Peak turning point
      final stepDetected = detector.process(AccelerometerEvent(1.0, 1.0, 9.8 + 2.0, now));

      expect(stepDetected, isTrue);
      expect(detector.stepCount, equals(1));

      // Attempt immediate subsequent triggers at 10ms, 50ms, 100ms (within 240ms debounce)
      for (int i = 0; i < 10; i++) {
        final reTrigger = detector.process(
          AccelerometerEvent(2.5, 2.5, 9.8 + 4.0, now.add(Duration(milliseconds: i * 15))),
        );
        expect(reTrigger, isFalse,
            reason: 'Must not trigger again during refractory debounce window');
      }
      expect(detector.stepCount, equals(1));
    });
  });

  group('LocationService Haversine Distance Tests', () {
    test('Calculates distance accurately', () {
      // Distance between Jakarta (-6.2088, 106.8456) and Bandung (-6.9175, 107.6191) is ~120-150 km
      final dist = LocationService.haversineDistance(
        -6.2088, 106.8456,
        -6.9175, 107.6191,
      );
      expect(dist, greaterThan(110.0));
      expect(dist, lessThan(160.0));
    });

    test('Zero distance for identical coordinates', () {
      final dist = LocationService.haversineDistance(
        -6.2088, 106.8456,
        -6.2088, 106.8456,
      );
      expect(dist, equals(0.0));
    });
  });
}
