// lib/services/tflite_service_enhanced.dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

// Detection results data class
class BoundingBox {
  final double x;
  final double y;
  final double width;
  final double height;
  final double confidence;
  final String className;
  final int classId;

  BoundingBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.confidence,
    required this.className,
    required this.classId,
  });

  // Get center point of bounding box
  Offset get center => Offset(x + width / 2, y + height / 2);

  @override
  String toString() {
    return 'BoundingBox(class: $className, conf: ${confidence.toStringAsFixed(3)}, '
           'x: ${x.toStringAsFixed(1)}, y: ${y.toStringAsFixed(1)}, '
           'w: ${width.toStringAsFixed(1)}, h: ${height.toStringAsFixed(1)})';
  }
}

class Offset {
  final double dx;
  final double dy;

  const Offset(this.dx, this.dy);
  static const Offset zero = Offset(0.0, 0.0);

  Offset operator +(Offset other) => Offset(dx + other.dx, dy + other.dy);
  Offset operator -(Offset other) => Offset(dx - other.dx, dy - other.dy);
  Offset operator /(double operand) => Offset(dx / operand, dy / operand);

  double get distance => math.sqrt(dx * dx + dy * dy);
}

class TFLiteService {
  late Interpreter _interpreter;
  late List<List<int>> _inputShape;
  late List<List<int>> _outputShape;
  late TfLiteType _inputType;
  late TfLiteType _outputType;
  
  // Performance monitoring
  int _inferenceCount = 0;
  double _totalInferenceTime = 0.0;
  
  // Model configuration
  static const int INPUT_SIZE = 640;
  static const double CONFIDENCE_THRESHOLD = 0.25;
  static const double NMS_THRESHOLD = 0.45;
  static const List<String> CLASS_NAMES = ['ball', 'club_head'];
  
  // Memory optimization - reuse buffers
  late Float32List _inputBuffer;
  late List<List<List<double>>> _outputBuffer;

  /// Initialize the TFLite model with GPU delegate optimization
  Future<void> loadModel() async {
    try {
      // Create interpreter options with GPU delegate
      final options = InterpreterOptions();
      
      // Try to add GPU delegate with error handling
      try {
        final gpuDelegate = GpuDelegateV2(
          options: GpuDelegateOptionsV2(
            isPrecisionLossAllowed: false,
            inferencePreference: TfLiteGpuInferenceUsage.fastSingleAnswer,
            inferencePriority1: TfLiteGpuInferencePriority.minLatency,
            inferencePriority2: TfLiteGpuInferencePriority.auto,
            inferencePriority3: TfLiteGpuInferencePriority.auto,
          ),
        );
        options.addDelegate(gpuDelegate);
        print('GPU delegate added successfully');
      } catch (e) {
        print('Failed to add GPU delegate, falling back to CPU: $e');
      }

      // Load the model
      _interpreter = await Interpreter.fromAsset(
        'assets/models/golfclub_ball_yolov8n.tflite',
        options: options,
      );

      // Get input/output tensor information
      _inputShape = _interpreter.getInputTensors().map((tensor) => tensor.shape).toList();
      _outputShape = _interpreter.getOutputTensors().map((tensor) => tensor.shape).toList();
      _inputType = _interpreter.getInputTensors().first.type;
      _outputType = _interpreter.getOutputTensors().first.type;

      // Pre-allocate buffers for performance
      final int inputSize = _inputShape[0].reduce((a, b) => a * b);
      _inputBuffer = Float32List(inputSize);
      
      // YOLOv8n output shape is typically [1, 84, 8400] or [1, 8400, 84]
      // where 84 = 4 (bbox coords) + 80 (COCO classes), but we have 2 classes
      // So our output should be [1, 6, 8400] or [1, 8400, 6]
      _outputBuffer = List.generate(
        _outputShape[0][0],
        (i) => List.generate(
          _outputShape[0][1],
          (j) => List.generate(_outputShape[0][2], (k) => 0.0),
        ),
      );

      print('TFLite model loaded successfully!');
      print('Input shape: $_inputShape, Input type: $_inputType');
      print('Output shape: $_outputShape, Output type: $_outputType');
    } catch (e) {
      print('Failed to load TFLite model: $e');
      rethrow;
    }
  }

