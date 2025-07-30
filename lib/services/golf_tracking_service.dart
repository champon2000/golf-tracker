// lib/services/golf_tracking_service.dart
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:golf_tracker/services/inference_isolate_service.dart';
import 'package:golf_tracker/services/tflite_service_enhanced.dart';

/// Golf tracking event types
enum GolfTrackingEvent {
  ballDetected,
  clubDetected,
  impactDetected,
  ballInFlight,
  ballLanded,
  trackingComplete,
}

/// Golf shot data structure
class GolfShotData {
  final DateTime timestamp;
  final double ballSpeed; // m/s
  final double launchAngle; // degrees
  final double carryDistance; // meters (estimated)
  final List<Offset> ballTrajectory;
  final Duration trackingDuration;
  final Map<String, dynamic> metadata;

  GolfShotData({
    required this.timestamp,
    required this.ballSpeed,
    required this.launchAngle,
    required this.carryDistance,
    required this.ballTrajectory,
    required this.trackingDuration,
    this.metadata = const {},
  });

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'ballSpeed': ballSpeed,
      'launchAngle': launchAngle,
      'carryDistance': carryDistance,
      'ballTrajectory': ballTrajectory.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
      'trackingDuration': trackingDuration.inMilliseconds,
      'metadata': metadata,
    };
  }
}

/// Comprehensive golf tracking service
class GolfTrackingService {
  final InferenceIsolateService _inferenceService;
  final StreamController<GolfTrackingEvent> _eventController;
  final StreamController<GolfShotData> _shotDataController;
  
  // Tracking state
  bool _isTracking = false;
  bool _impactDetected = false;
  DateTime? _trackingStartTime;
  DateTime? _impactTime;
  
  // Ball tracking data
  final List<Offset> _ballTrajectory = [];
  final List<double> _ballSpeeds = [];
  double _maxBallSpeed = 0.0;
  double _launchAngle = 0.0;
  
  // Club tracking data
  Offset? _lastClubPosition;
  bool _clubNearBall = false;
  
  // Configuration
  static const double IMPACT_DETECTION_DISTANCE = 50.0; // pixels
  static const double MIN_BALL_SPEED_FOR_FLIGHT = 10.0; // pixels/frame
  static const int MIN_TRAJECTORY_POINTS = 5;
  static const Duration MAX_TRACKING_DURATION = Duration(seconds: 10);
  
  // Performance monitoring
  int _framesProcessed = 0;
  int _ballDetections = 0;
  int _clubDetections = 0;
  
  /// Stream of tracking events
  Stream<GolfTrackingEvent> get events => _eventController.stream;
  
  /// Stream of completed shot data
  Stream<GolfShotData> get shotData => _shotDataController.stream;
  
  /// Current tracking status
  bool get isTracking => _isTracking;
  
  /// Performance statistics
  Map<String, dynamic> get performanceStats => {
    'framesProcessed': _framesProcessed,
    'ballDetections': _ballDetections,
    'clubDetections': _clubDetections,
    'ballDetectionRate': _framesProcessed > 0 ? _ballDetections / _framesProcessed : 0.0,
    'clubDetectionRate': _framesProcessed > 0 ? _clubDetections / _framesProcessed : 0.0,
    'isTracking': _isTracking,
    'impactDetected': _impactDetected,
    'trajectoryPoints': _ballTrajectory.length,
    'maxBallSpeed': _maxBallSpeed,
    'launchAngle': _launchAngle,
  };

  GolfTrackingService() 
    : _inferenceService = InferenceIsolateService(),
      _eventController = StreamController<GolfTrackingEvent>.broadcast(),
      _shotDataController = StreamController<GolfShotData>.broadcast() {
    
    // Listen to inference results
    _inferenceService.results.listen(_processInferenceResult);
  }

  /// Initialize the golf tracking service
  Future<bool> initialize() async {
    try {
      final success = await _inferenceService.initialize();
      if (success) {
        print('Golf tracking service initialized successfully');
      }
      return success;
    } catch (e) {
      print('Failed to initialize golf tracking service: $e');
      return false;
    }
  }

