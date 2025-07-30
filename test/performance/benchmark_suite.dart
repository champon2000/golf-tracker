// test/performance/benchmark_suite.dart
import 'dart:math' as math;
import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_tracker/services/tflite_service.dart';
import 'package:golf_tracker/services/kalman.dart';
import 'package:golf_tracker/services/database_service.dart';
import 'package:golf_tracker/services/inference_isolate_service.dart';
import '../helpers/test_data_generator.dart';
import '../helpers/mock_services.dart';

/// Base class for golf tracker benchmarks
abstract class GolfTrackerBenchmark extends BenchmarkBase {
  GolfTrackerBenchmark(String name) : super(name);
  
  @override
  void report() {
    final microsecondsPerOp = measure();
    final opsPerSecond = 1000000 / microsecondsPerOp;
    final millisecondsPerOp = microsecondsPerOp / 1000;
    
    print('$name:');
    print('  ${microsecondsPerOp.toStringAsFixed(2)} μs/op');
    print('  ${millisecondsPerOp.toStringAsFixed(3)} ms/op');
    print('  ${opsPerSecond.toStringAsFixed(0)} ops/sec');
    print('');
  }
}

/// TFLite inference benchmark
class TFLiteInferenceBenchmark extends GolfTrackerBenchmark {
  late MockTFLiteService _service;
  late TestDataGenerator _generator;
  static const int _frameWidth = 640;
  static const int _frameHeight = 480;

  TFLiteInferenceBenchmark() : super('TFLite Inference');

  @override
  void setup() async {
    _service = MockTFLiteService();
    _generator = TestDataGenerator();
    await _service.loadModel();
  }

  @override
  void run() {
    final imageData = TestDataGenerator.generateTestImageYUV420(_frameWidth, _frameHeight);
    _service.runInference(imageData, _frameWidth, _frameHeight);
  }

  @override
  void teardown() {
    _service.dispose();
  }
}

/// Kalman filter update benchmark
class KalmanFilterBenchmark extends GolfTrackerBenchmark {
  late KalmanFilter2D _filter;
  final _positions = <Offset>[];
  int _index = 0;

  KalmanFilterBenchmark() : super('Kalman Filter Update');

  @override
  void setup() {
    _filter = KalmanFilter2D(
      initialPosition: const Offset(100, 100),
      initialVelocityX: 10.0,
      initialVelocityY: -5.0,
      dt: 1.0 / 240.0, // 240fps
      processNoisePos: 0.1,
      processNoiseVel: 0.01,
      measurementNoisePos: 1.0,
    );

    // Pre-generate test positions
    _positions.addAll(TestDataGenerator.generateMotionPattern('parabolic', 1000));
  }

  @override
  void run() {
    final position = _positions[_index % _positions.length];
    _filter.update(position, confidence: 0.8);
    _index++;
  }
}

/// Database operations benchmark
class DatabaseBenchmark extends GolfTrackerBenchmark {
  late MockDatabaseService _service;
  final _testShots = <Map<String, dynamic>>[];

  DatabaseBenchmark() : super('Database Operations');

  @override
  void setup() {
    _service = MockDatabaseService();
    
    // Pre-generate test data
    for (int i = 0; i < 100; i++) {
      _testShots.add(TestDataGenerator.generateDatabaseShot());
    }
  }

  @override
  void run() {
    final shot = _testShots[math.Random().nextInt(_testShots.length)];
    _service.insertShot(shot);
  }

  @override
  void teardown() {
    _service.reset();
  }
}

/// Frame processing benchmark (240fps target)
class FrameProcessingBenchmark extends GolfTrackerBenchmark {
  late MockInferenceIsolateService _inferenceService;
  final _testFrames = <InferenceRequest>[];
  int _frameIndex = 0;

  FrameProcessingBenchmark() : super('Frame Processing (240fps)');

