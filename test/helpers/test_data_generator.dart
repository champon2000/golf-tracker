// test/helpers/test_data_generator.dart
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:faker/faker.dart';
import 'package:golf_tracker/models/bounding_box.dart';
import 'package:golf_tracker/services/golf_tracking_service.dart';
import 'package:golf_tracker/services/inference_isolate_service.dart';

/// Test data generator for golf tracker testing
class TestDataGenerator {
  static final _random = math.Random();
  static final _faker = Faker();

  /// Generate realistic golf shot data
  static GolfShotData generateGolfShotData({
    DateTime? timestamp,
    double? ballSpeed,
    double? launchAngle,
    double? carryDistance,
    int trajectoryPoints = 50,
  }) {
    timestamp ??= _faker.date.dateTime(minYear: 2023, maxYear: 2024);
    ballSpeed ??= _generateRealisticBallSpeed();
    launchAngle ??= _generateRealisticLaunchAngle();
    carryDistance ??= _estimateCarryDistance(ballSpeed, launchAngle);

    final trajectory = _generateBallTrajectory(
      trajectoryPoints,
      ballSpeed,
      launchAngle,
      carryDistance,
    );

    return GolfShotData(
      timestamp: timestamp,
      ballSpeed: ballSpeed,
      launchAngle: launchAngle,
      carryDistance: carryDistance,
      ballTrajectory: trajectory,
      trackingDuration: Duration(
        milliseconds: 3000 + _random.nextInt(2000),
      ),
      metadata: _generateShotMetadata(),
    );
  }

  /// Generate realistic ball speed (m/s)
  static double _generateRealisticBallSpeed() {
    // Professional golfers: 40-80 m/s, amateur: 25-50 m/s
    return 25.0 + _random.nextDouble() * 55.0;
  }

  /// Generate realistic launch angle (degrees)
  static double _generateRealisticLaunchAngle() {
    // Typical launch angles: 5-25 degrees
    return 5.0 + _random.nextDouble() * 20.0;
  }

  /// Estimate carry distance based on speed and angle
  static double _estimateCarryDistance(double speedMps, double launchAngleDegrees) {
    const double gravity = 9.81;
    final double launchAngleRad = launchAngleDegrees * (math.pi / 180.0);
    
    // Simple projectile motion (ignoring air resistance)
    final double range = (speedMps * speedMps * math.sin(2 * launchAngleRad)) / gravity;
    
    // Add some variation and realistic bounds
    final variation = 0.9 + _random.nextDouble() * 0.2; // ±10% variation
    return (range * variation).clamp(50.0, 300.0);
  }

  /// Generate realistic ball trajectory
  static List<Offset> _generateBallTrajectory(
    int points,
    double ballSpeed,
    double launchAngle,
    double carryDistance,
  ) {
    final trajectory = <Offset>[];
    final startX = 100.0 + _random.nextDouble() * 200.0; // Screen coordinates
    final startY = 400.0 + _random.nextDouble() * 100.0;
    
    final angleRad = launchAngle * (math.pi / 180.0);
    final timeTotal = 2.0 + _random.nextDouble() * 3.0; // Flight time in seconds
    
    for (int i = 0; i < points; i++) {
      final t = (i / (points - 1)) * timeTotal;
      
      // Projectile motion with some noise
      final x = startX + (ballSpeed * math.cos(angleRad) * t * 10); // Scale for screen
      final y = startY - (ballSpeed * math.sin(angleRad) * t * 10) + (0.5 * 9.81 * t * t * 10);
      
      // Add realistic noise to trajectory
      final noiseX = (_random.nextDouble() - 0.5) * 5.0;
      final noiseY = (_random.nextDouble() - 0.5) * 5.0;
      
      trajectory.add(Offset(x + noiseX, y + noiseY));
    }
    
    return trajectory;
  }

  /// Generate shot metadata
  static Map<String, dynamic> _generateShotMetadata() {
    return {
      'impactTime': _faker.date.dateTime().toIso8601String(),
      'pixelSpeed': 50.0 + _random.nextDouble() * 200.0,
      'trajectoryPoints': 40 + _random.nextInt(60),
      'framesProcessed': 200 + _random.nextInt(300),
      'ballDetections': 150 + _random.nextInt(200),
      'clubDetections': 50 + _random.nextInt(100),
      'weather': _faker.randomGenerator.element(['sunny', 'cloudy', 'windy']),
      'clubType': _faker.randomGenerator.element(['driver', '7-iron', 'pitching wedge']),
    };
  }

