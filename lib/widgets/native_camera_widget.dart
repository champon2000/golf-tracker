import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../services/native_camera_service.dart';

/// Widget that displays native camera stream with performance monitoring
class NativeCameraWidget extends StatefulWidget {
  final Function(CameraFrame)? onFrameAvailable;
  final bool showPerformanceOverlay;
  
  const NativeCameraWidget({
    Key? key,
    this.onFrameAvailable,
    this.showPerformanceOverlay = false,
  }) : super(key: key);
  
  @override
  State<NativeCameraWidget> createState() => _NativeCameraWidgetState();
}

class _NativeCameraWidgetState extends State<NativeCameraWidget> {
  final NativeCameraService _cameraService = NativeCameraService();
  StreamSubscription<CameraFrame>? _frameSubscription;
  
  // Camera state
  bool _isInitialized = false;
  bool _useFrontCamera = false;
  CameraStreamInfo? _streamInfo;
  CameraPerformanceMetrics? _performanceMetrics;
  
  // Image display
  ui.Image? _currentImage;
  Timer? _performanceTimer;
  
  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }
  
  Future<void> _initializeCamera() async {
    try {
      // Check camera availability
      final cameraInfo = await _cameraService.getCameraInfo();
      if (!cameraInfo.hasBackCamera && !cameraInfo.hasFrontCamera) {
        _showError('No cameras available');
        return;
      }
      
      // Start camera stream
      _streamInfo = await _cameraService.startCameraStream(
        useFrontCamera: _useFrontCamera,
      );
      
      // Subscribe to frame stream
      _frameSubscription = _cameraService.frameStream.listen(
        _onFrameReceived,
        onError: (error) {
          _showError('Camera stream error: $error');
        },
      );
      
      // Start performance monitoring
      if (widget.showPerformanceOverlay) {
        _startPerformanceMonitoring();
      }
      
      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      _showError('Failed to initialize camera: $e');
    }
  }
  
  void _onFrameReceived(CameraFrame frame) {
    // Notify external listener
    widget.onFrameAvailable?.call(frame);
    
    // Convert YUV to image for display
    _convertFrameToImage(frame);
  }
  
  Future<void> _convertFrameToImage(CameraFrame frame) async {
    try {
      // For YUV420 format, we need to convert to RGB
      // This is a simplified conversion - in production, use native conversion
      final completer = Completer<ui.Image>();
      
      // Create RGBA buffer from YUV (simplified conversion)
      final rgbaBuffer = _yuv420ToRgba(
        frame.data,
        frame.width,
        frame.height,
      );
      
      // Decode image from RGBA buffer
      ui.decodeImageFromPixels(
        rgbaBuffer,
        frame.width,
        frame.height,
        ui.PixelFormat.rgba8888,
        (ui.Image image) {
          if (mounted) {
            setState(() {
              _currentImage?.dispose();
              _currentImage = image;
            });
          }
          completer.complete(image);
        },
      );
    } catch (e) {
      print('Error converting frame to image: $e');
    }
  }
  
  Uint8List _yuv420ToRgba(Uint8List yuv, int width, int height) {
    final rgba = Uint8List(width * height * 4);
    final frameSize = width * height;
    
    for (int j = 0, yp = 0; j < height; j++) {
      int uvp = frameSize + (j >> 1) * width;
      int u = 0, v = 0;
      
      for (int i = 0; i < width; i++, yp++) {
        int y = yuv[yp] & 0xff;
        
        if ((i & 1) == 0) {
          v = yuv[uvp++] & 0xff;
          u = yuv[uvp++] & 0xff;
        }
        
        // YUV to RGB conversion
        int r = (y + 1.370705 * (v - 128)).round().clamp(0, 255);
        int g = (y - 0.698001 * (v - 128) - 0.337633 * (u - 128)).round().clamp(0, 255);
        int b = (y + 1.732446 * (u - 128)).round().clamp(0, 255);
        
        rgba[yp * 4] = r;
        rgba[yp * 4 + 1] = g;
        rgba[yp * 4 + 2] = b;
        rgba[yp * 4 + 3] = 255;
      }
    }
    
    return rgba;
  }
  
  void _startPerformanceMonitoring() {
    _performanceTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updatePerformanceMetrics(),
    );
  }
  
  Future<void> _updatePerformanceMetrics() async {
    if (!mounted) return;
    
    try {
      final metrics = await _cameraService.getPerformanceMetrics();
      setState(() {
        _performanceMetrics = metrics;
      });
    } catch (e) {
      print('Error getting performance metrics: $e');
    }
  }
  
  Future<void> _switchCamera() async {
    setState(() {
      _useFrontCamera = !_useFrontCamera;
    });
    
    try {
      await _cameraService.switchCamera(useFrontCamera: _useFrontCamera);
    } catch (e) {
      _showError('Failed to switch camera: $e');
    }
  }
  
  void _showError(String message) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Camera preview
        if (_currentImage != null)
          CustomPaint(
            painter: _ImagePainter(_currentImage!),
            size: Size.infinite,
          )
        else if (_isInitialized)
          const Center(
            child: CircularProgressIndicator(),
          )
        else
          const Center(
            child: Text('Initializing camera...'),
          ),
        
        // Performance overlay
        if (widget.showPerformanceOverlay && _performanceMetrics != null)
          Positioned(
            top: 50,
            left: 10,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'FPS: ${_performanceMetrics!.currentFps.toStringAsFixed(1)}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  Text(
                    'Avg FPS: ${_performanceMetrics!.averageFps.toStringAsFixed(1)}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  Text(
                    'Dropped: ${_performanceMetrics!.droppedFramesPercent.toStringAsFixed(1)}%',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  Text(
                    'Memory: ${_performanceMetrics!.memoryUsageMB}MB',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        
        // Camera switch button
        Positioned(
          bottom: 30,
          right: 30,
          child: FloatingActionButton(
            onPressed: _switchCamera,
            child: Icon(
              _useFrontCamera ? Icons.camera_front : Icons.camera_rear,
            ),
          ),
        ),
      ],
    );
  }
  
  @override
  void dispose() {
    _performanceTimer?.cancel();
    _frameSubscription?.cancel();
    _currentImage?.dispose();
    _cameraService.stopCameraStream();
    super.dispose();
  }
}

class _ImagePainter extends CustomPainter {
  final ui.Image image;
  
  _ImagePainter(this.image);
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..filterQuality = FilterQuality.medium;
    
    // Calculate scaling to fit the screen while maintaining aspect ratio
    final imageAspectRatio = image.width / image.height;
    final screenAspectRatio = size.width / size.height;
    
    double drawWidth, drawHeight;
    double offsetX = 0, offsetY = 0;
    
    if (imageAspectRatio > screenAspectRatio) {
      // Image is wider than screen
      drawWidth = size.width;
      drawHeight = size.width / imageAspectRatio;
      offsetY = (size.height - drawHeight) / 2;
    } else {
      // Image is taller than screen
      drawHeight = size.height;
      drawWidth = size.height * imageAspectRatio;
      offsetX = (size.width - drawWidth) / 2;
    }
    
    final destRect = Rect.fromLTWH(offsetX, offsetY, drawWidth, drawHeight);
    final srcRect = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    
    canvas.drawImageRect(image, srcRect, destRect, paint);
  }
  
  @override
  bool shouldRepaint(_ImagePainter oldDelegate) => oldDelegate.image != image;
}