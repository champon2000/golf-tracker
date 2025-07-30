// lib/utils/logger.dart
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Log levels for filtering and categorization
enum LogLevel {
  verbose(0, 'VERBOSE', '🔍'),
  debug(1, 'DEBUG', '🐛'),
  info(2, 'INFO', 'ℹ️'),
  warning(3, 'WARNING', '⚠️'),
  error(4, 'ERROR', '❌'),
  fatal(5, 'FATAL', '💀');

  const LogLevel(this.priority, this.name, this.emoji);
  final int priority;
  final String name;
  final String emoji;
}

/// Golf tracker application logger with production monitoring capabilities
class GolfTrackerLogger {
  static final GolfTrackerLogger _instance = GolfTrackerLogger._internal();
  factory GolfTrackerLogger() => _instance;
  GolfTrackerLogger._internal();

  // Configuration
  LogLevel _minLevel = kDebugMode ? LogLevel.debug : LogLevel.info;
  bool _enableConsoleLogging = true;
  bool _enableFileLogging = true;
  bool _enablePerformanceLogging = true;
  bool _enableCrashReporting = true;
  int _maxLogFileSize = 10 * 1024 * 1024; // 10MB
  int _maxLogFiles = 5;

  // Internal state
  final List<LogEntry> _logBuffer = [];
  final Map<String, PerformanceTimer> _activeTimers = {};
  File? _currentLogFile;
  int _sessionId = DateTime.now().millisecondsSinceEpoch;

  /// Initialize logger with configuration
  Future<void> initialize({
    LogLevel minLevel = LogLevel.info,
    bool enableConsoleLogging = true,
    bool enableFileLogging = true,
    bool enablePerformanceLogging = true,
    bool enableCrashReporting = true,
    int maxLogFileSize = 10 * 1024 * 1024,
    int maxLogFiles = 5,
  }) async {
    _minLevel = minLevel;
    _enableConsoleLogging = enableConsoleLogging;
    _enableFileLogging = enableFileLogging;
    _enablePerformanceLogging = enablePerformanceLogging;
    _enableCrashReporting = enableCrashReporting;
    _maxLogFileSize = maxLogFileSize;
    _maxLogFiles = maxLogFiles;

    if (_enableFileLogging) {
      await _initializeFileLogging();
    }

    if (_enableCrashReporting) {
      _initializeCrashReporting();
    }

    info('GolfTrackerLogger', 'Logger initialized - Session: $_sessionId');
  }

  /// Log verbose message
  void verbose(String tag, String message, [Map<String, dynamic>? extras]) {
    _log(LogLevel.verbose, tag, message, extras);
  }

  /// Log debug message
  void debug(String tag, String message, [Map<String, dynamic>? extras]) {
    _log(LogLevel.debug, tag, message, extras);
  }

  /// Log info message
  void info(String tag, String message, [Map<String, dynamic>? extras]) {
    _log(LogLevel.info, tag, message, extras);
  }

  /// Log warning message
  void warning(String tag, String message, [Map<String, dynamic>? extras]) {
    _log(LogLevel.warning, tag, message, extras);
  }

  /// Log error message
  void error(String tag, String message, [dynamic error, StackTrace? stackTrace, Map<String, dynamic>? extras]) {
    final errorExtras = <String, dynamic>{};
    if (extras != null) errorExtras.addAll(extras);
    
    if (error != null) {
      errorExtras['error'] = error.toString();
    }
    if (stackTrace != null) {
      errorExtras['stackTrace'] = stackTrace.toString();
    }

    _log(LogLevel.error, tag, message, errorExtras);
  }

  /// Log fatal message
  void fatal(String tag, String message, [dynamic error, StackTrace? stackTrace, Map<String, dynamic>? extras]) {
    final fatalExtras = <String, dynamic>{};
    if (extras != null) fatalExtras.addAll(extras);
    
    if (error != null) {
      fatalExtras['error'] = error.toString();
    }
    if (stackTrace != null) {
      fatalExtras['stackTrace'] = stackTrace.toString();
    }

    _log(LogLevel.fatal, tag, message, fatalExtras);
  }

  /// Start performance timer
  void startTimer(String name) {
    if (!_enablePerformanceLogging) return;
    
    _activeTimers[name] = PerformanceTimer(name, DateTime.now());
    debug('Performance', 'Started timer: $name');
  }

  /// End performance timer and log result
  void endTimer(String name, [Map<String, dynamic>? extras]) {
    if (!_enablePerformanceLogging) return;
    
    final timer = _activeTimers.remove(name);
    if (timer == null) {
      warning('Performance', 'Attempted to end non-existent timer: $name');
      return;
    }

    final duration = DateTime.now().difference(timer.startTime);
    final performanceExtras = <String, dynamic>{
      'duration_ms': duration.inMicroseconds / 1000.0,
      'duration_us': duration.inMicroseconds,
    };
    
    if (extras != null) performanceExtras.addAll(extras);
    
    info('Performance', 'Timer \'$name\' completed in ${duration.inMicroseconds / 1000.0}ms', performanceExtras);
  }

