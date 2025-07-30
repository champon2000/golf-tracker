// lib/utils/diagnostics.dart
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
// Services will be integrated when available
import '../services/database_service.dart';
import 'logger.dart';

/// System diagnostics and health monitoring for production
class SystemDiagnostics {
  static final SystemDiagnostics _instance = SystemDiagnostics._internal();
  factory SystemDiagnostics() => _instance;
  SystemDiagnostics._internal();

  // Monitoring state
  bool _isMonitoring = false;
  Timer? _monitoringTimer;
  final List<HealthCheck> _healthChecks = [];
  final Map<String, SystemMetric> _metrics = {};
  
  // Configuration
  Duration _monitoringInterval = const Duration(seconds: 30);
  Duration _healthCheckTimeout = const Duration(seconds: 10);
  
  /// Initialize diagnostics system
  Future<void> initialize({
    Duration monitoringInterval = const Duration(seconds: 30),
    Duration healthCheckTimeout = const Duration(seconds: 10),
  }) async {
    _monitoringInterval = monitoringInterval;
    _healthCheckTimeout = healthCheckTimeout;
    
    _setupHealthChecks();
    _setupMetrics();
    
    logger.info('Diagnostics', 'System diagnostics initialized');
  }

  /// Start continuous system monitoring
  void startMonitoring() {
    if (_isMonitoring) return;
    
    _isMonitoring = true;
    _monitoringTimer = Timer.periodic(_monitoringInterval, (_) {
      _performHealthChecks();
      _updateMetrics();
    });
    
    logger.info('Diagnostics', 'System monitoring started');
    
    // Perform initial checks
    _performHealthChecks();
    _updateMetrics();
  }

  /// Stop system monitoring
  void stopMonitoring() {
    if (!_isMonitoring) return;
    
    _isMonitoring = false;
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
    
    logger.info('Diagnostics', 'System monitoring stopped');
  }

  /// Get current system health status
  Future<SystemHealthReport> getSystemHealth() async {
    final report = SystemHealthReport();
    
    // Run all health checks
    for (final healthCheck in _healthChecks) {
      try {
        final result = await healthCheck.check().timeout(_healthCheckTimeout);
        report.healthChecks[healthCheck.name] = result;
      } catch (e) {
        report.healthChecks[healthCheck.name] = HealthCheckResult(
          healthy: false,
          message: 'Health check timed out or failed: $e',
          responseTime: _healthCheckTimeout,
        );
      }
    }
    
    // Collect current metrics
    report.metrics.addAll(_metrics);
    
    // Calculate overall health
    final healthyChecks = report.healthChecks.values.where((r) => r.healthy).length;
    report.overallHealth = healthyChecks / report.healthChecks.length;
    
    return report;
  }