  /// Generate bounding box detections
  static List<BoundingBox> generateDetections({
    int ballCount = 1,
    int clubCount = 1,
    double minConfidence = 0.3,
    double maxConfidence = 0.95,
  }) {
    final detections = <BoundingBox>[];
    
    // Generate ball detections
    for (int i = 0; i < ballCount; i++) {
      detections.add(BoundingBox(
        x: 100.0 + _random.nextDouble() * 500.0,
        y: 100.0 + _random.nextDouble() * 400.0,
        width: 15.0 + _random.nextDouble() * 25.0,
        height: 15.0 + _random.nextDouble() * 25.0,
        confidence: minConfidence + _random.nextDouble() * (maxConfidence - minConfidence),
        className: 'ball',
      ));
    }
    
    // Generate club head detections
    for (int i = 0; i < clubCount; i++) {
      detections.add(BoundingBox(
        x: 150.0 + _random.nextDouble() * 400.0,
        y: 200.0 + _random.nextDouble() * 300.0,
        width: 30.0 + _random.nextDouble() * 40.0,
        height: 20.0 + _random.nextDouble() * 30.0,
        confidence: minConfidence + _random.nextDouble() * (maxConfidence - minConfidence),
        className: 'club_head',
      ));
    }
    
    return detections;
  }

  /// Generate inference request
  static InferenceRequest generateInferenceRequest({
    int width = 640,
    int height = 480,
    int frameId = 0,
  }) {
    // Generate dummy YUV data
    final yuvSize = (width * height * 1.5).round();
    final yuvBytes = Uint8List(yuvSize);
    
    // Fill with realistic YUV values
    for (int i = 0; i < yuvSize; i++) {
      yuvBytes[i] = 64 + _random.nextInt(128); // YUV range
    }
    
    return InferenceRequest(
      yuvBytes: yuvBytes,
      width: width,
      height: height,
      bytesPerRow: width,
      uvBytesPerRow: width,
      frameId: frameId,
      timestamp: DateTime.now(),
    );
  }

  /// Generate inference result
  static InferenceResult generateInferenceResult({
    int frameId = 0,
    int detectionCount = 2,
    bool includeBallCenter = true,
    bool includeClubCenter = true,
  }) {
    final detections = generateDetections(
      ballCount: includeBallCenter ? 1 : 0,
      clubCount: includeClubCenter ? 1 : 0,
    );
    
    Offset? ballCenter;
    Offset? clubHeadCenter;
    
    if (includeBallCenter && detections.isNotEmpty) {
      final ballDetection = detections.firstWhere(
        (d) => d.className == 'ball',
        orElse: () => detections.first,
      );
      ballCenter = ballDetection.center;
    }
    
    if (includeClubCenter && detections.length > 1) {
      final clubDetection = detections.firstWhere(
        (d) => d.className == 'club_head',
        orElse: () => detections.last,
      );
      clubHeadCenter = clubDetection.center;
    }
    
    return InferenceResult(
      frameId: frameId,
      timestamp: DateTime.now(),
      detections: detections,
      ballCenter: ballCenter,
      clubHeadCenter: clubHeadCenter,
      predictedBallCenter: ballCenter != null 
        ? Offset(ballCenter.dx + _random.nextDouble() * 10 - 5, 
                ballCenter.dy + _random.nextDouble() * 10 - 5)
        : null,
      ballSpeed: _generateRealisticBallSpeed(),
      launchAngle: _generateRealisticLaunchAngle(),
      inferenceTime: 10.0 + _random.nextDouble() * 40.0, // ms
      performanceStats: generatePerformanceStats(),
    );
  }

  /// Generate performance statistics
  static Map<String, dynamic> generatePerformanceStats() {
    return {
      'inferenceTime': 10.0 + _random.nextDouble() * 40.0,
      'preprocessTime': 2.0 + _random.nextDouble() * 8.0,
      'postprocessTime': 1.0 + _random.nextDouble() * 5.0,
      'memoryUsage': 50 + _random.nextInt(200), // MB
      'gpuUsage': _random.nextDouble() * 100, // %
      'modelLoadTime': 500.0 + _random.nextDouble() * 1000.0,
    };
  }

  /// Generate database shot record
  static Map<String, dynamic> generateDatabaseShot({
    String? sessionId,
    String? clubType,
  }) {
    final shot = generateGolfShotData();
    
    return {
      'timestamp': shot.timestamp.millisecondsSinceEpoch,
      'speed': shot.ballSpeed,
      'angle': shot.launchAngle,
      'carry': shot.carryDistance,
      'session_id': sessionId ?? _faker.guid.guid(),
      'club_type': clubType ?? _faker.randomGenerator.element([
        'driver', '3-wood', '5-iron', '7-iron', '9-iron', 'pitching wedge', 'sand wedge'
      ]),
      'notes': _faker.lorem.sentence(),
    };
  }

  /// Generate database session record
  static Map<String, dynamic> generateDatabaseSession({
    bool active = true,
  }) {
    final startTime = _faker.date.dateTime(minYear: 2023, maxYear: 2024);
    final endTime = active ? null : startTime.add(Duration(hours: 1 + _random.nextInt(3)));
    
    return {
      'name': '${_faker.sport.name()} Practice Session',
      'start_time': startTime.millisecondsSinceEpoch,
      'end_time': endTime?.millisecondsSinceEpoch,
      'total_shots': active ? 0 : 10 + _random.nextInt(50),
      'average_speed': active ? 0.0 : 30.0 + _random.nextDouble() * 30.0,
      'best_distance': active ? 0.0 : 150.0 + _random.nextDouble() * 100.0,
      'notes': _faker.lorem.sentence(),
    };
  }