  @override
  void setup() async {
    _inferenceService = MockInferenceIsolateService();
    await _inferenceService.initialize();

    // Pre-generate test frames
    _testFrames.addAll(TestDataGenerator.generateStressTestFrames(
      frameCount: 1000,
      width: 640,
      height: 480,
    ));
  }

  @override
  void run() {
    final frame = _testFrames[_frameIndex % _testFrames.length];
    _inferenceService.processFrame(frame);
    _frameIndex++;
  }

  @override
  void teardown() async {
    await _inferenceService.dispose();
  }
}

/// Memory allocation benchmark
class MemoryAllocationBenchmark extends GolfTrackerBenchmark {
  MemoryAllocationBenchmark() : super('Memory Allocation');

  @override
  void run() {
    // Simulate typical memory allocations
    final imageData = TestDataGenerator.generateTestImageYUV420(640, 480);
    final detections = TestDataGenerator.generateDetections(ballCount: 2, clubCount: 1);
    final trajectory = TestDataGenerator.generateMotionPattern('parabolic', 50);
    
    // Force some operations to test GC pressure
    final combined = [
      ...imageData.take(100),
      ...detections.map((d) => d.confidence.toInt()),
      ...trajectory.map((p) => p.dx.toInt()),
    ];
    
    // Prevent optimization
    if (combined.isNotEmpty) {
      combined.length;
    }
  }
}

/// Comprehensive benchmark suite
class GolfTrackerBenchmarkSuite {
  final List<GolfTrackerBenchmark> _benchmarks = [];
  final Map<String, BenchmarkResult> _results = {};

  GolfTrackerBenchmarkSuite() {
    _benchmarks.addAll([
      TFLiteInferenceBenchmark(),
      KalmanFilterBenchmark(),
      DatabaseBenchmark(),
      FrameProcessingBenchmark(),
      MemoryAllocationBenchmark(),
    ]);
  }

  /// Run all benchmarks and collect results
  Future<Map<String, BenchmarkResult>> runAllBenchmarks() async {
    print('=== Golf Tracker Performance Benchmark Suite ===\n');
    
    for (final benchmark in _benchmarks) {
      print('Running ${benchmark.name}...');
      
      try {
        await benchmark.setup();
        final microseconds = benchmark.measure();
        await benchmark.teardown();
        
        final result = BenchmarkResult(
          name: benchmark.name,
          microsecondsPerOperation: microseconds,
          operationsPerSecond: 1000000 / microseconds,
          millisecondsPerOperation: microseconds / 1000,
        );
        
        _results[benchmark.name] = result;
        
        print('  ${result.microsecondsPerOperation.toStringAsFixed(2)} μs/op');
        print('  ${result.millisecondsPerOperation.toStringAsFixed(3)} ms/op');
        print('  ${result.operationsPerSecond.toStringAsFixed(0)} ops/sec');
        print('');
        
      } catch (e) {
        print('  ERROR: $e');
        print('');
      }
    }
    
    _printSummary();
    return Map.unmodifiable(_results);
  }

  /// Run specific benchmark by name
  Future<BenchmarkResult?> runBenchmark(String name) async {
    final benchmark = _benchmarks.firstWhere(
      (b) => b.name == name,
      orElse: () => throw ArgumentError('Benchmark "$name" not found'),
    );

    await benchmark.setup();
    final microseconds = benchmark.measure();
    await benchmark.teardown();

    final result = BenchmarkResult(
      name: benchmark.name,
      microsecondsPerOperation: microseconds,
      operationsPerSecond: 1000000 / microseconds,
      millisecondsPerOperation: microseconds / 1000,
    );

    _results[benchmark.name] = result;
    return result;
  }

