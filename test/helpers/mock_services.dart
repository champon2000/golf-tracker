// test/helpers/mock_services.dart
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:mockito/mockito.dart';
import 'package:golf_tracker/services/tflite_service.dart';
import 'package:golf_tracker/services/database_service.dart';
import 'package:golf_tracker/services/golf_tracking_service.dart';
import 'package:golf_tracker/services/inference_isolate_service.dart';
import 'package:golf_tracker/services/kalman.dart';
import 'package:golf_tracker/models/bounding_box.dart';
import 'test_data_generator.dart';

/// Mock TFLite Service for testing
class MockTFLiteService extends Mock implements TFLiteService {
  bool _isModelLoaded = false;
  int _inferenceCallCount = 0;
  List<BoundingBox>? _mockDetections;
  double _mockInferenceTime = 25.0; // ms
  
  @override
  Future<void> loadModel() async {
    _isModelLoaded = true;
  }
  
  @override
  List<BoundingBox>? runInference(
    Uint8List yuvBytes, 
    int width, 
    int height, {
    int? bytesPerRow,
    int? uvBytesPerRow,
  }) {
    if (!_isModelLoaded) return null;
    
    _inferenceCallCount++;
    
    // Return mock detections or generate realistic ones
    return _mockDetections ?? TestDataGenerator.generateDetections(
      ballCount: 1,
      clubCount: 1,
      minConfidence: 0.6,
      maxConfidence: 0.95,
    );
  }
  
  @override
  void dispose() {
    _isModelLoaded = false;
  }
  
  // Test helper methods
  void setMockDetections(List<BoundingBox> detections) {
    _mockDetections = detections;
  }
  
  void setMockInferenceTime(double timeMs) {
    _mockInferenceTime = timeMs;
  }
  
  bool get isModelLoaded => _isModelLoaded;
  int get inferenceCallCount => _inferenceCallCount;
  
  Map<String, dynamic> getPerformanceStats() {
    return {
      'inferenceTime': _mockInferenceTime,
      'preprocessTime': _mockInferenceTime * 0.3,
      'postprocessTime': _mockInferenceTime * 0.1,
      'totalCalls': _inferenceCallCount,
      'memoryUsage': 75.5,
      'gpuUsage': 45.2,
    };
  }
  
  void reset() {
    _inferenceCallCount = 0;
    _mockDetections = null;
    _mockInferenceTime = 25.0;
  }
}

/// Mock Database Service for testing
class MockDatabaseService extends Mock implements DatabaseService {
  final List<Map<String, dynamic>> _shots = [];
  final List<Map<String, dynamic>> _sessions = [];
  int _nextShotId = 1;
  int _nextSessionId = 1;
  
  @override
  Future<int> insertShot(Map<String, dynamic> shot) async {
    final shotWithId = Map<String, dynamic>.from(shot);
    shotWithId['id'] = _nextShotId++;
    shotWithId['timestamp'] ??= DateTime.now().millisecondsSinceEpoch;
    _shots.add(shotWithId);
    return shotWithId['id'];
  }
  
  @override
  Future<List<Map<String, dynamic>>> getAllShots({
    int? limit,
    int? offset,
    String? sessionId,
    String? orderBy,
  }) async {
    var filteredShots = _shots.where((shot) {
      if (sessionId != null) {
        return shot['session_id'] == sessionId;
      }
      return true;
    }).toList();
    
    // Simple ordering by timestamp desc
    if (orderBy == null || orderBy.contains('timestamp DESC')) {
      filteredShots.sort((a, b) => 
        (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0));
    }
    
    if (offset != null) {
      filteredShots = filteredShots.skip(offset).toList();
    }
    
    if (limit != null) {
      filteredShots = filteredShots.take(limit).toList();
    }
    
    return filteredShots;
  }
  
  @override
  Future<Map<String, dynamic>?> getShot(int id) async {
    try {
      return _shots.firstWhere((shot) => shot['id'] == id);
    } catch (e) {
      return null;
    }
  }
  
  @override
  Future<int> updateShot(int id, Map<String, dynamic> shot) async {
    final index = _shots.indexWhere((s) => s['id'] == id);
    if (index != -1) {
      _shots[index] = {..._shots[index], ...shot};
      return 1;
    }
    return 0;
  }
  
  @override
  Future<int> deleteShot(int id) async {
    final removed = _shots.removeWhere((shot) => shot['id'] == id);
    return removed ? 1 : 0;
  }
  