  /// Generate test image data (YUV420)
  static Uint8List generateTestImageYUV420(int width, int height) {
    final ySize = width * height;
    final uvSize = (width * height / 4).round();
    final totalSize = ySize + uvSize * 2;
    
    final imageData = Uint8List(totalSize);
    
    // Generate Y plane (luminance)
    for (int i = 0; i < ySize; i++) {
      imageData[i] = 64 + _random.nextInt(128);
    }
    
    // Generate U and V planes (chrominance)
    for (int i = ySize; i < totalSize; i++) {
      imageData[i] = 128 + _random.nextInt(64) - 32;
    }
    
    return imageData;
  }

  /// Generate stress test data
  static List<InferenceRequest> generateStressTestFrames({
    int frameCount = 1000,
    int width = 640,
    int height = 480,
  }) {
    final frames = <InferenceRequest>[];
    
    for (int i = 0; i < frameCount; i++) {
      frames.add(generateInferenceRequest(
        width: width,
        height: height,
        frameId: i,
      ));
    }
    
    return frames;
  }

  /// Generate edge case test data
  static Map<String, dynamic> generateEdgeCaseData() {
    return {
      'emptyDetections': <BoundingBox>[],
      'lowConfidenceDetections': generateDetections(
        ballCount: 2,
        clubCount: 1,
        minConfidence: 0.1,
        maxConfidence: 0.3,
      ),
      'overlappingDetections': _generateOverlappingDetections(),
      'extremeBallSpeeds': [0.0, 0.1, 100.0, 200.0], // m/s
      'extremeLaunchAngles': [-45.0, -10.0, 0.0, 90.0, 180.0], // degrees
      'malformedImageData': Uint8List.fromList([1, 2, 3]), // Too small
      'nullData': null,
      'largeImageData': generateTestImageYUV420(1920, 1080),
    };
  }

  /// Generate overlapping bounding box detections
  static List<BoundingBox> _generateOverlappingDetections() {
    final center = Offset(300, 200);
    final detections = <BoundingBox>[];
    
    // Create multiple overlapping detections
    for (int i = 0; i < 3; i++) {
      detections.add(BoundingBox(
        x: center.dx - 15 + i * 5,
        y: center.dy - 15 + i * 5,
        width: 30,
        height: 30,
        confidence: 0.8 - i * 0.1,
        className: 'ball',
      ));
    }
    
    return detections;
  }

  /// Generate motion pattern test data
  static List<Offset> generateMotionPattern(String patternType, int points) {
    switch (patternType) {
      case 'linear':
        return _generateLinearMotion(points);
      case 'parabolic':
        return _generateParabolicMotion(points);
      case 'circular':
        return _generateCircularMotion(points);
      case 'erratic':
        return _generateErraticMotion(points);
      case 'stationary':
        return _generateStationaryMotion(points);
      default:
        return _generateLinearMotion(points);
    }
  }

  static List<Offset> _generateLinearMotion(int points) {
    final start = Offset(100, 300);
    final end = Offset(500, 100);
    final positions = <Offset>[];
    
    for (int i = 0; i < points; i++) {
      final t = i / (points - 1);
      positions.add(Offset.lerp(start, end, t)!);
    }
    
    return positions;
  }

  static List<Offset> _generateParabolicMotion(int points) {
    final positions = <Offset>[];
    final startX = 100.0;
    final startY = 300.0;
    
    for (int i = 0; i < points; i++) {
      final t = i / (points - 1);
      final x = startX + t * 400;
      final y = startY - 200 * t + 150 * t * t; // Parabolic path
      positions.add(Offset(x, y));
    }
    
    return positions;
  }

  static List<Offset> _generateCircularMotion(int points) {
    final positions = <Offset>[];
    final center = const Offset(300, 200);
    final radius = 100.0;
    
    for (int i = 0; i < points; i++) {
      final angle = (i / points) * 2 * math.pi;
      final x = center.dx + radius * math.cos(angle);
      final y = center.dy + radius * math.sin(angle);
      positions.add(Offset(x, y));
    }
    
    return positions;
  }

  static List<Offset> _generateErraticMotion(int points) {
    final positions = <Offset>[];
    var currentPos = const Offset(300, 200);
    
    for (int i = 0; i < points; i++) {
      final deltaX = (_random.nextDouble() - 0.5) * 50;
      final deltaY = (_random.nextDouble() - 0.5) * 50;
      currentPos = Offset(
        (currentPos.dx + deltaX).clamp(50, 550),
        (currentPos.dy + deltaY).clamp(50, 350),
      );
      positions.add(currentPos);
    }
    
    return positions;
  }

  static List<Offset> _generateStationaryMotion(int points) {
    final position = Offset(
      200 + _random.nextDouble() * 200,
      150 + _random.nextDouble() * 150,
    );
    
    return List.generate(points, (_) {
      // Add small noise to simulate realistic stationary object
      final noise = Offset(
        (_random.nextDouble() - 0.5) * 2,
        (_random.nextDouble() - 0.5) * 2,
      );
      return position + noise;
    });
  }
}