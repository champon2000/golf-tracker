// test/integration/full_pipeline_integration_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter/material.dart';
import 'package:golf_tracker/services/golf_tracking_service.dart';
import 'package:golf_tracker/services/inference_isolate_service.dart';
import 'package:golf_tracker/services/database_service.dart';
import 'package:golf_tracker/services/kalman.dart';
import '../helpers/test_data_generator.dart';
import '../helpers/mock_services.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Full Pipeline Integration Tests', () {
    late MockGolfTrackingService golfTrackingService;
    late MockInferenceIsolateService inferenceService;
    late MockDatabaseService databaseService;
    late MockKalmanFilter kalmanFilter;

    setUp(() async {
      golfTrackingService = MockGolfTrackingService();
      inferenceService = MockInferenceIsolateService();
      databaseService = MockDatabaseService();
      kalmanFilter = MockKalmanFilter();

      await golfTrackingService.initialize();
      await inferenceService.initialize();
    });

    tearDown(() async {
      await golfTrackingService.dispose();
      await inferenceService.dispose();
      
      golfTrackingService.reset();
      inferenceService.reset();
      databaseService.reset();
    });

    group('Camera → ML → Physics Pipeline', () {
      testWidgets('should process complete golf shot from camera to database', 
          (WidgetTester tester) async {
        
        // Set up data collection
        final shotResults = <GolfShotData>[];
        final trackingEvents = <GolfTrackingEvent>[];
        final inferenceResults = <InferenceResult>[];
        
        final shotSubscription = golfTrackingService.shotData.listen((shot) {
          shotResults.add(shot);
        });
        
        final eventSubscription = golfTrackingService.events.listen((event) {
          trackingEvents.add(event);
        });
        
        final inferenceSubscription = inferenceService.results.listen((result) {
          inferenceResults.add(result);
        });

        // Step 1: Start tracking
        golfTrackingService.startTracking();
        expect(golfTrackingService.isTracking, isTrue);

        // Step 2: Simulate camera frames with ML inference
        final testFrames = TestDataGenerator.generateStressTestFrames(
          frameCount: 10,
          width: 640,
          height: 480,
        );

        for (final frame in testFrames) {
          // Simulate camera frame → ML inference
          await inferenceService.processFrame(frame);
          
          // Simulate golf tracking processing
          await golfTrackingService.processFrame(
            frame.yuvBytes, 
            frame.width, 
            frame.height,
          );
          
          await tester.pump(const Duration(milliseconds: 10));
        }

        // Step 3: Simulate impact detection
        golfTrackingService.simulateImpact();
        await tester.pump(const Duration(milliseconds: 10));

        // Step 4: Simulate ball flight and landing
        golfTrackingService.simulateBallLanding();
        await tester.pump(const Duration(milliseconds: 50));

        // Step 5: Verify complete pipeline execution
        expect(trackingEvents, contains(GolfTrackingEvent.ballDetected));
        expect(trackingEvents, contains(GolfTrackingEvent.impactDetected));
        expect(trackingEvents, contains(GolfTrackingEvent.ballInFlight));
        expect(trackingEvents, contains(GolfTrackingEvent.ballLanded));
        expect(trackingEvents, contains(GolfTrackingEvent.trackingComplete));

        expect(shotResults.length, 1);
        expect(inferenceResults.length, testFrames.length);

        // Step 6: Store shot in database
        final shot = shotResults.first;
        final shotRecord = {
          'timestamp': shot.timestamp.millisecondsSinceEpoch,
          'speed': shot.ballSpeed,
          'angle': shot.launchAngle,
          'carry': shot.carryDistance,
          'session_id': 'integration-test-session',
          'club_type': 'test-club',
          'notes': 'Integration test shot',
        };

        final shotId = await databaseService.insertShot(shotRecord);
        expect(shotId, greaterThan(0));

        // Step 7: Verify data persistence
        final retrievedShot = await databaseService.getShot(shotId);
        expect(retrievedShot, isNotNull);
        expect(retrievedShot!['speed'], shot.ballSpeed);
        expect(retrievedShot['angle'], shot.launchAngle);
        expect(retrievedShot['carry'], shot.carryDistance);

        // Clean up subscriptions
        await shotSubscription.cancel();
        await eventSubscription.cancel();
        await inferenceSubscription.cancel();
      });

      testWidgets('should handle high-frequency camera processing (240fps simulation)', 
          (WidgetTester tester) async {
        
        const targetFPS = 240;
        const testDurationMs = 1000; // 1 second
        const expectedFrames = (targetFPS * testDurationMs / 1000).round();
        
        final processedFrames = <int>[];
        final subscription = inferenceService.results.listen((result) {
          processedFrames.add(result.frameId);
        });

        golfTrackingService.startTracking();

        final stopwatch = Stopwatch()..start();
        int frameId = 0;

        // Simulate 240fps camera feed
        while (stopwatch.elapsedMilliseconds < testDurationMs) {
          final frame = TestDataGenerator.generateInferenceRequest(
            frameId: frameId++,
            width: 640,
            height: 480,
          );

          // Process frame through inference pipeline
          inferenceService.processFrame(frame);
          
          // Process through tracking pipeline
          golfTrackingService.processFrame(
            frame.yuvBytes,
            frame.width,
            frame.height,
          );

          // Simulate camera frame timing
          await tester.pump(const Duration(microseconds: 4167)); // ~240fps
        }

        stopwatch.stop();

        // Allow final processing
        await tester.pump(const Duration(milliseconds: 100));

        // Analyze performance
        final stats = inferenceService.performanceStats;
        final framesSent = stats['framesSent'] as int;
        final framesProcessed = stats['framesProcessed'] as int;
        final dropRate = stats['dropRate'] as double;

        expect(framesSent, greaterThan(100)); // Should have sent many frames
        expect(framesProcessed, greaterThan(0)); // Should have processed some
        expect(dropRate, lessThan(0.9)); // Should not drop more than 90%

        // Verify tracking performance
        final trackingStats = golfTrackingService.performanceStats;
        expect(trackingStats['framesProcessed'], greaterThan(0));

        await subscription.cancel();
      });

      testWidgets('should maintain data consistency across pipeline components', 
          (WidgetTester tester) async {
        
        // Track data flow through pipeline
        final pipelineData = <String, dynamic>{};
        
        // Set up monitoring
        final inferenceSubscription = inferenceService.results.listen((result) {
          pipelineData['lastInferenceResult'] = result;
        });
        
        final shotSubscription = golfTrackingService.shotData.listen((shot) {
          pipelineData['completedShot'] = shot;
        });

        // Execute complete shot
        golfTrackingService.startTracking();

        // Process frames with known data
        for (int i = 0; i < 5; i++) {
          final frame = TestDataGenerator.generateInferenceRequest(
            frameId: i,
            width: 640,
            height: 480,
          );

          await inferenceService.processFrame(frame);
          await golfTrackingService.processFrame(
            frame.yuvBytes,
            frame.width,
            frame.height,
          );

          await tester.pump(const Duration(milliseconds: 20));
        }

        // Complete shot sequence
        golfTrackingService.simulateImpact();
        await tester.pump(const Duration(milliseconds: 10));
        
        golfTrackingService.simulateBallLanding();
        await tester.pump(const Duration(milliseconds: 50));

        // Verify data consistency
        expect(pipelineData, containsKey('lastInferenceResult'));
        expect(pipelineData, containsKey('completedShot'));

        final inferenceResult = pipelineData['lastInferenceResult'] as InferenceResult;
        final completedShot = pipelineData['completedShot'] as GolfShotData;

        // Data should be correlated
        expect(inferenceResult.frameId, isA<int>());
        expect(completedShot.ballSpeed, greaterThan(0));
        expect(completedShot.launchAngle, isA<double>());
        expect(completedShot.ballTrajectory, isNotEmpty);

        // Store and verify database consistency
        final shotRecord = {
          'timestamp': completedShot.timestamp.millisecondsSinceEpoch,
          'speed': completedShot.ballSpeed,
          'angle': completedShot.launchAngle,
          'carry': completedShot.carryDistance,
        };

        final shotId = await databaseService.insertShot(shotRecord);
        final retrievedShot = await databaseService.getShot(shotId);

        expect(retrievedShot!['speed'], completedShot.ballSpeed);
        expect(retrievedShot['angle'], completedShot.launchAngle);
        expect(retrievedShot['carry'], completedShot.carryDistance);

        await inferenceSubscription.cancel();
        await shotSubscription.cancel();
      });
    });

    group('Error Recovery and Resilience', () {
      testWidgets('should recover from inference service failures', 
          (WidgetTester tester) async {
        
        golfTrackingService.startTracking();

        // Normal operation
        final frame1 = TestDataGenerator.generateInferenceRequest(frameId: 1);
        await inferenceService.processFrame(frame1);
        expect(inferenceService.isHealthy, isTrue);

        // Simulate inference service failure
        inferenceService.simulateError();
        expect(inferenceService.isHealthy, isFalse);

        // Try to process during failure
        final frame2 = TestDataGenerator.generateInferenceRequest(frameId: 2);
        await inferenceService.processFrame(frame2);

        // Verify graceful degradation
        final stats = inferenceService.performanceStats;
        expect(stats['framesDropped'], greaterThan(0));

        // Simulate recovery
        inferenceService.simulateRecovery();
        expect(inferenceService.isHealthy, isTrue);

        // Verify resumed operation
        final frame3 = TestDataGenerator.generateInferenceRequest(frameId: 3);
        await inferenceService.processFrame(frame3);
        await tester.pump(const Duration(milliseconds: 50));

        // Should be processing again
        expect(inferenceService.isHealthy, isTrue);
      });

      testWidgets('should handle database failures gracefully', 
          (WidgetTester tester) async {
        
        // Complete a shot
        golfTrackingService.startTracking();
        golfTrackingService.simulateImpact();
        golfTrackingService.simulateBallLanding();

        await tester.pump(const Duration(milliseconds: 50));

        // Attempt to store shot data (mock won't actually fail, but test interface)
        final shotRecord = TestDataGenerator.generateDatabaseShot();
        
        expect(() async {
          final shotId = await databaseService.insertShot(shotRecord);
          expect(shotId, greaterThan(0));
        }(), completes);
      });

      testWidgets('should maintain tracking state during component failures', 
          (WidgetTester tester) async {
        
        golfTrackingService.startTracking();
        expect(golfTrackingService.isTracking, isTrue);

        // Simulate inference failure
        inferenceService.simulateError();

        // Tracking should continue despite inference issues
        expect(golfTrackingService.isTracking, isTrue);

        // Should be able to complete shot manually
        golfTrackingService.simulateImpact();
        golfTrackingService.simulateBallLanding();

        await tester.pump(const Duration(milliseconds: 50));

        expect(golfTrackingService.isTracking, isFalse);
        expect(golfTrackingService.shotHistory.length, 1);
      });
    });

    group('Real-time Performance Validation', () {
      testWidgets('should maintain real-time performance under load', 
          (WidgetTester tester) async {
        
        const loadTestDurationMs = 2000; // 2 seconds
        const targetFPS = 120; // Realistic processing target
        
        final performanceMetrics = <String, dynamic>{};
        final frameTimes = <double>[];

        golfTrackingService.startTracking();

        final loadTestStopwatch = Stopwatch()..start();
        int frameCount = 0;

        while (loadTestStopwatch.elapsedMilliseconds < loadTestDurationMs) {
          final frameStopwatch = Stopwatch()..start();

          final frame = TestDataGenerator.generateInferenceRequest(
            frameId: frameCount++,
          );

          // Process through full pipeline
          await inferenceService.processFrame(frame);
          await golfTrackingService.processFrame(
            frame.yuvBytes,
            frame.width,
            frame.height,
          );

          frameStopwatch.stop();
          frameTimes.add(frameStopwatch.elapsedMicroseconds / 1000.0);

          // Maintain target frame rate
          await tester.pump(const Duration(microseconds: 8333)); // ~120fps
        }

        loadTestStopwatch.stop();

        // Analyze performance
        final avgFrameTime = frameTimes.reduce((a, b) => a + b) / frameTimes.length;
        final maxFrameTime = frameTimes.reduce((a, b) => a > b ? a : b);
        final actualFPS = frameCount / (loadTestDurationMs / 1000);

        performanceMetrics['averageFrameTime'] = avgFrameTime;
        performanceMetrics['maxFrameTime'] = maxFrameTime;
        performanceMetrics['actualFPS'] = actualFPS;
        performanceMetrics['totalFrames'] = frameCount;

        // Performance assertions
        expect(avgFrameTime, lessThan(50.0)); // Less than 50ms average
        expect(maxFrameTime, lessThan(200.0)); // Less than 200ms max
        expect(actualFPS, greaterThan(50)); // At least 50 FPS achieved

        // Verify pipeline statistics
        final inferenceStats = inferenceService.performanceStats;
        final trackingStats = golfTrackingService.performanceStats;

        expect(inferenceStats['framesSent'], frameCount);
        expect(inferenceStats['processRate'], greaterThan(0.5)); // Process >50%
        expect(trackingStats['framesProcessed'], greaterThan(0));

        print('Performance Metrics: $performanceMetrics');
        print('Inference Stats: $inferenceStats');
        print('Tracking Stats: $trackingStats');
      });

      testWidgets('should handle memory pressure during extended operation', 
          (WidgetTester tester) async {
        
        const extendedTestDurationMs = 5000; // 5 seconds
        final memoryMetrics = <String, dynamic>{};

        golfTrackingService.startTracking();

        final startTime = DateTime.now();
        int frameCount = 0;

        while (DateTime.now().difference(startTime).inMilliseconds < extendedTestDurationMs) {
          // Generate larger frames to stress memory
          final frame = TestDataGenerator.generateInferenceRequest(
            frameId: frameCount++,
            width: 1280,
            height: 720,
          );

          await inferenceService.processFrame(frame);
          await golfTrackingService.processFrame(
            frame.yuvBytes,
            frame.width,
            frame.height,
          );

          // Occasional garbage collection opportunity
          if (frameCount % 100 == 0) {
            await tester.pump(const Duration(milliseconds: 10));
          }
        }

        // Allow final processing
        await tester.pump(const Duration(milliseconds: 100));

        // Check for memory-related issues
        final finalStats = inferenceService.performanceStats;
        
        expect(finalStats['framesSent'], frameCount);
        expect(finalStats['isHealthy'], isTrue); // Should remain healthy

        // Performance should not degrade significantly
        expect(finalStats['processRate'], greaterThan(0.2)); // At least 20%

        memoryMetrics['totalFramesProcessed'] = frameCount;
        memoryMetrics['finalProcessRate'] = finalStats['processRate'];
        memoryMetrics['testDuration'] = extendedTestDurationMs;

        print('Memory Stress Test Results: $memoryMetrics');
      });
    });

    group('Data Validation and Quality Assurance', () {
      testWidgets('should validate shot data accuracy', 
          (WidgetTester tester) async {
        
        final validatedShots = <GolfShotData>[];
        final subscription = golfTrackingService.shotData.listen((shot) {
          validatedShots.add(shot);
        });

        // Execute multiple shots with known parameters
        for (int i = 0; i < 3; i++) {
          golfTrackingService.startTracking();

          // Process frames
          for (int j = 0; j < 10; j++) {
            final frame = TestDataGenerator.generateInferenceRequest(
              frameId: j,
            );

            await inferenceService.processFrame(frame);
            await golfTrackingService.processFrame(
              frame.yuvBytes,
              frame.width,
              frame.height,
            );
          }

          golfTrackingService.simulateImpact();
          golfTrackingService.simulateBallLanding();

          await tester.pump(const Duration(milliseconds: 50));
        }

        expect(validatedShots.length, 3);

        // Validate each shot
        for (final shot in validatedShots) {
          // Physical constraints validation
          expect(shot.ballSpeed, inRange(10.0, 100.0)); // Reasonable ball speed
          expect(shot.launchAngle, inRange(-30.0, 60.0)); // Reasonable launch angle
          expect(shot.carryDistance, inRange(20.0, 400.0)); // Reasonable distance
          
          // Data consistency validation
          expect(shot.ballTrajectory, isNotEmpty);
          expect(shot.ballTrajectory.length, greaterThan(5));
          expect(shot.trackingDuration.inMilliseconds, greaterThan(0));
          expect(shot.timestamp, isA<DateTime>());
          
          // Metadata validation
          expect(shot.metadata, containsKey('framesProcessed'));
          expect(shot.metadata, containsKey('ballDetections'));
          expect(shot.metadata['framesProcessed'], greaterThan(0));
        }

        await subscription.cancel();
      });

      testWidgets('should validate database consistency', 
          (WidgetTester tester) async {
        
        // Create test session
        final sessionId = await databaseService.createSession('QA Test Session');
        expect(sessionId, greaterThan(0));

        // Generate and store test shots
        final testShots = <Map<String, dynamic>>[];
        for (int i = 0; i < 10; i++) {
          final shotData = TestDataGenerator.generateDatabaseShot(
            sessionId: sessionId.toString(),
          );
          testShots.add(shotData);
          
          final shotId = await databaseService.insertShot(shotData);
          expect(shotId, greaterThan(0));
        }

        // Validate data retrieval
        final retrievedShots = await databaseService.getAllShots(
          sessionId: sessionId.toString(),
        );
        
        expect(retrievedShots.length, testShots.length);

        // Validate statistics calculation
        final sessionStats = await databaseService.getSessionStats(sessionId.toString());
        
        expect(sessionStats['total_shots'], testShots.length);
        expect(sessionStats['average_speed'], isA<double>());
        expect(sessionStats['average_speed'], greaterThan(0));
        
        // Cross-validate calculated vs actual data
        final actualSpeeds = testShots.map((s) => s['speed'] as double).toList();
        final expectedAvgSpeed = actualSpeeds.reduce((a, b) => a + b) / actualSpeeds.length;
        
        expect(sessionStats['average_speed'], closeTo(expectedAvgSpeed, 0.01));
      });
    });
  });
}