  @override
  Future<int> createSession(String name, {String? notes}) async {
    final session = {
      'id': _nextSessionId++,
      'name': name,
      'start_time': DateTime.now().millisecondsSinceEpoch,
      'notes': notes,
      'total_shots': 0,
      'average_speed': 0.0,
      'best_distance': 0.0,
    };
    _sessions.add(session);
    return session['id'];
  }
  
  @override
  Future<int> endSession(int sessionId) async {
    final index = _sessions.indexWhere((s) => s['id'] == sessionId);
    if (index != -1) {
      _sessions[index]['end_time'] = DateTime.now().millisecondsSinceEpoch;
      return 1;
    }
    return 0;
  }
  
  @override
  Future<List<Map<String, dynamic>>> getAllSessions({
    int? limit,
    int? offset,
  }) async {
    var sessions = List<Map<String, dynamic>>.from(_sessions);
    
    sessions.sort((a, b) => 
      (b['start_time'] ?? 0).compareTo(a['start_time'] ?? 0));
    
    if (offset != null) {
      sessions = sessions.skip(offset).toList();
    }
    
    if (limit != null) {
      sessions = sessions.take(limit).toList();
    }
    
    return sessions;
  }
  
  @override
  Future<Map<String, dynamic>> getSessionStats(String sessionId) async {
    final sessionShots = _shots.where((shot) => 
      shot['session_id'] == sessionId).toList();
    
    if (sessionShots.isEmpty) {
      return {
        'total_shots': 0,
        'average_speed': 0.0,
        'max_speed': 0.0,
        'min_speed': 0.0,
        'average_angle': 0.0,
        'best_distance': 0.0,
        'average_distance': 0.0,
      };
    }
    
    final speeds = sessionShots.map((s) => s['speed'] as double).toList();
    final angles = sessionShots.map((s) => s['angle'] as double).toList();
    final distances = sessionShots.map((s) => s['carry'] as double).toList();
    
    return {
      'total_shots': sessionShots.length,
      'average_speed': speeds.reduce((a, b) => a + b) / speeds.length,
      'max_speed': speeds.reduce((a, b) => a > b ? a : b),
      'min_speed': speeds.reduce((a, b) => a < b ? a : b),
      'average_angle': angles.reduce((a, b) => a + b) / angles.length,
      'best_distance': distances.reduce((a, b) => a > b ? a : b),
      'average_distance': distances.reduce((a, b) => a + b) / distances.length,
    };
  }
  
  @override
  Future<Map<String, dynamic>> getOverallStats() async {
    if (_shots.isEmpty) {
      return {
        'total_shots': 0,
        'average_speed': 0.0,
        'max_speed': 0.0,
        'min_speed': 0.0,
        'average_angle': 0.0,
        'best_distance': 0.0,
        'average_distance': 0.0,
        'practice_days': 0,
      };
    }
    
    final speeds = _shots.map((s) => s['speed'] as double).toList();
    final angles = _shots.map((s) => s['angle'] as double).toList();
    final distances = _shots.map((s) => s['carry'] as double).toList();
    final timestamps = _shots.map((s) => s['timestamp'] as int).toList();
    
    // Calculate unique practice days
    final uniqueDays = timestamps.map((ts) {
      final date = DateTime.fromMillisecondsSinceEpoch(ts);
      return '${date.year}-${date.month}-${date.day}';
    }).toSet().length;
    
    return {
      'total_shots': _shots.length,
      'average_speed': speeds.reduce((a, b) => a + b) / speeds.length,
      'max_speed': speeds.reduce((a, b) => a > b ? a : b),
      'min_speed': speeds.reduce((a, b) => a < b ? a : b),
      'average_angle': angles.reduce((a, b) => a + b) / angles.length,
      'best_distance': distances.reduce((a, b) => a > b ? a : b),
      'average_distance': distances.reduce((a, b) => a + b) / distances.length,
      'practice_days': uniqueDays,
    };
  }
  
  // Test helper methods
  void reset() {
    _shots.clear();
    _sessions.clear();
    _nextShotId = 1;
    _nextSessionId = 1;
  }
  
  void addTestShots(int count, {String? sessionId}) {
    for (int i = 0; i < count; i++) {
      final shot = TestDataGenerator.generateDatabaseShot(sessionId: sessionId);
      insertShot(shot);
    }
  }
  
  List<Map<String, dynamic>> get allShots => List.unmodifiable(_shots);
  List<Map<String, dynamic>> get allSessions => List.unmodifiable(_sessions);
}

/// Mock Kalman Filter for testing
class MockKalmanFilter extends Mock implements KalmanFilter2D {
  Offset _currentPosition = const Offset(300, 200);
  Offset _currentVelocity = const Offset(10, -5);
  double _confidence = 0.8;
  bool _isInitialized = true;
  int _updateCount = 0;
  
