// test/unit/kalman_filter_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:golf_tracker/services/kalman.dart';
import '../helpers/test_data_generator.dart';

void main() {
  group('KalmanFilter2D', () {
    late KalmanFilter2D kalmanFilter;
    
    setUp(() {
      kalmanFilter = KalmanFilter2D(
        initialPosition: const Offset(100, 100),
        initialVelocityX: 10.0,
        initialVelocityY: -5.0,
        dt: 1.0 / 30.0, // 30 FPS
        processNoisePos: 0.1,
        processNoiseVel: 0.01,
        measurementNoisePos: 1.0,
      );
    });

    group('Initialization', () {
      test('should initialize with correct initial values', () {
        expect(kalmanFilter.position, const Offset(100, 100));
        expect(kalmanFilter.velocity.dx, 10.0);
        expect(kalmanFilter.velocity.dy, -5.0);
        expect(kalmanFilter.uncertainty, greaterThan(0));
        expect(kalmanFilter.confidenceScore, inRange(0.0, 1.0));
      });

      test('should have reasonable initial uncertainty', () {
        // Initial uncertainty should be high (filter not yet converged)
        expect(kalmanFilter.uncertainty, greaterThan(100));
      });
    });

    group('Basic Tracking', () {
      test('should update position with single measurement', () {
        final measurement = const Offset(110, 95);
        final result = kalmanFilter.update(measurement);
        
        // Result should be between initial position and measurement
        expect(result.dx, inRange(100, 110));
        expect(result.dy, inRange(95, 100));
        
        // Position should be updated
        expect(kalmanFilter.position, result);
      });

      test('should track linear motion accurately', () {
        final linearMotion = TestDataGenerator.generateMotionPattern('linear', 20);
        final results = <Offset>[];
        
        for (final measurement in linearMotion) {
          final result = kalmanFilter.update(measurement);
          results.add(result);
        }
        
        // Filter should converge to follow the linear motion
        expect(results.length, linearMotion.length);
        
        // Last few results should be close to measurements
        final lastResults = results.skip(15).toList();
        final lastMeasurements = linearMotion.skip(15).toList();
        
        for (int i = 0; i < lastResults.length; i++) {
          final error = (lastResults[i] - lastMeasurements[i]).distance;
          expect(error, lessThan(10.0)); // Should be within 10 pixels
        }
      });

      test('should handle erratic motion with smoothing', () {
        final erraticMotion = TestDataGenerator.generateMotionPattern('erratic', 50);
        final results = <Offset>[];
        
        for (final measurement in erraticMotion) {
          final result = kalmanFilter.update(measurement);
          results.add(result);
        }
        
        // Calculate smoothness - filtered results should be smoother than measurements
        final measurementVariance = _calculateVariance(erraticMotion);
        final resultVariance = _calculateVariance(results);
        
        expect(resultVariance, lessThan(measurementVariance));
      });
    });

    group('Confidence-based Adaptation', () {
      test('should adjust noise based on confidence', () {
        final initialNoise = kalmanFilter.adaptiveNoiseMultiplier;
        
        // Low confidence should increase noise
        kalmanFilter.update(const Offset(150, 120), confidence: 0.3);
        expect(kalmanFilter.adaptiveNoiseMultiplier, greaterThan(initialNoise));
        
        // High confidence should decrease noise
        kalmanFilter.update(const Offset(160, 115), confidence: 0.9);
        expect(kalmanFilter.adaptiveNoiseMultiplier, lessThan(1.5));
      });

      test('should handle extreme confidence values', () {
        // Test with confidence = 0
        expect(() => kalmanFilter.update(const Offset(100, 100), confidence: 0.0),
               returnsNormally);
        
        // Test with confidence = 1
        expect(() => kalmanFilter.update(const Offset(100, 100), confidence: 1.0),
               returnsNormally);
        
        // Confidence should be clamped to reasonable bounds
        expect(kalmanFilter.adaptiveNoiseMultiplier, inRange(0.1, 5.0));
      });
    });

    group('Outlier Detection', () {
      test('should detect and reject outliers', () {
        // Establish normal tracking pattern
        for (int i = 0; i < 10; i++) {
          kalmanFilter.update(Offset(100 + i * 5, 100 + i * 2));
        }
        
        final beforeOutlier = kalmanFilter.position;
        
        // Inject outlier measurement
        final outlierResult = kalmanFilter.update(const Offset(500, 300));
        
        // Position should not jump dramatically to outlier
        final jumpDistance = (outlierResult - beforeOutlier).distance;
        expect(jumpDistance, lessThan(100)); // Should be limited
      });

      test('should recover from outliers and continue normal tracking', () {
        // Normal tracking
        for (int i = 0; i < 5; i++) {
          kalmanFilter.update(Offset(100 + i * 10, 100));
        }
        
        // Outlier
        kalmanFilter.update(const Offset(1000, 1000));
        
        // Resume normal tracking
        final results = <Offset>[];
        for (int i = 6; i < 15; i++) {
          final result = kalmanFilter.update(Offset(100 + i * 10, 100));
          results.add(result);
        }
        
        // Should converge back to the expected pattern
        final lastResult = results.last;
        final expectedPosition = const Offset(240, 100); // 100 + 14*10
        final error = (lastResult - expectedPosition).distance;
        expect(error, lessThan(20));
      });
    });

    group('Prediction', () {
      test('should provide reasonable position prediction', () {
        // Establish motion pattern
        for (int i = 0; i < 5; i++) {
          kalmanFilter.update(Offset(100 + i * 20, 100 + i * 10));
        }
        
        final currentPos = kalmanFilter.position;
        final predictedPos = kalmanFilter.predictedPosition;
        
        // Prediction should be ahead of current position in motion direction
        expect(predictedPos.dx, greaterThan(currentPos.dx));
        expect(predictedPos.dy, greaterThan(currentPos.dy));
        
        // But not too far ahead
        final predictionDistance = (predictedPos - currentPos).distance;
        expect(predictionDistance, lessThan(50));
      });

      test('should predict stationary object correctly', () {
        final stationaryMotion = TestDataGenerator.generateMotionPattern('stationary', 10);
        
        for (final measurement in stationaryMotion) {
          kalmanFilter.update(measurement);
        }
        
        final currentPos = kalmanFilter.position;
        final predictedPos = kalmanFilter.predictedPosition;
        
        // Prediction should be very close to current position for stationary object
        final predictionError = (predictedPos - currentPos).distance;
        expect(predictionError, lessThan(5));
      });
    });

    group('Performance Metrics', () {
      test('should calculate confidence score correctly', () {
        // New filter should have lower confidence
        final initialConfidence = kalmanFilter.confidenceScore;
        
        // Add measurements to improve confidence
        for (int i = 0; i < 10; i++) {
          kalmanFilter.update(Offset(100 + i * 5, 100));
        }
        
        final improvedConfidence = kalmanFilter.confidenceScore;
        
        expect(improvedConfidence, greaterThan(initialConfidence));
        expect(improvedConfidence, inRange(0.0, 1.0));
      });

      test('should track average residual', () {
        // Perfect measurements should have low residual
        for (int i = 0; i < 5; i++) {
          final perfectMeasurement = kalmanFilter.predictedPosition;
          kalmanFilter.update(perfectMeasurement);
        }
        
        final lowResidual = kalmanFilter.averageResidual;
        
        // Noisy measurements should have higher residual
        kalmanFilter.reset(initialPosition: const Offset(100, 100));
        for (int i = 0; i < 5; i++) {
          final noisyMeasurement = Offset(
            100 + i * 10 + (i % 2 == 0 ? 20 : -20), // Add noise
            100 + i * 5 + (i % 2 == 0 ? 15 : -15),
          );
          kalmanFilter.update(noisyMeasurement);
        }
        
        final highResidual = kalmanFilter.averageResidual;
        
        expect(highResidual, greaterThan(lowResidual));
      });
    });

    group('Reset Functionality', () {
      test('should reset to new initial conditions', () {
        // Use filter for a while
        for (int i = 0; i < 10; i++) {
          kalmanFilter.update(Offset(200 + i * 10, 200 + i * 5));
        }
        
        final beforeReset = kalmanFilter.position;
        
        // Reset with new position
        const newPosition = Offset(50, 300);
        kalmanFilter.reset(
          initialPosition: newPosition,
          initialVelocityX: -5.0,
          initialVelocityY: 10.0,
        );
        
        expect(kalmanFilter.position, newPosition);
        expect(kalmanFilter.velocity.dx, -5.0);
        expect(kalmanFilter.velocity.dy, 10.0);
        expect(kalmanFilter.position, isNot(beforeReset));
        
        // Uncertainty should be high again
        expect(kalmanFilter.uncertainty, greaterThan(100));
      });

      test('should clear residual history on reset', () {
        // Build up residual history
        for (int i = 0; i < 10; i++) {
          kalmanFilter.update(Offset(100 + i * 20, 100));
        }
        
        final beforeReset = kalmanFilter.averageResidual;
        
        kalmanFilter.reset(initialPosition: const Offset(0, 0));
        
        final afterReset = kalmanFilter.averageResidual;
        expect(afterReset, 0.0); // Should be reset
      });
    });

    group('Edge Cases', () {
      test('should handle identical consecutive measurements', () {
        const identicalMeasurement = Offset(150, 200);
        
        for (int i = 0; i < 5; i++) {
          expect(() => kalmanFilter.update(identicalMeasurement), returnsNormally);
        }
        
        // Should converge to the measurement
        final finalPosition = kalmanFilter.position;
        final error = (finalPosition - identicalMeasurement).distance;
        expect(error, lessThan(5));
      });

      test('should handle extreme coordinate values', () {
        const extremeValues = [
          Offset(0, 0),
          Offset(10000, 10000),
          Offset(-1000, -1000),
          Offset(1e6, 1e6),
        ];
        
        for (final measurement in extremeValues) {
          expect(() => kalmanFilter.update(measurement), returnsNormally);
          expect(kalmanFilter.position.dx.isFinite, isTrue);
          expect(kalmanFilter.position.dy.isFinite, isTrue);
        }
      });

      test('should maintain numerical stability', () {
        // Run for many iterations to test numerical stability
        for (int i = 0; i < 1000; i++) {
          final measurement = Offset(100 + i * 0.1, 100 + i * 0.05);
          kalmanFilter.update(measurement);
          
          // Check for NaN or infinite values
          expect(kalmanFilter.position.dx.isFinite, isTrue);
          expect(kalmanFilter.position.dy.isFinite, isTrue);
          expect(kalmanFilter.velocity.dx.isFinite, isTrue);
          expect(kalmanFilter.velocity.dy.isFinite, isTrue);
          expect(kalmanFilter.uncertainty.isFinite, isTrue);
        }
      });
    });

    group('Parabolic Motion Tracking', () {
      test('should track parabolic motion (ball trajectory)', () {
        final parabolicMotion = TestDataGenerator.generateMotionPattern('parabolic', 30);
        final results = <Offset>[];
        
        for (final measurement in parabolicMotion) {
          final result = kalmanFilter.update(measurement);
          results.add(result);
        }
        
        // Should track the parabolic path reasonably well
        final totalError = _calculateTotalTrackingError(results, parabolicMotion);
        final avgError = totalError / results.length;
        
        expect(avgError, lessThan(15.0)); // Average error should be reasonable
      });
    });
  });
}

/// Helper function to calculate variance of position data
double _calculateVariance(List<Offset> positions) {
  if (positions.length < 2) return 0.0;
  
  final meanX = positions.map((p) => p.dx).reduce((a, b) => a + b) / positions.length;
  final meanY = positions.map((p) => p.dy).reduce((a, b) => a + b) / positions.length;
  
  final varianceX = positions.map((p) => (p.dx - meanX) * (p.dx - meanX))
                           .reduce((a, b) => a + b) / positions.length;
  final varianceY = positions.map((p) => (p.dy - meanY) * (p.dy - meanY))
                           .reduce((a, b) => a + b) / positions.length;
  
  return varianceX + varianceY;
}

/// Helper function to calculate total tracking error
double _calculateTotalTrackingError(List<Offset> tracked, List<Offset> actual) {
  double totalError = 0.0;
  final minLength = tracked.length < actual.length ? tracked.length : actual.length;
  
  for (int i = 0; i < minLength; i++) {
    totalError += (tracked[i] - actual[i]).distance;
  }
  
  return totalError;
}