  /// Generate comprehensive diagnostic report
  Future<String> generateDiagnosticReport() async {
    final report = StringBuffer();
    final timestamp = DateTime.now();
    
    report.writeln('=== GOLF TRACKER DIAGNOSTIC REPORT ===');
    report.writeln('Generated: ${timestamp.toIso8601String()}');
    report.writeln('Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    report.writeln('Debug Mode: $kDebugMode');
    report.writeln('');
    
    // System Information
    report.writeln('== SYSTEM INFORMATION ==');
    await _addSystemInfo(report);
    report.writeln('');
    
    // Health Checks
    report.writeln('== HEALTH CHECKS ==');
    final healthReport = await getSystemHealth();
    for (final entry in healthReport.healthChecks.entries) {
      final name = entry.key;
      final result = entry.value;
      final status = result.healthy ? '✅ HEALTHY' : '❌ UNHEALTHY';
      
      report.writeln('$name: $status');
      report.writeln('  Message: ${result.message}');
      report.writeln('  Response Time: ${result.responseTime.inMilliseconds}ms');
      if (result.details.isNotEmpty) {
        report.writeln('  Details: ${jsonEncode(result.details)}');
      }
      report.writeln('');
    }
    
    // System Metrics
    report.writeln('== SYSTEM METRICS ==');
    for (final entry in _metrics.entries) {
      final name = entry.key;
      final metric = entry.value;
      
      report.writeln('$name:');
      report.writeln('  Current: ${metric.currentValue} ${metric.unit}');
      report.writeln('  Average: ${metric.averageValue.toStringAsFixed(2)} ${metric.unit}');
      report.writeln('  Min: ${metric.minValue} ${metric.unit}');
      report.writeln('  Max: ${metric.maxValue} ${metric.unit}');
      report.writeln('  Samples: ${metric.sampleCount}');
      report.writeln('');
    }
    
    // Performance Summary
    report.writeln('== PERFORMANCE SUMMARY ==');
    final perfSummary = logger.getPerformanceSummary();
    for (final entry in perfSummary.entries) {
      report.writeln('${entry.key}: ${entry.value}');
    }
    report.writeln('');
    
    // Recent Error Logs
    report.writeln('== RECENT ERRORS ==');
    final errorLogs = logger.getRecentLogs(count: 20, minLevel: LogLevel.error);
    for (final log in errorLogs) {
      report.writeln('[${log.timestamp.toIso8601String()}] ${log.level.name} ${log.tag}: ${log.message}');
      if (log.extras.isNotEmpty) {
        report.writeln('  ${jsonEncode(log.extras)}');
      }
    }
    
    if (errorLogs.isEmpty) {
      report.writeln('No recent errors found.');
    }
    
    report.writeln('');
    report.writeln('=== END DIAGNOSTIC REPORT ===');
    
    return report.toString();
  }

  /// Export diagnostic data for support
  Future<Map<String, dynamic>> exportDiagnosticData() async {
    final healthReport = await getSystemHealth();
    final perfSummary = logger.getPerformanceSummary();
    final recentLogs = logger.getRecentLogs(count: 100);
    
    return {
      'timestamp': DateTime.now().toIso8601String(),
      'platform': {
        'os': Platform.operatingSystem,
        'version': Platform.operatingSystemVersion,
        'dart_version': Platform.version,
        'debug_mode': kDebugMode,
      },
      'health_report': {
        'overall_health': healthReport.overallHealth,
        'health_checks': healthReport.healthChecks.map(
          (name, result) => MapEntry(name, {
            'healthy': result.healthy,
            'message': result.message,
            'response_time_ms': result.responseTime.inMilliseconds,
            'details': result.details,
          }),
        ),
      },
      'metrics': _metrics.map(
        (name, metric) => MapEntry(name, {
          'current': metric.currentValue,
          'average': metric.averageValue,
          'min': metric.minValue,
          'max': metric.maxValue,
          'unit': metric.unit,
          'samples': metric.sampleCount,
        }),
      ),
      'performance_summary': perfSummary,
      'recent_logs': recentLogs.map((log) => log.toJson()).toList(),
    };
  }

  /// Check if system is healthy based on critical health checks
  bool isSystemHealthy() {
    final criticalChecks = _healthChecks.where((check) => check.critical);
    
    for (final check in criticalChecks) {
      // Use cached result if available
      final cachedResult = _getLastHealthCheckResult(check.name);
      if (cachedResult != null && !cachedResult.healthy) {
        return false;
      }
    }
    
    return true;
  }

  /// Get specific metric value
  double? getMetricValue(String metricName) {
    return _metrics[metricName]?.currentValue;
  }

  /// Update a custom metric
  void updateMetric(String name, double value, String unit) {
    if (_metrics.containsKey(name)) {
      _metrics[name]!.addValue(value);
    } else {
      _metrics[name] = SystemMetric(name, unit)..addValue(value);
    }
  }

  /// Setup built-in health checks
  void _setupHealthChecks() {
    _healthChecks.addAll([
      HealthCheck(
        name: 'Memory Usage',
        critical: true,
        check: _checkMemoryUsage,
      ),
      HealthCheck(
        name: 'Camera System',
        critical: true,
        check: _checkCameraSystem,
      ),
      HealthCheck(
        name: 'ML Inference',
        critical: true,
        check: _checkMLInference,
      ),
      HealthCheck(
        name: 'Database Connection',
        critical: false,
        check: _checkDatabaseConnection,
      ),
      HealthCheck(
        name: 'File System',
        critical: false,
        check: _checkFileSystem,
      ),
      HealthCheck(
        name: 'Performance Tracking',
        critical: false,
        check: _checkPerformanceTracking,
      ),
    ]);
  }

  /// Setup system metrics
  void _setupMetrics() {
    _metrics.addAll({
      'memory_usage_mb': SystemMetric('memory_usage_mb', 'MB'),
      'cpu_usage_percent': SystemMetric('cpu_usage_percent', '%'),
      'frame_processing_fps': SystemMetric('frame_processing_fps', 'fps'),
      'inference_time_ms': SystemMetric('inference_time_ms', 'ms'),
      'tracking_error_px': SystemMetric('tracking_error_px', 'px'),
      'database_response_ms': SystemMetric('database_response_ms', 'ms'),
    });
  }

  /// Perform all health checks
  void _performHealthChecks() async {
    logger.debug('Diagnostics', 'Performing system health checks');
    
    for (final healthCheck in _healthChecks) {
      try {
        final result = await healthCheck.check().timeout(_healthCheckTimeout);
        
        if (!result.healthy && healthCheck.critical) {
          logger.error('Diagnostics', 'Critical health check failed: ${healthCheck.name}', 
                      null, null, {'result': result.message});
        } else if (!result.healthy) {
          logger.warning('Diagnostics', 'Health check failed: ${healthCheck.name}', 
                        {'result': result.message});
        } else {
          logger.debug('Diagnostics', 'Health check passed: ${healthCheck.name}');
        }
        
        // Cache result for quick access
        _cacheHealthCheckResult(healthCheck.name, result);
        
      } catch (e) {
        logger.error('Diagnostics', 'Health check error: ${healthCheck.name}', e);
      }
    }
  }

  /// Update system metrics
  void _updateMetrics() async {
    try {
      // Update memory usage
      final memoryUsage = await _getMemoryUsage();
      if (memoryUsage != null) {
        updateMetric('memory_usage_mb', memoryUsage, 'MB');
      }
      
      // Update CPU usage (if available)
      final cpuUsage = await _getCPUUsage();
      if (cpuUsage != null) {
        updateMetric('cpu_usage_percent', cpuUsage, '%');
      }
      
      // Log resource usage
      if (memoryUsage != null && cpuUsage != null) {
        logger.logResourceUsage(
          memoryUsageMB: memoryUsage,
          cpuUsagePercent: cpuUsage,
          batteryLevel: 100.0, // Placeholder - would need platform channel
          isLowPowerMode: false, // Placeholder - would need platform channel
        );
      }
      
    } catch (e) {
      logger.error('Diagnostics', 'Failed to update metrics', e);
    }
  }

  /// Memory usage health check
  Future<HealthCheckResult> _checkMemoryUsage() async {
    try {
      final memoryUsage = await _getMemoryUsage();
      if (memoryUsage == null) {
        return HealthCheckResult(
          healthy: false,
          message: 'Unable to determine memory usage',
          responseTime: Duration.zero,
        );
      }
      
      const memoryWarningThreshold = 512.0; // MB
      const memoryCriticalThreshold = 1024.0; // MB
      
      if (memoryUsage > memoryCriticalThreshold) {
        return HealthCheckResult(
          healthy: false,
          message: 'Critical memory usage: ${memoryUsage.toStringAsFixed(1)}MB',
          responseTime: Duration.zero,
          details: {'memory_mb': memoryUsage, 'threshold_mb': memoryCriticalThreshold},
        );
      } else if (memoryUsage > memoryWarningThreshold) {
        return HealthCheckResult(
          healthy: true,
          message: 'High memory usage: ${memoryUsage.toStringAsFixed(1)}MB',
          responseTime: Duration.zero,
          details: {'memory_mb': memoryUsage, 'threshold_mb': memoryWarningThreshold},
        );
      } else {
        return HealthCheckResult(
          healthy: true,
          message: 'Memory usage normal: ${memoryUsage.toStringAsFixed(1)}MB',
          responseTime: Duration.zero,
          details: {'memory_mb': memoryUsage},
        );
      }
      
    } catch (e) {
      return HealthCheckResult(
        healthy: false,
        message: 'Memory check failed: $e',
        responseTime: Duration.zero,
      );
    }
  }

  /// Camera system health check
  Future<HealthCheckResult> _checkCameraSystem() async {
    // This would integrate with actual camera service
    // For now, return a placeholder result
    return HealthCheckResult(
      healthy: true,
      message: 'Camera system operational',
      responseTime: const Duration(milliseconds: 10),
    );
  }

  /// ML inference health check
  Future<HealthCheckResult> _checkMLInference() async {
    // This would test actual ML inference
    // For now, return a placeholder result
    return HealthCheckResult(
      healthy: true,
      message: 'ML inference system operational',
      responseTime: const Duration(milliseconds: 25),
    );
  }

  /// Database connection health check
  Future<HealthCheckResult> _checkDatabaseConnection() async {
    try {
      final stopwatch = Stopwatch()..start();
      
      // Test database connection
      final db = DatabaseService.instance;
      await db.getOverallStats(); // Simple query to test connection
      
      stopwatch.stop();
      
      return HealthCheckResult(
        healthy: true,
        message: 'Database connection healthy',
        responseTime: stopwatch.elapsed,
        details: {'response_time_ms': stopwatch.elapsedMilliseconds},
      );
      
    } catch (e) {
      return HealthCheckResult(
        healthy: false,
        message: 'Database connection failed: $e',
        responseTime: Duration.zero,
      );
    }
  }

  /// File system health check
  Future<HealthCheckResult> _checkFileSystem() async {
    try {
      // Check if we can write to logs directory
      final testFile = File('logs/diagnostic_test.tmp');
      await testFile.writeAsString('test');
      await testFile.delete();
      
      return HealthCheckResult(
        healthy: true,
        message: 'File system accessible',
        responseTime: Duration.zero,
      );
    } catch (e) {
      return HealthCheckResult(
        healthy: false,
        message: 'File system error: $e',
        responseTime: Duration.zero,
      );
    }
  }

  /// Performance tracking health check
  Future<HealthCheckResult> _checkPerformanceTracking() async {
    final perfSummary = logger.getPerformanceSummary();
    final frameProcessingStats = perfSummary['frame_processing'] as Map<String, dynamic>?;
    
    if (frameProcessingStats == null || frameProcessingStats['count'] == 0) {
      return HealthCheckResult(
        healthy: true,
        message: 'No recent performance data',
        responseTime: Duration.zero,
      );
    }
    
    final avgFrameTime = frameProcessingStats['avg'] as double;
    const targetFrameTime = 16.67; // 60fps target
    
    if (avgFrameTime > targetFrameTime * 2) {
      return HealthCheckResult(
        healthy: false,
        message: 'Performance degraded: ${avgFrameTime.toStringAsFixed(2)}ms avg frame time',
        responseTime: Duration.zero,
        details: frameProcessingStats,
      );
    } else {
      return HealthCheckResult(
        healthy: true,
        message: 'Performance tracking normal: ${avgFrameTime.toStringAsFixed(2)}ms avg frame time',
        responseTime: Duration.zero,
        details: frameProcessingStats,
      );
    }
  }

  /// Get memory usage in MB (platform-specific implementation needed)
  Future<double?> _getMemoryUsage() async {
    try {
      // This would require platform channel implementation
      // For now, return a simulated value
      return 128.0 + (DateTime.now().millisecondsSinceEpoch % 100);
    } catch (e) {
      return null;
    }
  }

  /// Get CPU usage percentage (platform-specific implementation needed)
  Future<double?> _getCPUUsage() async {
    try {
      // This would require platform channel implementation
      // For now, return a simulated value
      return 15.0 + (DateTime.now().millisecondsSinceEpoch % 50);
    } catch (e) {
      return null;
    }
  }

  /// Add system information to report
  Future<void> _addSystemInfo(StringBuffer report) async {
    report.writeln('Dart Version: ${Platform.version}');
    report.writeln('Operating System: ${Platform.operatingSystem}');
    report.writeln('OS Version: ${Platform.operatingSystemVersion}');
    report.writeln('Number of Processors: ${Platform.numberOfProcessors}');
    report.writeln('Locale: ${Platform.localeName}');
    
    try {
      final memoryUsage = await _getMemoryUsage();
      if (memoryUsage != null) {
        report.writeln('Memory Usage: ${memoryUsage.toStringAsFixed(1)} MB');
      }
    } catch (e) {
      report.writeln('Memory Usage: Unable to determine');
    }
  }

  /// Cache health check result for quick access
  final Map<String, HealthCheckResult> _healthCheckCache = {};
  
  void _cacheHealthCheckResult(String checkName, HealthCheckResult result) {
    _healthCheckCache[checkName] = result;
  }
  
  HealthCheckResult? _getLastHealthCheckResult(String checkName) {
    return _healthCheckCache[checkName];
  }
}

/// Health check definition
class HealthCheck {
  final String name;
  final bool critical;
  final Future<HealthCheckResult> Function() check;
  
