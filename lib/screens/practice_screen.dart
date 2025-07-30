// lib/screens/practice_screen.dart
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import '../services/kalman.dart';
import '../services/tflite_service.dart';
import '../widgets/hud_overlay.dart';
import '../widgets/club_selector.dart';
import '../services/database_service.dart';
import '../services/app_state.dart';
import '../models/bounding_box.dart';

// Data model for isolate communication
class InferenceData {
  final Uint8List yuvBytes;
  final int width;
  final int height;
  final int bytesPerRow;
  final int uvBytesPerRow;
  final DateTime timestamp;

  InferenceData({
    required this.yuvBytes,
    required this.width,
    required this.height,
    required this.bytesPerRow,
    required this.uvBytesPerRow,
    required this.timestamp,
  });
}

// Result model for isolate communication
class InferenceResult {
  final List<Map<String, dynamic>>? detections;
  final double ballSpeed;
  final double launchAngle;
  final double estimatedCarryDistance;
  final double spinRate;
  final double trajectoryConfidence;
  final double inferenceTime;
  final bool ballDetected;
  final bool clubDetected;
  final String? error;

  InferenceResult({
    this.detections,
    this.ballSpeed = 0.0,
    this.launchAngle = 0.0,
    this.estimatedCarryDistance = 0.0,
    this.spinRate = 0.0,
    this.trajectoryConfidence = 0.0,
    this.inferenceTime = 0.0,
    this.ballDetected = false,
    this.clubDetected = false,
    this.error,
  });

  factory InferenceResult.error(String error) {
    return InferenceResult(error: error);
  }
}

// Enhanced isolate entry function with proper error handling
void inferenceIsolate(SendPort sendPort) async {
  final ReceivePort receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);

  TFLiteService? tfliteService;
  KalmanFilter2D? kalmanFilter;
  final List<Offset> ballCenterHistory = [];
  const int historyLength = 5;
  
  try {
    // Initialize TFLite service
    tfliteService = TFLiteService();
    await tfliteService.loadModel();

    // Initialize Kalman Filter
    kalmanFilter = KalmanFilter2D(
      initialPosition: Offset.zero,
      initialVelocityX: 0.0,
      initialVelocityY: 0.0,
      dt: 1.0 / 240.0,
      processNoisePos: 0.1,
      processNoiseVel: 0.01,
      measurementNoisePos: 1.0,
    );

    sendPort.send(InferenceResult()); // Signal successful initialization
  } catch (e) {
    sendPort.send(InferenceResult.error('Initialization failed: $e'));
    return;
  }

  await for (var message in receivePort) {
    if (message == 'dispose') {
      break;
    }
    
    if (message is InferenceData) {
      final startTime = DateTime.now();
      
      try {
        final List<BoundingBox>? detections = tfliteService!.runInference(
          message.yuvBytes,
          message.width,
          message.height,
        );

        Offset? ballCenter;
        Offset? clubHeadCenter;
        bool ballDetected = false;
        bool clubDetected = false;

        if (detections != null) {
          for (var box in detections) {
            if (box.className == 'ball' && box.confidence > 0.5) {
              ballCenter = box.center;
              ballDetected = true;
            } else if (box.className == 'club_head' && box.confidence > 0.5) {
              clubHeadCenter = box.center;
              clubDetected = true;
            }
          }
        }

        // Smooth ball center coordinates using enhanced Kalman filter
        if (ballCenter != null && kalmanFilter != null) {
          // Get confidence from ball detection
          final ballBox = detections?.firstWhere(
            (box) => box.className == 'ball',
            orElse: () => BoundingBox(x: 0, y: 0, width: 0, height: 0, confidence: 0.5, className: 'ball'),
          );
          final confidence = ballBox?.confidence ?? 0.5;
          
          final Offset smoothedBallCenter = kalmanFilter.update(ballCenter, confidence: confidence);
          ballCenterHistory.add(smoothedBallCenter);
          if (ballCenterHistory.length > historyLength) {
            ballCenterHistory.removeAt(0);
          }
        }

        // Calculate metrics
        double ballSpeed = 0.0;
        double launchAngle = 0.0;
        double estimatedCarryDistance = 0.0;
        double spinRate = 0.0;
        double trajectoryConfidence = 0.0;

        if (ballCenterHistory.length >= 3) {
          // Detect impact moment and calculate initial velocity
          bool isImpact = _detectImpact(ballCenterHistory, clubHeadCenter);

          if (isImpact) {
            final metrics = _calculateBallMetrics(
              ballCenterHistory,
              pixelsPerMeter: 100.0, // This should be calibrated based on camera setup
              cameraHeight: 1.5,
              cameraAngle: 0.0,
            );
            ballSpeed = metrics['speed'] ?? 0.0;
            launchAngle = metrics['angle'] ?? 0.0;
            estimatedCarryDistance = metrics['distance'] ?? 0.0;
            final spinRate = metrics['spinRate'] ?? 0.0;
            final trajectoryConfidence = metrics['confidence'] ?? 0.5;

            // Shot data will be stored in the main thread
          }
        }

        final inferenceTime = DateTime.now().difference(startTime).inMicroseconds / 1000.0;

        sendPort.send(InferenceResult(
          detections: detections?.map((box) => {
            'x': box.x,
            'y': box.y,
            'width': box.width,
            'height': box.height,
            'confidence': box.confidence,
            'className': box.className,
          }).toList(),
          ballSpeed: ballSpeed,
          launchAngle: launchAngle,
          estimatedCarryDistance: estimatedCarryDistance,
          spinRate: spinRate,
          trajectoryConfidence: trajectoryConfidence,
          inferenceTime: inferenceTime,
          ballDetected: ballDetected,
          clubDetected: clubDetected,
        ));
      } catch (e) {
        sendPort.send(InferenceResult.error('Inference error: $e'));
      }
    }
  }
}

