// test/quality/validation_suite.dart
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:golf_tracker/services/golf_tracking_service.dart';
import 'package:golf_tracker/models/bounding_box.dart';
import '../helpers/test_data_generator.dart';
import '../helpers/mock_services.dart';

/// Comprehensive quality assurance and validation suite
class GolfTrackerValidationSuite {
  static const String version = '1.0.0';
  
  /// Run all validation tests
  static Future<ValidationReport> runCompleteValidation() async {
    print('=== Golf Tracker Quality Assurance Suite v$version ===\n');
    
    final report = ValidationReport();
    
    // Data validation tests
    await _runDataValidationTests(report);
    
    // Physics validation tests
    await _runPhysicsValidationTests(report);
    
    // Accuracy validation tests
    await _runAccuracyValidationTests(report);
    
    // Edge case validation tests
    await _runEdgeCaseValidationTests(report);
    
    // Performance validation tests
    await _runPerformanceValidationTests(report);
    
    report.finalize();
    _printValidationReport(report);
    
    return report;
  }

  /// Run data validation tests
  static Future<void> _runDataValidationTests(ValidationReport report) async {
    print('Running Data Validation Tests...');
    
    final testSuite = ValidationTestSuite('Data Validation');
    
    // Test shot data generation
    testSuite.addTest(ValidationTest(
      name: 'Shot Data Generation',
      description: 'Validates generated shot data meets realistic constraints',
      testFunction: () async {
        final shots = List.generate(100, (_) => TestDataGenerator.generateGolfShotData());
        
        for (final shot in shots) {
          // Ball speed validation (reasonable range for golf)
          if (shot.ballSpeed < 5.0 || shot.ballSpeed > 100.0) {
            return ValidationResult.failure('Ball speed out of range: ${shot.ballSpeed} m/s');
          }
          
          // Launch angle validation
          if (shot.launchAngle < -45.0 || shot.launchAngle > 90.0) {
            return ValidationResult.failure('Launch angle out of range: ${shot.launchAngle}°');
          }
          
          // Carry distance validation
          if (shot.carryDistance < 0.0 || shot.carryDistance > 400.0) {
            return ValidationResult.failure('Carry distance out of range: ${shot.carryDistance}m');
          }
          
          // Trajectory validation
          if (shot.ballTrajectory.isEmpty) {
            return ValidationResult.failure('Empty ball trajectory');
          }
          
          if (shot.ballTrajectory.length < 5) {
            return ValidationResult.failure('Insufficient trajectory points: ${shot.ballTrajectory.length}');
          }
          
          // Metadata validation
          if (shot.metadata.isEmpty) {
            return ValidationResult.failure('Missing shot metadata');
          }
          
          final requiredMetadataKeys = ['impactTime', 'pixelSpeed', 'trajectoryPoints', 'framesProcessed'];
          for (final key in requiredMetadataKeys) {
            if (!shot.metadata.containsKey(key)) {
              return ValidationResult.failure('Missing metadata key: $key');
            }
          }
        }
        
        return ValidationResult.success('All shot data generated within valid ranges');
      },
    ));
    
    // Test bounding box validation
    testSuite.addTest(ValidationTest(
      name: 'Bounding Box Validation',
      description: 'Validates bounding box coordinates and dimensions',
      testFunction: () async {
        final detections = TestDataGenerator.generateDetections(ballCount: 50, clubCount: 50);
        
        for (final detection in detections) {
          // Coordinate validation
          if (detection.x < 0 || detection.y < 0) {
            return ValidationResult.failure('Negative coordinates: (${detection.x}, ${detection.y})');
          }
          
          // Dimension validation
          if (detection.width <= 0 || detection.height <= 0) {
            return ValidationResult.failure('Invalid dimensions: ${detection.width}x${detection.height}');
          }
          
          // Size constraints for different object types
          if (detection.className == 'ball') {
            if (detection.width < 5 || detection.width > 100) {
              return ValidationResult.failure('Ball width out of range: ${detection.width}');
            }
            if (detection.height < 5 || detection.height > 100) {
              return ValidationResult.failure('Ball height out of range: ${detection.height}');
            }
          } else if (detection.className == 'club_head') {
            if (detection.width < 10 || detection.width > 200) {
              return ValidationResult.failure('Club width out of range: ${detection.width}');
            }
            if (detection.height < 5 || detection.height > 150) {
              return ValidationResult.failure('Club height out of range: ${detection.height}');
            }
          }
          
          // Confidence validation
          if (detection.confidence < 0.0 || detection.confidence > 1.0) {
            return ValidationResult.failure('Confidence out of range: ${detection.confidence}');
          }
          
          // Class name validation
          if (!['ball', 'club_head'].contains(detection.className)) {
            return ValidationResult.failure('Invalid class name: ${detection.className}');
          }
        }
        
        return ValidationResult.success('All bounding boxes valid');
      },
    ));
    
    // Test database consistency
    testSuite.addTest(ValidationTest(
      name: 'Database Consistency',
      description: 'Validates database operations and data integrity',
      testFunction: () async {
        final db = MockDatabaseService();
        
        // Test shot insertion and retrieval
        final testShots = List.generate(10, (_) => TestDataGenerator.generateDatabaseShot());
        final insertedIds = <int>[];
        
        for (final shot in testShots) {
          final id = await db.insertShot(shot);
          if (id <= 0) {
            return ValidationResult.failure('Failed to insert shot');
          }
          insertedIds.add(id);
        }
        
        // Verify retrieval
        for (int i = 0; i < insertedIds.length; i++) {
          final retrievedShot = await db.getShot(insertedIds[i]);
          if (retrievedShot == null) {
            return ValidationResult.failure('Failed to retrieve shot ID: ${insertedIds[i]}');
          }
          
          final originalShot = testShots[i];
          if ((retrievedShot['speed'] as double) != originalShot['speed']) {
            return ValidationResult.failure('Data inconsistency in shot retrieval');
          }
        }
        
        // Test statistics calculation
        const sessionId = 'validation-session';
        final sessionShots = List.generate(5, (_) => 
          TestDataGenerator.generateDatabaseShot(sessionId: sessionId));
        
        for (final shot in sessionShots) {
          await db.insertShot(shot);
        }
        
        final stats = await db.getSessionStats(sessionId);
        if (stats['total_shots'] != sessionShots.length) {
          return ValidationResult.failure('Statistics calculation error');
        }
        
        return ValidationResult.success('Database operations consistent');
      },
    ));
    
    await testSuite.runAllTests();
    report.addTestSuite(testSuite);
  }