  /// Start tracking a golf shot
  void startTracking() {
    if (_isTracking) return;
    
    print('Starting golf shot tracking...');
    _isTracking = true;
    _impactDetected = false;
    _trackingStartTime = DateTime.now();
    _impactTime = null;
    
    // Clear previous tracking data
    _ballTrajectory.clear();
    _ballSpeeds.clear();
    _maxBallSpeed = 0.0;
    _launchAngle = 0.0;
    _lastClubPosition = null;
    _clubNearBall = false;
    
    _eventController.add(GolfTrackingEvent.ballDetected);
  }

  /// Stop tracking
  void stopTracking() {
    if (!_isTracking) return;
    
    print('Stopping golf shot tracking...');
    _isTracking = false;
    
    // Generate shot data if we have enough information
    if (_ballTrajectory.length >= MIN_TRAJECTORY_POINTS && _impactDetected) {
      _generateShotData();
    }
    
    _eventController.add(GolfTrackingEvent.trackingComplete);
  }

  /// Process a camera frame
  Future<void> processFrame(Uint8List yuvBytes, int width, int height, 
                           {int? bytesPerRow, int? uvBytesPerRow}) async {
    if (!_isTracking) return;
    
    // Check for tracking timeout
    if (_trackingStartTime != null) {
      final elapsed = DateTime.now().difference(_trackingStartTime!);
      if (elapsed > MAX_TRACKING_DURATION) {
        print('Tracking timeout reached, stopping...');
        stopTracking();
        return;
      }
    }
    
    // Create inference request
    final request = InferenceRequest(
      yuvBytes: yuvBytes,
      width: width,
      height: height,
      bytesPerRow: bytesPerRow ?? width,
      uvBytesPerRow: uvBytesPerRow ?? width,
      frameId: _framesProcessed,
      timestamp: DateTime.now(),
    );
    
    // Send to inference service
    await _inferenceService.processFrame(request);
  }

  /// Process inference results
  void _processInferenceResult(InferenceResult result) {
    if (!_isTracking) return;
    
    _framesProcessed++;
    
    // Extract ball and club positions
    Offset? ballPosition;
    Offset? clubPosition;
    
    for (final detection in result.detections) {
      if (detection.className == 'ball' && detection.confidence > 0.5) {
        ballPosition = detection.center;
        _ballDetections++;
      } else if (detection.className == 'club_head' && detection.confidence > 0.3) {
        clubPosition = detection.center;
        _clubDetections++;
      }
    }
    
    // Use predicted ball position if available
    if (result.predictedBallCenter != null) {
      ballPosition = result.predictedBallCenter;
    }
    
    // Update ball tracking
    if (ballPosition != null) {
      _updateBallTracking(ballPosition, result.ballSpeed, result.launchAngle);
    }
    
    // Update club tracking
    if (clubPosition != null) {
      _updateClubTracking(clubPosition, ballPosition);
    }
    
    // Check for impact detection
    if (!_impactDetected && ballPosition != null && clubPosition != null) {
      _checkForImpact(ballPosition, clubPosition, result.timestamp);
    }
    
    // Check for ball landing or tracking completion
    _checkTrackingCompletion(ballPosition, result.ballSpeed);
  }

  /// Update ball tracking data
  void _updateBallTracking(Offset ballPosition, double ballSpeed, double launchAngle) {
    _ballTrajectory.add(ballPosition);
    _ballSpeeds.add(ballSpeed);
    
    // Update maximum speed
    if (ballSpeed > _maxBallSpeed) {
      _maxBallSpeed = ballSpeed;
    }
    
    // Update launch angle (take the angle from early in the trajectory)
    if (_ballTrajectory.length <= 5 && launchAngle != 0.0) {
      _launchAngle = launchAngle;
    }
    
    // Emit ball in flight event if speed is high enough
    if (ballSpeed > MIN_BALL_SPEED_FOR_FLIGHT && _impactDetected) {
      _eventController.add(GolfTrackingEvent.ballInFlight);
    }
  }

  /// Update club tracking data
  void _updateClubTracking(Offset clubPosition, Offset? ballPosition) {
    _lastClubPosition = clubPosition;
    
    // Check if club is near ball
    if (ballPosition != null) {
      final distance = (clubPosition - ballPosition).distance;
      _clubNearBall = distance < IMPACT_DETECTION_DISTANCE;
      
      if (_clubNearBall) {
        _eventController.add(GolfTrackingEvent.clubDetected);
      }
    }
  }

