// lib/services/inference_isolate_service.dart
import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:golf_tracker/services/tflite_service_enhanced.dart';
import 'package:golf_tracker/services/kalman.dart';

/// Data structure for passing frame data to inference isolate
class InferenceRequest {
  final Uint8List yuvBytes;
  final int width;
  final int height;
  final int bytesPerRow;
  final int uvBytesPerRow;
  final int frameId;
  final DateTime timestamp;

  InferenceRequest({
    required this.yuvBytes,
    required this.width,
    required this.height,
    required this.bytesPerRow,
    required this.uvBytesPerRow,
    required this.frameId,
    required this.timestamp,
  });
}

/// Results from inference processing
class InferenceResult {
  final int frameId;
  final DateTime timestamp;
  final List<BoundingBox> detections;
  final Offset? ballCenter;
  final Offset? clubHeadCenter;
  final Offset? predictedBallCenter;
  final double ballSpeed;
  final double launchAngle;
  final double inferenceTime;
  final Map<String, dynamic> performanceStats;

  InferenceResult({
    required this.frameId,
    required this.timestamp,
    required this.detections,
    this.ballCenter,
    this.clubHeadCenter,
    this.predictedBallCenter,
    this.ballSpeed = 0.0,
    this.launchAngle = 0.0,
    required this.inferenceTime,
    required this.performanceStats,
  });
}

/// High-performance inference service using isolates for 240fps processing
class InferenceIsolateService {
  static const String _isolateName = 'InferenceIsolate';
  
  Isolate? _isolate;
  SendPort? _sendPort;
  ReceivePort? _receivePort;
  StreamController<InferenceResult>? _resultController;
  
  // Performance monitoring
  int _framesSent = 0;
  int _framesProcessed = 0;
  int _framesDropped = 0;
  DateTime? _lastStatsReport;
  
  // Frame rate control
  static const int TARGET_FPS = 240;
  static const int PROCESS_EVERY_N_FRAMES = 2; // Process every 2nd frame for 120fps processing
  int _frameCounter = 0;
  
  // Isolate health monitoring
  Timer? _healthCheckTimer;
  DateTime? _lastResultTime;
  bool _isHealthy = true;

  /// Stream of inference results
  Stream<InferenceResult> get results => _resultController?.stream ?? const Stream.empty();

  /// Current performance statistics
  Map<String, dynamic> get performanceStats => {
    'framesSent': _framesSent,
    'framesProcessed': _framesProcessed,
    'framesDropped': _framesDropped,
    'dropRate': _framesSent > 0 ? _framesDropped / _framesSent : 0.0,
    'processRate': _framesSent > 0 ? _framesProcessed / _framesSent : 0.0,
    'isHealthy': _isHealthy,
    'lastResultTime': _lastResultTime?.toIso8601String(),
  };

  /// Initialize the inference isolate service
  Future<bool> initialize() async {
    try {
      // Create result stream controller
      _resultController = StreamController<InferenceResult>.broadcast();
      
      // Create receive port for isolate communication
      _receivePort = ReceivePort();
      
      // Spawn the inference isolate
      _isolate = await Isolate.spawn(
        _inferenceIsolateEntryPoint,
        _receivePort!.sendPort,
        debugName: _isolateName,
      );

      // Listen for messages from isolate
      _receivePort!.listen(_handleIsolateMessage);
      
      // Start health monitoring
      _startHealthMonitoring();
      
      // Start performance reporting
      _lastStatsReport = DateTime.now();
      
      print('Inference isolate service initialized successfully');
      return true;
      
    } catch (e) {
      print('Failed to initialize inference isolate service: $e');
      await dispose();
      return false;
    }
  }

  /// Process a camera frame (with frame rate control)
  Future<void> processFrame(InferenceRequest request) async {
    if (_sendPort == null || !_isHealthy) {
      _framesDropped++;
      return;
    }

    // Frame rate control - only process every Nth frame
    _frameCounter++;
    if (_frameCounter % PROCESS_EVERY_N_FRAMES != 0) {
      _framesDropped++;
      return;
    }

    try {
      _framesSent++;
      _sendPort!.send(request);
      
      // Report performance stats periodically
      _reportPerformanceStats();
      
    } catch (e) {
      print('Failed to send frame to isolate: $e');
      _framesDropped++;
    }
  }