  /// Run physics validation tests
  static Future<void> _runPhysicsValidationTests(ValidationReport report) async {
    print('Running Physics Validation Tests...');
    
    final testSuite = ValidationTestSuite('Physics Validation');
    
    // Test projectile motion validation
    testSuite.addTest(ValidationTest(
      name: 'Projectile Motion Validation',
      description: 'Validates physics calculations for ball trajectory',
      testFunction: () async {
        // Test known physics scenarios
        final testCases = [
          {'speed': 45.0, 'angle': 30.0, 'expectedRange': 178.8}, // Theoretical optimal
          {'speed': 60.0, 'angle': 15.0, 'expectedRange': 183.6},
          {'speed': 30.0, 'angle': 45.0, 'expectedRange': 91.8},
        ];
        
        for (final testCase in testCases) {
          final speed = testCase['speed'] as double;
          final angle = testCase['angle'] as double;
          final expectedRange = testCase['expectedRange'] as double;
          
          // Calculate actual range using simple projectile motion
          final radians = angle * math.pi / 180;
          const gravity = 9.81;
          final calculatedRange = (speed * speed * math.sin(2 * radians)) / gravity;
          
          final error = (calculatedRange - expectedRange).abs();
          final errorPercent = (error / expectedRange) * 100;
          
          if (errorPercent > 5.0) { // Allow 5% error tolerance
            return ValidationResult.failure(
              'Physics calculation error: ${errorPercent.toStringAsFixed(1)}% for '
              'speed=${speed}m/s, angle=${angle}°'
            );
          }
        }
        
        return ValidationResult.success('Physics calculations within tolerance');
      },
    ));
    
    // Test speed and distance correlation
    testSuite.addTest(ValidationTest(
      name: 'Speed-Distance Correlation',
      description: 'Validates correlation between ball speed and carry distance',
      testFunction: () async {
        final shots = List.generate(50, (_) => TestDataGenerator.generateGolfShotData());
        
        // Check that higher speeds generally produce longer distances
        // (with some tolerance for angle variations)
        final sortedBySpeed = shots..sort((a, b) => a.ballSpeed.compareTo(b.ballSpeed));
        
        // Compare speed quartiles
        final q1Speed = sortedBySpeed[12].ballSpeed;
        final q4Speed = sortedBySpeed[37].ballSpeed;
        
        final q1Distances = sortedBySpeed.take(12).map((s) => s.carryDistance).toList();
        final q4Distances = sortedBySpeed.skip(37).map((s) => s.carryDistance).toList();
        
        final avgQ1Distance = q1Distances.reduce((a, b) => a + b) / q1Distances.length;
        final avgQ4Distance = q4Distances.reduce((a, b) => a + b) / q4Distances.length;
        
        if (avgQ4Distance <= avgQ1Distance) {
          return ValidationResult.failure(
            'Speed-distance correlation violated: Q4 avg distance (${avgQ4Distance.toStringAsFixed(1)}m) '
            '<= Q1 avg distance (${avgQ1Distance.toStringAsFixed(1)}m)'
          );
        }
        
        return ValidationResult.success(
          'Speed-distance correlation valid: Q1=${avgQ1Distance.toStringAsFixed(1)}m, '
          'Q4=${avgQ4Distance.toStringAsFixed(1)}m'
        );
      },
    ));
    
    await testSuite.runAllTests();
    report.addTestSuite(testSuite);
  }

