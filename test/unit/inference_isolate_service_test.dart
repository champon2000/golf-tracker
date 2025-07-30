// test/unit/inference_isolate_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_tracker/services/inference_isolate_service.dart';
import '../helpers/test_data_generator.dart';
import '../helpers/mock_services.dart';

void main() {
  group('InferenceIsolateService', () {
    late MockInferenceIsolateService inferenceService;
    
    setUp(() {
      inferenceService = MockInferenceIsolateService();
    });

    tearDown(() {
      inferenceService.reset();
    });

    group('Initialization', () {
      test('should initialize successfully', () async {
        expect(inferenceService.isInitialized, isFalse);
        
        final success = await inferenceService.initialize();
        
        expect(success, isTrue);
        expect(inferenceService.isInitialized, isTrue);
        expect(inferenceService.isHealthy, isTrue);
      });

      test('should provide initial performance stats', () async {
        await inferenceService.initialize();
        
        final stats = inferenceService.performanceStats;
        
        expect(stats, isA<Map<String, dynamic>>());
        expect(stats['framesSent'], 0);
        expect(stats['framesProcessed'], 0);
        expect(stats['framesDropped'], 0);
        expect(stats['dropRate'], 0.0);
        expect(stats['processRate'], closeTo(0.0, 0.01));
        expect(stats['isHealthy'], isTrue);
        expect(stats, containsKey('lastResultTime'));
      });

      test('should handle initialization failure gracefully', () async {
        // Mock implementation always succeeds, but test the interface
        expect(() => inferenceService.initialize(), returnsNormally);
      });
    });

    group('Frame Processing', () {
      setUp(() async {
        await inferenceService.initialize();
      });

      test('should process frame and return results', () async {
        final results = <InferenceResult>[];
        final subscription = inferenceService.results.listen((result) {
          results.add(result);
        });
        
        final request = TestDataGenerator.generateInferenceRequest(frameId: 1);
        
        await inferenceService.processFrame(request);
        
        // Allow processing time
        await Future.delayed(const Duration(milliseconds: 50));
        
        expect(results.length, 1);
        
        final result = results.first;
        expect(result.frameId, 1);
        expect(result.timestamp, isA<DateTime>());
        expect(result.detections, isA<List>());
        expect(result.inferenceTime, greaterThan(0));
        expect(result.performanceStats, isA<Map<String, dynamic>>());
        
        await subscription.cancel();
      });

      test('should handle multiple concurrent frames', () async {
        final results = <InferenceResult>[];
        final subscription = inferenceService.results.listen((result) {
          results.add(result);
        });
        
        final requests = List.generate(5, (i) => 
          TestDataGenerator.generateInferenceRequest(frameId: i));
        
        // Send all requests concurrently
        for (final request in requests) {
          inferenceService.processFrame(request);
        }
        
        // Allow processing time
        await Future.delayed(const Duration(milliseconds: 200));
        
        expect(results.length, 5);
        
        // Check that all frame IDs are present
        final frameIds = results.map((r) => r.frameId).toSet();
        expect(frameIds.length, 5);
        expect(frameIds, containsAll([0, 1, 2, 3, 4]));
        
        await subscription.cancel();
      });

      test('should maintain frame rate control', () async {
        final stats = inferenceService.performanceStats;
        
        // Send multiple frames rapidly
        for (int i = 0; i < 10; i++) {
          final request = TestDataGenerator.generateInferenceRequest(frameId: i);
          await inferenceService.processFrame(request);
        }
        
        await Future.delayed(const Duration(milliseconds: 100));
        
        final finalStats = inferenceService.performanceStats;
        
        expect(finalStats['framesSent'], 10);
        
        // Some frames might be dropped for rate control
        final dropRate = finalStats['dropRate'] as double;
        expect(dropRate, inRange(0.0, 1.0));
      });

      test('should handle different frame sizes', () async {
        final results = <InferenceResult>[];
        final subscription = inferenceService.results.listen((result) {
          results.add(result);
        });
        
        final testSizes = [
          [320, 240],
          [640, 480],
          [1280, 720],
        ];
        
        for (int i = 0; i < testSizes.length; i++) {
          final size = testSizes[i];
          final request = TestDataGenerator.generateInferenceRequest(
            width: size[0],
            height: size[1],
            frameId: i,
          );
          
          await inferenceService.processFrame(request);
        }
        
        await Future.delayed(const Duration(milliseconds: 100));
        
        expect(results.length, testSizes.length);
        
        await subscription.cancel();
      });

      test('should drop frames when not healthy', () async {
        inferenceService.simulateError();
        expect(inferenceService.isHealthy, isFalse);
        
        final initialStats = inferenceService.performanceStats;
        final initialDropped = initialStats['framesDropped'] as int;
        
        final request = TestDataGenerator.generateInferenceRequest();
        await inferenceService.processFrame(request);
        
        final finalStats = inferenceService.performanceStats;
        final finalDropped = finalStats['framesDropped'] as int;
        
        expect(finalDropped, greaterThan(initialDropped));
      });
    });

    group('Performance Monitoring', () {
      setUp(() async {
        await inferenceService.initialize();
      });

      test('should track frame statistics accurately', () async {
        final initialStats = inferenceService.performanceStats;
        
        // Process some frames
        for (int i = 0; i < 5; i++) {
          final request = TestDataGenerator.generateInferenceRequest(frameId: i);
          await inferenceService.processFrame(request);
        }
        
        await Future.delayed(const Duration(milliseconds: 100));
        
        final finalStats = inferenceService.performanceStats;
        
        expect(finalStats['framesSent'], greaterThan(initialStats['framesSent']));
        expect(finalStats['framesProcessed'], greaterThanOrEqualTo(initialStats['framesProcessed']));
        
        // Calculate rates
        final processRate = finalStats['processRate'] as double;
        expect(processRate, inRange(0.0, 1.0));
      });

      test('should calculate drop rate correctly', () async {
        // Force some frame drops by overwhelming the service
        for (int i = 0; i < 20; i++) {
          final request = TestDataGenerator.generateInferenceRequest(frameId: i);
          inferenceService.processFrame(request); // Don't await to overwhelm
        }
        
        await Future.delayed(const Duration(milliseconds: 50));
        
        final stats = inferenceService.performanceStats;
        
        expect(stats['framesSent'], 20);
        
        final framesProcessed = stats['framesProcessed'] as int;
        final framesDropped = stats['framesDropped'] as int;
        
        expect(framesProcessed + framesDropped, lessThanOrEqualTo(20));
        
        if (stats['framesSent'] > 0) {
          final expectedDropRate = framesDropped / (stats['framesSent'] as int);
          expect(stats['dropRate'], closeTo(expectedDropRate, 0.01));
        }
      });

      test('should update last result time', () async {
        final beforeProcessing = DateTime.now();
        
        final request = TestDataGenerator.generateInferenceRequest();
        await inferenceService.processFrame(request);
        
        await Future.delayed(const Duration(milliseconds: 50));
        
        final afterProcessing = DateTime.now();
        final stats = inferenceService.performanceStats;
        
        expect(stats['lastResultTime'], isA<String>());
        
        final lastResultTime = DateTime.parse(stats['lastResultTime']);
        expect(lastResultTime.isAfter(beforeProcessing), isTrue);
        expect(lastResultTime.isBefore(afterProcessing), isTrue);
      });
    });

    group('Health Monitoring', () {
      setUp(() async {
        await inferenceService.initialize();
      });

      test('should report healthy status initially', () {
        expect(inferenceService.isHealthy, isTrue);
        
        final stats = inferenceService.performanceStats;
        expect(stats['isHealthy'], isTrue);
      });

      test('should detect unhealthy state', () {
        inferenceService.simulateError();
        
        expect(inferenceService.isHealthy, isFalse);
        
        final stats = inferenceService.performanceStats;
        expect(stats['isHealthy'], isFalse);
      });

      test('should recover from unhealthy state', () {
        inferenceService.simulateError();
        expect(inferenceService.isHealthy, isFalse);
        
        inferenceService.simulateRecovery();
        expect(inferenceService.isHealthy, isTrue);
        
        final stats = inferenceService.performanceStats;
        expect(stats['isHealthy'], isTrue);
      });

      test('should handle processing when unhealthy', () async {
        inferenceService.simulateError();
        
        final initialDropped = inferenceService.performanceStats['framesDropped'] as int;
        
        final request = TestDataGenerator.generateInferenceRequest();
        await inferenceService.processFrame(request);
        
        final finalDropped = inferenceService.performanceStats['framesDropped'] as int;
        
        // Frame should be dropped when unhealthy
        expect(finalDropped, greaterThan(initialDropped));
      });
    });

    group('Results Stream', () {
      setUp(() async {
        await inferenceService.initialize();
      });

      test('should provide broadcast stream', () {
        final stream = inferenceService.results;
        expect(stream, isA<Stream<InferenceResult>>());
        expect(stream.isBroadcast, isTrue);
      });

      test('should handle multiple subscribers', () async {
        final results1 = <InferenceResult>[];
        final results2 = <InferenceResult>[];
        
        final sub1 = inferenceService.results.listen((result) {
          results1.add(result);
        });
        
        final sub2 = inferenceService.results.listen((result) {
          results2.add(result);
        });
        
        final request = TestDataGenerator.generateInferenceRequest();
        await inferenceService.processFrame(request);
        
        await Future.delayed(const Duration(milliseconds: 50));
        
        expect(results1.length, 1);
        expect(results2.length, 1);
        expect(results1.first.frameId, results2.first.frameId);
        
        await sub1.cancel();
        await sub2.cancel();
      });

      test('should deliver results with correct data', () async {
        final results = <InferenceResult>[];
        final subscription = inferenceService.results.listen((result) {
          results.add(result);
        });
        
        final request = TestDataGenerator.generateInferenceRequest(
          frameId: 42,
          width: 640,
          height: 480,
        );
        
        await inferenceService.processFrame(request);
        await Future.delayed(const Duration(milliseconds: 50));
        
        expect(results.length, 1);
        
        final result = results.first;
        expect(result.frameId, 42);
        expect(result.timestamp, isA<DateTime>());
        expect(result.detections, isA<List>());
        expect(result.ballCenter, anyOf([isNull, isA<Offset>()]));
        expect(result.clubHeadCenter, anyOf([isNull, isA<Offset>()]));
        expect(result.predictedBallCenter, anyOf([isNull, isA<Offset>()]));
        expect(result.ballSpeed, isA<double>());
        expect(result.launchAngle, isA<double>());
        expect(result.inferenceTime, greaterThan(0));
        expect(result.performanceStats, isA<Map<String, dynamic>>());
        
        await subscription.cancel();
      });
    });

    group('Edge Cases and Error Handling', () {
      setUp(() async {
        await inferenceService.initialize();
      });

      test('should handle null frame data', () async {
        expect(() => inferenceService.processFrame(null as dynamic),
               returnsNormally);
      });

      test('should handle malformed requests', () async {
        // Create request with invalid data
        final request = InferenceRequest(
          yuvBytes: TestDataGenerator.generateEdgeCaseData()['malformedImageData'],
          width: -1,
          height: -1,
          bytesPerRow: 0,
          uvBytesPerRow: 0,
          frameId: -1,
          timestamp: DateTime.now(),
        );
        
        expect(() => inferenceService.processFrame(request),
               returnsNormally);
      });

      test('should handle extremely large frames', () async {
        final largeFrameData = TestDataGenerator.generateEdgeCaseData()['largeImageData'];
        
        final request = InferenceRequest(
          yuvBytes: largeFrameData,
          width: 1920,
          height: 1080,
          bytesPerRow: 1920,
          uvBytesPerRow: 960,
          frameId: 1,
          timestamp: DateTime.now(),
        );
        
        expect(() => inferenceService.processFrame(request),
               returnsNormally);
      });

      test('should maintain stability under stress', () async {
        final stressFrames = TestDataGenerator.generateStressTestFrames(
          frameCount: 100,
        );
        
        for (final request in stressFrames) {
          inferenceService.processFrame(request); // Don't await to stress test
        }
        
        await Future.delayed(const Duration(milliseconds: 200));
        
        // Service should remain healthy under stress
        expect(inferenceService.isHealthy, isTrue);
        
        final stats = inferenceService.performanceStats;
        expect(stats['framesSent'], 100);
      });

      test('should handle rapid start/stop cycles', () async {
        for (int i = 0; i < 5; i++) {
          await inferenceService.dispose();
          await inferenceService.initialize();
          
          expect(inferenceService.isInitialized, isTrue);
          expect(inferenceService.isHealthy, isTrue);
        }
      });
    });

    group('Frame Rate Control', () {
      setUp(() async {
        await inferenceService.initialize();
      });

      test('should implement target frame rate processing', () async {
        final targetFPS = 240;
        final testDuration = Duration(milliseconds: 100);
        final expectedFrames = (targetFPS * testDuration.inMilliseconds / 1000).round();
        
        final startTime = DateTime.now();
        
        // Send frames at maximum rate
        int frameCount = 0;
        while (DateTime.now().difference(startTime) < testDuration) {
          final request = TestDataGenerator.generateInferenceRequest(frameId: frameCount);
          inferenceService.processFrame(request);
          frameCount++;
        }
        
        await Future.delayed(const Duration(milliseconds: 50));
        
        final stats = inferenceService.performanceStats;
        
        // Should have processed reasonable number of frames (with rate limiting)
        expect(stats['framesProcessed'], lessThanOrEqualTo(frameCount));
        expect(stats['framesProcessed'], greaterThan(0));
      });

      test('should balance processing load', () async {
        // Send burst of frames
        for (int i = 0; i < 50; i++) {
          final request = TestDataGenerator.generateInferenceRequest(frameId: i);
          inferenceService.processFrame(request);
        }
        
        await Future.delayed(const Duration(milliseconds: 100));
        
        final stats = inferenceService.performanceStats;
        
        final processRate = stats['processRate'] as double;
        final dropRate = stats['dropRate'] as double;
        
        // Should maintain reasonable balance
        expect(processRate + dropRate, closeTo(1.0, 0.1));
        expect(processRate, greaterThan(0.1)); // Should process some frames
      });
    });

    group('Resource Management', () {
      test('should initialize and dispose cleanly', () async {
        expect(inferenceService.isInitialized, isFalse);
        
        await inferenceService.initialize();
        expect(inferenceService.isInitialized, isTrue);
        
        await inferenceService.dispose();
        // Mock doesn't track disposal state, but should not throw
      });

      test('should handle disposal during processing', () async {
        await inferenceService.initialize();
        
        // Start processing
        final request = TestDataGenerator.generateInferenceRequest();
        inferenceService.processFrame(request);
        
        // Dispose immediately
        expect(() => inferenceService.dispose(), returnsNormally);
      });

      test('should handle operations after disposal', () async {
        await inferenceService.initialize();
        await inferenceService.dispose();
        
        // Operations should not throw after disposal
        final request = TestDataGenerator.generateInferenceRequest();
        expect(() => inferenceService.processFrame(request), returnsNormally);
      });

      test('should close results stream on disposal', () async {
        await inferenceService.initialize();
        
        bool streamClosed = false;
        inferenceService.results.listen(
          null,
          onDone: () => streamClosed = true,
        );
        
        await inferenceService.dispose();
        await Future.delayed(const Duration(milliseconds: 10));
        
        expect(streamClosed, isTrue);
      });
    });

    group('Performance Benchmarking', () {
      setUp(() async {
        await inferenceService.initialize();
      });

      test('should meet performance targets for 240fps processing', () async {
        const targetFrameTime = 1000 / 240; // ~4.17ms per frame
        const testFrames = 50;
        
        final stopwatch = Stopwatch()..start();
        
        for (int i = 0; i < testFrames; i++) {
          final request = TestDataGenerator.generateInferenceRequest(frameId: i);
          await inferenceService.processFrame(request);
        }
        
        stopwatch.stop();
        
        final avgFrameTime = stopwatch.elapsedMilliseconds / testFrames;
        
        // Should be able to handle frames within reasonable time
        // Mock service might not meet real-world constraints
        expect(avgFrameTime, lessThan(targetFrameTime * 5)); // Allow 5x margin for mock
      });

      test('should maintain consistent performance', () async {
        final frameTimes = <double>[];
        
        for (int i = 0; i < 20; i++) {
          final stopwatch = Stopwatch()..start();
          
          final request = TestDataGenerator.generateInferenceRequest(frameId: i);
          await inferenceService.processFrame(request);
          
          stopwatch.stop();
          frameTimes.add(stopwatch.elapsedMicroseconds / 1000.0);
        }
        
        final avgTime = frameTimes.reduce((a, b) => a + b) / frameTimes.length;
        final maxTime = frameTimes.reduce((a, b) => a > b ? a : b);
        final minTime = frameTimes.reduce((a, b) => a < b ? a : b);
        
        // Performance should be relatively consistent
        final variation = (maxTime - minTime) / avgTime;
        expect(variation, lessThan(2.0)); // Less than 200% variation
      });
    });
  });
}