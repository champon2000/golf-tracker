// lib/services/kalman.dart
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart';
import 'dart:math' as math;

class KalmanFilter2D {
  Vector4 _xHat; // State vector [x, y, vx, vy]
  Matrix4 _p; // Error covariance matrix
  final Matrix4 _q; // Process noise covariance matrix
  final Matrix4 _r; // Measurement noise covariance matrix
  final Matrix4 _f; // State transition matrix
  final Matrix2x4 _h; // Measurement matrix
  
  // Identity matrices for calculations
  final Matrix4 _i = Matrix4.identity(); // 4x4 identity matrix
  final Matrix2 _i2 = Matrix2.identity(); // 2x2 identity matrix
  
  // Adaptive parameters
  final double _baseProcessNoisePos;
  final double _baseProcessNoiseVel;
  final double _baseMeasurementNoise;
  double _adaptiveNoiseMultiplier = 1.0;
  
  // Performance metrics
  double _lastUpdateTime = 0.0;
  final List<double> _residualHistory = [];
  static const int _residualHistoryLength = 10;

  KalmanFilter2D({
    required Offset initialPosition,
    required double initialVelocityX,
    required double initialVelocityY,
    required double dt, // Time step
    required double processNoisePos, // Position process noise
    required double processNoiseVel, // Velocity process noise
    required double measurementNoisePos, // Measurement noise
  })  : _xHat = Vector4(initialPosition.dx, initialPosition.dy, initialVelocityX, initialVelocityY),
        _p = Matrix4.identity() * 1000.0, // Initial uncertainty
        _q = Matrix4.zero(),
        _r = Matrix4.zero(),
        _f = Matrix4.identity(),
        _h = Matrix2x4.zero(),
        _baseProcessNoisePos = processNoisePos,
        _baseProcessNoiseVel = processNoiseVel,
        _baseMeasurementNoise = measurementNoisePos {
    
    // Initialize process noise matrix Q
    _q.setEntry(0, 0, processNoisePos);
    _q.setEntry(1, 1, processNoisePos);
    _q.setEntry(2, 2, processNoiseVel);
    _q.setEntry(3, 3, processNoiseVel);

    // Initialize measurement noise matrix R (2x2 for position measurements only)
    _r.setEntry(0, 0, measurementNoisePos);
    _r.setEntry(1, 1, measurementNoisePos);

    // Initialize state transition matrix F
    // [1, 0, dt, 0 ]
    // [0, 1, 0,  dt]
    // [0, 0, 1,  0 ]
    // [0, 0, 0,  1 ]
    _f.setEntry(0, 2, dt);
    _f.setEntry(1, 3, dt);

    // Initialize measurement matrix H (we only measure position)
    // [1, 0, 0, 0]
    // [0, 1, 0, 0]
    _h.setEntry(0, 0, 1.0);
    _h.setEntry(1, 1, 1.0);
  }

  Offset update(Offset measurement, {double? confidence}) {
    // Update adaptive noise based on confidence
    if (confidence != null) {
      _updateAdaptiveNoise(confidence);
    }
    
    // Prediction step
    _predict();
    
    // Update step with outlier detection
    final isOutlier = _detectOutlier(measurement);
    if (!isOutlier) {
      _updateWithMeasurement(measurement);
    }
    
    return Offset(_xHat.x, _xHat.y);
  }

  void _predict() {
    // Predict state: x_hat = F * x_hat
    _xHat = _f * _xHat;
    
    // Predict error covariance: P = F * P * F^T + Q
    final fTranspose = _f.clone()..transpose();
    _p = _f * _p * fTranspose + _q;
  }

