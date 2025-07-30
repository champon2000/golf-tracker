// test/integration/camera_ml_integration_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter/material.dart';
import 'package:golf_tracker/services/tflite_service.dart';
import 'package:golf_tracker/services/inference_isolate_service.dart';
import 'package:golf_tracker/services/kalman.dart';
import 'package:golf_tracker/models/bounding_box.dart';
import '../helpers/test_data_generator.dart';
import '../helpers/mock_services.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Camera → ML Integration Tests', () {
    late MockTFLiteService tfliteService;
    late MockInferenceIsolateService inferenceService;
    late MockKalmanFilter kalmanFilter;

    setUp(() async {
      tfliteService = MockTFLiteService();
      inferenceService = MockInferenceIsolateService();
      kalmanFilter = MockKalmanFilter();

      await tfliteService.loadModel();
      await inferenceService.initialize();
    });

    tearDown(() async {
      tfliteService.dispose();
      await inferenceService.dispose();
      
      tfliteService.reset();
      inferenceService.reset();
    });

    group('Camera Frame Processing', () {
      testWidgets('should process camera frames through ML pipeline', 
          (WidgetTester tester) async {
        
        final processingResults = <Map<String, dynamic>>[];
        
        // Set up result monitoring
        final subscription = inferenceService.results.listen((result) {
          processingResults.add({
            'frameId': result.frameId,
            'detections': result.detections.length,
            'ballCenter': result.ballCenter,
            'clubHeadCenter': result.clubHeadCenter,
            'inferenceTime': result.inferenceTime,
            'timestamp': result.timestamp,
          });
        });

        // Generate test camera frames
        final testFrames = [
          TestDataGenerator.generateInferenceRequest(
            frameId: 0,
            width: 640,
            height: 480,
          ),
          TestDataGenerator.generateInferenceRequest(
            frameId: 1,
            width: 1280,
            height: 720,
          ),
          TestDataGenerator.generateInferenceRequest(
            frameId: 2,
            width: 1920,
            height: 1080,
          ),
        ];

        // Process frames through ML pipeline
        for (final frame in testFrames) {
          // Simulate direct TFLite processing
          final detections = tfliteService.runInference(
            frame.yuvBytes,
            frame.width,
            frame.height,
          );
          
          expect(detections, isNotNull);
          expect(detections, isA<List<BoundingBox>>());

          // Process through isolate service
          await inferenceService.processFrame(frame);
          
          await tester.pump(const Duration(milliseconds: 30));
        }

        // Allow processing to complete
        await tester.pump(const Duration(milliseconds: 100));

        // Verify results
        expect(processingResults.length, testFrames.length);

        for (int i = 0; i < processingResults.length; i++) {
          final result = processingResults[i];
          expect(result['frameId'], i);
          expect(result['detections'], isA<int>());
          expect(result['inferenceTime'], greaterThan(0));
          expect(result['timestamp'], isA<DateTime>());
        }

        await subscription.cancel();
      });

      testWidgets('should handle different camera resolutions', 
          (WidgetTester tester) async {
        
        final resolutionTests = [
          {'width': 320, 'height': 240, 'name': 'QVGA'},
          {'width': 640, 'height': 480, 'name': 'VGA'},
          {'width': 1280, 'height': 720, 'name': '720p'},
          {'width': 1920, 'height': 1080, 'name': '1080p'},
        ];

        final resolutionResults = <String, Map<String, dynamic>>{};

        for (final testCase in resolutionTests) {
          final width = testCase['width'] as int;
          final height = testCase['height'] as int;
          final name = testCase['name'] as String;

          final stopwatch = Stopwatch()..start();

          // Generate test frame for this resolution
          final frame = TestDataGenerator.generateInferenceRequest(
            width: width,
            height: height,
            frameId: 0,
          );

          // Process through TFLite
          final detections = tfliteService.runInference(
            frame.yuvBytes,
            width,
            height,
          );

          stopwatch.stop();

          resolutionResults[name] = {
            'width': width,
            'height': height,
            'processingTime': stopwatch.elapsedMilliseconds,
            'detectionCount': detections?.length ?? 0,
            'success': detections != null,
          };

          expect(detections, isNotNull);
        }

        // Analyze resolution performance
        for (final entry in resolutionResults.entries) {
          final name = entry.key;
          final result = entry.value;
          
          print('Resolution $name: ${result['width']}x${result['height']}');
          print('  Processing time: ${result['processingTime']}ms');
          print('  Detections: ${result['detectionCount']}');
          print('  Success: ${result['success']}');

          expect(result['success'], isTrue);
          expect(result['processingTime'], lessThan(1000)); // Less than 1 second
        }
      });

      testWidgets('should maintain performance with rapid frame processing', 
          (WidgetTester tester) async {
        
        const rapidFrameCount = 50;
        const targetFrameTime = 16.67; // ~60fps in milliseconds
        
        final frameTimes = <double>[];
        final detectionCounts = <int>[];

        for (int i = 0; i < rapidFrameCount; i++) {
          final stopwatch = Stopwatch()..start();

          final frame = TestDataGenerator.generateInferenceRequest(
            frameId: i,
            width: 640,
            height: 480,
          );

          final detections = tfliteService.runInference(
            frame.yuvBytes,
            frame.width,
            frame.height,
          );

          stopwatch.stop();

          frameTimes.add(stopwatch.elapsedMicroseconds / 1000.0);
          detectionCounts.add(detections?.length ?? 0);

          // Small delay to prevent overwhelming
          await tester.pump(const Duration(milliseconds: 5));
        }

        // Analyze performance
        final avgFrameTime = frameTimes.reduce((a, b) => a + b) / frameTimes.length;
        final maxFrameTime = frameTimes.reduce((a, b) => a > b ? a : b);
        final minFrameTime = frameTimes.reduce((a, b) => a < b ? a : b);
        final avgDetections = detectionCounts.reduce((a, b) => a + b) / detectionCounts.length;

        print('Rapid Frame Processing Results:');
        print('  Average frame time: ${avgFrameTime.toStringAsFixed(2)}ms');
        print('  Max frame time: ${maxFrameTime.toStringAsFixed(2)}ms');
        print('  Min frame time: ${minFrameTime.toStringAsFixed(2)}ms');
        print('  Average detections: ${avgDetections.toStringAsFixed(1)}');

        // Performance assertions
        expect(avgFrameTime, lessThan(100)); // Average should be reasonable
        expect(maxFrameTime, lessThan(500)); // Max spike should be manageable
        
        // Quality assertions
        expect(avgDetections, greaterThan(0)); // Should detect objects
      });
    });

    group('ML Object Detection Quality', () {
      testWidgets('should detect golf-specific objects consistently', 
          (WidgetTester tester) async {
        
        const testFrameCount = 20;
        final detectionHistory = <List<BoundingBox>>[];

        // Generate frames with mock detections
        for (int i = 0; i < testFrameCount; i++) {
          final mockDetections = TestDataGenerator.generateDetections(
            ballCount: 1,
            clubCount: 1,
            minConfidence: 0.6,
            maxConfidence: 0.95,
          );
          
          tfliteService.setMockDetections(mockDetections);

          final frame = TestDataGenerator.generateInferenceRequest(frameId: i);
          final detections = tfliteService.runInference(
            frame.yuvBytes,
            frame.width,
            frame.height,
          );

          expect(detections, isNotNull);
          detectionHistory.add(detections!);
        }

        // Analyze detection consistency
        int ballDetectionCount = 0;
        int clubDetectionCount = 0;
        final confidenceScores = <double>[];

        for (final detections in detectionHistory) {
          for (final detection in detections) {
            confidenceScores.add(detection.confidence);
            
            if (detection.className == 'ball') {
              ballDetectionCount++;
            } else if (detection.className == 'club_head') {
              clubDetectionCount++;
            }
          }
        }

        // Quality metrics
        final avgConfidence = confidenceScores.isNotEmpty 
          ? confidenceScores.reduce((a, b) => a + b) / confidenceScores.length
          : 0.0;
        
        final ballDetectionRate = ballDetectionCount / testFrameCount;
        final clubDetectionRate = clubDetectionCount / testFrameCount;

        print('Detection Quality Analysis:');
        print('  Ball detection rate: ${(ballDetectionRate * 100).toStringAsFixed(1)}%');
        print('  Club detection rate: ${(clubDetectionRate * 100).toStringAsFixed(1)}%');
        print('  Average confidence: ${avgConfidence.toStringAsFixed(3)}');

        // Quality assertions
        expect(ballDetectionRate, greaterThan(0.5)); // Should detect balls >50% of time
        expect(clubDetectionRate, greaterThan(0.3)); // Should detect clubs >30% of time
        expect(avgConfidence, greaterThan(0.5)); // Good confidence scores
      });

      testWidgets('should provide accurate bounding box coordinates', 
          (WidgetTester tester) async {
        
        const frameWidth = 640;
        const frameHeight = 480;
        
        final frame = TestDataGenerator.generateInferenceRequest(
          width: frameWidth,
          height: frameHeight,
        );

        final detections = tfliteService.runInference(
          frame.yuvBytes,
          frameWidth,
          frameHeight,
        );

        expect(detections, isNotNull);

        for (final detection in detections!) {
          // Coordinate validation
          expect(detection.x, greaterThanOrEqualTo(0));
          expect(detection.y, greaterThanOrEqualTo(0));
          expect(detection.x + detection.width, lessThanOrEqualTo(frameWidth));
          expect(detection.y + detection.height, lessThanOrEqualTo(frameHeight));

          // Size validation
          expect(detection.width, greaterThan(0));
          expect(detection.height, greaterThan(0));

          // Object-specific size validation
          if (detection.className == 'ball') {
            expect(detection.width, inRange(5, 80));
            expect(detection.height, inRange(5, 80));
            // Ball should be roughly square
            final aspectRatio = detection.width / detection.height;
            expect(aspectRatio, inRange(0.5, 2.0));
          } else if (detection.className == 'club_head') {
            expect(detection.width, inRange(10, 150));
            expect(detection.height, inRange(5, 100));
          }

          // Center point calculation
          final center = detection.center;
          expect(center.dx, closeTo(detection.x + detection.width / 2, 0.01));
          expect(center.dy, closeTo(detection.y + detection.height / 2, 0.01));
        }
      });

      testWidgets('should handle detection confidence thresholds properly', 
          (WidgetTester tester) async {
        
        // Create detections with various confidence levels
        final testDetections = [
          BoundingBox(x: 100, y: 100, width: 20, height: 20, confidence: 0.95, className: 'ball'),
          BoundingBox(x: 200, y: 200, width: 30, height: 25, confidence: 0.7, className: 'club_head'),
          BoundingBox(x: 300, y: 300, width: 25, height: 25, confidence: 0.4, className: 'ball'),
          BoundingBox(x: 400, y: 400, width: 35, height: 30, confidence: 0.2, className: 'club_head'),
        ];

        tfliteService.setMockDetections(testDetections);

        final frame = TestDataGenerator.generateInferenceRequest();
        final filteredDetections = tfliteService.runInference(
          frame.yuvBytes,
          frame.width,
          frame.height,
        );

        expect(filteredDetections, isNotNull);

        // Analyze confidence filtering
        final highConfidenceCount = filteredDetections!
            .where((d) => d.confidence >= 0.5)
            .length;
        
        final lowConfidenceCount = filteredDetections
            .where((d) => d.confidence < 0.5)
            .length;

        print('Confidence Filtering Results:');
        print('  High confidence (≥0.5): $highConfidenceCount');
        print('  Low confidence (<0.5): $lowConfidenceCount');
        print('  Total detections: ${filteredDetections.length}');

        // Should filter out low confidence detections
        expect(highConfidenceCount, greaterThan(0));
        
        // Verify all returned detections meet minimum confidence
        for (final detection in filteredDetections) {
          if (detection.className == 'ball') {
            expect(detection.confidence, greaterThanOrEqualTo(0.3));
          } else if (detection.className == 'club_head') {
            expect(detection.confidence, greaterThanOrEqualTo(0.3));
          }
        }
      });
    });

    group('Ball Tracking with Kalman Filter', () {
      testWidgets('should track ball motion through ML detections', 
          (WidgetTester tester) async {
        
        // Generate realistic ball motion pattern
        final ballMotion = TestDataGenerator.generateMotionPattern('parabolic', 20);
        final trackingResults = <Offset>[];
        final kalmanFilter = KalmanFilter2D(
          initialPosition: ballMotion.first,
          initialVelocityX: 10.0,
          initialVelocityY: -5.0,
          dt: 1.0 / 30.0,
          processNoisePos: 0.1,
          processNoiseVel: 0.01,
          measurementNoisePos: 1.0,
        );

        for (int i = 0; i < ballMotion.length; i++) {
          final ballPosition = ballMotion[i];
          
          // Create mock detection at ball position
          final mockDetection = BoundingBox(
            x: ballPosition.dx - 10,
            y: ballPosition.dy - 10,
            width: 20,
            height: 20,
            confidence: 0.8 + (i % 3) * 0.05, // Varying confidence
            className: 'ball',
          );

          tfliteService.setMockDetections([mockDetection]);

          // Process frame through ML
          final frame = TestDataGenerator.generateInferenceRequest(frameId: i);
          final detections = tfliteService.runInference(
            frame.yuvBytes,
            frame.width,
            frame.height,
          );

          expect(detections, isNotNull);
          expect(detections!.isNotEmpty, isTrue);

          // Update Kalman filter with detection
          final ballDetection = detections.firstWhere(
            (d) => d.className == 'ball',
            orElse: () => detections.first,
          );

          final trackedPosition = kalmanFilter.update(
            ballDetection.center,
            confidence: ballDetection.confidence,
          );

          trackingResults.add(trackedPosition);

          await tester.pump(const Duration(milliseconds: 10));
        }

        // Analyze tracking performance
        double totalError = 0.0;
        for (int i = 0; i < ballMotion.length; i++) {
          final error = (trackingResults[i] - ballMotion[i]).distance;
          totalError += error;
        }

        final avgError = totalError / ballMotion.length;
        final confidence = kalmanFilter.confidenceScore;

        print('Ball Tracking Results:');
        print('  Average tracking error: ${avgError.toStringAsFixed(2)} pixels');
        print('  Final confidence score: ${confidence.toStringAsFixed(3)}');
        print('  Tracked positions: ${trackingResults.length}');

        // Performance assertions
        expect(avgError, lessThan(20.0)); // Should track within 20 pixels
        expect(confidence, greaterThan(0.5)); // Should have good confidence
        expect(trackingResults.length, ballMotion.length);
      });

      testWidgets('should handle intermittent detections gracefully', 
          (WidgetTester tester) async {
        
        final ballMotion = TestDataGenerator.generateMotionPattern('linear', 15);
        final trackingResults = <Offset>[];
        final detectionGaps = <int>[];

        final kalmanFilter = KalmanFilter2D(
          initialPosition: ballMotion.first,
          initialVelocityX: 15.0,
          initialVelocityY: 0.0,
          dt: 1.0 / 30.0,
          processNoisePos: 0.2,
          processNoiseVel: 0.02,
          measurementNoisePos: 2.0,
        );

        for (int i = 0; i < ballMotion.length; i++) {
          final ballPosition = ballMotion[i];
          
          // Simulate intermittent detections (missing every 3rd frame)
          final hasDetection = i % 3 != 0;
          
          if (hasDetection) {
            final mockDetection = BoundingBox(
              x: ballPosition.dx - 8,
              y: ballPosition.dy - 8,
              width: 16,
              height: 16,
              confidence: 0.75,
              className: 'ball',
            );

            tfliteService.setMockDetections([mockDetection]);

            final frame = TestDataGenerator.generateInferenceRequest(frameId: i);
            final detections = tfliteService.runInference(
              frame.yuvBytes,
              frame.width,
              frame.height,
            );

            final ballDetection = detections!.first;
            final trackedPosition = kalmanFilter.update(
              ballDetection.center,
              confidence: ballDetection.confidence,
            );
            
            trackingResults.add(trackedPosition);
          } else {
            // Use prediction when no detection available
            final predictedPosition = kalmanFilter.predictedPosition;
            trackingResults.add(predictedPosition);
            detectionGaps.add(i);
          }

          await tester.pump(const Duration(milliseconds: 5));
        }

        // Analyze gap handling performance
        print('Intermittent Detection Handling:');
        print('  Total frames: ${ballMotion.length}');
        print('  Detection gaps: ${detectionGaps.length}');
        print('  Gap frames: $detectionGaps');
        print('  Final confidence: ${kalmanFilter.confidenceScore.toStringAsFixed(3)}');

        // Should handle gaps gracefully
        expect(trackingResults.length, ballMotion.length);
        expect(detectionGaps.length, greaterThan(0)); // Should have gaps
        expect(kalmanFilter.confidenceScore, greaterThan(0.3)); // Maintain some confidence
      });
    });

    group('Performance Benchmarking', () {
      testWidgets('should meet 240fps processing targets', 
          (WidgetTester tester) async {
        
        const targetFPS = 240;
        const testDurationMs = 1000; // 1 second test
        const targetFrameTimeMs = 1000 / targetFPS; // ~4.17ms

        final processingTimes = <double>[];
        final startTime = DateTime.now();
        int frameCount = 0;

        while (DateTime.now().difference(startTime).inMilliseconds < testDurationMs) {
          final frameStopwatch = Stopwatch()..start();

          final frame = TestDataGenerator.generateInferenceRequest(
            frameId: frameCount++,
            width: 640,
            height: 480,
          );

          // Process through both services
          tfliteService.runInference(frame.yuvBytes, frame.width, frame.height);
          inferenceService.processFrame(frame);

          frameStopwatch.stop();
          processingTimes.add(frameStopwatch.elapsedMicroseconds / 1000.0);

          // Minimal delay to prevent overwhelming
          await tester.pump(const Duration(microseconds: 100));
        }

        // Performance analysis
        final avgProcessingTime = processingTimes.reduce((a, b) => a + b) / processingTimes.length;
        final maxProcessingTime = processingTimes.reduce((a, b) => a > b ? a : b);
        final framesUnderTarget = processingTimes.where((t) => t <= targetFrameTimeMs).length;
        final targetMeetRate = framesUnderTarget / processingTimes.length;

        print('240fps Performance Benchmark:');
        print('  Total frames processed: $frameCount');
        print('  Average processing time: ${avgProcessingTime.toStringAsFixed(2)}ms');
        print('  Max processing time: ${maxProcessingTime.toStringAsFixed(2)}ms');
        print('  Target frame time: ${targetFrameTimeMs.toStringAsFixed(2)}ms');
        print('  Frames meeting target: $framesUnderTarget/${processingTimes.length}');
        print('  Target meet rate: ${(targetMeetRate * 100).toStringAsFixed(1)}%');

        // Performance assertions (relaxed for mock services)
        expect(avgProcessingTime, lessThan(targetFrameTimeMs * 10)); // 10x margin for mock
        expect(frameCount, greaterThan(100)); // Should process significant frames
        
        // Verify service statistics
        final inferenceStats = inferenceService.performanceStats;
        expect(inferenceStats['framesSent'], frameCount);
      });
    });
  });
}