  /// Print benchmark summary with performance targets
  void _printSummary() {
    print('=== Performance Summary ===\n');
    
    final targets = {
      'TFLite Inference': PerformanceTarget(
        maxMilliseconds: 20.0,
        minOperationsPerSecond: 50,
        description: 'ML inference should complete within 20ms for real-time processing',
      ),
      'Kalman Filter Update': PerformanceTarget(
        maxMilliseconds: 1.0,
        minOperationsPerSecond: 1000,
        description: 'Kalman updates must be fast enough for 240fps',
      ),
      'Database Operations': PerformanceTarget(
        maxMilliseconds: 10.0,
        minOperationsPerSecond: 100,
        description: 'Database operations should not block UI',
      ),
      'Frame Processing (240fps)': PerformanceTarget(
        maxMilliseconds: 4.17,
        minOperationsPerSecond: 240,
        description: 'Frame processing target for 240fps camera feed',
      ),
      'Memory Allocation': PerformanceTarget(
        maxMilliseconds: 5.0,
        minOperationsPerSecond: 200,
        description: 'Memory operations should minimize GC pressure',
      ),
    };

    for (final entry in _results.entries) {
      final name = entry.key;
      final result = entry.value;
      final target = targets[name];
      
      print('$name:');
      print('  Performance: ${result.millisecondsPerOperation.toStringAsFixed(3)} ms/op');
      
      if (target != null) {
        final meetsTimeTarget = result.millisecondsPerOperation <= target.maxMilliseconds;
        final meetsRateTarget = result.operationsPerSecond >= target.minOperationsPerSecond;
        
        print('  Target: ≤${target.maxMilliseconds} ms/op, ≥${target.minOperationsPerSecond} ops/sec');
        print('  Status: ${meetsTimeTarget && meetsRateTarget ? '✅ PASS' : '❌ FAIL'}');
        
        if (!meetsTimeTarget) {
          final overage = result.millisecondsPerOperation - target.maxMilliseconds;
          print('  ⚠️  ${overage.toStringAsFixed(3)} ms over target');
        }
        
        if (!meetsRateTarget) {
          final shortage = target.minOperationsPerSecond - result.operationsPerSecond;
          print('  ⚠️  ${shortage.toStringAsFixed(0)} ops/sec under target');
        }
        
        print('  Note: ${target.description}');
      }
      
      print('');
    }
  }

  /// Get results for analysis
  Map<String, BenchmarkResult> get results => Map.unmodifiable(_results);
}

/// Performance target specification
class PerformanceTarget {
  final double maxMilliseconds;
  final double minOperationsPerSecond;
  final String description;

  PerformanceTarget({
    required this.maxMilliseconds,
    required this.minOperationsPerSecond,
    required this.description,
  });
}

/// Benchmark result data
class BenchmarkResult {
  final String name;
  final double microsecondsPerOperation;
  final double operationsPerSecond;
  final double millisecondsPerOperation;

  BenchmarkResult({
    required this.name,
    required this.microsecondsPerOperation,
    required this.operationsPerSecond,
    required this.millisecondsPerOperation,
  });

  /// Check if result meets a performance target
  bool meetsTarget(PerformanceTarget target) {
    return millisecondsPerOperation <= target.maxMilliseconds &&
           operationsPerSecond >= target.minOperationsPerSecond;
  }

  @override
  String toString() {
    return 'BenchmarkResult($name: ${millisecondsPerOperation.toStringAsFixed(3)} ms/op)';
  }
}

/// Performance regression detector
class PerformanceRegressionDetector {
  final Map<String, List<BenchmarkResult>> _historicalResults = {};

  /// Add benchmark results to history
  void addResults(Map<String, BenchmarkResult> results) {
    for (final entry in results.entries) {
      final name = entry.key;
      final result = entry.value;
      
      _historicalResults.putIfAbsent(name, () => []);
      _historicalResults[name]!.add(result);
      
      // Keep last 10 results
      if (_historicalResults[name]!.length > 10) {
        _historicalResults[name]!.removeAt(0);
      }
    }
  }