  /// Log performance metric
  void logPerformanceMetric(String name, double value, String unit, [Map<String, dynamic>? extras]) {
    if (!_enablePerformanceLogging) return;
    
    final metricExtras = <String, dynamic>{
      'metric_name': name,
      'metric_value': value,
      'metric_unit': unit,
    };
    
    if (extras != null) metricExtras.addAll(extras);
    
    info('Metrics', '$name: $value $unit', metricExtras);
  }

  /// Log frame processing performance
  void logFramePerformance({
    required int frameId,
    required double processingTimeMs,
    required int detectionCount,
    String? stage,
    Map<String, dynamic>? extras,
  }) {
    if (!_enablePerformanceLogging) return;
    
    final frameExtras = <String, dynamic>{
      'frame_id': frameId,
      'processing_time_ms': processingTimeMs,
      'detection_count': detectionCount,
      'fps': processingTimeMs > 0 ? 1000.0 / processingTimeMs : 0.0,
    };
    
    if (stage != null) frameExtras['stage'] = stage;
    if (extras != null) frameExtras.addAll(extras);
    
    debug('FrameProcessing', 'Frame $frameId processed in ${processingTimeMs.toStringAsFixed(2)}ms', frameExtras);
  }

  /// Log ML inference performance
  void logInferencePerformance({
    required int frameId,
    required double inferenceTimeMs,
    required double preprocessTimeMs,
    required double postprocessTimeMs,
    required int detectionCount,
    required double avgConfidence,
    Map<String, dynamic>? extras,
  }) {
    if (!_enablePerformanceLogging) return;
    
    final inferenceExtras = <String, dynamic>{
      'frame_id': frameId,
      'inference_time_ms': inferenceTimeMs,
      'preprocess_time_ms': preprocessTimeMs,
      'postprocess_time_ms': postprocessTimeMs,
      'total_time_ms': inferenceTimeMs + preprocessTimeMs + postprocessTimeMs,
      'detection_count': detectionCount,
      'avg_confidence': avgConfidence,
      'inference_fps': inferenceTimeMs > 0 ? 1000.0 / inferenceTimeMs : 0.0,
    };
    
    if (extras != null) inferenceExtras.addAll(extras);
    
    debug('MLInference', 'Inference completed in ${inferenceTimeMs.toStringAsFixed(2)}ms', inferenceExtras);
  }

  /// Log tracking performance
  void logTrackingPerformance({
    required String trackingType,
    required int frameId,
    required double trackingTimeMs,
    required double trackingError,
    required double confidence,
    Map<String, dynamic>? extras,
  }) {
    if (!_enablePerformanceLogging) return;
    
    final trackingExtras = <String, dynamic>{
      'tracking_type': trackingType,
      'frame_id': frameId,
      'tracking_time_ms': trackingTimeMs,
      'tracking_error': trackingError,
      'confidence': confidence,
    };
    
    if (extras != null) trackingExtras.addAll(extras);
    
    debug('Tracking', '$trackingType tracking: error=${trackingError.toStringAsFixed(2)}px, confidence=${confidence.toStringAsFixed(3)}', trackingExtras);
  }

  /// Log system resource usage
  void logResourceUsage({
    required double memoryUsageMB,
    required double cpuUsagePercent,
    required double batteryLevel,
    required bool isLowPowerMode,
    Map<String, dynamic>? extras,
  }) {
    final resourceExtras = <String, dynamic>{
      'memory_usage_mb': memoryUsageMB,
      'cpu_usage_percent': cpuUsagePercent,
      'battery_level': batteryLevel,
      'low_power_mode': isLowPowerMode,
    };
    
    if (extras != null) resourceExtras.addAll(extras);
    
    info('Resources', 'Memory: ${memoryUsageMB.toStringAsFixed(1)}MB, CPU: ${cpuUsagePercent.toStringAsFixed(1)}%, Battery: ${batteryLevel.toStringAsFixed(0)}%', resourceExtras);
  }

