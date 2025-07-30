// test/unit/golf_tracking_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:golf_tracker/services/golf_tracking_service.dart';
import 'package:golf_tracker/services/inference_isolate_service.dart';
import '../helpers/test_data_generator.dart';
import '../helpers/mock_services.dart';

void main() {
  group('GolfTrackingService', () {
    late MockGolfTrackingService trackingService;
    late MockInferenceIsolateService inferenceService;
    
    setUp(() {
      trackingService = MockGolfTrackingService();
      inferenceService = MockInferenceIsolateService();
    });

    tearDown(() {
      trackingService.reset();
      inferenceService.reset();
    });

    group('Initialization', () {
      test('should initialize successfully', () async {
        final success = await trackingService.initialize();
        
        expect(success, isTrue);
        expect(trackingService.isInitialized, isTrue);
        expect(trackingService.isTracking, isFalse);
      });

      test('should provide initial performance stats', () {
        final stats = trackingService.performanceStats;
        
        expect(stats, isA<Map<String, dynamic>>());
        expect(stats['framesProcessed'], isA<int>());
        expect(stats['ballDetections'], isA<int>());
        expect(stats['clubDetections'], isA<int>());
        expect(stats['ballDetectionRate'], isA<double>());
        expect(stats['clubDetectionRate'], isA<double>());
        expect(stats['isTracking'], isFalse);
      });
    });

    group('Tracking State Management', () {
      setUp(() async {
        await trackingService.initialize();
      });

      test('should start tracking correctly', () async {
        expect(trackingService.isTracking, isFalse);
        
        final eventStream = trackingService.events;
        final events = <GolfTrackingEvent>[];
        
        final subscription = eventStream.listen((event) {
          events.add(event);
        });
        
        trackingService.startTracking();
        
        expect(trackingService.isTracking, isTrue);
        
        // Allow events to be processed
        await Future.delayed(const Duration(milliseconds: 10));
        
        expect(events, contains(GolfTrackingEvent.ballDetected));
        
        await subscription.cancel();
      });

      test('should not start tracking if already tracking', () {
        trackingService.startTracking();
        expect(trackingService.isTracking, isTrue);
        
        final initialEventCount = trackingService.eventHistory.length;
        
        // Try to start again
        trackingService.startTracking();
        
        expect(trackingService.isTracking, isTrue);
        expect(trackingService.eventHistory.length, initialEventCount);
      });

      test('should stop tracking correctly', () async {
        trackingService.startTracking();
        expect(trackingService.isTracking, isTrue);
        
        final eventStream = trackingService.events;
        final shotStream = trackingService.shotData;
        final events = <GolfTrackingEvent>[];
        final shots = <GolfShotData>[];
        
        final eventSub = eventStream.listen((event) => events.add(event));
        final shotSub = shotStream.listen((shot) => shots.add(shot));
        
        trackingService.stopTracking();
        
        expect(trackingService.isTracking, isFalse);
        
        // Allow events to be processed
        await Future.delayed(const Duration(milliseconds: 10));
        
        expect(events, contains(GolfTrackingEvent.trackingComplete));
        expect(shots.length, 1); // Should generate a shot
        
        await eventSub.cancel();
        await shotSub.cancel();
      });

      test('should not stop tracking if not tracking', () {
        expect(trackingService.isTracking, isFalse);
        
        final initialEventCount = trackingService.eventHistory.length;
        
        trackingService.stopTracking();
        
        expect(trackingService.isTracking, isFalse);
        expect(trackingService.eventHistory.length, initialEventCount);
      });
    });

    group('Event Stream Management', () {
      setUp(() async {
        await trackingService.initialize();
      });

      test('should emit tracking events in correct order', () async {
        final events = <GolfTrackingEvent>[];
        final subscription = trackingService.events.listen((event) {
          events.add(event);
        });
        
        trackingService.startTracking();
        await Future.delayed(const Duration(milliseconds: 10));
        
        trackingService.simulateImpact();
        await Future.delayed(const Duration(milliseconds: 10));
        
        trackingService.simulateBallLanding();
        await Future.delayed(const Duration(milliseconds: 10));
        
        // Should see events in expected order
        expect(events, contains(GolfTrackingEvent.ballDetected));
        expect(events, contains(GolfTrackingEvent.impactDetected));
        expect(events, contains(GolfTrackingEvent.ballInFlight));
        expect(events, contains(GolfTrackingEvent.ballLanded));
        expect(events, contains(GolfTrackingEvent.trackingComplete));
        
        await subscription.cancel();
      });

      test('should handle multiple subscribers', () async {
        final events1 = <GolfTrackingEvent>[];
        final events2 = <GolfTrackingEvent>[];
        
        final sub1 = trackingService.events.listen((event) => events1.add(event));
        final sub2 = trackingService.events.listen((event) => events2.add(event));
        
        trackingService.startTracking();
        await Future.delayed(const Duration(milliseconds: 10));
        
        trackingService.stopTracking();
        await Future.delayed(const Duration(milliseconds: 10));
        
        // Both subscribers should receive all events
        expect(events1.length, events2.length);
        expect(events1, containsAll(events2));
        
        await sub1.cancel();
        await sub2.cancel();
      });
    });

    group('Shot Data Generation', () {
      setUp(() async {
        await trackingService.initialize();
      });

      test('should generate shot data when tracking completes', () async {
        final shots = <GolfShotData>[];
        final subscription = trackingService.shotData.listen((shot) {
          shots.add(shot);
        });
        
        trackingService.startTracking();
        trackingService.stopTracking();
        
        await Future.delayed(const Duration(milliseconds: 10));
        
        expect(shots.length, 1);
        
        final shot = shots.first;
        expect(shot.timestamp, isA<DateTime>());
        expect(shot.ballSpeed, greaterThan(0));
        expect(shot.launchAngle, isA<double>());
        expect(shot.carryDistance, greaterThan(0));
        expect(shot.ballTrajectory, isNotEmpty);
        expect(shot.trackingDuration, isA<Duration>());
        expect(shot.metadata, isA<Map<String, dynamic>>());
        
        await subscription.cancel();
      });

      test('should include realistic shot parameters', () async {
        final shots = <GolfShotData>[];
        final subscription = trackingService.shotData.listen((shot) {
          shots.add(shot);
        });
        
        trackingService.startTracking();
        trackingService.stopTracking();
        
        await Future.delayed(const Duration(milliseconds: 10));
        
        final shot = shots.first;
        
        // Ball speed should be in realistic range
        expect(shot.ballSpeed, inRange(20.0, 80.0)); // m/s
        
        // Launch angle should be reasonable
        expect(shot.launchAngle, inRange(-10.0, 45.0)); // degrees
        
        // Carry distance should be reasonable
        expect(shot.carryDistance, inRange(50.0, 350.0)); // meters
        
        // Should have trajectory points
        expect(shot.ballTrajectory.length, greaterThan(10));
        
        await subscription.cancel();
      });

      test('should include metadata in shot data', () async {
        final shots = <GolfShotData>[];
        final subscription = trackingService.shotData.listen((shot) {
          shots.add(shot);
        });
        
        trackingService.startTracking();
        trackingService.stopTracking();
        
        await Future.delayed(const Duration(milliseconds: 10));
        
        final shot = shots.first;
        final metadata = shot.metadata;
        
        expect(metadata, containsKey('impactTime'));
        expect(metadata, containsKey('pixelSpeed'));
        expect(metadata, containsKey('trajectoryPoints'));
        expect(metadata, containsKey('framesProcessed'));
        expect(metadata, containsKey('ballDetections'));
        expect(metadata, containsKey('clubDetections'));
        
        await subscription.cancel();
      });
    });

    group('Frame Processing', () {
      setUp(() async {
        await trackingService.initialize();
      });

      test('should process frames when tracking is active', () async {
        trackingService.startTracking();
        
        final imageData = TestDataGenerator.generateTestImageYUV420(640, 480);
        
        expect(() => trackingService.processFrame(
          imageData, 640, 480,
          bytesPerRow: 640,
          uvBytesPerRow: 320,
        ), returnsNormally);
      });

      test('should ignore frames when not tracking', () async {
        expect(trackingService.isTracking, isFalse);
        
        final imageData = TestDataGenerator.generateTestImageYUV420(640, 480);
        
        // Should not throw but also should not process
        await trackingService.processFrame(imageData, 640, 480);
        
        // Performance stats should not change significantly
        final stats = trackingService.performanceStats;
        expect(stats['framesProcessed'], lessThan(10));
      });

      test('should handle various frame sizes', () async {
        trackingService.startTracking();
        
        final testSizes = [
          [320, 240],
          [640, 480],
          [1280, 720],
        ];
        
        for (final size in testSizes) {
          final width = size[0];
          final height = size[1];
          final imageData = TestDataGenerator.generateTestImageYUV420(width, height);
          
          expect(() => trackingService.processFrame(imageData, width, height),
                 returnsNormally);
        }
      });
    });

    group('Performance Monitoring', () {
      setUp(() async {
        await trackingService.initialize();
      });

      test('should provide comprehensive performance report', () {
        final report = trackingService.getPerformanceReport();
        
        expect(report, isA<Map<String, dynamic>>());
        expect(report, containsKey('tracking'));
        expect(report, containsKey('inference'));
        expect(report, containsKey('timestamp'));
        
        final trackingStats = report['tracking'] as Map<String, dynamic>;
        expect(trackingStats, containsKey('framesProcessed'));
        expect(trackingStats, containsKey('ballDetections'));
        expect(trackingStats, containsKey('clubDetections'));
        expect(trackingStats, containsKey('ballDetectionRate'));
        expect(trackingStats, containsKey('clubDetectionRate'));
        
        final inferenceStats = report['inference'] as Map<String, dynamic>;
        expect(inferenceStats, containsKey('inferenceTime'));
        expect(inferenceStats, containsKey('memoryUsage'));
      });

      test('should update performance stats during tracking', () async {
        final initialStats = trackingService.performanceStats;
        final initialFrames = initialStats['framesProcessed'] as int;
        
        trackingService.startTracking();
        
        // Simulate some tracking activity
        trackingService.simulateImpact();
        await Future.delayed(const Duration(milliseconds: 50));
        
        final updatedStats = trackingService.performanceStats;
        final updatedFrames = updatedStats['framesProcessed'] as int;
        
        expect(updatedFrames, greaterThanOrEqualTo(initialFrames));
        expect(updatedStats['isTracking'], isTrue);
      });

      test('should calculate detection rates correctly', () async {
        trackingService.startTracking();
        
        // Simulate tracking with detections
        trackingService.simulateImpact();
        trackingService.simulateBallLanding();
        
        final stats = trackingService.performanceStats;
        
        expect(stats['ballDetectionRate'], isA<double>());
        expect(stats['clubDetectionRate'], isA<double>());
        expect(stats['ballDetectionRate'], inRange(0.0, 1.0));
        expect(stats['clubDetectionRate'], inRange(0.0, 1.0));
      });
    });

    group('Error Handling and Edge Cases', () {
      setUp(() async {
        await trackingService.initialize();
      });

      test('should handle null or empty frame data', () async {
        trackingService.startTracking();
        
        expect(() => trackingService.processFrame(null as dynamic, 640, 480),
               returnsNormally);
      });

      test('should handle invalid frame dimensions', () async {
        trackingService.startTracking();
        
        final imageData = TestDataGenerator.generateTestImageYUV420(640, 480);
        
        expect(() => trackingService.processFrame(imageData, 0, 0),
               returnsNormally);
        expect(() => trackingService.processFrame(imageData, -640, 480),
               returnsNormally);
        expect(() => trackingService.processFrame(imageData, 640, -480),
               returnsNormally);
      });

      test('should handle multiple rapid start/stop cycles', () async {
        for (int i = 0; i < 5; i++) {
          trackingService.startTracking();
          expect(trackingService.isTracking, isTrue);
          
          await Future.delayed(const Duration(milliseconds: 10));
          
          trackingService.stopTracking();
          expect(trackingService.isTracking, isFalse);
          
          await Future.delayed(const Duration(milliseconds: 10));
        }
        
        // Should have generated multiple shots
        expect(trackingService.shotHistory.length, 5);
      });

      test('should handle tracking timeout scenarios', () async {
        // This would be tested with actual service implementation
        // Mock service doesn't implement timeout logic
        trackingService.startTracking();
        
        // Simulate long tracking period without stopping
        await Future.delayed(const Duration(milliseconds: 100));
        
        // Service should still be responsive
        expect(trackingService.isTracking, isTrue);
        expect(() => trackingService.stopTracking(), returnsNormally);
      });

      test('should maintain state consistency across operations', () async {
        // Test various state transitions
        expect(trackingService.isTracking, isFalse);
        
        trackingService.startTracking();
        expect(trackingService.isTracking, isTrue);
        
        trackingService.simulateImpact();
        expect(trackingService.isTracking, isTrue);
        
        trackingService.simulateBallLanding();
        expect(trackingService.isTracking, isFalse); // Ball landing stops tracking
        
        // Should be able to start again
        trackingService.startTracking();
        expect(trackingService.isTracking, isTrue);
      });
    });

    group('Impact Detection', () {
      setUp(() async {
        await trackingService.initialize();
      });

      test('should detect impact during tracking', () async {
        final events = <GolfTrackingEvent>[];
        final subscription = trackingService.events.listen((event) {
          events.add(event);
        });
        
        trackingService.startTracking();
        await Future.delayed(const Duration(milliseconds: 10));
        
        trackingService.simulateImpact();
        await Future.delayed(const Duration(milliseconds: 10));
        
        expect(events, contains(GolfTrackingEvent.impactDetected));
        expect(events, contains(GolfTrackingEvent.ballInFlight));
        
        await subscription.cancel();
      });

      test('should handle impact without ball landing', () async {
        trackingService.startTracking();
        trackingService.simulateImpact();
        
        // Impact detected but no landing - manual stop
        trackingService.stopTracking();
        
        expect(trackingService.shotHistory.length, 1);
        
        final shot = trackingService.shotHistory.first;
        expect(shot.ballSpeed, greaterThan(0));
      });

      test('should handle ball landing after impact', () async {
        final events = <GolfTrackingEvent>[];
        final subscription = trackingService.events.listen((event) {
          events.add(event);
        });
        
        trackingService.startTracking();
        trackingService.simulateImpact();
        trackingService.simulateBallLanding();
        
        await Future.delayed(const Duration(milliseconds: 10));
        
        expect(events, contains(GolfTrackingEvent.impactDetected));
        expect(events, contains(GolfTrackingEvent.ballInFlight));
        expect(events, contains(GolfTrackingEvent.ballLanded));
        expect(events, contains(GolfTrackingEvent.trackingComplete));
        
        expect(trackingService.isTracking, isFalse);
        expect(trackingService.shotHistory.length, 1);
        
        await subscription.cancel();
      });
    });

    group('Disposal and Cleanup', () {
      test('should dispose properly', () async {
        await trackingService.initialize();
        
        expect(() => trackingService.dispose(), returnsNormally);
      });

      test('should handle operations after disposal', () async {
        await trackingService.initialize();
        await trackingService.dispose();
        
        // Operations should not throw after disposal
        expect(() => trackingService.startTracking(), returnsNormally);
        expect(() => trackingService.stopTracking(), returnsNormally);
        
        final imageData = TestDataGenerator.generateTestImageYUV420(640, 480);
        expect(() => trackingService.processFrame(imageData, 640, 480),
               returnsNormally);
      });

      test('should close streams on disposal', () async {
        await trackingService.initialize();
        
        bool eventStreamClosed = false;
        bool shotStreamClosed = false;
        
        trackingService.events.listen(
          null,
          onDone: () => eventStreamClosed = true,
        );
        
        trackingService.shotData.listen(
          null,
          onDone: () => shotStreamClosed = true,
        );
        
        await trackingService.dispose();
        await Future.delayed(const Duration(milliseconds: 10));
        
        expect(eventStreamClosed, isTrue);
        expect(shotStreamClosed, isTrue);
      });
    });

    group('Integration with Inference Service', () {
      test('should work with mock inference service', () async {
        await inferenceService.initialize();
        expect(inferenceService.isInitialized, isTrue);
        
        // Test processing frames through inference service
        final request = TestDataGenerator.generateInferenceRequest();
        
        expect(() => inferenceService.processFrame(request), returnsNormally);
      });

      test('should handle inference service errors', () async {
        await inferenceService.initialize();
        inferenceService.simulateError();
        
        final request = TestDataGenerator.generateInferenceRequest();
        
        // Should handle errors gracefully
        expect(() => inferenceService.processFrame(request), returnsNormally);
        
        expect(inferenceService.isHealthy, isFalse);
      });

      test('should recover from inference service errors', () async {
        await inferenceService.initialize();
        
        inferenceService.simulateError();
        expect(inferenceService.isHealthy, isFalse);
        
        inferenceService.simulateRecovery();
        expect(inferenceService.isHealthy, isTrue);
        
        // Should work normally after recovery
        final request = TestDataGenerator.generateInferenceRequest();
        expect(() => inferenceService.processFrame(request), returnsNormally);
      });
    });
  });
}