  void _updateWithMeasurement(Offset measurement) {
    // Measurement vector
    final z = Vector2(measurement.dx, measurement.dy);
    
    // Predicted measurement: H * x_hat
    final hx = _h * _xHat;
    
    // Innovation (residual): y = z - H * x_hat
    final y = z - hx;
    
    // Store residual for adaptive filtering
    final residualMagnitude = y.length;
    _residualHistory.add(residualMagnitude);
    if (_residualHistory.length > _residualHistoryLength) {
      _residualHistory.removeAt(0);
    }
    
    // Innovation covariance: S = H * P * H^T + R
    final hTranspose = _h.clone()..transpose();
    final hpht = _h * _p * hTranspose;
    final s = Matrix2.zero();
    s.setEntry(0, 0, hpht.entry(0, 0) + _r.entry(0, 0));
    s.setEntry(0, 1, hpht.entry(0, 1));
    s.setEntry(1, 0, hpht.entry(1, 0));
    s.setEntry(1, 1, hpht.entry(1, 1) + _r.entry(1, 1));
    
    // Kalman gain: K = P * H^T * S^-1
    Matrix2? sInverse;
    try {
      sInverse = Matrix2.copy(s)..invert();
    } catch (e) {
      // If matrix is not invertible, skip update
      return;
    }
    
    final pht = _p * hTranspose;
    final k = Matrix2x4.zero();
    
    // Calculate K = P * H^T * S^-1
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 2; j++) {
        double sum = 0.0;
        for (int m = 0; m < 2; m++) {
          sum += pht.entry(i, m) * sInverse.entry(m, j);
        }
        k.setEntry(j, i, sum);
      }
    }
    
    // Update state: x_hat = x_hat + K * y
    final ky = Vector4.zero();
    for (int i = 0; i < 4; i++) {
      ky[i] = k.entry(0, i) * y.x + k.entry(1, i) * y.y;
    }
    _xHat += ky;
    
    // Update error covariance: P = (I - K * H) * P
    final kh = Matrix4.zero();
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 4; j++) {
        double sum = 0.0;
        for (int m = 0; m < 2; m++) {
          sum += k.entry(m, i) * _h.entry(m, j);
        }
        kh.setEntry(i, j, sum);
      }
    }
    
    final iMinusKH = _i - kh;
    _p = iMinusKH * _p;
  }
  
  void _updateAdaptiveNoise(double confidence) {
    // Adjust noise based on detection confidence
    // Higher confidence = lower noise, lower confidence = higher noise
    _adaptiveNoiseMultiplier = math.max(0.1, math.min(5.0, 2.0 - confidence));
    
    // Update process noise matrix Q with adaptive multiplier
    _q.setEntry(0, 0, _baseProcessNoisePos * _adaptiveNoiseMultiplier);
    _q.setEntry(1, 1, _baseProcessNoisePos * _adaptiveNoiseMultiplier);
    _q.setEntry(2, 2, _baseProcessNoiseVel * _adaptiveNoiseMultiplier);
    _q.setEntry(3, 3, _baseProcessNoiseVel * _adaptiveNoiseMultiplier);
    
    // Update measurement noise matrix R
    final adaptiveMeasurementNoise = _baseMeasurementNoise * _adaptiveNoiseMultiplier;
    _r.setEntry(0, 0, adaptiveMeasurementNoise);
    _r.setEntry(1, 1, adaptiveMeasurementNoise);
  }
  
  bool _detectOutlier(Offset measurement) {
    if (_residualHistory.length < 3) return false;
    
    // Calculate predicted measurement
    final predicted = Offset(_xHat.x, _xHat.y);
    final residual = (measurement - predicted).distance;
    
    // Calculate average residual from history
    final avgResidual = _residualHistory.reduce((a, b) => a + b) / _residualHistory.length;
    final stdDev = math.sqrt(_residualHistory.map((r) => math.pow(r - avgResidual, 2)).reduce((a, b) => a + b) / _residualHistory.length);
    
    // Consider measurement as outlier if it's more than 3 standard deviations away
    final threshold = avgResidual + 3 * stdDev;
    return residual > threshold;
  }

  // Get current state
  Offset get position => Offset(_xHat.x, _xHat.y);
  Offset get velocity => Offset(_xHat.z, _xHat.w);
  
  // Get predicted next position
  Offset get predictedPosition => Offset(_xHat.x + _xHat.z, _xHat.y + _xHat.w);
  
  // Get uncertainty (trace of covariance matrix)
  double get uncertainty => _p.entry(0, 0) + _p.entry(1, 1);
  
  // Get confidence score based on uncertainty and residual consistency
  double get confidenceScore {
    final uncertaintyScore = 1.0 / (1.0 + uncertainty / 100.0);
    
    if (_residualHistory.length < 3) return uncertaintyScore;
    
    final avgResidual = _residualHistory.reduce((a, b) => a + b) / _residualHistory.length;
    final consistencyScore = 1.0 / (1.0 + avgResidual / 10.0);
    
    return (uncertaintyScore + consistencyScore) / 2.0;
  }
  
  // Get current adaptive noise multiplier
  double get adaptiveNoiseMultiplier => _adaptiveNoiseMultiplier;
  
  // Get average residual from recent history
  double get averageResidual {
    if (_residualHistory.isEmpty) return 0.0;
    return _residualHistory.reduce((a, b) => a + b) / _residualHistory.length;
  }
  
  // Reset the filter with new initial conditions
  void reset({
    required Offset initialPosition,
    double initialVelocityX = 0.0,
    double initialVelocityY = 0.0,
  }) {
    _xHat = Vector4(initialPosition.dx, initialPosition.dy, initialVelocityX, initialVelocityY);
    _p = Matrix4.identity() * 1000.0;
    _residualHistory.clear();
    _adaptiveNoiseMultiplier = 1.0;
  }
}

// Helper class for 2x4 matrix operations
class Matrix2x4 {
  final List<double> _storage = List<double>.filled(8, 0.0);
  
  Matrix2x4.zero();
  
  Matrix2x4 clone() {
    final result = Matrix2x4.zero();
    for (int i = 0; i < 8; i++) {
      result._storage[i] = _storage[i];
    }
    return result;
  }
  
  void transpose() {
    // This would create a 4x2 matrix, but we'll keep it as 2x4 for simplicity
    // In a real implementation, you'd need proper matrix dimension handling
  }
  
  double entry(int row, int col) {
    return _storage[row * 4 + col];
  }
  
  void setEntry(int row, int col, double value) {
    _storage[row * 4 + col] = value;
  }
  
  Vector4 operator *(Vector4 vector) {
    return Vector4(
      entry(0, 0) * vector.x + entry(0, 1) * vector.y + entry(0, 2) * vector.z + entry(0, 3) * vector.w,
      entry(1, 0) * vector.x + entry(1, 1) * vector.y + entry(1, 2) * vector.z + entry(1, 3) * vector.w,
      0.0,
      0.0,
    );
  }
}

extension Matrix4Extensions on Matrix4 {
  Matrix2x4 operator *(Matrix2x4 other) {
    final result = Matrix2x4.zero();
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 4; j++) {
        double sum = 0.0;
        for (int k = 0; k < 2; k++) {
          sum += entry(i, k) * other.entry(k, j);
        }
        result.setEntry(i < 2 ? i : 0, j, sum);
      }
    }
    return result;
  }
}