  /// Handle messages from the inference isolate
  void _handleIsolateMessage(dynamic message) {
    if (message is SendPort) {
      // Isolate is ready, store its send port
      _sendPort = message;
      print('Inference isolate is ready');
    } else if (message is InferenceResult) {
      // Received inference result
      _framesProcessed++;
      _lastResultTime = DateTime.now();
      _isHealthy = true;
      
      _resultController?.add(message);
    } else if (message is Map<String, dynamic> && message['error'] != null) {
      // Error from isolate
      print('Isolate error: ${message['error']}');
      _isHealthy = false;
    }
  }

  /// Start health monitoring timer
  void _startHealthMonitoring() {
    _healthCheckTimer = Timer.periodic(const Duration(seconds=5), (timer) {
      final now = DateTime.now();
      
      // Check if we've received results recently
      if (_lastResultTime != null) {
        final timeSinceLastResult = now.difference(_lastResultTime!);
        if (timeSinceLastResult.inSeconds > 10) {
          _isHealthy = false;
          print('Warning: No inference results received for ${timeSinceLastResult.inSeconds} seconds');
        }
      }
      
      // Consider restarting isolate if unhealthy for too long
      if (!_isHealthy && _lastResultTime != null) {
        final timeSinceLastResult = now.difference(_lastResultTime!);
        if (timeSinceLastResult.inSeconds > 30) {
          print('Isolate appears to be stuck, considering restart...');
          // TODO: Implement isolate restart logic if needed
        }
      }
    });
  }

  /// Report performance statistics
  void _reportPerformanceStats() {
    final now = DateTime.now();
    if (_lastStatsReport != null) {
      final elapsed = now.difference(_lastStatsReport!);
      
      // Report every 10 seconds
      if (elapsed.inSeconds >= 10) {
        final stats = performanceStats;
        print('Inference Performance Stats:');
        print('  Frames sent: ${stats['framesSent']}');
        print('  Frames processed: ${stats['framesProcessed']}');
        print('  Frames dropped: ${stats['framesDropped']}');
        print('  Process rate: ${(stats['processRate'] * 100).toStringAsFixed(1)}%');
        print('  Drop rate: ${(stats['dropRate'] * 100).toStringAsFixed(1)}%');
        print('  Isolate healthy: ${stats['isHealthy']}');
        
        _lastStatsReport = now;
      }
    }
  }

  /// Dispose of the isolate service
  Future<void> dispose() async {
    print('Disposing inference isolate service...');
    
    // Stop health monitoring
    _healthCheckTimer?.cancel();
    
    // Close result controller
    await _resultController?.close();
    _resultController = null;
    
    // Kill isolate
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    
    // Close receive port
    _receivePort?.close();
    _receivePort = null;
    
    _sendPort = null;
    
    print('Inference isolate service disposed');
  }
}

/// Entry point for the inference processing isolate
void _inferenceIsolateEntryPoint(SendPort mainSendPort) async {
  print('Inference isolate starting...');
  
  // Create receive port for this isolate
  final isolateReceivePort = ReceivePort();
  
  // Send our send port back to main isolate
  mainSendPort.send(isolateReceivePort.sendPort);
  
  // Initialize TFLite service
  TFLiteService? tfliteService;
  try {
    tfliteService = TFLiteService();
    await tfliteService.loadModel();
    print('TFLite model loaded in isolate');
  } catch (e) {
    mainSendPort.send({'error': 'Failed to load TFLite model: $e'});
    return;
  }
  
  // Initialize Kalman filter for ball tracking
  final kalmanFilter = KalmanFilter2D(
    initialPosition: const Offset(0, 0),
    initialVelocityX: 0.0,
    initialVelocityY: 0.0,
    dt: 1.0 / 120.0, // Effective frame rate after decimation
    processNoisePos: 0.1,
    processNoiseVel: 0.01,
    measurementNoisePos: 1.0,
  );
  
  // Ball tracking history for speed calculation
  final List<Offset> ballHistory = [];
  const int maxHistoryLength = 10;
  
  print('Inference isolate ready');
  
  // Listen for inference requests
  await for (final message in isolateReceivePort) {
    if (message is InferenceRequest) {
      await _processInferenceRequest(
        message,
        tfliteService,
        kalmanFilter,
        ballHistory,
        maxHistoryLength,
        mainSendPort,
      );
    }
  }
}

