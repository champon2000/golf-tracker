// lib/widgets/hud_overlay.dart
import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../models/bounding_box.dart';

class HUDOverlay extends StatelessWidget {
  final double ballSpeed; // Ball speed (m/s)
  final double launchAngle; // Launch angle (degrees)
  final double estimatedCarryDistance; // Estimated carry distance (m)
  final double spinRate; // Spin rate (rpm)
  final double trajectoryConfidence; // Trajectory confidence score
  final double fps; // Current FPS
  final int frameCount; // Total frame count
  final int ballDetectionCount; // Number of ball detections
  final int clubDetectionCount; // Number of club detections
  final double averageInferenceTime; // Average inference time (ms)

  const HUDOverlay({
    super.key,
    required this.ballSpeed,
    required this.launchAngle,
    required this.estimatedCarryDistance,
    this.spinRate = 0.0,
    this.trajectoryConfidence = 0.0,
    this.fps = 0.0,
    this.frameCount = 0,
    this.ballDetectionCount = 0,
    this.clubDetectionCount = 0,
    this.averageInferenceTime = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Main metrics panel
        Positioned(
          right: 16.0,
          top: 16.0,
          child: _buildMainMetricsPanel(context),
        ),
        // Performance metrics panel
        Positioned(
          left: 16.0,
          top: 16.0,
          child: _buildPerformancePanel(context),
        ),
        // Status indicators
        Positioned(
          left: 16.0,
          bottom: 80.0,
          child: _buildStatusIndicators(context),
        ),
        // Speed gauge
        if (ballSpeed > 0)
          Positioned(
            right: 16.0,
            bottom: 100.0,
            child: _buildSpeedGauge(context),
          ),
      ],
    );
  }

  Widget _buildMainMetricsPanel(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 12.0,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildMetricRow(
            'Ball Speed',
            '${ballSpeed.toStringAsFixed(1)} m/s', 
            ballSpeed > 10 ? Colors.green : Colors.white,
            Icons.speed,
          ),
          const SizedBox(height: 12.0),
          _buildMetricRow(
            'Launch Angle',
            '${launchAngle.toStringAsFixed(1)}°',
            _getAngleColor(launchAngle),
            Icons.trending_up,
          ),
          const SizedBox(height: 12.0),
          _buildMetricRow(
            'Carry Distance',
            '${estimatedCarryDistance.toStringAsFixed(1)} m',
            estimatedCarryDistance > 50 ? Colors.green : Colors.white,
            Icons.golf_course,
          ),
          const SizedBox(height: 12.0),
          _buildMetricRow(
            'Spin Rate',
            '${spinRate.toStringAsFixed(0)} rpm',
            _getSpinRateColor(spinRate),
            Icons.rotate_right,
          ),
          const SizedBox(height: 12.0),
          _buildMetricRow(
            'Confidence',
            '${(trajectoryConfidence * 100).toStringAsFixed(0)}%',
            _getConfidenceColor(trajectoryConfidence),
            Icons.check_circle,
          ),
        ],
      ),
    );
  }

  Widget _buildPerformancePanel(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Performance',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 12.0,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8.0),
          _buildCompactMetric('FPS', '${fps.toStringAsFixed(1)}', _getFPSColor(fps)),
          _buildCompactMetric('Frames', '$frameCount', Colors.white70),
          _buildCompactMetric('Inference', '${averageInferenceTime.toStringAsFixed(1)}ms', 
            _getInferenceColor(averageInferenceTime)),
        ],
      ),
    );
  }

  Widget _buildStatusIndicators(BuildContext context) {
    return Row(
      children: [
        _buildStatusIndicator(
          'Ball',
          ballDetectionCount > 0,
          Colors.orange,
          Icons.sports_golf,
        ),
        const SizedBox(width: 12.0),
        _buildStatusIndicator(
          'Club',
          clubDetectionCount > 0,
          Colors.blue,
          Icons.golf_course,
        ),
      ],
    );
  }

  Widget _buildStatusIndicator(String label, bool isActive, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: isActive ? color.withOpacity(0.2) : Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(20.0),
        border: Border.all(
          color: isActive ? color : Colors.white.withOpacity(0.2),
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16.0,
            color: isActive ? color : Colors.white.withOpacity(0.5),
          ),
          const SizedBox(width: 4.0),
          Text(
            label,
            style: TextStyle(
              color: isActive ? color : Colors.white.withOpacity(0.5),
              fontSize: 12.0,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedGauge(BuildContext context) {
    return Container(
      width: 80,
      height: 80,
      child: CustomPaint(
        painter: SpeedGaugePainter(ballSpeed),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${ballSpeed.toStringAsFixed(0)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16.0,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Text(
                'm/s',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 10.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricRow(String label, String value, Color valueColor, IconData icon) {
    return Row(
      children: [
        Icon(
          icon,
          size: 20.0,
          color: Colors.white.withOpacity(0.7),
        ),
        const SizedBox(width: 8.0),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 14.0,
                fontWeight: FontWeight.w400,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                color: valueColor,
                fontSize: 18.0,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCompactMetric(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '$label:',
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 11.0,
            ),
          ),
          const SizedBox(width: 8.0),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 11.0,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Color _getAngleColor(double angle) {
    if (angle < 5 || angle > 50) return Colors.red;
    if (angle >= 10 && angle <= 20) return Colors.green;
    return Colors.orange;
  }

  Color _getFPSColor(double fps) {
    if (fps >= 200) return Colors.green;
    if (fps >= 120) return Colors.orange;
    return Colors.red;
  }

  Color _getInferenceColor(double inferenceTime) {
    if (inferenceTime <= 5) return Colors.green;
    if (inferenceTime <= 10) return Colors.orange;
    return Colors.red;
  }

  Color _getSpinRateColor(double spinRate) {
    if (spinRate >= 2000 && spinRate <= 6000) return Colors.green; // Optimal spin range
    if (spinRate >= 1000 && spinRate <= 8000) return Colors.orange; // Acceptable range
    return Colors.red; // Too low or too high
  }

  Color _getConfidenceColor(double confidence) {
    if (confidence >= 0.8) return Colors.green;
    if (confidence >= 0.5) return Colors.orange;
    return Colors.red;
  }
}

class SpeedGaugePainter extends CustomPainter {
  final double speed;
  final double maxSpeed = 100.0; // Maximum speed for gauge

  SpeedGaugePainter(this.speed);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 8;

    // Background circle
    final backgroundPaint = Paint()
      ..color = Colors.white.withOpacity(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0;
    canvas.drawCircle(center, radius, backgroundPaint);

    // Speed arc
    final speedPaint = Paint()
      ..color = _getSpeedColor()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round;

    final sweepAngle = (speed / maxSpeed) * 2 * math.pi;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2, // Start from top
      sweepAngle,
      false,
      speedPaint,
    );
  }

  Color _getSpeedColor() {
    final normalizedSpeed = speed / maxSpeed;
    if (normalizedSpeed <= 0.3) return Colors.green;
    if (normalizedSpeed <= 0.7) return Colors.orange;
    return Colors.red;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return oldDelegate is SpeedGaugePainter && oldDelegate.speed != speed;
  }
}

class BoundingBoxPainter extends CustomPainter {
  final List<BoundingBox> boundingBoxes;
  final Size previewSize;
  final Size imageSize;

  BoundingBoxPainter({
    required this.boundingBoxes,
    required this.previewSize,
    required this.imageSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Calculate scaling factors
    final double scaleX = previewSize.width / imageSize.width;
    final double scaleY = previewSize.height / imageSize.height;

    // Center the preview within the canvas
    final double offsetX = (size.width - previewSize.width) / 2;
    final double offsetY = (size.height - previewSize.height) / 2;

    for (var box in boundingBoxes) {
      final paint = Paint()
        ..color = _getBoxColor(box.className, box.confidence)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;

      // Scale and position the bounding box
      final scaledRect = Rect.fromLTWH(
        offsetX + box.x * scaleX,
        offsetY + box.y * scaleY,
        box.width * scaleX,
        box.height * scaleY,
      );

      // Draw bounding box
      canvas.drawRect(scaledRect, paint);

      // Draw confidence label
      if (box.confidence > 0.5) {
        _drawLabel(
          canvas,
          '${box.className} ${(box.confidence * 100).toInt()}%',
          scaledRect.topLeft,
          paint.color,
        );
      }

      // Draw center point for ball
      if (box.className == 'ball') {
        final centerPaint = Paint()
          ..color = Colors.red
          ..style = PaintingStyle.fill;
        canvas.drawCircle(
          scaledRect.center,
          4.0,
          centerPaint,
        );
      }
    }
  }

  void _drawLabel(Canvas canvas, String text, Offset position, Color color) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.white,
          fontSize: 12.0,
          fontWeight: FontWeight.w500,
          backgroundColor: color.withOpacity(0.7),
        ),
      ),
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();

    // Draw background
    final backgroundRect = Rect.fromLTWH(
      position.dx,
      position.dy - textPainter.height - 4,
      textPainter.width + 8,
      textPainter.height + 4,
    );

    final backgroundPaint = Paint()..color = color.withOpacity(0.8);
    canvas.drawRect(backgroundRect, backgroundPaint);

    // Draw text
    textPainter.paint(
      canvas,
      Offset(position.dx + 4, position.dy - textPainter.height - 2),
    );
  }

  Color _getBoxColor(String className, double confidence) {
    Color baseColor;
    switch (className) {
      case 'ball':
        baseColor = Colors.orange;
        break;
      case 'club_head':
        baseColor = Colors.blue;
        break;
      default:
        baseColor = Colors.white;
    }

    // Adjust opacity based on confidence
    final opacity = (confidence * 0.8 + 0.2).clamp(0.0, 1.0);
    return baseColor.withOpacity(opacity);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return oldDelegate is BoundingBoxPainter &&
           (oldDelegate.boundingBoxes != boundingBoxes ||
            oldDelegate.previewSize != previewSize ||
            oldDelegate.imageSize != imageSize);
  }
}