// Enhanced impact detection with multiple criteria
bool _detectImpact(List<Offset> ballHistory, Offset? clubHeadCenter) {
  if (ballHistory.length < 5) return false;
  
  // Multi-criteria impact detection
  final recentBall = ballHistory.sublist(ballHistory.length - 5);
  
  // 1. Check for sudden velocity change (acceleration)
  final velocities = <Offset>[];
  for (int i = 1; i < recentBall.length; i++) {
    velocities.add(recentBall[i] - recentBall[i - 1]);
  }
  
  // Calculate acceleration magnitudes
  final accelerations = <double>[];
  for (int i = 1; i < velocities.length; i++) {
    final acceleration = (velocities[i] - velocities[i - 1]).distance;
    accelerations.add(acceleration);
  }
  
  final maxAcceleration = accelerations.isNotEmpty ? accelerations.reduce(math.max) : 0.0;
  final suddenAcceleration = maxAcceleration > 8.0; // Increased threshold
  
  // 2. Check for velocity direction change (impact signature)
  bool directionChange = false;
  if (velocities.length >= 3) {
    final beforeImpact = velocities[velocities.length - 3];
    final afterImpact = velocities[velocities.length - 1];
    
    // Check if velocity direction changed significantly
    final angleDiff = _angleBetweenVectors(beforeImpact, afterImpact);
    directionChange = angleDiff > 30.0; // 30 degrees threshold
  }
  
  // 3. Ball-club proximity check (if club is detected)
  bool proximityImpact = false;
  if (clubHeadCenter != null && ballHistory.isNotEmpty) {
    final ballCenter = ballHistory.last;
    final distance = (ballCenter - clubHeadCenter).distance;
    proximityImpact = distance < 50.0; // Proximity threshold in pixels
  }
  
  // 4. Check for ball motion pattern (stationary -> moving)
  bool motionPattern = false;
  if (ballHistory.length >= 4) {
    final earlyVelocities = velocities.take(2).map((v) => v.distance).toList();
    final lateVelocities = velocities.skip(2).map((v) => v.distance).toList();
    
    final avgEarlySpeed = earlyVelocities.reduce((a, b) => a + b) / earlyVelocities.length;
    final avgLateSpeed = lateVelocities.reduce((a, b) => a + b) / lateVelocities.length;
    
    // Ball was relatively stationary, then started moving
    motionPattern = avgEarlySpeed < 2.0 && avgLateSpeed > 5.0;
  }
  
  // Combine criteria for robust detection
  final criteriaCount = [suddenAcceleration, directionChange, proximityImpact, motionPattern]
      .where((criteria) => criteria).length;
  
  // Impact detected if at least 2 criteria are met
  return criteriaCount >= 2;
}