  /// Convert YUV420 bytes to RGB image with proper stride handling
  img.Image _convertYuv420ToRgb(Uint8List yuvBytes, int width, int height, 
                                int bytesPerRow, int uvBytesPerRow) {
    // Calculate plane sizes
    final int ySize = bytesPerRow * height;
    final int uvPixelStride = 2; // NV12 format has UV interleaved
    final int uvSize = uvBytesPerRow * (height ~/ 2);
    
    // Ensure we have enough data
    if (yuvBytes.length < ySize + uvSize) {
      throw ArgumentError('Insufficient YUV data: expected ${ySize + uvSize}, got ${yuvBytes.length}');
    }

    // Extract Y plane
    final yPlane = yuvBytes.sublist(0, ySize);
    // Extract UV plane (interleaved U and V)
    final uvPlane = yuvBytes.sublist(ySize, ySize + uvSize);

    // Create RGB image
    final rgbImage = img.Image(width: width, height: height);

    // Convert YUV to RGB pixel by pixel
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        // Get Y value
        final int yIndex = y * bytesPerRow + x;
        if (yIndex >= yPlane.length) continue;
        final int yValue = yPlane[yIndex];

        // Get UV values (subsampled by 2)
        final int uvY = y ~/ 2;
        final int uvX = x ~/ 2;
        final int uvIndex = uvY * uvBytesPerRow + uvX * uvPixelStride;
        
        int uValue = 128, vValue = 128; // Default neutral values
        if (uvIndex < uvPlane.length - 1) {
          uValue = uvPlane[uvIndex];
          vValue = uvPlane[uvIndex + 1];
        }

        // YUV to RGB conversion
        final int c = yValue - 16;
        final int d = uValue - 128;
        final int e = vValue - 128;

        final int r = ((298 * c + 409 * e + 128) >> 8).clamp(0, 255);
        final int g = ((298 * c - 100 * d - 208 * e + 128) >> 8).clamp(0, 255);
        final int b = ((298 * c + 516 * d + 128) >> 8).clamp(0, 255);

        rgbImage.setPixelRgba(x, y, r, g, b, 255);
      }
    }

    return rgbImage;
  }

  /// Preprocess image for YOLOv8n input (640x640 RGB, normalized to 0-1)
  Float32List _preprocessImage(img.Image image) {
    // Resize image to model input size
    final resizedImage = img.copyResize(image, width: INPUT_SIZE, height: INPUT_SIZE);
    
    // Convert to float array with normalization (0-1)
    final input = Float32List(1 * INPUT_SIZE * INPUT_SIZE * 3);
    int pixelIndex = 0;
    
    for (int y = 0; y < INPUT_SIZE; y++) {
      for (int x = 0; x < INPUT_SIZE; x++) {
        final pixel = resizedImage.getPixel(x, y);
        final r = img.getRed(pixel);
        final g = img.getGreen(pixel);
        final b = img.getBlue(pixel);
        
        // Normalize to 0-1 range
        input[pixelIndex++] = r / 255.0;
        input[pixelIndex++] = g / 255.0;
        input[pixelIndex++] = b / 255.0;
      }
    }
    
    return input;
  }

  /// Parse YOLOv8n output and extract bounding boxes
  List<BoundingBox> _parseYoloOutput(List<List<List<double>>> output, 
                                     int originalWidth, int originalHeight) {
    final List<BoundingBox> detections = [];
    
    // YOLOv8n output format: [1, 84, 8400] or [1, 8400, 84]
    // For our 2-class model: [1, 6, 8400] where 6 = 4 (bbox) + 2 (classes)
    final outputData = output[0]; // Remove batch dimension
    
    // Determine output format
    bool isTransposed = false;
    int numBoxes, numValues;
    
    if (outputData.length == 6 && outputData[0].length == 8400) {
      // Format: [6, 8400] - need to transpose
      numBoxes = outputData[0].length;
      numValues = outputData.length;
      isTransposed = true;
    } else if (outputData.length == 8400 && outputData[0].length == 6) {
      // Format: [8400, 6] - already in correct format
      numBoxes = outputData.length;
      numValues = outputData[0].length;
      isTransposed = false;
    } else {
      print('Unexpected output format: ${outputData.length} x ${outputData[0].length}');
      return detections;
    }

    // Calculate scale factors
    final double scaleX = originalWidth / INPUT_SIZE;
    final double scaleY = originalHeight / INPUT_SIZE;
    
    // Process each detection
    for (int i = 0; i < numBoxes; i++) {
      late double cx, cy, w, h, ballConf, clubConf;
      
      if (isTransposed) {
        // Extract values from transposed format [6, 8400]
        cx = outputData[0][i]; // center x
        cy = outputData[1][i]; // center y
        w = outputData[2][i];  // width
        h = outputData[3][i];  // height
        ballConf = outputData[4][i]; // ball confidence
        clubConf = outputData[5][i]; // club_head confidence
      } else {
        // Extract values from standard format [8400, 6]
        cx = outputData[i][0]; // center x
        cy = outputData[i][1]; // center y
        w = outputData[i][2];  // width
        h = outputData[i][3];  // height
        ballConf = outputData[i][4]; // ball confidence
        clubConf = outputData[i][5]; // club_head confidence
      }
      
      // Find the class with highest confidence
      double maxConf = math.max(ballConf, clubConf);
      int classId = ballConf > clubConf ? 0 : 1;
      
      // Filter by confidence threshold
      if (maxConf > CONFIDENCE_THRESHOLD) {
        // Convert center coordinates to top-left coordinates
        final double x = (cx - w / 2) * scaleX;
        final double y = (cy - h / 2) * scaleY;
        final double width = w * scaleX;
        final double height = h * scaleY;
        
        detections.add(BoundingBox(
          x: x.clamp(0, originalWidth.toDouble()),
          y: y.clamp(0, originalHeight.toDouble()),
          width: width,
          height: height,
          confidence: maxConf,
          className: CLASS_NAMES[classId],
          classId: classId,
        ));
      }
    }
    
    return detections;
  }

  /// Apply Non-Maximum Suppression to remove duplicate detections
  List<BoundingBox> _applyNMS(List<BoundingBox> detections) {
    if (detections.isEmpty) return detections;
    
    // Separate detections by class
    final Map<int, List<BoundingBox>> classSeparated = {};
    for (final detection in detections) {
      classSeparated.putIfAbsent(detection.classId, () => []).add(detection);
    }
    
    final List<BoundingBox> results = [];
    
    // Apply NMS for each class separately
    for (final classDetections in classSeparated.values) {
      results.addAll(_nmsForClass(classDetections));
    }
    
    return results;
  }
  
  /// Apply NMS for a single class
  List<BoundingBox> _nmsForClass(List<BoundingBox> detections) {
    // Sort by confidence (descending)
    detections.sort((a, b) => b.confidence.compareTo(a.confidence));
    
    final List<BoundingBox> results = [];
    final List<bool> suppressed = List.filled(detections.length, false);
    
    for (int i = 0; i < detections.length; i++) {
      if (suppressed[i]) continue;
      
      results.add(detections[i]);
      
      // Suppress overlapping boxes
      for (int j = i + 1; j < detections.length; j++) {
        if (suppressed[j]) continue;
        
        final double iou = _calculateIoU(detections[i], detections[j]);
        if (iou > NMS_THRESHOLD) {
          suppressed[j] = true;
        }
      }
    }
    
    return results;
  }
  
  /// Calculate Intersection over Union (IoU) between two bounding boxes
  double _calculateIoU(BoundingBox box1, BoundingBox box2) {
    final double x1 = math.max(box1.x, box2.x);
    final double y1 = math.max(box1.y, box2.y);
    final double x2 = math.min(box1.x + box1.width, box2.x + box2.width);
    final double y2 = math.min(box1.y + box1.height, box2.y + box2.height);
    
    if (x2 <= x1 || y2 <= y1) return 0.0;
    
    final double intersection = (x2 - x1) * (y2 - y1);
    final double area1 = box1.width * box1.height;
    final double area2 = box2.width * box2.height;
    final double union = area1 + area2 - intersection;
    
    return union > 0 ? intersection / union : 0.0;
  }

  /// Main inference method - optimized for 240fps processing
  List<BoundingBox>? runInference(Uint8List yuvBytes, int width, int height, 
                                  {int? bytesPerRow, int? uvBytesPerRow}) async {
    if (!_interpreter.isAllocated) {
      print('Model not loaded yet');
      return null;
    }

    final stopwatch = Stopwatch()..start();
    
    try {
      // Use provided stride values or calculate defaults
      final int actualBytesPerRow = bytesPerRow ?? width;
      final int actualUvBytesPerRow = uvBytesPerRow ?? width;
      
      // Step 1: Convert YUV to RGB
      final img.Image rgbImage = _convertYuv420ToRgb(
        yuvBytes, width, height, actualBytesPerRow, actualUvBytesPerRow);
      
      // Step 2: Preprocess image
      final Float32List input = _preprocessImage(rgbImage);
      
      // Step 3: Run inference
      _interpreter.run(input.buffer.asUint8List().buffer, _outputBuffer.buffer);
      
      // Step 4: Parse output
      final List<BoundingBox> rawDetections = _parseYoloOutput(_outputBuffer, width, height);
      
      // Step 5: Apply NMS
      final List<BoundingBox> finalDetections = _applyNMS(rawDetections);
      
      stopwatch.stop();
      
      // Update performance metrics
      _inferenceCount++;
      _totalInferenceTime += stopwatch.elapsedMicroseconds / 1000.0; // Convert to milliseconds
      
      // Log performance every 100 inferences
      if (_inferenceCount % 100 == 0) {
        final avgTime = _totalInferenceTime / _inferenceCount;
        print('Inference #$_inferenceCount: ${stopwatch.elapsedMicroseconds / 1000.0}ms '
              '(avg: ${avgTime.toStringAsFixed(2)}ms, ${(1000 / avgTime).toStringAsFixed(1)} FPS)');
      }
      
      return finalDetections;
      
    } catch (e) {
      print('Inference failed: $e');
      return null;
    }
  }

  /// Get performance statistics
  Map<String, dynamic> getPerformanceStats() {
    if (_inferenceCount == 0) {
      return {'count': 0, 'avgTime': 0.0, 'estimatedFPS': 0.0};
    }
    
    final double avgTime = _totalInferenceTime / _inferenceCount;
    return {
      'count': _inferenceCount,
      'avgTime': avgTime,
      'estimatedFPS': 1000.0 / avgTime,
      'totalTime': _totalInferenceTime,
    };
  }

  /// Reset performance counters
  void resetPerformanceStats() {
    _inferenceCount = 0;
    _totalInferenceTime = 0.0;
  }

  /// Cleanup resources
  void dispose() {
    _interpreter.close();
    print('TFLite service disposed');
  }
}