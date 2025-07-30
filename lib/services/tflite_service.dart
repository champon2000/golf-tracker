// lib/services/tflite_service.dart
import 'dart:typed_data';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:tflite_flutter_helper/tflite_flutter_helper.dart';
import '../models/bounding_box.dart';

class TFLiteService {
  Interpreter? _interpreter;
  List<List<int>>? _inputShape;
  List<List<int>>? _outputShape;
  TfLiteType? _inputType;
  TfLiteType? _outputType;
  
  // Model configuration
  static const String _modelPath = 'assets/models/golf_detection_model.tflite';
  static const int _inputSize = 640; // YOLO input size
  static const double _confidenceThreshold = 0.5;
  static const double _iouThreshold = 0.4;
  
  // Class labels
  static const List<String> _labels = ['ball', 'club_head'];

  Future<void> loadModel() async {
    try {
      // Create interpreter options
      final options = InterpreterOptions();
      
      // Try to use GPU delegate if available
      try {
        options.addDelegate(GpuDelegate());
      } catch (e) {
        print('GPU delegate not available, using CPU: $e');
      }
      
      // Load model from assets
      _interpreter = await Interpreter.fromAsset(_modelPath, options: options);
      
      // Get input and output shapes
      _inputShape = _interpreter!.getInputTensors().map((tensor) => tensor.shape).toList();
      _outputShape = _interpreter!.getOutputTensors().map((tensor) => tensor.shape).toList();
      _inputType = _interpreter!.getInputTensors().first.type;
      _outputType = _interpreter!.getOutputTensors().first.type;
      
      print('Model loaded successfully');
      print('Input shape: $_inputShape');
      print('Output shape: $_outputShape');
      print('Input type: $_inputType');
      print('Output type: $_outputType');
      
    } catch (e) {
      print('Error loading TFLite model: $e');
      rethrow;
    }
  }

  List<BoundingBox>? runInference(Uint8List yuvBytes, int width, int height) {
    if (_interpreter == null) {
      print('Model not loaded');
      return null;
    }

    try {
      // Preprocess image
      final preprocessedImage = _preprocessImage(yuvBytes, width, height);
      if (preprocessedImage == null) return null;

      // Prepare input and output tensors
      final input = [preprocessedImage];
      final output = <int, Object>{};
      
      // Initialize output tensor
      final outputTensor = List.filled(_outputShape![0][1] * _outputShape![0][2], 0.0)
          .reshape(_outputShape![0].sublist(1));
      output[0] = outputTensor;

      // Run inference
      _interpreter!.runForMultipleInputs(input, output);

      // Post-process results
      final detections = _postprocessOutput(output[0] as List<List<double>>, width, height);
      
      return detections;
    } catch (e) {
      print('Error during inference: $e');
      return null;
    }
  }

  Float32List? _preprocessImage(Uint8List yuvBytes, int width, int height) {
    try {
      // Convert YUV420 to RGB
      final rgbBytes = _yuv420ToRgb(yuvBytes, width, height);
      if (rgbBytes == null) return null;

      // Resize to model input size
      final resizedImage = _resizeImage(rgbBytes, width, height, _inputSize, _inputSize);
      
      // Normalize pixel values to [0, 1]
      final normalizedImage = Float32List(_inputSize * _inputSize * 3);
      for (int i = 0; i < normalizedImage.length; i++) {
        normalizedImage[i] = resizedImage[i] / 255.0;
      }

      return normalizedImage;
    } catch (e) {
      print('Error preprocessing image: $e');
      return null;
    }
  }

  Uint8List? _yuv420ToRgb(Uint8List yuvBytes, int width, int height) {
    try {
      final rgbBytes = Uint8List(width * height * 3);
      int rgbIndex = 0;

      // Simple YUV420 to RGB conversion
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final yIndex = y * width + x;
          final uvIndex = (y ~/ 2) * (width ~/ 2) + (x ~/ 2);
          
          if (yIndex >= yuvBytes.length) break;
          
          final yValue = yuvBytes[yIndex];
          final uValue = yuvBytes.length > width * height + uvIndex ? 
              yuvBytes[width * height + uvIndex] : 128;
          final vValue = yuvBytes.length > width * height + (width * height ~/ 4) + uvIndex ? 
              yuvBytes[width * height + (width * height ~/ 4) + uvIndex] : 128;

          // YUV to RGB conversion
          final r = (yValue + 1.402 * (vValue - 128)).clamp(0, 255).toInt();
          final g = (yValue - 0.344136 * (uValue - 128) - 0.714136 * (vValue - 128)).clamp(0, 255).toInt();
          final b = (yValue + 1.772 * (uValue - 128)).clamp(0, 255).toInt();

          if (rgbIndex + 2 < rgbBytes.length) {
            rgbBytes[rgbIndex++] = r;
            rgbBytes[rgbIndex++] = g;
            rgbBytes[rgbIndex++] = b;
          }
        }
      }

