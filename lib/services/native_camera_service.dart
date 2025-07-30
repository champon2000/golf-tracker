import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';

/// Native camera service for high-performance camera streaming
class NativeCameraService {
  static const String _channelName = 'com.example.golf_tracker/camera_stream';
  static const String _eventChannelName = 'com.example.golf_tracker/camera_events';
  
  static const MethodChannel _channel = MethodChannel(_channelName);
  static const EventChannel _eventChannel = EventChannel(_eventChannelName);
  
  // Stream controller for camera frames
  StreamController<CameraFrame>? _frameStreamController;
  StreamSubscription<dynamic>? _eventSubscription;
  
  // Camera state
  bool _isStreaming = false;
  bool get isStreaming => _isStreaming;
  
  // Singleton pattern
  static final NativeCameraService _instance = NativeCameraService._internal();
  factory NativeCameraService() => _instance;
  NativeCameraService._internal() {
    _setupMethodCallHandler();
  }
  
  void _setupMethodCallHandler() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onPermissionGranted':
          _onPermissionGranted();
          break;
        case 'onPermissionDenied':
          _onPermissionDenied();
          break;
        default:
          print('Unknown method: ${call.method}');
      }
    });
  }
  
  /// Start camera streaming
  Future<CameraStreamInfo> startCameraStream({bool useFrontCamera = false}) async {
    try {
      final result = await _channel.invokeMethod('startCameraStream', {
        'useFrontCamera': useFrontCamera,
      });
      
      if (result['status'] == 'streaming_started') {
        _isStreaming = true;
        _startFrameStream();
        
        return CameraStreamInfo(
          width: result['width'] ?? 1280,
          height: result['height'] ?? 720,
          fps: result['fps'] ?? 30,
        );
      } else {
        throw Exception('Failed to start camera stream: ${result['status']}');
      }
    } on PlatformException catch (e) {
      throw Exception('Camera error: ${e.message}');
    }
  }
  
  /// Stop camera streaming
  Future<void> stopCameraStream() async {
    try {
      await _channel.invokeMethod('stopCameraStream');
      _isStreaming = false;
      await _stopFrameStream();
    } on PlatformException catch (e) {
      throw Exception('Failed to stop camera: ${e.message}');
    }
  }
  
  /// Switch between front and back camera
  Future<void> switchCamera({required bool useFrontCamera}) async {
    try {
      await _channel.invokeMethod('switchCamera', {
        'useFrontCamera': useFrontCamera,
      });
    } on PlatformException catch (e) {
      throw Exception('Failed to switch camera: ${e.message}');
    }
  }
  
  /// Get camera information
  Future<CameraInfo> getCameraInfo() async {
    try {
      final result = await _channel.invokeMethod('getCameraInfo');
      return CameraInfo(
        hasBackCamera: result['hasBackCamera'] ?? false,
        hasFrontCamera: result['hasFrontCamera'] ?? false,
        isStreaming: result['isStreaming'] ?? false,
      );
    } on PlatformException catch (e) {
      throw Exception('Failed to get camera info: ${e.message}');
    }
  }
  
  /// Get performance metrics
  Future<CameraPerformanceMetrics> getPerformanceMetrics() async {
    try {
      final result = await _channel.invokeMethod('getPerformanceMetrics');
      return CameraPerformanceMetrics(
        currentFps: (result['currentFps'] ?? 0.0).toDouble(),
        averageFps: (result['averageFps'] ?? 0.0).toDouble(),
        droppedFramesPercent: (result['droppedFramesPercent'] ?? 0.0).toDouble(),
        averageProcessingTime: result['averageProcessingTime'] ?? 0,
        memoryUsageMB: result['memoryUsageMB'] ?? 0,
        peakMemoryUsageMB: result['peakMemoryUsageMB'] ?? 0,
      );
    } on PlatformException catch (e) {
      throw Exception('Failed to get performance metrics: ${e.message}');
    }
  }
  
  /// Get stream of camera frames
  Stream<CameraFrame> get frameStream {
    if (_frameStreamController == null) {
      _frameStreamController = StreamController<CameraFrame>.broadcast(
        onListen: _startFrameStream,
        onCancel: _stopFrameStream,
      );
    }
    return _frameStreamController!.stream;
  }
  
  void _startFrameStream() {
    _eventSubscription?.cancel();
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is Map) {
          final type = event['type'];
          if (type == 'frame') {
            final frame = CameraFrame(
              data: Uint8List.fromList(event['data']),
              width: event['width'] ?? 0,
              height: event['height'] ?? 0,
              timestamp: event['timestamp'] ?? 0,
              format: event['format'] ?? 'unknown',
            );
            _frameStreamController?.add(frame);
          }
        }
      },
      onError: (error) {
        print('Camera stream error: $error');
        _frameStreamController?.addError(error);
      },
    );
  }
  
  Future<void> _stopFrameStream() async {
    await _eventSubscription?.cancel();
    _eventSubscription = null;
  }
  
  void _onPermissionGranted() {
    print('Camera permission granted');
  }
  
  void _onPermissionDenied() {
    print('Camera permission denied');
  }
  
  /// Dispose resources
  void dispose() {
    _stopFrameStream();
    _frameStreamController?.close();
    _frameStreamController = null;
  }
}

/// Camera frame data
class CameraFrame {
  final Uint8List data;
  final int width;
  final int height;
  final int timestamp;
  final String format;
  
  CameraFrame({
    required this.data,
    required this.width,
    required this.height,
    required this.timestamp,
    required this.format,
  });
}

/// Camera stream information
class CameraStreamInfo {
  final int width;
  final int height;
  final int fps;
  
  CameraStreamInfo({
    required this.width,
    required this.height,
    required this.fps,
  });
}

/// Camera information
class CameraInfo {
  final bool hasBackCamera;
  final bool hasFrontCamera;
  final bool isStreaming;
  
  CameraInfo({
    required this.hasBackCamera,
    required this.hasFrontCamera,
    required this.isStreaming,
  });
}

/// Camera performance metrics
class CameraPerformanceMetrics {
  final double currentFps;
  final double averageFps;
  final double droppedFramesPercent;
  final int averageProcessingTime;
  final int memoryUsageMB;
  final int peakMemoryUsageMB;
  
  CameraPerformanceMetrics({
    required this.currentFps,
    required this.averageFps,
    required this.droppedFramesPercent,
    required this.averageProcessingTime,
    required this.memoryUsageMB,
    required this.peakMemoryUsageMB,
  });
  
  @override
  String toString() {
    return '''
CameraPerformanceMetrics:
  Current FPS: ${currentFps.toStringAsFixed(1)}
  Average FPS: ${averageFps.toStringAsFixed(1)}
  Dropped Frames: ${droppedFramesPercent.toStringAsFixed(1)}%
  Avg Processing Time: ${averageProcessingTime}ms
  Memory Usage: ${memoryUsageMB}MB
  Peak Memory: ${peakMemoryUsageMB}MB
''';
  }
}