// Helper function to calculate angle between two vectors in degrees
double _angleBetweenVectors(Offset v1, Offset v2) {
  if (v1.distance == 0 || v2.distance == 0) return 0.0;
  
  final dot = v1.dx * v2.dx + v1.dy * v2.dy;
  final det = v1.dx * v2.dy - v1.dy * v2.dx;
  final angle = math.atan2(det, dot) * 180 / math.pi;
  
  return angle.abs();
}

// Enhanced physics calculations with coordinate system transformations
Map<String, double> _calculateBallMetrics(List<Offset> ballHistory, {
  double pixelsPerMeter = 100.0, // Calibration factor - pixels per meter
  double cameraHeight = 1.5, // Camera height in meters
  double cameraAngle = 0.0, // Camera tilt angle in degrees
}) {
  if (ballHistory.length < 3) return {};
  
  final p0 = ballHistory[ballHistory.length - 3];
  final p1 = ballHistory[ballHistory.length - 2];
  final p2 = ballHistory[ballHistory.length - 1];

  final displacement1 = p1 - p0;
  final displacement2 = p2 - p1;

  const double dt = 1.0 / 240.0;
  final avgVelocity = (displacement1 + displacement2) / (2 * dt);
  
  // Convert pixel velocity to real-world velocity (m/s)
  final realWorldVelocityX = avgVelocity.dx / pixelsPerMeter;
  final realWorldVelocityY = -avgVelocity.dy / pixelsPerMeter; // Flip Y axis (screen vs world)
  
  // Apply camera angle correction if needed
  final correctedVelocityX = realWorldVelocityX;
  final correctedVelocityY = realWorldVelocityY * math.cos(cameraAngle * math.pi / 180);
  final correctedVelocityZ = realWorldVelocityY * math.sin(cameraAngle * math.pi / 180);
  
  // Calculate 3D speed and launch angle
  final ballSpeed3D = math.sqrt(
    correctedVelocityX * correctedVelocityX + 
    correctedVelocityY * correctedVelocityY + 
    correctedVelocityZ * correctedVelocityZ
  );
  
  // Launch angle from horizontal plane
  final launchAngle = math.atan2(correctedVelocityZ, 
    math.sqrt(correctedVelocityX * correctedVelocityX + correctedVelocityY * correctedVelocityY)
  ) * 180 / math.pi;
  
  // Enhanced ballistic calculation with air resistance approximation
  const double g = 9.81;
  const double airDensity = 1.225; // kg/m³ at sea level
  const double ballMass = 0.0459; // kg (golf ball)
  const double ballRadius = 0.0214; // m (golf ball)
  const double dragCoefficient = 0.47; // Sphere drag coefficient
  
  // Cross-sectional area
  final ballArea = math.pi * ballRadius * ballRadius;
  
  // Drag force coefficient
  final dragForceCoeff = 0.5 * airDensity * dragCoefficient * ballArea / ballMass;
  
  // Simplified trajectory with air resistance (using average velocity approximation)
  final avgSpeed = ballSpeed3D * 0.7; // Approximation for drag effect
  final effectiveVx = avgSpeed * math.cos(launchAngle * math.pi / 180);
  final effectiveVz = avgSpeed * math.sin(launchAngle * math.pi / 180);
  
  // Time of flight with air resistance approximation
  var timeOfFlight = 2 * effectiveVz / g;
  if (timeOfFlight < 0) timeOfFlight = 0;
  
  // Carry distance with drag approximation
  final estimatedCarryDistance = effectiveVx * timeOfFlight;
  
  // Calculate spin rate estimation (simplified)
  final spinRate = _estimateSpinRate(ballHistory, dt);
  
  // Magnus effect approximation (for backspin)
  final magnusCoeff = 0.25; // Simplified Magnus coefficient
  final magnusLift = magnusCoeff * spinRate * ballSpeed3D * timeOfFlight;
  final adjustedDistance = estimatedCarryDistance + magnusLift;
  
  return {
    'speed': ballSpeed3D,
    'angle': launchAngle,
    'distance': math.max(0, adjustedDistance),
    'spinRate': spinRate,
    'confidence': _calculateTrajectoryConfidence(ballHistory),
  };
}

