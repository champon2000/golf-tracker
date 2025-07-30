// lib/services/integration_example.dart
// Example integration of the enhanced TensorFlow Lite ML pipeline

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:golf_tracker/services/golf_tracking_service.dart';
import 'package:golf_tracker/services/inference_isolate_service.dart';
import 'package:golf_tracker/services/tflite_service_enhanced.dart';

/// Example widget demonstrating the enhanced ML pipeline integration
class EnhancedGolfTrackerExample extends StatefulWidget {
  const EnhancedGolfTrackerExample({Key? key}) : super(key: key);

  @override
  State<EnhancedGolfTrackerExample> createState() => _EnhancedGolfTrackerExampleState();
}

class _EnhancedGolfTrackerExampleState extends State<EnhancedGolfTrackerExample> {
  late GolfTrackingService _golfTrackingService;
  late CameraController _cameraController;
  
  bool _isInitialized = false;
  bool _isTracking = false;
  String _statusMessage = 'Initializing...';
  
  // Real-time metrics
  Map<String, dynamic> _performanceStats = {};
  List<BoundingBox> _currentDetections = [];
  GolfShotData? _lastShotData;
  
  // Camera stream subscription
  StreamSubscription? _trackingEventSubscription;
  StreamSubscription? _shotDataSubscription;
  Timer? _statsUpdateTimer;

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  /// Initialize all services
  Future<void> _initializeServices() async {
    try {
      setState(() {
        _statusMessage = 'Initializing camera...';
      });
      
      // Initialize camera
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw Exception('No cameras available');
      }
      
      _cameraController = CameraController(
        cameras.first,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      
      await _cameraController.initialize();
      
      setState(() {
        _statusMessage = 'Initializing ML services...';
      });
      
      // Initialize golf tracking service
      _golfTrackingService = GolfTrackingService();
      final success = await _golfTrackingService.initialize();
      
      if (!success) {
        throw Exception('Failed to initialize golf tracking service');
      }
      
      // Subscribe to tracking events
      _trackingEventSubscription = _golfTrackingService.events.listen(_handleTrackingEvent);
      _shotDataSubscription = _golfTrackingService.shotData.listen(_handleShotData);
      
      // Start performance monitoring
      _startPerformanceMonitoring();
      
      setState(() {
        _isInitialized = true;
        _statusMessage = 'Ready to track golf shots';
      });
      
      print('Enhanced golf tracking system initialized successfully');
      
    } catch (e) {
      setState(() {
        _statusMessage = 'Initialization failed: $e';
      });
      print('Initialization error: $e');
    }
  }

  /// Handle tracking events
  void _handleTrackingEvent(GolfTrackingEvent event) {
    switch (event) {
      case GolfTrackingEvent.ballDetected:
        setState(() {
          _statusMessage = 'Ball detected - tracking started';
          _isTracking = true;
        });
        break;
      case GolfTrackingEvent.clubDetected:
        setState(() {
          _statusMessage = 'Club detected near ball';
        });
        break;
      case GolfTrackingEvent.impactDetected:
        setState(() {
          _statusMessage = 'Impact detected!';
        });
        break;
      case GolfTrackingEvent.ballInFlight:
        setState(() {
          _statusMessage = 'Ball in flight...';
        });
        break;
      case GolfTrackingEvent.ballLanded:
        setState(() {
          _statusMessage = 'Ball landed - analyzing shot';
        });
        break;
      case GolfTrackingEvent.trackingComplete:
        setState(() {
          _statusMessage = 'Shot analysis complete';
          _isTracking = false;
        });
        break;
    }
  }

  /// Handle completed shot data
  void _handleShotData(GolfShotData shotData) {
    setState(() {
      _lastShotData = shotData;
      _statusMessage = 'Shot: ${shotData.ballSpeed.toStringAsFixed(1)} m/s, '
                      '${shotData.launchAngle.toStringAsFixed(1)}°, '
                      '${shotData.carryDistance.toStringAsFixed(1)}m';
    });
    
    print('Shot completed: ${shotData.toJson()}');
  }