  /// Log golf shot data
  void logGolfShot({
    required double ballSpeed,
    required double launchAngle,
    required double carryDistance,
    required int trajectoryPoints,
    required Duration trackingDuration,
    String? sessionId,
    Map<String, dynamic>? extras,
  }) {
    final shotExtras = <String, dynamic>{
      'ball_speed_ms': ballSpeed,
      'launch_angle_deg': launchAngle,
      'carry_distance_m': carryDistance,
      'trajectory_points': trajectoryPoints,
      'tracking_duration_ms': trackingDuration.inMilliseconds,
    };
    
    if (sessionId != null) shotExtras['session_id'] = sessionId;
    if (extras != null) shotExtras.addAll(extras);
    
    info('GolfShot', 'Shot recorded: ${ballSpeed.toStringAsFixed(1)}m/s, ${launchAngle.toStringAsFixed(1)}°, ${carryDistance.toStringAsFixed(1)}m', shotExtras);
  }

  /// Get recent log entries
  List<LogEntry> getRecentLogs({int count = 100, LogLevel? minLevel}) {
    var logs = _logBuffer.toList();
    
    if (minLevel != null) {
      logs = logs.where((log) => log.level.priority >= minLevel.priority).toList();
    }
    
    logs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    
    return logs.take(count).toList();
  }

  /// Export logs to string (for sharing/debugging)
  String exportLogs({LogLevel? minLevel, DateTime? since}) {
    var logs = _logBuffer.toList();
    
    if (minLevel != null) {
      logs = logs.where((log) => log.level.priority >= minLevel.priority).toList();
    }
    
    if (since != null) {
      logs = logs.where((log) => log.timestamp.isAfter(since)).toList();
    }
    
    logs.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    
    final buffer = StringBuffer();
    buffer.writeln('Golf Tracker Logs Export');
    buffer.writeln('Session: $_sessionId');
    buffer.writeln('Generated: ${DateTime.now().toIso8601String()}');
    buffer.writeln('Min Level: ${minLevel?.name ?? 'ALL'}');
    buffer.writeln('Since: ${since?.toIso8601String() ?? 'START'}');
    buffer.writeln('Count: ${logs.length}');
    buffer.writeln('${'-' * 60}');
    
    for (final log in logs) {
      buffer.writeln('[${log.timestamp.toIso8601String()}] ${log.level.name} ${log.tag}: ${log.message}');
      if (log.extras.isNotEmpty) {
        buffer.writeln('  Extras: ${jsonEncode(log.extras)}');
      }
    }
    
    return buffer.toString();
  }

  /// Get performance summary
  Map<String, dynamic> getPerformanceSummary() {
    final performanceLogs = _logBuffer.where((log) => 
      log.tag == 'Performance' || 
      log.tag == 'Metrics' || 
      log.tag == 'FrameProcessing' ||
      log.tag == 'MLInference' ||
      log.tag == 'Tracking'
    ).toList();
    
    final frameProcessingTimes = <double>[];
    final inferenceTimes = <double>[];
    final trackingErrors = <double>[];
    
    for (final log in performanceLogs) {
      if (log.extras.containsKey('processing_time_ms')) {
        frameProcessingTimes.add(log.extras['processing_time_ms']);
      }
      if (log.extras.containsKey('inference_time_ms')) {
        inferenceTimes.add(log.extras['inference_time_ms']);
      }
      if (log.extras.containsKey('tracking_error')) {
        trackingErrors.add(log.extras['tracking_error']);
      }
    }
    
    return {
      'session_id': _sessionId,
      'total_performance_logs': performanceLogs.length,
      'frame_processing': _calculateStats(frameProcessingTimes),
      'inference_times': _calculateStats(inferenceTimes),
      'tracking_errors': _calculateStats(trackingErrors),
      'active_timers': _activeTimers.keys.toList(),
    };
  }

  /// Clear logs (for memory management)
  void clearLogs() {
    _logBuffer.clear();
    info('Logger', 'Log buffer cleared');
  }

  /// Flush logs to file
  Future<void> flushLogs() async {
    if (!_enableFileLogging || _currentLogFile == null) return;
    
    try {
      final logsToWrite = _logBuffer.where((log) => !log.writtenToFile).toList();
      if (logsToWrite.isEmpty) return;
      
      final buffer = StringBuffer();
      for (final log in logsToWrite) {
        buffer.writeln(jsonEncode(log.toJson()));
        log.writtenToFile = true;
      }
      
      await _currentLogFile!.writeAsString(buffer.toString(), mode: FileMode.append);
      
      // Check file size and rotate if needed
      final stat = await _currentLogFile!.stat();
      if (stat.size > _maxLogFileSize) {
        await _rotateLogFile();
      }
      
    } catch (e) {
      // Fallback to console logging if file logging fails
      if (_enableConsoleLogging) {
        print('Failed to flush logs to file: $e');
      }
    }
  }

  /// Internal logging method
  void _log(LogLevel level, String tag, String message, [Map<String, dynamic>? extras]) {
    if (level.priority < _minLevel.priority) return;
    
    final logEntry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      tag: tag,
      message: message,
      extras: extras ?? {},
      sessionId: _sessionId,
    );
    