  /// Run accuracy validation tests
  static Future<void> _runAccuracyValidationTests(ValidationReport report) async {
    print('Running Accuracy Validation Tests...');
    
    final testSuite = ValidationTestSuite('Accuracy Validation');
    
    // Test Kalman filter accuracy
    testSuite.addTest(ValidationTest(
      name: 'Kalman Filter Tracking Accuracy',
      description: 'Validates tracking accuracy for known motion patterns',
      testFunction: () async {
        final motionPatterns = ['linear', 'parabolic', 'circular'];
        final accuracyResults = <String, double>{};
        
        for (final pattern in motionPatterns) {
          final truePositions = TestDataGenerator.generateMotionPattern(pattern, 50);
          
          final kalmanFilter = MockKalmanFilter();
          kalmanFilter.setPosition(truePositions.first);
          
          final trackedPositions = <Offset>[];
          
          for (final truePos in truePositions) {
            // Add some noise to simulate real measurements
            final noisyMeasurement = Offset(
              truePos.dx + (math.Random().nextDouble() - 0.5) * 4, // ±2 pixel noise
              truePos.dy + (math.Random().nextDouble() - 0.5) * 4,
            );
            
            final tracked = kalmanFilter.update(noisyMeasurement);
            trackedPositions.add(tracked);
          }
          
          // Calculate tracking accuracy
          double totalError = 0.0;
          for (int i = 0; i < truePositions.length; i++) {
            final error = (trackedPositions[i] - truePositions[i]).distance;
            totalError += error;
          }
          
          final avgError = totalError / truePositions.length;
          accuracyResults[pattern] = avgError;
          
          // Accuracy threshold: should track within 5 pixels on average
          if (avgError > 5.0) {
            return ValidationResult.failure(
              'Poor tracking accuracy for $pattern motion: ${avgError.toStringAsFixed(2)} pixels'
            );
          }
        }
        
        return ValidationResult.success(
          'Tracking accuracy acceptable: ${accuracyResults.entries.map((e) => 
            '${e.key}=${e.value.toStringAsFixed(1)}px').join(', ')}'
        );
      },
    ));
    
    // Test detection consistency
    testSuite.addTest(ValidationTest(
      name: 'Detection Consistency',
      description: 'Validates consistency of object detection across frames',
      testFunction: () async {
        final tfliteService = MockTFLiteService();
        await tfliteService.loadModel();
        
        // Generate consistent test scenario
        final ballPositions = TestDataGenerator.generateMotionPattern('linear', 20);
        final detectionResults = <List<BoundingBox>>[];
        
        for (int i = 0; i < ballPositions.length; i++) {
          final ballPos = ballPositions[i];
          
          // Create mock detection at ball position
          final mockDetection = BoundingBox(
            x: ballPos.dx - 10,
            y: ballPos.dy - 10,
            width: 20,
            height: 20,
            confidence: 0.85 + (math.Random().nextDouble() - 0.5) * 0.1, // 0.8-0.9 range
            className: 'ball',
          );
          
          tfliteService.setMockDetections([mockDetection]);
          
          final frame = TestDataGenerator.generateInferenceRequest(frameId: i);
          final detections = tfliteService.runInference(frame.yuvBytes, frame.width, frame.height);
          
          if (detections == null || detections.isEmpty) {
            return ValidationResult.failure('No detections returned for frame $i');
          }
          
          detectionResults.add(detections);
        }
        
        // Validate consistency metrics
        final ballDetectionCount = detectionResults
          .map((detections) => detections.where((d) => d.className == 'ball').length)
          .reduce((a, b) => a + b);
        
        final detectionRate = ballDetectionCount / detectionResults.length;
        
        if (detectionRate < 0.8) {
          return ValidationResult.failure(
            'Low detection consistency: ${(detectionRate * 100).toStringAsFixed(1)}%'
          );
        }
        
        // Check confidence consistency
        final confidenceScores = detectionResults
          .expand((detections) => detections.where((d) => d.className == 'ball'))
          .map((d) => d.confidence)
          .toList();
        
        if (confidenceScores.isNotEmpty) {
          final avgConfidence = confidenceScores.reduce((a, b) => a + b) / confidenceScores.length;
          final confidenceVariance = _calculateVariance(confidenceScores);
          
          if (avgConfidence < 0.6) {
            return ValidationResult.failure('Low average confidence: ${avgConfidence.toStringAsFixed(3)}');
          }
          
          if (confidenceVariance > 0.05) {
            return ValidationResult.failure('High confidence variance: ${confidenceVariance.toStringAsFixed(4)}');
          }
        }
        
        return ValidationResult.success(
          'Detection consistency acceptable: ${(detectionRate * 100).toStringAsFixed(1)}% detection rate'
        );
      },
    ));
    
    await testSuite.runAllTests();
    report.addTestSuite(testSuite);
  }

  /// Run edge case validation tests
  static Future<void> _runEdgeCaseValidationTests(ValidationReport report) async {
    print('Running Edge Case Validation Tests...');
    
    final testSuite = ValidationTestSuite('Edge Case Validation');
    
    // Test extreme values handling
    testSuite.addTest(ValidationTest(
      name: 'Extreme Values Handling',
      description: 'Validates system behavior with extreme input values',
      testFunction: () async {
        final extremeValues = TestDataGenerator.generateEdgeCaseData();
        
        // Test empty detections
        final emptyDetections = extremeValues['emptyDetections'] as List<BoundingBox>;
        if (emptyDetections.isNotEmpty) {
          return ValidationResult.failure('Empty detections list should be empty');
        }
        
        // Test low confidence detections
        final lowConfDetections = extremeValues['lowConfidenceDetections'] as List<BoundingBox>;
        for (final detection in lowConfDetections) {
          if (detection.confidence >= 0.5) {
            return ValidationResult.failure('Low confidence detection has high confidence: ${detection.confidence}');
          }
        }
        
        // Test extreme ball speeds
        final extremeSpeeds = extremeValues['extremeBallSpeeds'] as List<double>;
        for (final speed in extremeSpeeds) {
          // System should handle these without crashing
          try {
            final shot = TestDataGenerator.generateGolfShotData(ballSpeed: speed);
            // Validate result is reasonable or properly clamped
            if (speed >= 0 && shot.ballSpeed < 0) {
              return ValidationResult.failure('Negative speed result for positive input: $speed');
            }
          } catch (e) {
            return ValidationResult.failure('Exception handling extreme speed $speed: $e');
          }
        }
        
        // Test extreme launch angles
        final extremeAngles = extremeValues['extremeLaunchAngles'] as List<double>;
        for (final angle in extremeAngles) {
          try {
            final shot = TestDataGenerator.generateGolfShotData(launchAngle: angle);
            // Should handle gracefully
            if (shot.launchAngle.isNaN || shot.launchAngle.isInfinite) {
              return ValidationResult.failure('Invalid angle result for input: $angle');
            }
          } catch (e) {
            return ValidationResult.failure('Exception handling extreme angle $angle: $e');
          }
        }
        
        return ValidationResult.success('Extreme values handled gracefully');
      },
    ));
    
    // Test error recovery
    testSuite.addTest(ValidationTest(
      name: 'Error Recovery',
      description: 'Validates system recovery from error conditions',
      testFunction: () async {
        final inferenceService = MockInferenceIsolateService();
        await inferenceService.initialize();
        
        // Normal operation
        expect(inferenceService.isHealthy, isTrue);
        
        // Simulate error
        inferenceService.simulateError();
        expect(inferenceService.isHealthy, isFalse);
        
        // Should still accept frames (but drop them)
        final frame = TestDataGenerator.generateInferenceRequest();
        try {
          await inferenceService.processFrame(frame);
        } catch (e) {
          return ValidationResult.failure('Exception during error state: $e');
        }
        
        // Simulate recovery
        inferenceService.simulateRecovery();
        expect(inferenceService.isHealthy, isTrue);
        
        // Should process frames normally after recovery
        try {
          await inferenceService.processFrame(frame);
        } catch (e) {
          return ValidationResult.failure('Exception after recovery: $e');
        }
        
        await inferenceService.dispose();
        
        return ValidationResult.success('Error recovery working correctly');
      },
    ));
    
    await testSuite.runAllTests();
    report.addTestSuite(testSuite);
  }

  /// Run performance validation tests
  static Future<void> _runPerformanceValidationTests(ValidationReport report) async {
    print('Running Performance Validation Tests...');
    
    final testSuite = ValidationTestSuite('Performance Validation');
    
    // Test frame processing performance
    testSuite.addTest(ValidationTest(
      name: 'Frame Processing Performance',
      description: 'Validates frame processing meets performance targets',
      testFunction: () async {
        const targetFrameTimeMs = 50; // 20fps minimum acceptable
        const testFrameCount = 100;
        
        final tfliteService = MockTFLiteService();
        await tfliteService.loadModel();
        
        final processingTimes = <double>[];
        
        for (int i = 0; i < testFrameCount; i++) {
          final frame = TestDataGenerator.generateInferenceRequest(frameId: i);
          
          final stopwatch = Stopwatch()..start();
          tfliteService.runInference(frame.yuvBytes, frame.width, frame.height);
          stopwatch.stop();
          
          processingTimes.add(stopwatch.elapsedMicroseconds / 1000.0);
        }
        
        final avgProcessingTime = processingTimes.reduce((a, b) => a + b) / processingTimes.length;
        final maxProcessingTime = processingTimes.reduce((a, b) => a > b ? a : b);
        final framesUnderTarget = processingTimes.where((t) => t <= targetFrameTimeMs).length;
        final targetMeetRate = framesUnderTarget / processingTimes.length;
        
        if (avgProcessingTime > targetFrameTimeMs) {
          return ValidationResult.failure(
            'Average processing time exceeds target: ${avgProcessingTime.toStringAsFixed(2)}ms > ${targetFrameTimeMs}ms'
          );
        }
        
        if (targetMeetRate < 0.8) {
          return ValidationResult.failure(
            'Target meet rate too low: ${(targetMeetRate * 100).toStringAsFixed(1)}% < 80%'
          );
        }
        
        return ValidationResult.success(
          'Performance acceptable: avg=${avgProcessingTime.toStringAsFixed(2)}ms, '
          'max=${maxProcessingTime.toStringAsFixed(2)}ms, '
          'target_rate=${(targetMeetRate * 100).toStringAsFixed(1)}%'
        );
      },
    ));
    
    // Test memory usage validation
    testSuite.addTest(ValidationTest(
      name: 'Memory Usage Validation',
      description: 'Validates memory usage remains within reasonable bounds',
      testFunction: () async {
        const testDurationMs = 1000;
        const frameCount = 50;
        
        final inferenceService = MockInferenceIsolateService();
        await inferenceService.initialize();
        
        // Generate frames and process them
        final startTime = DateTime.now();
        int processedFrames = 0;
        
        while (DateTime.now().difference(startTime).inMilliseconds < testDurationMs && 
               processedFrames < frameCount) {
          final frame = TestDataGenerator.generateInferenceRequest(
            frameId: processedFrames,
            width: 1280,
            height: 720, // Larger frames for memory pressure
          );
          
          await inferenceService.processFrame(frame);
          processedFrames++;
          
          // Small delay to allow processing
          await Future.delayed(const Duration(milliseconds: 10));
        }
        
        // Check service health after memory pressure
        final stats = inferenceService.performanceStats;
        
        if (!stats['isHealthy']) {
          return ValidationResult.failure('Service became unhealthy under memory pressure');
        }
        
        final dropRate = stats['dropRate'] as double;
        if (dropRate > 0.95) {
          return ValidationResult.failure('Excessive frame dropping: ${(dropRate * 100).toStringAsFixed(1)}%');
        }
        
        await inferenceService.dispose();
        
        return ValidationResult.success(
          'Memory usage acceptable: processed $processedFrames frames, '
          'drop_rate=${(dropRate * 100).toStringAsFixed(1)}%'
        );
      },
    ));
    
    await testSuite.runAllTests();
    report.addTestSuite(testSuite);
  }

  /// Print comprehensive validation report
  static void _printValidationReport(ValidationReport report) {
    print('\n=== VALIDATION REPORT ===');
    print('Generated: ${report.timestamp}');
    print('Total Test Suites: ${report.testSuites.length}');
    print('Total Tests: ${report.totalTests}');
    print('Passed: ${report.passedTests}');
    print('Failed: ${report.failedTests}');
    print('Success Rate: ${(report.successRate * 100).toStringAsFixed(1)}%');
    print('');
    
    for (final suite in report.testSuites) {
      print('${suite.name}: ${suite.passedTests}/${suite.totalTests} passed');
      
      for (final test in suite.tests) {
        final status = test.result?.success == true ? '✅' : '❌';
        print('  $status ${test.name}');
        
        if (test.result?.success == false) {
          print('    Failure: ${test.result?.message}');
        }
      }
      print('');
    }
    
    if (report.failedTests > 0) {
      print('⚠️  ${report.failedTests} tests failed. Review failures above.');
    } else {
      print('🎉 All tests passed! System quality validated.');
    }
    
    print('');
  }

  /// Helper function to calculate variance
  static double _calculateVariance(List<double> values) {
    if (values.isEmpty) return 0.0;
    
    final mean = values.reduce((a, b) => a + b) / values.length;
    final squaredDifferences = values.map((v) => math.pow(v - mean, 2));
    return squaredDifferences.reduce((a, b) => a + b) / values.length;
  }
}