  /// Detect performance regressions
  Map<String, RegressionAnalysis> analyzeRegressions() {
    final regressions = <String, RegressionAnalysis>{};
    
    for (final entry in _historicalResults.entries) {
      final name = entry.key;
      final results = entry.value;
      
      if (results.length < 2) continue;
      
      final latest = results.last;
      final previous = results[results.length - 2];
      
      final performanceChange = latest.millisecondsPerOperation - previous.millisecondsPerOperation;
      final percentChange = (performanceChange / previous.millisecondsPerOperation) * 100;
      
      final isRegression = percentChange > 10.0; // >10% slower is regression
      final isImprovement = percentChange < -10.0; // >10% faster is improvement
      
      final avgPrevious = results.take(results.length - 1)
          .map((r) => r.millisecondsPerOperation)
          .reduce((a, b) => a + b) / (results.length - 1);
      
      final trendChange = latest.millisecondsPerOperation - avgPrevious;
      final trendPercent = (trendChange / avgPrevious) * 100;
      
      regressions[name] = RegressionAnalysis(
        benchmarkName: name,
        latestResult: latest,
        previousResult: previous,
        performanceChange: performanceChange,
        percentChange: percentChange,
        isRegression: isRegression,
        isImprovement: isImprovement,
        trendChange: trendChange,
        trendPercent: trendPercent,
        historicalCount: results.length,
      );
    }
    
    return regressions;
  }

  /// Print regression analysis report
  void printRegressionReport() {
    final regressions = analyzeRegressions();
    
    print('=== Performance Regression Analysis ===\n');
    
    final hasRegressions = regressions.values.any((r) => r.isRegression);
    final hasImprovements = regressions.values.any((r) => r.isImprovement);
    
    if (!hasRegressions && !hasImprovements) {
      print('No significant performance changes detected.\n');
      return;
    }
    
    for (final regression in regressions.values) {
      if (regression.isRegression) {
        print('❌ REGRESSION: ${regression.benchmarkName}');
        print('  Latest: ${regression.latestResult.millisecondsPerOperation.toStringAsFixed(3)} ms/op');
        print('  Previous: ${regression.previousResult.millisecondsPerOperation.toStringAsFixed(3)} ms/op');
        print('  Change: +${regression.performanceChange.toStringAsFixed(3)} ms (+${regression.percentChange.toStringAsFixed(1)}%)');
        print('  Trend: ${regression.trendPercent >= 0 ? '+' : ''}${regression.trendPercent.toStringAsFixed(1)}% vs average');
        print('');
      }
    }
    
    for (final improvement in regressions.values) {
      if (improvement.isImprovement) {
        print('✅ IMPROVEMENT: ${improvement.benchmarkName}');
        print('  Latest: ${improvement.latestResult.millisecondsPerOperation.toStringAsFixed(3)} ms/op');
        print('  Previous: ${improvement.previousResult.millisecondsPerOperation.toStringAsFixed(3)} ms/op');
        print('  Change: ${improvement.performanceChange.toStringAsFixed(3)} ms (${improvement.percentChange.toStringAsFixed(1)}%)');
        print('  Trend: ${improvement.trendPercent >= 0 ? '+' : ''}${improvement.trendPercent.toStringAsFixed(1)}% vs average');
        print('');
      }
    }
  }
}

/// Regression analysis result
class RegressionAnalysis {
  final String benchmarkName;
  final BenchmarkResult latestResult;
  final BenchmarkResult previousResult;
  final double performanceChange;
  final double percentChange;
  final bool isRegression;
  final bool isImprovement;
  final double trendChange;
  final double trendPercent;
  final int historicalCount;

  RegressionAnalysis({
    required this.benchmarkName,
    required this.latestResult,
    required this.previousResult,
    required this.performanceChange,
    required this.percentChange,
    required this.isRegression,
    required this.isImprovement,
    required this.trendChange,
    required this.trendPercent,
    required this.historicalCount,
  });
}