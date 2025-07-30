// lib/services/app_state.dart
import 'package:flutter/foundation.dart';

class AppState extends ChangeNotifier {
  bool _isRecording = false;
  bool _isCameraInitialized = false;
  String? _errorMessage;
  
  // Camera performance metrics
  double _fps = 0.0;
  int _frameCount = 0;
  DateTime? _lastFrameTime;
  
  // Detection metrics
  int _ballDetectionCount = 0;
  int _clubDetectionCount = 0;
  double _averageInferenceTime = 0.0;
  
  // Getters
  bool get isRecording => _isRecording;
  bool get isCameraInitialized => _isCameraInitialized;
  String? get errorMessage => _errorMessage;
  double get fps => _fps;
  int get frameCount => _frameCount;
  int get ballDetectionCount => _ballDetectionCount;
  int get clubDetectionCount => _clubDetectionCount;
  double get averageInferenceTime => _averageInferenceTime;
  
  // Recording control
  void startRecording() {
    _isRecording = true;
    _errorMessage = null;
    notifyListeners();
  }
  
  void stopRecording() {
    _isRecording = false;
    notifyListeners();
  }
  
  // Camera state management
  void setCameraInitialized(bool initialized) {
    _isCameraInitialized = initialized;
    if (!initialized) {
      _fps = 0.0;
      _frameCount = 0;
      _lastFrameTime = null;
    }
    notifyListeners();
  }
  
  // Error handling
  void setError(String? error) {
    _errorMessage = error;
    notifyListeners();
  }
  
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
  
  // Performance metrics
  void updateFrameMetrics() {
    final now = DateTime.now();
    _frameCount++;
    
    if (_lastFrameTime != null) {
      final deltaTime = now.difference(_lastFrameTime!).inMicroseconds / 1000000.0;
      if (deltaTime > 0) {
        _fps = 1.0 / deltaTime;
      }
    }
    _lastFrameTime = now;
    
    // Notify listeners every 30 frames to avoid excessive UI updates
    if (_frameCount % 30 == 0) {
      notifyListeners();
    }
  }
  
  // Detection metrics
  void updateDetectionMetrics({
    required bool ballDetected,
    required bool clubDetected,
    required double inferenceTime,
  }) {
    if (ballDetected) _ballDetectionCount++;
    if (clubDetected) _clubDetectionCount++;
    
    // Update running average of inference time
    const double alpha = 0.1; // Smoothing factor
    _averageInferenceTime = _averageInferenceTime * (1 - alpha) + inferenceTime * alpha;
  }
  
  // Reset metrics
  void resetMetrics() {
    _frameCount = 0;
    _ballDetectionCount = 0;
    _clubDetectionCount = 0;
    _averageInferenceTime = 0.0;
    _fps = 0.0;
    _lastFrameTime = null;
    notifyListeners();
  }
}