// Estimate spin rate from ball trajectory curvature
double _estimateSpinRate(List<Offset> ballHistory, double dt) {
  if (ballHistory.length < 4) return 0.0;
  
  // Calculate trajectory curvature
  final points = ballHistory.sublist(ballHistory.length - 4);
  
  // Simple curvature estimation using three points
  final p1 = points[0];
  final p2 = points[1];
  final p3 = points[2];
  final p4 = points[3];
  
  // Calculate vectors
  final v1 = p2 - p1;
  final v2 = p3 - p2;
  final v3 = p4 - p3;
  
  // Calculate change in direction
  final angle1 = math.atan2(v1.dy, v1.dx);
  final angle2 = math.atan2(v2.dy, v2.dx);
  final angle3 = math.atan2(v3.dy, v3.dx);
  
  final angularChange = ((angle2 - angle1) + (angle3 - angle2)) / 2;
  
  // Convert to approximate spin rate (rpm)
  final spinRate = (angularChange / (dt * 2 * math.pi)) * 60;
  
  return spinRate.abs().clamp(0, 10000); // Reasonable spin rate range
}

// Calculate confidence score for trajectory measurements
double _calculateTrajectoryConfidence(List<Offset> ballHistory) {
  if (ballHistory.length < 4) return 0.5;
  
  // Check trajectory smoothness
  final velocities = <double>[];
  for (int i = 1; i < ballHistory.length; i++) {
    final velocity = (ballHistory[i] - ballHistory[i - 1]).distance;
    velocities.add(velocity);
  }
  
  if (velocities.isEmpty) return 0.5;
  
  // Calculate velocity consistency
  final avgVelocity = velocities.reduce((a, b) => a + b) / velocities.length;
  final velocityVariance = velocities
      .map((v) => math.pow(v - avgVelocity, 2))
      .reduce((a, b) => a + b) / velocities.length;
  
  final velocityConsistency = 1.0 / (1.0 + velocityVariance / (avgVelocity * avgVelocity));
  
  // Check for reasonable trajectory shape
  final totalDistance = (ballHistory.last - ballHistory.first).distance;
  final pathDistance = ballHistory
      .asMap()
      .entries
      .skip(1)
      .map((entry) => (entry.value - ballHistory[entry.key - 1]).distance)
      .reduce((a, b) => a + b);
  
  final pathEfficiency = totalDistance / pathDistance;
  
  // Combine factors
  final confidence = (velocityConsistency + pathEfficiency) / 2.0;
  
  return confidence.clamp(0.0, 1.0);
}

// Helper function to store shot data with enhanced metrics
Future<void> _storeShotData(double speed, double angle, double distance, 
    String clubType, [double spinRate = 0.0, double confidence = 1.0]) async {
  try {
    await DatabaseService.instance.insertShot({
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'ball_speed': speed,
      'launch_angle': angle,
      'carry_distance': distance,
      'club_type': clubType,
      'spin_rate': spinRate,
      'confidence': confidence,
    });
  } catch (e) {
    print('Error storing shot data: $e');
  }
}