/// Process a single inference request in the isolate
Future<void> _processInferenceRequest(
  InferenceRequest request,
  TFLiteService tfliteService,
  KalmanFilter2D kalmanFilter,
  List<Offset> ballHistory,
  int maxHistoryLength,
  SendPort mainSendPort,
) async {
  final stopwatch = Stopwatch()..start();
  
  try {
    // Run inference
    final detections = await tfliteService.runInference(
      request.yuvBytes,
      request.width,
      request.height,
      bytesPerRow: request.bytesPerRow,
      uvBytesPerRow: request.uvBytesPerRow,
    );
    
    Offset? ballCenter;
    Offset? clubHeadCenter;
    Offset? predictedBallCenter;
    double ballSpeed = 0.0;
    double launchAngle = 0.0;
    
    if (detections != null && detections.isNotEmpty) {
      // Extract ball and club head positions
      for (final detection in detections) {
        if (detection.className == 'ball' && detection.confidence > 0.5) {
          ballCenter = detection.center;
        } else if (detection.className == 'club_head' && detection.confidence > 0.3) {
          clubHeadCenter = detection.center;
        }
      }
      
      // Update ball tracking with Kalman filter
      if (ballCenter != null) {
        predictedBallCenter = kalmanFilter.update(ballCenter);
        
        // Update ball history
        ballHistory.add(predictedBallCenter);
        if (ballHistory.length > maxHistoryLength) {
          ballHistory.removeAt(0);
        }
        
        // Calculate ball speed and launch angle
        if (ballHistory.length >= 3) {
          final recentPositions = ballHistory.skip(ballHistory.length - 3).toList();
          ballSpeed = _calculateBallSpeed(recentPositions, 1.0 / 120.0);
          launchAngle = _calculateLaunchAngle(recentPositions);
        }
      }
    }
    
    stopwatch.stop();
    
    // Send result back to main isolate
    final result = InferenceResult(
      frameId: request.frameId,
      timestamp: request.timestamp,
      detections: detections ?? [],
      ballCenter: ballCenter,
      clubHeadCenter: clubHeadCenter,
      predictedBallCenter: predictedBallCenter,
      ballSpeed: ballSpeed,
      launchAngle: launchAngle,
      inferenceTime: stopwatch.elapsedMicroseconds / 1000.0,
      performanceStats: tfliteService.getPerformanceStats(),
    );
    
    mainSendPort.send(result);
    
  } catch (e) {
    // Send error back to main isolate
    mainSendPort.send({
      'error': 'Inference processing failed: $e',
      'frameId': request.frameId,
    });
  }
}

/// Calculate ball speed from recent position history
double _calculateBallSpeed(List<Offset> positions, double dt) {
  if (positions.length < 2) return 0.0;
  
  double totalDistance = 0.0;
  for (int i = 1; i < positions.length; i++) {
    final distance = (positions[i] - positions[i-1]).distance;
    totalDistance += distance;
  }
  
  final avgDistance = totalDistance / (positions.length - 1);
  return avgDistance / dt; // pixels per second
}

/// Calculate launch angle from recent position history
double _calculateLaunchAngle(List<Offset> positions) {
  if (positions.length < 2) return 0.0;
  
  final start = positions.first;
  final end = positions.last;
  final displacement = end - start;
  
  // Calculate angle in degrees (negative dy because screen coordinates have y increasing downward)
  return math.atan2(-displacement.dy, displacement.dx) * 180 / math.pi;
}

// Import math for atan2
import 'dart:math' as math;