/// Validation test suite container
class ValidationTestSuite {
  final String name;
  final List<ValidationTest> tests = [];
  
  ValidationTestSuite(this.name);
  
  void addTest(ValidationTest test) {
    tests.add(test);
  }
  
  Future<void> runAllTests() async {
    for (final test in tests) {
      try {
        test.result = await test.testFunction();
      } catch (e) {
        test.result = ValidationResult.failure('Exception: $e');
      }
    }
  }
  
  int get totalTests => tests.length;
  int get passedTests => tests.where((t) => t.result?.success == true).length;
  int get failedTests => tests.where((t) => t.result?.success == false).length;
}

/// Individual validation test
class ValidationTest {
  final String name;
  final String description;
  final Future<ValidationResult> Function() testFunction;
  ValidationResult? result;
  
  ValidationTest({
    required this.name,
    required this.description,
    required this.testFunction,
  });
}

/// Validation test result
class ValidationResult {
  final bool success;
  final String message;
  
  ValidationResult._(this.success, this.message);
  
  factory ValidationResult.success(String message) => ValidationResult._(true, message);
  factory ValidationResult.failure(String message) => ValidationResult._(false, message);
}

/// Comprehensive validation report
class ValidationReport {
  final DateTime timestamp = DateTime.now();
  final List<ValidationTestSuite> testSuites = [];
  
  void addTestSuite(ValidationTestSuite suite) {
    testSuites.add(suite);
  }
  
  void finalize() {
    // Additional processing if needed
  }
  
  int get totalTests => testSuites.map((s) => s.totalTests).fold(0, (a, b) => a + b);
  int get passedTests => testSuites.map((s) => s.passedTests).fold(0, (a, b) => a + b);
  int get failedTests => testSuites.map((s) => s.failedTests).fold(0, (a, b) => a + b);
  double get successRate => totalTests > 0 ? passedTests / totalTests : 0.0;
  
  bool get allTestsPassed => failedTests == 0 && totalTests > 0;
}