class PracticeScreen extends StatefulWidget {
  const PracticeScreen({super.key});

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen> with WidgetsBindingObserver {
  CameraController? _cameraController;
  bool _isCameraInitializing = false;
  StreamSubscription? _cameraStreamSubscription;
  final EventChannel _cameraStreamChannel = const EventChannel('com.example.golf_tracker/camera_stream');
  final MethodChannel _cameraControlChannel = const MethodChannel('com.example.golf_tracker/camera_control');

  List<BoundingBox> _boundingBoxes = [];
  double _ballSpeed = 0.0;
  double _launchAngle = 0.0;
  double _estimatedCarryDistance = 0.0;
  double _spinRate = 0.0;
  double _trajectoryConfidence = 0.0;

  Isolate? _inferenceIsolate;
  SendPort? _sendPort;
  ReceivePort? _receivePort;
  bool _isolateReady = false;
  String? _isolateError;

  // Performance monitoring
  final Stopwatch _frameStopwatch = Stopwatch();
  int _droppedFrames = 0;

  // Club selection
  String _selectedClub = 'driver';
  bool _showClubSelector = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
    _startInferenceIsolate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cleanupResources();
    super.dispose();
  }

  Future<void> _cleanupResources() async {
    await _cameraStreamSubscription?.cancel();
    await _cameraController?.dispose();
    
    _sendPort?.send('dispose');
    _inferenceIsolate?.kill(priority: Isolate.immediate);
    _receivePort?.close();
    
    if (mounted) {
      context.read<AppState>().setCameraInitialized(false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pauseCamera();
    } else if (state == AppLifecycleState.resumed) {
      _resumeCamera();
    }
  }

  Future<void> _pauseCamera() async {
    await _cameraStreamSubscription?.cancel();
    _cameraStreamSubscription = null;
  }

  Future<void> _resumeCamera() async {
    if (_cameraController?.value.isInitialized == true && _cameraStreamSubscription == null) {
      _setupCameraStream();
    }
  }

  Future<void> _initializeCamera() async {
    if (_isCameraInitializing) return;
    
    setState(() {
      _isCameraInitializing = true;
    });

    try {
      final cameras = await availableCameras();
      final backCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => throw Exception('No back camera found'),
      );

      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _cameraController!.initialize();
      
      if (!mounted) return;

      context.read<AppState>().setCameraInitialized(true);
      _setupCameraStream();

    } catch (e) {
      if (mounted) {
        context.read<AppState>().setError('Camera initialization failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCameraInitializing = false;
        });
      }
    }
  }

  void _setupCameraStream() {
    _cameraStreamSubscription = _cameraStreamChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (!_isolateReady) return;
        
        _frameStopwatch.reset();
        _frameStopwatch.start();
        
        if (event is Map) {
          try {
            final inferenceData = InferenceData(
              yuvBytes: event['buffer'] as Uint8List,
              width: event['width'] as int,
              height: event['height'] as int,
              bytesPerRow: event['bytesPerRow'] as int,
              uvBytesPerRow: event['uvBytesPerRow'] as int,
              timestamp: DateTime.now(),
            );

            _sendPort?.send(inferenceData);
            context.read<AppState>().updateFrameMetrics();
          } catch (e) {
            print('Error processing camera frame: $e');
          }
        }
      },
      onError: (error) {
        print('Camera stream error: $error');
        context.read<AppState>().setError('Camera stream error: $error');
        _retryCamera();
      },
      cancelOnError: false,
    );
  }

  Future<void> _retryCamera() async {
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) {
      _initializeCamera();
    }
  }

  Future<void> _startInferenceIsolate() async {
    try {
      _receivePort = ReceivePort();
      _inferenceIsolate = await Isolate.spawn(inferenceIsolate, _receivePort!.sendPort);

      _receivePort!.listen((dynamic message) {
        if (message is SendPort) {
          _sendPort = message;
          setState(() {
            _isolateReady = true;
            _isolateError = null;
          });
        } else if (message is InferenceResult) {
          if (message.error != null) {
            setState(() {
              _isolateError = message.error;
              _isolateReady = false;
            });
            context.read<AppState>().setError(message.error);
          } else {
            _updateUIWithResults(message);
          }
        }
      });
    } catch (e) {
      setState(() {
        _isolateError = 'Failed to start inference isolate: $e';
        _isolateReady = false;
      });
      context.read<AppState>().setError(_isolateError);
    }
  }

  void _updateUIWithResults(InferenceResult result) {
    if (!mounted) return;
    
    setState(() {
      if (result.detections != null) {
        _boundingBoxes = result.detections!.map((boxMap) => BoundingBox(
          x: boxMap['x'] as double,
          y: boxMap['y'] as double,
          width: boxMap['width'] as double,
          height: boxMap['height'] as double,
          confidence: boxMap['confidence'] as double,
          className: boxMap['className'] as String,
        )).toList();
      }
      _ballSpeed = result.ballSpeed;
      _launchAngle = result.launchAngle;
      _estimatedCarryDistance = result.estimatedCarryDistance;
      _spinRate = result.spinRate;
      _trajectoryConfidence = result.trajectoryConfidence;
    });

    // Update app state with detection metrics
    context.read<AppState>().updateDetectionMetrics(
      ballDetected: result.ballDetected,
      clubDetected: result.clubDetected,
      inferenceTime: result.inferenceTime,
    );

    // Store shot data with enhanced metrics (if high quality)
    if (result.ballSpeed > 1.0 && result.trajectoryConfidence > 0.3) {
      _storeShotData(
        result.ballSpeed,
        result.launchAngle,
        result.estimatedCarryDistance,
        _selectedClub,
        result.spinRate,
        result.trajectoryConfidence,
      );
    }
  }

  Widget _buildErrorScreen(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red[400],
            ),
            const SizedBox(height: 16),
            Text(
              'Camera Error',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              error,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                context.read<AppState>().clearError();
                _initializeCamera();
                _startInferenceIsolate();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingScreen() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Initializing camera and AI model...'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        if (appState.errorMessage != null) {
          return _buildErrorScreen(appState.errorMessage!);
        }

        if (_isCameraInitializing || !_isolateReady || 
            _cameraController == null || !_cameraController!.value.isInitialized) {
          return _buildLoadingScreen();
        }

        // Calculate preview size
        final Size mediaSize = MediaQuery.of(context).size;
        final double aspectRatio = _cameraController!.value.aspectRatio;
        double previewWidth = mediaSize.width;
        double previewHeight = previewWidth / aspectRatio;

        if (previewHeight > mediaSize.height) {
          previewHeight = mediaSize.height;
          previewWidth = previewHeight * aspectRatio;
        }

        return Stack(
          children: [
            // Camera preview
            Center(
              child: SizedBox(
                width: previewWidth,
                height: previewHeight,
                child: CameraPreview(_cameraController!),
              ),
            ),
            // HUD overlay
            HUDOverlay(
              ballSpeed: _ballSpeed,
              launchAngle: _launchAngle,
              estimatedCarryDistance: _estimatedCarryDistance,
              spinRate: _spinRate,
              trajectoryConfidence: _trajectoryConfidence,
              fps: appState.fps,
              frameCount: appState.frameCount,
              ballDetectionCount: appState.ballDetectionCount,
              clubDetectionCount: appState.clubDetectionCount,
              averageInferenceTime: appState.averageInferenceTime,
            ),
            // Bounding boxes overlay
            Positioned.fill(
              child: CustomPaint(
                painter: BoundingBoxPainter(
                  boundingBoxes: _boundingBoxes,
                  previewSize: Size(previewWidth, previewHeight),
                  imageSize: _cameraController!.value.previewSize!,
                ),
              ),
            ),
            // Club selector button
            Positioned(
              top: MediaQuery.of(context).padding.top + 60,
              left: 16,
              child: ClubSelectorButton(
                selectedClub: _selectedClub,
                onTap: () => setState(() => _showClubSelector = !_showClubSelector),
              ),
            ),
            // Club selector overlay
            if (_showClubSelector)
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => setState(() => _showClubSelector = false),
                  child: Container(
                    color: Colors.black.withOpacity(0.5),
                    child: Center(
                      child: GestureDetector(
                        onTap: () {}, // Prevent dismissal when tapping on selector
                        child: ClubSelector(
                          selectedClub: _selectedClub,
                          onClubSelected: (club) {
                            setState(() {
                              _selectedClub = club;
                              _showClubSelector = false;
                            });
                          },
                          isVisible: _showClubSelector,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}