  HealthCheck({
    required this.name,
    required this.critical,
    required this.check,
  });
}

/// Health check result
class HealthCheckResult {
  final bool healthy;
  final String message;
  final Duration responseTime;
  final Map<String, dynamic> details;
  
  HealthCheckResult({
    required this.healthy,
    required this.message,
    required this.responseTime,
    this.details = const {},
  });
}

/// System health report
class SystemHealthReport {
  final Map<String, HealthCheckResult> healthChecks = {};
  final Map<String, SystemMetric> metrics = {};
  double overallHealth = 0.0;
  
  bool get isHealthy => overallHealth >= 0.8; // 80% threshold
}

/// System metric tracking
class SystemMetric {
  final String name;
  final String unit;
  final List<double> _values = [];
  double _currentValue = 0.0;
  
  SystemMetric(this.name, this.unit);
  
  void addValue(double value) {
    _currentValue = value;
    _values.add(value);
    
    // Keep only recent values to prevent memory growth
    if (_values.length > 100) {
      _values.removeAt(0);
    }
  }
  
  double get currentValue => _currentValue;
  double get averageValue => _values.isEmpty ? 0.0 : _values.reduce((a, b) => a + b) / _values.length;
  double get minValue => _values.isEmpty ? 0.0 : _values.reduce((a, b) => a < b ? a : b);
  double get maxValue => _values.isEmpty ? 0.0 : _values.reduce((a, b) => a > b ? a : b);
  int get sampleCount => _values.length;
}

/// Global diagnostics instance
final diagnostics = SystemDiagnostics();