  /// Start performance monitoring
  void _startPerformanceMonitoring() {
    _statsUpdateTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (mounted) {
        setState(() {
          _performanceStats = _golfTrackingService.getPerformanceReport();
        });
      }
    });
  }

  /// Start camera stream and processing
  Future<void> _startCameraStream() async {
    if (!_cameraController.value.isInitialized) return;
    
    await _cameraController.startImageStream((CameraImage image) {
      if (!_isTracking && !_shouldStartTracking()) {
        return; // Only process frames when tracking is active or should start
      }
      
      // Convert CameraImage to format expected by inference service
      _processCameraImage(image);
    });
  }

  /// Determine if tracking should start based on current conditions
  bool _shouldStartTracking() {
    // Auto-start tracking logic could be implemented here
    // For now, we'll start tracking manually via UI
    return false;
  }

  /// Process camera image for inference
  void _processCameraImage(CameraImage image) async {
    try {
      // Convert CameraImage to Uint8List
      final Uint8List yuvBytes = _convertCameraImageToYUV(image);
      
      // Process frame through golf tracking service
      await _golfTrackingService.processFrame(
        yuvBytes,
        image.width,
        image.height,
        bytesPerRow: image.planes[0].bytesPerRow,
        uvBytesPerRow: image.planes[1].bytesPerRow,
      );
      
    } catch (e) {
      print('Error processing camera image: $e');
    }
  }

  /// Convert CameraImage to YUV bytes
  Uint8List _convertCameraImageToYUV(CameraImage image) {
    final planes = image.planes;
    final yPlane = planes[0];
    final uPlane = planes[1];
    final vPlane = planes[2];
    
    final ySize = yPlane.bytes.length;
    final uvSize = uPlane.bytes.length + vPlane.bytes.length;
    
    final yuvBytes = Uint8List(ySize + uvSize);
    
    // Copy Y plane
    yuvBytes.setRange(0, ySize, yPlane.bytes);
    
    // Interleave U and V planes for NV12 format
    int uvIndex = ySize;
    for (int i = 0; i < uPlane.bytes.length; i++) {
      yuvBytes[uvIndex++] = uPlane.bytes[i];
      if (i < vPlane.bytes.length) {
        yuvBytes[uvIndex++] = vPlane.bytes[i];
      }
    }
    
    return yuvBytes;
  }

  /// Start tracking manually
  void _startTracking() {
    if (_isInitialized && !_isTracking) {
      _golfTrackingService.startTracking();
      _startCameraStream();
    }
  }

  /// Stop tracking manually
  void _stopTracking() {
    if (_isTracking) {
      _golfTrackingService.stopTracking();
      _cameraController.stopImageStream();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Enhanced Golf Tracker'),
        backgroundColor: Colors.green[800],
      ),
      body: Column(
        children: [
          // Camera preview
          Expanded(
            flex: 3,
            child: _isInitialized 
              ? Stack(
                  children: [
                    CameraPreview(_cameraController),
                    // Overlay current detections
                    CustomPaint(
                      painter: DetectionOverlayPainter(_currentDetections),
                      size: Size.infinite,
                    ),
                    // Status overlay
                    Positioned(
                      top: 16,
                      left: 16,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _statusMessage,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                )
              : Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(_statusMessage),
                    ],
                  ),
                ),
          ),
          
          // Control panel
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              border: Border(
                top: BorderSide(color: Colors.grey[300]!),
              ),
            ),
            child: Column(
              children: [
                // Control buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _isInitialized && !_isTracking ? _startTracking : null,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start Tracking'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _isTracking ? _stopTracking : null,
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop Tracking'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),
                
                // Performance stats
                if (_performanceStats.isNotEmpty) ...[
                  const Text(
                    'Performance Stats',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      _buildStatChip('FPS', '${(_performanceStats['inference']?['estimatedFPS'] ?? 0).toStringAsFixed(1)}'),
                      _buildStatChip('Avg Time', '${(_performanceStats['inference']?['avgTime'] ?? 0).toStringAsFixed(1)}ms'),
                      _buildStatChip('Ball Det.', '${(_performanceStats['tracking']?['ballDetectionRate'] ?? 0 * 100).toStringAsFixed(1)}%'),
                      _buildStatChip('Club Det.', '${(_performanceStats['tracking']?['clubDetectionRate'] ?? 0 * 100).toStringAsFixed(1)}%'),
                    ],
                  ),
                ],
                
                // Last shot data
                if (_lastShotData != null) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Last Shot',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Ball Speed: ${_lastShotData!.ballSpeed.toStringAsFixed(1)} m/s'),
                        Text('Launch Angle: ${_lastShotData!.launchAngle.toStringAsFixed(1)}°'),
                        Text('Carry Distance: ${_lastShotData!.carryDistance.toStringAsFixed(1)} m'),
                        Text('Tracking Duration: ${_lastShotData!.trackingDuration.inMilliseconds} ms'),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, String value) {
    return Chip(
      label: Text('$label: $value'),
      backgroundColor: Colors.blue[100],
      labelStyle: const TextStyle(fontSize: 12),
    );
  }

  @override
  void dispose() {
    _statsUpdateTimer?.cancel();
    _trackingEventSubscription?.cancel();
    _shotDataSubscription?.cancel();
    _golfTrackingService.dispose();
    _cameraController.dispose();
    super.dispose();
  }
}

/// Custom painter for drawing detection overlays
class DetectionOverlayPainter extends CustomPainter {
  final List<BoundingBox> detections;

  DetectionOverlayPainter(this.detections);

  @override
  void paint(Canvas canvas, Size size) {
    for (final detection in detections) {
      final paint = Paint()
        ..color = detection.className == 'ball' ? Colors.red : Colors.blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      final rect = Rect.fromLTWH(
        detection.x,
        detection.y,
        detection.width,
        detection.height,
      );

      canvas.drawRect(rect, paint);

      // Draw label
      final textPainter = TextPainter(
        text: TextSpan(
          text: '${detection.className} ${(detection.confidence * 100).toInt()}%',
          style: TextStyle(
            color: detection.className == 'ball' ? Colors.red : Colors.blue,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      
      textPainter.layout();
      textPainter.paint(canvas, Offset(detection.x, detection.y - 20));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}