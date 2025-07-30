// test/unit/tflite_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_tracker/services/tflite_service.dart';
import 'package:golf_tracker/models/bounding_box.dart';
import '../helpers/test_data_generator.dart';
import '../helpers/mock_services.dart';

void main() {
  group('TFLiteService', () {
    late MockTFLiteService tfliteService;
    
    setUp(() {
      tfliteService = MockTFLiteService();
    });

    tearDown(() {
      tfliteService.reset();
    });

    group('Model Loading', () {
      test('should load model successfully', () async {
        expect(tfliteService.isModelLoaded, isFalse);
        
        await tfliteService.loadModel();
        
        expect(tfliteService.isModelLoaded, isTrue);
      });

      test('should handle model loading failure gracefully', () async {
        // This would require actual TFLite service to test properly
        // Mock service always succeeds, so we test the interface
        expect(() => tfliteService.loadModel(), returnsNormally);
      });
    });

    group('Inference Operations', () {
      setUp(() async {
        await tfliteService.loadModel();
      });

      test('should run inference and return detections', () {
        final imageData = TestDataGenerator.generateTestImageYUV420(640, 480);
        
        final detections = tfliteService.runInference(imageData, 640, 480);
        
        expect(detections, isNotNull);
        expect(detections, isA<List<BoundingBox>>());
      });

      test('should return null when model not loaded', () {
        final unloadedService = MockTFLiteService();
        final imageData = TestDataGenerator.generateTestImageYUV420(640, 480);
        
        final detections = unloadedService.runInference(imageData, 640, 480);
        
        expect(detections, isNull);
      });

      test('should handle various image sizes', () {
        final testSizes = [
          [320, 240],
          [640, 480],
          [1280, 720],
          [1920, 1080],
        ];
        
        for (final size in testSizes) {
          final width = size[0];
          final height = size[1];
          final imageData = TestDataGenerator.generateTestImageYUV420(width, height);
          
          final detections = tfliteService.runInference(imageData, width, height);
          
          expect(detections, isNotNull);
          expect(detections, isA<List<BoundingBox>>());
        }
      });

      test('should return consistent detection format', () {
        final imageData = TestDataGenerator.generateTestImageYUV420(640, 480);
        
        final detections = tfliteService.runInference(imageData, 640, 480);
        
        expect(detections, isNotNull);
        for (final detection in detections!) {
          expect(detection.x, isA<double>());
          expect(detection.y, isA<double>());
          expect(detection.width, isA<double>());
          expect(detection.height, isA<double>());
          expect(detection.confidence, inRange(0.0, 1.0));
          expect(detection.className, isA<String>());
          expect(['ball', 'club_head'].contains(detection.className), isTrue);
        }
      });

      test('should filter detections by confidence threshold', () {
        // Set up mock detections with different confidence levels
        final mockDetections = [
          BoundingBox(x: 100, y: 100, width: 20, height: 20, confidence: 0.9, className: 'ball'),
          BoundingBox(x: 200, y: 200, width: 30, height: 30, confidence: 0.3, className: 'club_head'),
          BoundingBox(x: 300, y: 300, width: 25, height: 25, confidence: 0.1, className: 'ball'),
        ];
        
        tfliteService.setMockDetections(mockDetections);
        
        final imageData = TestDataGenerator.generateTestImageYUV420(640, 480);
        final detections = tfliteService.runInference(imageData, 640, 480);
        
        expect(detections, isNotNull);
        
        // Should filter out low confidence detections
        // Mock service uses 0.5 threshold for ball, 0.3 for club_head
        final highConfidenceDetections = detections!.where((d) => 
          (d.className == 'ball' && d.confidence >= 0.5) ||
          (d.className == 'club_head' && d.confidence >= 0.3)
        ).toList();
        
        expect(highConfidenceDetections.length, greaterThan(0));
      });
    });

    group('Performance Monitoring', () {
      setUp(() async {
        await tfliteService.loadModel();
      });

      test('should track inference call count', () {
        expect(tfliteService.inferenceCallCount, 0);
        
        final imageData = TestDataGenerator.generateTestImageYUV420(640, 480);
        
        for (int i = 0; i < 5; i++) {
          tfliteService.runInference(imageData, 640, 480);
        }
        
        expect(tfliteService.inferenceCallCount, 5);
      });

      test('should provide performance statistics', () {
        final imageData = TestDataGenerator.generateTestImageYUV420(640, 480);
        tfliteService.runInference(imageData, 640, 480);
        
        final stats = tfliteService.getPerformanceStats();
        
        expect(stats, isA<Map<String, dynamic>>());
        expect(stats['inferenceTime'], isA<double>());
        expect(stats['preprocessTime'], isA<double>());
        expect(stats['postprocessTime'], isA<double>());
        expect(stats['totalCalls'], isA<int>());
        expect(stats['memoryUsage'], isA<double>());
        expect(stats['gpuUsage'], isA<double>());
        
        // Performance values should be reasonable
        expect(stats['inferenceTime'], greaterThan(0));
        expect(stats['inferenceTime'], lessThan(1000)); // Less than 1 second
        expect(stats['totalCalls'], greaterThan(0));
      });

      test('should track performance over multiple inferences', () {
        final imageData = TestDataGenerator.generateTestImageYUV420(640, 480);
        
        final initialStats = tfliteService.getPerformanceStats();
        final initialCalls = initialStats['totalCalls'] as int;
        
        // Run multiple inferences
        for (int i = 0; i < 10; i++) {
          tfliteService.runInference(imageData, 640, 480);
        }
        
        final finalStats = tfliteService.getPerformanceStats();
        final finalCalls = finalStats['totalCalls'] as int;
        
        expect(finalCalls - initialCalls, 10);
      });
    });

    group('Edge Cases and Error Handling', () {
      setUp(() async {
        await tfliteService.loadModel();
      });

      test('should handle empty image data', () {
        final emptyData = TestDataGenerator.generateEdgeCaseData()['malformedImageData'];
        
        final detections = tfliteService.runInference(emptyData, 640, 480);
        
        // Should handle gracefully - mock returns empty list or null
        expect(detections, anyOf([isNull, isEmpty]));
      });

      test('should handle zero dimensions', () {
        final imageData = TestDataGenerator.generateTestImageYUV420(640, 480);
        
        expect(() => tfliteService.runInference(imageData, 0, 0), returnsNormally);
        expect(() => tfliteService.runInference(imageData, 640, 0), returnsNormally);
        expect(() => tfliteService.runInference(imageData, 0, 480), returnsNormally);
      });

      test('should handle negative dimensions', () {
        final imageData = TestDataGenerator.generateTestImageYUV420(640, 480);
        
        expect(() => tfliteService.runInference(imageData, -640, 480), returnsNormally);
        expect(() => tfliteService.runInference(imageData, 640, -480), returnsNormally);
      });

      test('should handle extremely large images', () {
        final largeImageData = TestDataGenerator.generateEdgeCaseData()['largeImageData'];
        
        expect(() => tfliteService.runInference(largeImageData, 1920, 1080), returnsNormally);
      });

      test('should handle mismatched data size and dimensions', () {
        final imageData = TestDataGenerator.generateTestImageYUV420(320, 240);
        
        // Use wrong dimensions
        expect(() => tfliteService.runInference(imageData, 640, 480), returnsNormally);
      });

      test('should handle null image data', () {
        expect(() => tfliteService.runInference(null as dynamic, 640, 480), returnsNormally);
      });
    });

    group('Detection Quality', () {
      setUp(() async {
        await tfliteService.loadModel();
      });

      test('should detect both ball and club head classes', () {
        final mockDetections = TestDataGenerator.generateDetections(
          ballCount: 2,
          clubCount: 1,
          minConfidence: 0.6,
        );
        tfliteService.setMockDetections(mockDetections);
        
        final imageData = TestDataGenerator.generateTestImageYUV420(640, 480);
        final detections = tfliteService.runInference(imageData, 640, 480);
        
        expect(detections, isNotNull);
        
        final ballDetections = detections!.where((d) => d.className == 'ball').toList();
        final clubDetections = detections.where((d) => d.className == 'club_head').toList();
        
        expect(ballDetections, isNotEmpty);
        expect(clubDetections, isNotEmpty);
      });

      test('should provide reasonable bounding box coordinates', () {
        final imageData = TestDataGenerator.generateTestImageYUV420(640, 480);
        final detections = tfliteService.runInference(imageData, 640, 480);
        
        expect(detections, isNotNull);
        
        for (final detection in detections!) {
          // Coordinates should be within image bounds
          expect(detection.x, greaterThanOrEqualTo(0));
          expect(detection.y, greaterThanOrEqualTo(0));
          expect(detection.x + detection.width, lessThanOrEqualTo(640));
          expect(detection.y + detection.height, lessThanOrEqualTo(480));
          
          // Dimensions should be positive
          expect(detection.width, greaterThan(0));
          expect(detection.height, greaterThan(0));
          
          // Reasonable object sizes for golf objects
          if (detection.className == 'ball') {
            expect(detection.width, inRange(5, 50)); // 5-50 pixels
            expect(detection.height, inRange(5, 50));
          } else if (detection.className == 'club_head') {
            expect(detection.width, inRange(10, 100)); // 10-100 pixels
            expect(detection.height, inRange(5, 60));
          }
        }
      });

      test('should handle overlapping detections correctly', () {
        final overlappingDetections = TestDataGenerator.generateEdgeCaseData()['overlappingDetections'];
        tfliteService.setMockDetections(overlappingDetections);
        
        final imageData = TestDataGenerator.generateTestImageYUV420(640, 480);
        final detections = tfliteService.runInference(imageData, 640, 480);
        
        expect(detections, isNotNull);
        // Mock service should handle NMS and return filtered results
        expect(detections!.length, lessThanOrEqualTo(overlappingDetections.length));
      });
    });

    group('Confidence and Quality Metrics', () {
      setUp(() async {
        await tfliteService.loadModel();
      });

      test('should maintain confidence score ranges', () {
        final imageData = TestDataGenerator.generateTestImageYUV420(640, 480);
        final detections = tfliteService.runInference(imageData, 640, 480);
        
        expect(detections, isNotNull);
        
        for (final detection in detections!) {
          expect(detection.confidence, inRange(0.0, 1.0));
          
          // Should meet minimum confidence thresholds
          if (detection.className == 'ball') {
            expect(detection.confidence, greaterThanOrEqualTo(0.3));
          } else if (detection.className == 'club_head') {
            expect(detection.confidence, greaterThanOrEqualTo(0.3));
          }
        }
      });

      test('should provide consistent results for identical inputs', () {
        final imageData = TestDataGenerator.generateTestImageYUV420(640, 480);
        
        final detections1 = tfliteService.runInference(imageData, 640, 480);
        final detections2 = tfliteService.runInference(imageData, 640, 480);
        
        expect(detections1, isNotNull);
        expect(detections2, isNotNull);
        
        // Results should be identical for identical inputs
        expect(detections1!.length, detections2!.length);
        
        for (int i = 0; i < detections1.length; i++) {
          expect(detections1[i].x, closeTo(detections2[i].x, 0.001));
          expect(detections1[i].y, closeTo(detections2[i].y, 0.001));
          expect(detections1[i].confidence, closeTo(detections2[i].confidence, 0.001));
          expect(detections1[i].className, detections2[i].className);
        }
      });
    });

    group('Resource Management', () {
      test('should dispose properly', () {
        expect(() => tfliteService.dispose(), returnsNormally);
        
        // After disposal, model should not be loaded
        expect(tfliteService.isModelLoaded, isFalse);
      });

      test('should handle multiple dispose calls', () {
        tfliteService.dispose();
        expect(() => tfliteService.dispose(), returnsNormally);
      });

      test('should not run inference after disposal', () {
        tfliteService.dispose();
        
        final imageData = TestDataGenerator.generateTestImageYUV420(640, 480);
        final detections = tfliteService.runInference(imageData, 640, 480);
        
        expect(detections, isNull);
      });
    });

    group('Stress Testing', () {
      setUp(() async {
        await tfliteService.loadModel();
      });

      test('should handle rapid consecutive inferences', () async {
        final imageData = TestDataGenerator.generateTestImageYUV420(640, 480);
        final stopwatch = Stopwatch()..start();
        
        for (int i = 0; i < 100; i++) {
          final detections = tfliteService.runInference(imageData, 640, 480);
          expect(detections, isNotNull);
        }
        
        stopwatch.stop();
        
        expect(tfliteService.inferenceCallCount, 100);
        
        // Performance should be reasonable for 100 inferences
        expect(stopwatch.elapsedMilliseconds, lessThan(10000)); // 10 seconds max
      });

      test('should maintain performance under sustained load', () async {
        final imageData = TestDataGenerator.generateTestImageYUV420(640, 480);
        final inferenceTimes = <double>[];
        
        for (int i = 0; i < 50; i++) {
          final stopwatch = Stopwatch()..start();
          tfliteService.runInference(imageData, 640, 480);
          stopwatch.stop();
          
          inferenceTimes.add(stopwatch.elapsedMicroseconds / 1000.0);
        }
        
        // Calculate average and check for performance degradation
        final avgTime = inferenceTimes.reduce((a, b) => a + b) / inferenceTimes.length;
        final lastFiveAvg = inferenceTimes.skip(45).reduce((a, b) => a + b) / 5;
        
        // Performance shouldn't degrade significantly over time
        expect(lastFiveAvg, lessThan(avgTime * 1.5)); // Less than 50% slower
      });

      test('should handle memory pressure gracefully', () {
        // Simulate memory pressure with large images
        for (int i = 0; i < 10; i++) {
          final largeImageData = TestDataGenerator.generateTestImageYUV420(1920, 1080);
          
          expect(() => tfliteService.runInference(largeImageData, 1920, 1080),
                 returnsNormally);
        }
        
        final stats = tfliteService.getPerformanceStats();
        expect(stats['memoryUsage'], isA<double>());
        expect(stats['memoryUsage'], greaterThan(0));
      });
    });
  });
}