      return rgbBytes;
    } catch (e) {
      print('Error converting YUV to RGB: $e');
      return null;
    }
  }

  Uint8List _resizeImage(Uint8List imageBytes, int originalWidth, int originalHeight, 
                        int targetWidth, int targetHeight) {
    final resizedBytes = Uint8List(targetWidth * targetHeight * 3);
    
    final xRatio = originalWidth / targetWidth;
    final yRatio = originalHeight / targetHeight;

    for (int y = 0; y < targetHeight; y++) {
      for (int x = 0; x < targetWidth; x++) {
        final originalX = (x * xRatio).floor();
        final originalY = (y * yRatio).floor();
        
        final originalIndex = (originalY * originalWidth + originalX) * 3;
        final resizedIndex = (y * targetWidth + x) * 3;
        
        if (originalIndex + 2 < imageBytes.length && resizedIndex + 2 < resizedBytes.length) {
          resizedBytes[resizedIndex] = imageBytes[originalIndex];
          resizedBytes[resizedIndex + 1] = imageBytes[originalIndex + 1];
          resizedBytes[resizedIndex + 2] = imageBytes[originalIndex + 2];
        }
      }
    }

    return resizedBytes;
  }

  List<BoundingBox> _postprocessOutput(List<List<double>> rawOutput, int imageWidth, int imageHeight) {
    final detections = <BoundingBox>[];
    
    try {
      // Assuming YOLO format: [x_center, y_center, width, height, confidence, class_scores...]
      for (int i = 0; i < rawOutput.length; i++) {
        final detection = rawOutput[i];
        
        if (detection.length < 5) continue;
        
        final confidence = detection[4];
        if (confidence < _confidenceThreshold) continue;
        
        // Find the class with highest score
        double maxClassScore = 0.0;
        int classIndex = 0;
        
        for (int j = 5; j < detection.length; j++) {
          if (detection[j] > maxClassScore) {
            maxClassScore = detection[j];
            classIndex = j - 5;
          }
        }
        
        final finalConfidence = confidence * maxClassScore;
        if (finalConfidence < _confidenceThreshold) continue;
        
        // Convert from normalized coordinates to pixel coordinates
        final centerX = detection[0] * imageWidth;
        final centerY = detection[1] * imageHeight;
        final width = detection[2] * imageWidth;
        final height = detection[3] * imageHeight;
        
        // Convert from center coordinates to top-left coordinates
        final x = centerX - width / 2;
        final y = centerY - height / 2;
        
        final className = classIndex < _labels.length ? _labels[classIndex] : 'unknown';
        
        detections.add(BoundingBox(
          x: x,
          y: y,
          width: width,
          height: height,
          confidence: finalConfidence,
          className: className,
        ));
      }
      
      // Apply Non-Maximum Suppression
      return _applyNMS(detections);
      
    } catch (e) {
      print('Error post-processing output: $e');
      return [];
    }
  }

  List<BoundingBox> _applyNMS(List<BoundingBox> detections) {
    if (detections.isEmpty) return detections;
    
    // Sort by confidence in descending order
    detections.sort((a, b) => b.confidence.compareTo(a.confidence));
    
    final filteredDetections = <BoundingBox>[];
    final suppressed = List<bool>.filled(detections.length, false);
    
    for (int i = 0; i < detections.length; i++) {
      if (suppressed[i]) continue;
      
      filteredDetections.add(detections[i]);
      
      // Suppress overlapping detections
      for (int j = i + 1; j < detections.length; j++) {
        if (suppressed[j]) continue;
        
        // Only apply NMS to same class detections
        if (detections[i].className != detections[j].className) continue;
        
        final iou = detections[i].iou(detections[j]);
        if (iou > _iouThreshold) {
          suppressed[j] = true;
        }
      }
    }
    
    return filteredDetections;
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }
}