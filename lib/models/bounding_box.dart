// lib/models/bounding_box.dart
import 'package:flutter/material.dart';

class BoundingBox {
  final double x;
  final double y;
  final double width;
  final double height;
  final double confidence;
  final String className;

  BoundingBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.confidence,
    required this.className,
  });

  // Get center point coordinates
  Offset get center => Offset(x + width / 2, y + height / 2);
  
  // Get rect representation
  Rect get rect => Rect.fromLTWH(x, y, width, height);
  
  // Get scaled bounding box
  BoundingBox scale(double scaleX, double scaleY) {
    return BoundingBox(
      x: x * scaleX,
      y: y * scaleY,
      width: width * scaleX,
      height: height * scaleY,
      confidence: confidence,
      className: className,
    );
  }
  
  // Check if box contains a point
  bool contains(Offset point) {
    return point.dx >= x && 
           point.dx <= x + width && 
           point.dy >= y && 
           point.dy <= y + height;
  }
  
  // Get area of bounding box
  double get area => width * height;
  
  // Calculate IoU (Intersection over Union) with another box
  double iou(BoundingBox other) {
    final double intersectionX = (x + width).clamp(0, other.x + other.width) - 
                               (x).clamp(other.x, double.infinity);
    final double intersectionY = (y + height).clamp(0, other.y + other.height) - 
                               (y).clamp(other.y, double.infinity);
    
    if (intersectionX <= 0 || intersectionY <= 0) return 0.0;
    
    final double intersectionArea = intersectionX * intersectionY;
    final double unionArea = area + other.area - intersectionArea;
    
    return unionArea > 0 ? intersectionArea / unionArea : 0.0;
  }
  
  @override
  String toString() {
    return 'BoundingBox{class: $className, confidence: ${confidence.toStringAsFixed(2)}, '
           'rect: (${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)}, '
           '${width.toStringAsFixed(1)}, ${height.toStringAsFixed(1)})}';
  }
  
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BoundingBox &&
           other.x == x &&
           other.y == y &&
           other.width == width &&
           other.height == height &&
           other.confidence == confidence &&
           other.className == className;
  }
  
  @override
  int get hashCode {
    return Object.hash(x, y, width, height, confidence, className);
  }
}