  @override
  Offset update(Offset measurement, {double? confidence}) {
    _updateCount++;
    
    // Simple mock behavior: move slightly towards measurement
    _currentPosition = Offset.lerp(_currentPosition, measurement, 0.7)!;
    
    if (confidence != null) {
      _confidence = confidence;
    }
    
    return _currentPosition;
  }
  
  @override
  Offset get position => _currentPosition;
  
  @override
  Offset get velocity => _currentVelocity;
  
  @override
  Offset get predictedPosition => _currentPosition + _currentVelocity;
  
  @override
  double get uncertainty => (1.0 - _confidence) * 100.0;
  
  @override
  double get confidenceScore => _confidence;
  
  @override
  double get adaptiveNoiseMultiplier => 1.0;
  
  @override
  double get averageResidual => 5.0;
  
  @override
  void reset({
    required Offset initialPosition,
    double initialVelocityX = 0.0,
    double initialVelocityY = 0.0,
  }) {
    _currentPosition = initialPosition;
    _currentVelocity = Offset(initialVelocityX, initialVelocityY);
    _confidence = 0.8;
    _updateCount = 0;
  }
  
  // Test helper methods
  void setPosition(Offset position) => _currentPosition = position;
  void setVelocity(Offset velocity) => _currentVelocity = velocity;
  void setConfidence(double confidence) => _confidence = confidence;
  int get updateCount => _updateCount;
}

/// Mock Inference Isolate Service for testing
class MockInferenceIsolateService extends Mock implements InferenceIsolateService {
  final StreamController<InferenceResult> _resultController = 
      StreamController<InferenceResult>.broadcast();
  
  bool _isInitialized = false;
  int _framesSent = 0;
  int _framesProcessed = 0;
  int _framesDropped = 0;
  bool _isHealthy = true;
  
  @override
  Stream<InferenceResult> get results => _resultController.stream;
  
  @override
  Map<String, dynamic> get performanceStats => {
    'framesSent': _framesSent,
    'framesProcessed': _framesProcessed,
    'framesDropped': _framesDropped,
    'dropRate': _framesSent > 0 ? _framesDropped / _framesSent : 0.0,
    'processRate': _framesSent > 0 ? _framesProcessed / _framesSent : 0.0,
    'isHealthy': _isHealthy,
    'lastResultTime': DateTime.now().toIso8601String(),
  };
  
  @override
  Future<bool> initialize() async {
    await Future.delayed(const Duration(milliseconds: 100)); // Simulate init time
    _isInitialized = true;
    return true;
  }
  
  @override
  Future<void> processFrame(InferenceRequest request) async {
    if (!_isInitialized || !_isHealthy) {
      _framesDropped++;
      return;
    }
    
    _framesSent++;
    
    // Simulate processing delay
    await Future.delayed(const Duration(milliseconds: 20));
    
    // Generate mock result
    final result = TestDataGenerator.generateInferenceResult(
      frameId: request.frameId,
    );
    
    _framesProcessed++;
    _resultController.add(result);
  }
  
  @override
  Future<void> dispose() async {
    await _resultController.close();
    _isInitialized = false;
  }
  
  // Test helper methods
  void simulateError() {
    _isHealthy = false;
  }
  
  void simulateRecovery() {
    _isHealthy = true;
  }
  
  void reset() {
    _framesSent = 0;
    _framesProcessed = 0;
    _framesDropped = 0;
    _isHealthy = true;
  }
  
  bool get isInitialized => _isInitialized;
  bool get isHealthy => _isHealthy;
}

/// Mock Golf Tracking Service for testing
class MockGolfTrackingService extends Mock implements GolfTrackingService {
  final StreamController<GolfTrackingEvent> _eventController = 
      StreamController<GolfTrackingEvent>.broadcast();
  final StreamController<GolfShotData> _shotDataController = 
      StreamController<GolfShotData>.broadcast();
  
  bool _isTracking = false;
  bool _isInitialized = false;
  final List<GolfTrackingEvent> _eventHistory = [];
  final List<GolfShotData> _shotHistory = [];
  
  @override
  Stream<GolfTrackingEvent> get events => _eventController.stream;
  
  @override
  Stream<GolfShotData> get shotData => _shotDataController.stream;
  
  @override
  bool get isTracking => _isTracking;
  