  /// Check for impact detection
  void _checkForImpact(Offset ballPosition, Offset clubPosition, DateTime timestamp) {
    final distance = (clubPosition - ballPosition).distance;
    
    // Impact detected if club is very close to ball and moving
    if (distance < IMPACT_DETECTION_DISTANCE / 2) {
      _impactDetected = true;
      _impactTime = timestamp;
      
      print('Impact detected! Distance: ${distance.toStringAsFixed(1)} pixels');
      _eventController.add(GolfTrackingEvent.impactDetected);
    }
  }

  /// Check if tracking should be completed
  void _checkTrackingCompletion(Offset? ballPosition, double ballSpeed) {
    // Stop tracking if ball speed drops significantly after impact
    if (_impactDetected && ballSpeed < MIN_BALL_SPEED_FOR_FLIGHT / 2) {
      if (_ballTrajectory.length >= MIN_TRAJECTORY_POINTS) {
        print('Ball appears to have landed, completing tracking...');
        _eventController.add(GolfTrackingEvent.ballLanded);
        stopTracking();
      }
    }
    
    // Stop tracking if no ball detected for a while after impact
    if (_impactDetected && ballPosition == null) {
      final recentTrajectory = _ballTrajectory.skip(
        (_ballTrajectory.length - 10).clamp(0, _ballTrajectory.length)
      ).toList();
      
      if (recentTrajectory.isEmpty) {
        print('Ball lost after impact, completing tracking...');
        stopTracking();
      }
    }
  }

  /// Generate shot data from collected tracking information
  void _generateShotData() {
    if (_trackingStartTime == null || _ballTrajectory.isEmpty) return;
    
    final now = DateTime.now();
    final trackingDuration = now.difference(_trackingStartTime!);
    
    // Convert pixel-based speed to real-world units (rough estimation)
    // This would need calibration based on camera setup and field of view
    final realWorldSpeedMps = _convertPixelSpeedToRealWorld(_maxBallSpeed);
    
    // Estimate carry distance based on ball speed and launch angle
    final carryDistance = _estimateCarryDistance(realWorldSpeedMps, _launchAngle);
    
    final shotData = GolfShotData(
      timestamp: _trackingStartTime!,
      ballSpeed: realWorldSpeedMps,
      launchAngle: _launchAngle,
      carryDistance: carryDistance,
      ballTrajectory: List.from(_ballTrajectory),
      trackingDuration: trackingDuration,
      metadata: {
        'impactTime': _impactTime?.toIso8601String(),
        'pixelSpeed': _maxBallSpeed,
        'trajectoryPoints': _ballTrajectory.length,
        'framesProcessed': _framesProcessed,
        'ballDetections': _ballDetections,
        'clubDetections': _clubDetections,
      },
    );
    
    print('Generated shot data: ${shotData.ballSpeed.toStringAsFixed(1)} m/s, '
          '${shotData.launchAngle.toStringAsFixed(1)}°, '
          '${shotData.carryDistance.toStringAsFixed(1)}m');
    
    _shotDataController.add(shotData);
  }

  /// Convert pixel-based speed to real-world speed (rough estimation)
  double _convertPixelSpeedToRealWorld(double pixelsPerSecond) {
    // This is a rough conversion that would need calibration
    // Assuming: 1 meter ≈ 100 pixels at typical golf shot distance
    const double pixelsPerMeter = 100.0;
    return pixelsPerSecond / pixelsPerMeter;
  }

  /// Estimate carry distance using simple ballistics
  double _estimateCarryDistance(double speedMps, double launchAngleDegrees) {
    if (speedMps <= 0) return 0.0;
    
    const double gravity = 9.81; // m/s²
    final double launchAngleRad = launchAngleDegrees * (3.14159 / 180.0);
    
    // Simple projectile motion formula (ignoring air resistance)
    final double range = (speedMps * speedMps * (2 * launchAngleRad).sin()) / gravity;
    
    return range.clamp(0.0, 300.0); // Reasonable bounds for golf shots
  }

  /// Get comprehensive performance report
  Map<String, dynamic> getPerformanceReport() {
    final trackingStats = performanceStats;
    final inferenceStats = _inferenceService.performanceStats;
    
    return {
      'tracking': trackingStats,
      'inference': inferenceStats,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  /// Dispose of the service
  Future<void> dispose() async {
    print('Disposing golf tracking service...');
    
    await _eventController.close();
    await _shotDataController.close();
    await _inferenceService.dispose();
    
    print('Golf tracking service disposed');
  }
}