    _logBuffer.add(logEntry);
    
    // Limit buffer size to prevent memory issues
    if (_logBuffer.length > 1000) {
      _logBuffer.removeAt(0);
    }
    
    // Console logging
    if (_enableConsoleLogging) {
      final formattedMessage = '${level.emoji} [$tag] $message';
      if (kDebugMode) {
        print(formattedMessage);
        if (extras != null && extras.isNotEmpty) {
          print('  ${jsonEncode(extras)}');
        }
      }
    }
    
    // Periodic file flush
    if (_enableFileLogging && _logBuffer.length % 10 == 0) {
      flushLogs();
    }
  }

  /// Initialize file logging
  Future<void> _initializeFileLogging() async {
    try {
      // Create logs directory
      final logsDir = Directory('logs');
      if (!await logsDir.exists()) {
        await logsDir.create(recursive: true);
      }
      
      // Create log file
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      _currentLogFile = File('logs/golf_tracker_$timestamp.log');
      
      // Write session header
      final header = {
        'session_start': DateTime.now().toIso8601String(),
        'session_id': _sessionId,
        'app_version': '1.0.0',
        'platform': Platform.operatingSystem,
        'debug_mode': kDebugMode,
      };
      
      await _currentLogFile!.writeAsString('${jsonEncode(header)}\n');
      
    } catch (e) {
      _enableFileLogging = false;
      if (_enableConsoleLogging) {
        print('Failed to initialize file logging: $e');
      }
    }
  }

  /// Initialize crash reporting
  void _initializeCrashReporting() {
    if (!_enableCrashReporting) return;
    
    // Catch Flutter framework errors
    FlutterError.onError = (FlutterErrorDetails details) {
      fatal('FlutterError', 'Flutter framework error', details.exception, details.stack, {
        'library': details.library,
        'context': details.context?.toString(),
      });
      
      // Also call the default error handler
      FlutterError.presentError(details);
    };
    
    // Catch async errors
    PlatformDispatcher.instance.onError = (error, stack) {
      fatal('AsyncError', 'Uncaught async error', error, stack);
      return true;
    };
  }

  /// Rotate log file when it gets too large
  Future<void> _rotateLogFile() async {
    if (_currentLogFile == null) return;
    
    try {
      // Flush any remaining logs
      await flushLogs();
      
      // Archive current file
      final archiveName = '${_currentLogFile!.path}.${DateTime.now().millisecondsSinceEpoch}';
      await _currentLogFile!.rename(archiveName);
      
      // Clean up old log files
      await _cleanupOldLogFiles();
      
      // Create new log file
      await _initializeFileLogging();
      
    } catch (e) {
      if (_enableConsoleLogging) {
        print('Failed to rotate log file: $e');
      }
    }
  }

  /// Clean up old log files
  Future<void> _cleanupOldLogFiles() async {
    try {
      final logsDir = Directory('logs');
      if (!await logsDir.exists()) return;
      
      final logFiles = await logsDir.list()
          .where((entity) => entity is File && entity.path.contains('golf_tracker_'))
          .cast<File>()
          .toList();
      
      // Sort by modification time (newest first)
      logFiles.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      
      // Delete oldest files if we exceed the limit
      if (logFiles.length > _maxLogFiles) {
        for (int i = _maxLogFiles; i < logFiles.length; i++) {
          await logFiles[i].delete();
        }
      }
      
    } catch (e) {
      if (_enableConsoleLogging) {
        print('Failed to cleanup old log files: $e');
      }
    }
  }

  /// Calculate statistics for a list of values
  Map<String, dynamic> _calculateStats(List<double> values) {
    if (values.isEmpty) {
      return {'count': 0};
    }
    
    values.sort();
    final count = values.length;
    final sum = values.reduce((a, b) => a + b);
    final avg = sum / count;
    final min = values.first;
    final max = values.last;
    final median = count % 2 == 0 
      ? (values[count ~/ 2 - 1] + values[count ~/ 2]) / 2
      : values[count ~/ 2];
    
    return {
      'count': count,
      'avg': avg,
      'min': min,
      'max': max,
      'median': median,
      'sum': sum,
    };
  }
}

/// Individual log entry
class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String tag;
  final String message;
  final Map<String, dynamic> extras;
  final int sessionId;
  bool writtenToFile = false;
  
  LogEntry({
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
    required this.extras,
    required this.sessionId,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'level': level.name,
      'tag': tag,
      'message': message,
      'extras': extras,
      'session_id': sessionId,
    };
  }
}

/// Performance timer for measuring execution times
class PerformanceTimer {
  final String name;
  final DateTime startTime;
  
  PerformanceTimer(this.name, this.startTime);
}

/// Global logger instance
final logger = GolfTrackerLogger();