  @override
  Map<String, dynamic> get performanceStats => {
    'framesProcessed': 150 + _shotHistory.length * 200,
    'ballDetections': 120 + _shotHistory.length * 150,
    'clubDetections': 80 + _shotHistory.length * 100,
    'ballDetectionRate': 0.8,
    'clubDetectionRate': 0.6,
    'isTracking': _isTracking,
    'impactDetected': _shotHistory.isNotEmpty,
    'trajectoryPoints': _shotHistory.isNotEmpty ? 45 : 0,
    'maxBallSpeed': _shotHistory.isNotEmpty ? 
        _shotHistory.last.ballSpeed : 0.0,
    'launchAngle': _shotHistory.isNotEmpty ? 
        _shotHistory.last.launchAngle : 0.0,
  };
  
  @override
  Future<bool> initialize() async {
    await Future.delayed(const Duration(milliseconds: 50));
    _isInitialized = true;
    return true;
  }
  
  @override
  void startTracking() {
    if (_isTracking) return;
    
    _isTracking = true;
    _addEvent(GolfTrackingEvent.ballDetected);
  }
  
  @override
  void stopTracking() {
    if (!_isTracking) return;
    
    _isTracking = false;
    _addEvent(GolfTrackingEvent.trackingComplete);
    
    // Generate a shot if tracking was active
    final shot = TestDataGenerator.generateGolfShotData();
    _shotHistory.add(shot);
    _shotDataController.add(shot);
  }
  
  @override
  Future<void> processFrame(
    Uint8List yuvBytes, 
    int width, 
    int height, {
    int? bytesPerRow,
    int? uvBytesPerRow,
  }) async {
    if (!_isTracking) return;
    
    // Simulate frame processing
    await Future.delayed(const Duration(microseconds: 500));
  }
  
  @override
  Map<String, dynamic> getPerformanceReport() {
    return {
      'tracking': performanceStats,
      'inference': TestDataGenerator.generatePerformanceStats(),
      'timestamp': DateTime.now().toIso8601String(),
    };
  }
  
  @override
  Future<void> dispose() async {
    await _eventController.close();
    await _shotDataController.close();
    _isInitialized = false;
  }
  
  // Test helper methods
  void _addEvent(GolfTrackingEvent event) {
    _eventHistory.add(event);
    _eventController.add(event);
  }
  
  void simulateImpact() {
    if (_isTracking) {
      _addEvent(GolfTrackingEvent.impactDetected);
      _addEvent(GolfTrackingEvent.ballInFlight);
    }
  }
  
  void simulateBallLanding() {
    if (_isTracking) {
      _addEvent(GolfTrackingEvent.ballLanded);
      stopTracking();
    }
  }
  
  void reset() {
    _isTracking = false;
    _eventHistory.clear();
    _shotHistory.clear();
  }
  
  List<GolfTrackingEvent> get eventHistory => List.unmodifiable(_eventHistory);
  List<GolfShotData> get shotHistory => List.unmodifiable(_shotHistory);
  bool get isInitialized => _isInitialized;
}

/// Test utilities for managing mock services
class MockServiceFactory {
  static MockTFLiteService createTFLiteService({
    bool preloadModel = true,
    List<BoundingBox>? defaultDetections,
  }) {
    final service = MockTFLiteService();
    if (preloadModel) {
      service.loadModel();
    }
    if (defaultDetections != null) {
      service.setMockDetections(defaultDetections);
    }
    return service;
  }
  
  static MockDatabaseService createDatabaseService({
    int initialShots = 0,
    int initialSessions = 0,
  }) {
    final service = MockDatabaseService();
    if (initialSessions > 0) {
      for (int i = 0; i < initialSessions; i++) {
        final sessionData = TestDataGenerator.generateDatabaseSession();
        service.createSession(sessionData['name'], notes: sessionData['notes']);
      }
    }
    if (initialShots > 0) {
      service.addTestShots(initialShots);
    }
    return service;
  }
  
  static MockKalmanFilter createKalmanFilter({
    Offset? initialPosition,
    Offset? initialVelocity,
    double initialConfidence = 0.8,
  }) {
    final filter = MockKalmanFilter();
    if (initialPosition != null) {
      filter.setPosition(initialPosition);
    }
    if (initialVelocity != null) {
      filter.setVelocity(initialVelocity);
    }
    filter.setConfidence(initialConfidence);
    return filter;
  }
  
  static MockInferenceIsolateService createInferenceService({
    bool autoInitialize = true,
  }) {
    final service = MockInferenceIsolateService();
    if (autoInitialize) {
      service.initialize();
    }
    return service;
  }
  
  static MockGolfTrackingService createGolfTrackingService({
    bool autoInitialize = true,
  }) {
    final service = MockGolfTrackingService();
    if (autoInitialize) {
      service.initialize();
    }
    return service;
  }
}