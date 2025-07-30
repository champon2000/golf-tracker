// test/performance/fps_performance_test.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_tracker/services/inference_isolate_service.dart';
import 'package:golf_tracker/services/golf_tracking_service.dart';
import '../helpers/test_data_generator.dart';
import '../helpers/mock_services.dart';

void main() {
  group('FPS Performance Tests', () {
    late MockInferenceIsolateService inferenceService;
    late MockGolfTrackingService trackingService;

    setUp(() async {
      inferenceService = MockInferenceIsolateService();
      trackingService = MockGolfTrackingService();
      
      await inferenceService.initialize();
      await trackingService.initialize();
    });

    tearDown(() async {
      await inferenceService.dispose();
      await trackingService.dispose();
      
      inferenceService.reset();
      trackingService.reset();
    });

    group('240fps Processing Target', () {
      test('should process frames at target 240fps rate', () async {
        const targetFPS = 240;
        const testDurationSeconds = 2;
        const targetFrameTimeMs = 1000 / targetFPS; // ~4.17ms
        
        final frameProcessingTimes = <double>[];
        final frameTimestamps = <DateTime>[];
        final processedFrameIds = <int>[];
        
        // Set up result monitoring
        final subscription = inferenceService.results.listen((result) {
          processedFrameIds.add(result.frameId);
        });

        trackingService.startTracking();
        
        final testStartTime = DateTime.now();
        int frameId = 0;
        
        // Simulate 240fps camera feed
        while (DateTime.now().difference(testStartTime).inSeconds < testDurationSeconds) {
          final frameStartTime = DateTime.now();
          
          final frame = TestDataGenerator.generateInferenceRequest(
            frameId: frameId++,
            width: 640,
            height: 480,
          );
          
          // Process through pipeline
          await inferenceService.processFrame(frame);
          await trackingService.processFrame(
            frame.yuvBytes,
            frame.width,
            frame.height,
          );
          
          final frameEndTime = DateTime.now();
          final processingTimeMs = frameEndTime.difference(frameStartTime).inMicroseconds / 1000.0;
          
          frameProcessingTimes.add(processingTimeMs);
          frameTimestamps.add(frameStartTime);
          
          // Maintain 240fps timing (approximately)
          const targetFrameIntervalMicros = 1000000 ~/ targetFPS; // ~4167 microseconds
          await Future.delayed(Duration(microseconds: math.max(1, 
            targetFrameIntervalMicros - frameEndTime.difference(frameStartTime).inMicroseconds)));
        }
        
        final actualTestDuration = DateTime.now().difference(testStartTime);
        
        // Performance analysis
        final totalFramesSent = frameId;
        final actualFPS = totalFramesSent / actualTestDuration.inSeconds;
        final avgProcessingTime = frameProcessingTimes.reduce((a, b) => a + b) / frameProcessingTimes.length;
        final maxProcessingTime = frameProcessingTimes.reduce((a, b) => a > b ? a : b);
        final minProcessingTime = frameProcessingTimes.reduce((a, b) => a < b ? a : b);
        
        final framesUnderTarget = frameProcessingTimes.where((t) => t <= targetFrameTimeMs).length;
        final targetMeetRate = framesUnderTarget / frameProcessingTimes.length;
        
        print('240fps Performance Test Results:');
        print('  Test duration: ${actualTestDuration.inMilliseconds}ms');
        print('  Frames sent: $totalFramesSent');
        print('  Actual FPS: ${actualFPS.toStringAsFixed(1)}');
        print('  Target FPS: $targetFPS');
        print('  Average processing time: ${avgProcessingTime.toStringAsFixed(3)}ms');
        print('  Max processing time: ${maxProcessingTime.toStringAsFixed(3)}ms');
        print('  Min processing time: ${minProcessingTime.toStringAsFixed(3)}ms');
        print('  Target frame time: ${targetFrameTimeMs.toStringAsFixed(3)}ms');
        print('  Frames meeting target: $framesUnderTarget/$totalFramesSent');
        print('  Target meet rate: ${(targetMeetRate * 100).toStringAsFixed(1)}%');
        
        // Assertions
        expect(totalFramesSent, greaterThan(targetFPS * testDurationSeconds * 0.8)); // At least 80% of target
        expect(actualFPS, greaterThan(targetFPS * 0.5)); // At least 50% of target FPS
        expect(avgProcessingTime, lessThan(targetFrameTimeMs * 5)); // Allow 5x margin for mock services
        expect(targetMeetRate, greaterThan(0.1)); // At least 10% of frames should meet target
        
        // Verify service statistics
        final inferenceStats = inferenceService.performanceStats;
        expect(inferenceStats['framesSent'], totalFramesSent);
        expect(inferenceStats['isHealthy'], isTrue);
        
        await subscription.cancel();
      });

      test('should maintain stable frame processing rates', () async {
        const testFPS = 120; // More realistic target for sustained performance
        const testDurationSeconds = 3;
        const measurementIntervalMs = 500; // Measure FPS every 500ms
        
        final fpsReadings = <double>[];
        final timestamps = <DateTime>[];
        
        trackingService.startTracking();
        
        final testStartTime = DateTime.now();
        var lastMeasurementTime = testStartTime;
        var framesSinceLastMeasurement = 0;
        int totalFrames = 0;
        
        while (DateTime.now().difference(testStartTime).inSeconds < testDurationSeconds) {
          final frame = TestDataGenerator.generateInferenceRequest(
            frameId: totalFrames++,
            width: 640,
            height: 480,
          );
          
          await inferenceService.processFrame(frame);
          framesSinceLastMeasurement++;
          
          final now = DateTime.now();
          final timeSinceLastMeasurement = now.difference(lastMeasurementTime);
          
          if (timeSinceLastMeasurement.inMilliseconds >= measurementIntervalMs) {
            final currentFPS = framesSinceLastMeasurement / (timeSinceLastMeasurement.inMilliseconds / 1000.0);
            fpsReadings.add(currentFPS);
            timestamps.add(now);
            
            framesSinceLastMeasurement = 0;
            lastMeasurementTime = now;
          }
          
          // Target frame interval
          await Future.delayed(Duration(microseconds: 1000000 ~/ testFPS));
        }
        
        // Stability analysis
        if (fpsReadings.isNotEmpty) {
          final avgFPS = fpsReadings.reduce((a, b) => a + b) / fpsReadings.length;
          final maxFPS = fpsReadings.reduce((a, b) => a > b ? a : b);
          final minFPS = fpsReadings.reduce((a, b) => a < b ? a : b);
          final fpsVariance = _calculateVariance(fpsReadings);
          final fpsStdDev = math.sqrt(fpsVariance);
          final coefficientOfVariation = fpsStdDev / avgFPS;
          
          print('FPS Stability Test Results:');
          print('  Total frames: $totalFrames');
          print('  Average FPS: ${avgFPS.toStringAsFixed(1)}');
          print('  Max FPS: ${maxFPS.toStringAsFixed(1)}');
          print('  Min FPS: ${minFPS.toStringAsFixed(1)}');
          print('  FPS Standard Deviation: ${fpsStdDev.toStringAsFixed(2)}');
          print('  Coefficient of Variation: ${(coefficientOfVariation * 100).toStringAsFixed(1)}%');
          print('  FPS Readings: ${fpsReadings.map((f) => f.toStringAsFixed(1)).join(', ')}');
          
          // Stability assertions
          expect(avgFPS, greaterThan(testFPS * 0.3)); // At least 30% of target
          expect(coefficientOfVariation, lessThan(0.5)); // CV should be less than 50%
          expect(fpsReadings.length, greaterThan(3)); // Should have multiple readings
          
          // No single reading should be drastically different
          for (final fps in fpsReadings) {
            expect(fps, greaterThan(avgFPS * 0.2)); // No reading below 20% of average
            expect(fps, lessThan(avgFPS * 3.0)); // No reading above 300% of average
          }
        }
      });

      test('should handle frame rate spikes and drops gracefully', () async {
        const baseFPS = 60;
        const spikeFPS = 240;
        const dropFPS = 15;
        const testDurationSeconds = 2;
        
        final processingTimes = <double>[];
        final fpsHistory = <double>[];
        
        trackingService.startTracking();
        
        final testStartTime = DateTime.now();
        int frameId = 0;
        var phaseStartTime = testStartTime;
        
        while (DateTime.now().difference(testStartTime).inSeconds < testDurationSeconds) {
          final elapsed = DateTime.now().difference(phaseStartTime).inMilliseconds;
          
          // Determine current phase (cycling through different FPS targets)
          int currentTargetFPS;
          if (elapsed < 500) {
            currentTargetFPS = baseFPS;
          } else if (elapsed < 1000) {
            currentTargetFPS = spikeFPS; // Spike phase
          } else if (elapsed < 1500) {
            currentTargetFPS = dropFPS; // Drop phase
          } else {
            currentTargetFPS = baseFPS; // Back to base
            if (elapsed >= 2000) {
              phaseStartTime = DateTime.now(); // Reset cycle
            }
          }
          
          final frameStartTime = DateTime.now();
          
          final frame = TestDataGenerator.generateInferenceRequest(
            frameId: frameId++,
            width: 640,
            height: 480,
          );
          
          await inferenceService.processFrame(frame);
          
          final processingTime = DateTime.now().difference(frameStartTime).inMicroseconds / 1000.0;
          processingTimes.add(processingTime);
          fpsHistory.add(currentTargetFPS.toDouble());
          
          // Maintain target FPS timing
          final targetInterval = Duration(microseconds: 1000000 ~/ currentTargetFPS);
          await Future.delayed(targetInterval);
        }
        
        // Analyze handling of rate changes
        final avgProcessingTime = processingTimes.reduce((a, b) => a + b) / processingTimes.length;
        final maxProcessingTime = processingTimes.reduce((a, b) => a > b ? a : b);
        final processingTimeVariance = _calculateVariance(processingTimes);
        
        print('Frame Rate Adaptation Test Results:');
        print('  Total frames: ${frameId}');
        print('  Average processing time: ${avgProcessingTime.toStringAsFixed(3)}ms');
        print('  Max processing time: ${maxProcessingTime.toStringAsFixed(3)}ms');
        print('  Processing time variance: ${processingTimeVariance.toStringAsFixed(3)}');
        print('  Frame rate phases: ${baseFPS} → ${spikeFPS} → ${dropFPS} → ${baseFPS}');
        
        // Adaptation assertions
        expect(frameId, greaterThan(50)); // Should process significant frames
        expect(avgProcessingTime, lessThan(100)); // Should remain reasonable
        expect(maxProcessingTime, lessThan(500)); // No extreme spikes
        
        // Service should remain healthy throughout
        final stats = inferenceService.performanceStats;
        expect(stats['isHealthy'], isTrue);
        expect(stats['framesSent'], frameId);
      });
    });

    group('Memory Performance Under Load', () {
      test('should maintain performance under memory pressure', () async {
        const testDurationSeconds = 3;
        const largeFrameWidth = 1920;
        const largeFrameHeight = 1080;
        const targetFPS = 60;
        
        final memoryPressureData = <Map<String, dynamic>>[];
        
        trackingService.startTracking();
        
        final testStartTime = DateTime.now();
        int frameId = 0;
        
        while (DateTime.now().difference(testStartTime).inSeconds < testDurationSeconds) {
          final frameStartTime = DateTime.now();
          
          // Generate large frame to create memory pressure
          final frame = TestDataGenerator.generateInferenceRequest(
            frameId: frameId++,
            width: largeFrameWidth,
            height: largeFrameHeight,
          );
          
          await inferenceService.processFrame(frame);
          
          final processingTime = DateTime.now().difference(frameStartTime).inMicroseconds / 1000.0;
          
          // Collect memory pressure indicators
          final stats = inferenceService.performanceStats;
          memoryPressureData.add({
            'frameId': frameId,
            'processingTime': processingTime,
            'framesSent': stats['framesSent'],
            'framesProcessed': stats['framesProcessed'],
            'dropRate': stats['dropRate'],
            'isHealthy': stats['isHealthy'],
          });
          
          await Future.delayed(Duration(microseconds: 1000000 ~/ targetFPS));
        }
        
        // Analyze memory performance
        final processingTimes = memoryPressureData.map((d) => d['processingTime'] as double).toList();
        final dropRates = memoryPressureData.map((d) => d['dropRate'] as double).toList();
        
        final avgProcessingTime = processingTimes.reduce((a, b) => a + b) / processingTimes.length;
        final finalDropRate = dropRates.last;
        final healthyFrames = memoryPressureData.where((d) => d['isHealthy'] == true).length;
        
        print('Memory Pressure Test Results:');
        print('  Frame resolution: ${largeFrameWidth}x${largeFrameHeight}');
        print('  Total frames: $frameId');
        print('  Average processing time: ${avgProcessingTime.toStringAsFixed(3)}ms');
        print('  Final drop rate: ${(finalDropRate * 100).toStringAsFixed(1)}%');
        print('  Healthy frame count: $healthyFrames/$frameId');
        
        // Memory performance assertions
        expect(frameId, greaterThan(30)); // Should process reasonable number of large frames
        expect(avgProcessingTime, lessThan(200)); // Should handle large frames reasonably
        expect(finalDropRate, lessThan(0.9)); // Should not drop more than 90%
        expect(healthyFrames / frameId, greaterThan(0.5)); // Should remain healthy >50% of time
      });

      test('should recover from memory stress gracefully', () async {
        const stressDurationSeconds = 1;
        const recoveryDurationSeconds = 2;
        
        final performanceHistory = <Map<String, dynamic>>[];
        
        trackingService.startTracking();
        
        // Phase 1: Memory stress with large frames
        print('Phase 1: Memory stress...');
        final stressStartTime = DateTime.now();
        int frameId = 0;
        
        while (DateTime.now().difference(stressStartTime).inSeconds < stressDurationSeconds) {
          final frame = TestDataGenerator.generateInferenceRequest(
            frameId: frameId++,
            width: 1920,
            height: 1080,
          );
          
          await inferenceService.processFrame(frame);
          
          final stats = inferenceService.performanceStats;
          performanceHistory.add({
            'phase': 'stress',
            'frameId': frameId,
            'dropRate': stats['dropRate'],
            'isHealthy': stats['isHealthy'],
          });
          
          await Future.delayed(const Duration(milliseconds: 8)); // ~120fps
        }
        
        // Simulate error condition
        inferenceService.simulateError();
        await Future.delayed(const Duration(milliseconds: 100));
        
        // Phase 2: Recovery with normal frames
        print('Phase 2: Recovery...');
        inferenceService.simulateRecovery();
        
        final recoveryStartTime = DateTime.now();
        
        while (DateTime.now().difference(recoveryStartTime).inSeconds < recoveryDurationSeconds) {
          final frame = TestDataGenerator.generateInferenceRequest(
            frameId: frameId++,
            width: 640,
            height: 480,
          );
          
          await inferenceService.processFrame(frame);
          
          final stats = inferenceService.performanceStats;
          performanceHistory.add({
            'phase': 'recovery',
            'frameId': frameId,
            'dropRate': stats['dropRate'],
            'isHealthy': stats['isHealthy'],
          });
          
          await Future.delayed(const Duration(milliseconds: 16)); // ~60fps
        }
        
        // Analyze recovery
        final stressData = performanceHistory.where((d) => d['phase'] == 'stress').toList();
        final recoveryData = performanceHistory.where((d) => d['phase'] == 'recovery').toList();
        
        final stressHealthyRate = stressData.where((d) => d['isHealthy'] == true).length / stressData.length;
        final recoveryHealthyRate = recoveryData.where((d) => d['isHealthy'] == true).length / recoveryData.length;
        
        final finalDropRate = recoveryData.isNotEmpty 
          ? recoveryData.last['dropRate'] as double
          : 1.0;
        
        print('Memory Recovery Test Results:');
        print('  Stress phase healthy rate: ${(stressHealthyRate * 100).toStringAsFixed(1)}%');
        print('  Recovery phase healthy rate: ${(recoveryHealthyRate * 100).toStringAsFixed(1)}%');
        print('  Final drop rate: ${(finalDropRate * 100).toStringAsFixed(1)}%');
        print('  Total frames processed: $frameId');
        
        // Recovery assertions
        expect(recoveryHealthyRate, greaterThan(stressHealthyRate)); // Should improve
        expect(recoveryHealthyRate, greaterThan(0.7)); // Should be mostly healthy in recovery
        expect(finalDropRate, lessThan(0.8)); // Should recover to reasonable drop rate
        expect(recoveryData.length, greaterThan(0)); // Should have recovery data
      });
    });

    group('Sustained Performance Testing', () {
      test('should maintain performance over extended periods', () async {
        const testDurationSeconds = 10; // Extended test
        const measurementIntervalSeconds = 1; // Measure every second
        const targetFPS = 60;
        
        final performanceSnapshots = <Map<String, dynamic>>[];
        
        trackingService.startTracking();
        
        final testStartTime = DateTime.now();
        var lastMeasurementTime = testStartTime;
        int totalFrames = 0;
        
        while (DateTime.now().difference(testStartTime).inSeconds < testDurationSeconds) {
          final frame = TestDataGenerator.generateInferenceRequest(
            frameId: totalFrames++,
            width: 640,
            height: 480,
          );
          
          await inferenceService.processFrame(frame);
          
          final now = DateTime.now();
          if (now.difference(lastMeasurementTime).inSeconds >= measurementIntervalSeconds) {
            final stats = inferenceService.performanceStats;
            final elapsedSeconds = now.difference(testStartTime).inSeconds;
            
            performanceSnapshots.add({
              'elapsedSeconds': elapsedSeconds,
              'totalFrames': totalFrames,
              'framesSent': stats['framesSent'],
              'framesProcessed': stats['framesProcessed'],
              'dropRate': stats['dropRate'],
              'isHealthy': stats['isHealthy'],
              'currentFPS': totalFrames / elapsedSeconds,
            });
            
            lastMeasurementTime = now;
          }
          
          await Future.delayed(Duration(microseconds: 1000000 ~/ targetFPS));
        }
        
        // Analyze sustained performance
        final fpsReadings = performanceSnapshots.map((s) => s['currentFPS'] as double).toList();
        final dropRates = performanceSnapshots.map((s) => s['dropRate'] as double).toList();
        final healthyStates = performanceSnapshots.map((s) => s['isHealthy'] as bool).toList();
        
        if (fpsReadings.isNotEmpty && dropRates.isNotEmpty) {
          final avgFPS = fpsReadings.reduce((a, b) => a + b) / fpsReadings.length;
          final finalFPS = fpsReadings.last;
          final initialFPS = fpsReadings.first;
          final fpsDecline = initialFPS - finalFPS;
          
          final avgDropRate = dropRates.reduce((a, b) => a + b) / dropRates.length;
          final finalDropRate = dropRates.last;
          
          final healthyRatio = healthyStates.where((h) => h).length / healthyStates.length;
          
          print('Sustained Performance Test Results:');
          print('  Test duration: ${testDurationSeconds}s');
          print('  Total frames: $totalFrames');
          print('  Average FPS: ${avgFPS.toStringAsFixed(1)}');
          print('  Initial FPS: ${initialFPS.toStringAsFixed(1)}');
          print('  Final FPS: ${finalFPS.toStringAsFixed(1)}');
          print('  FPS decline: ${fpsDecline.toStringAsFixed(1)}');
          print('  Average drop rate: ${(avgDropRate * 100).toStringAsFixed(1)}%');
          print('  Final drop rate: ${(finalDropRate * 100).toStringAsFixed(1)}%');
          print('  Healthy ratio: ${(healthyRatio * 100).toStringAsFixed(1)}%');
          
          // Sustained performance assertions
          expect(totalFrames, greaterThan(testDurationSeconds * targetFPS * 0.3)); // At least 30% of target
          expect(avgFPS, greaterThan(targetFPS * 0.2)); // Average should be reasonable
          expect(fpsDecline, lessThan(avgFPS * 0.5)); // Decline should be less than 50% of average
          expect(healthyRatio, greaterThan(0.6)); // Should be healthy most of the time
          expect(finalDropRate, lessThan(0.9)); // Final drop rate should be manageable
        }
      });
    });
  });
}

/// Helper function to calculate variance
double _calculateVariance(List<double> values) {
  if (values.isEmpty) return 0.0;
  
  final mean = values.reduce((a, b) => a + b) / values.length;
  final squaredDifferences = values.map((v) => math.pow(v - mean, 2));
  return squaredDifferences.reduce((a, b) => a + b) / values.length;
}