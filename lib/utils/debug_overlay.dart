// lib/utils/debug_overlay.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
// Services will be integrated when available
import 'logger.dart';
import 'diagnostics.dart';

/// Debug overlay widget for development and testing
class DebugOverlay extends StatefulWidget {
  final Widget child;
  final bool enabled;
  
  const DebugOverlay({
    Key? key,
    required this.child,
    this.enabled = kDebugMode,
  }) : super(key: key);

  @override
  State<DebugOverlay> createState() => _DebugOverlayState();
}

class _DebugOverlayState extends State<DebugOverlay> with TickerProviderStateMixin {
  bool _showOverlay = false;
  bool _showPerformanceStats = true;
  bool _showSystemHealth = false;
  bool _showLogs = false;
  
  late AnimationController _animationController;
  late Animation<double> _slideAnimation;
  
  @override
  void initState() {
    super.initState();
    
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _slideAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.child;
    }

    return Stack(
      children: [
        widget.child,
        
        // Debug toggle button
        Positioned(
          top: MediaQuery.of(context).padding.top + 10,
          right: 10,
          child: GestureDetector(
            onTap: _toggleOverlay,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.bug_report,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ),
        
        // Debug overlay panel
        if (_showOverlay)
          SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1.0, 0.0),
              end: Offset.zero,
            ).animate(_slideAnimation),
            child: _buildDebugPanel(context),
          ),
      ],
    );
  }

  Widget _buildDebugPanel(BuildContext context) {
    return Positioned(
      top: 0,
      right: 0,
      bottom: 0,
      width: MediaQuery.of(context).size.width * 0.4,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.9),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildDebugHeader(),
              _buildTabSelector(),
              Expanded(
                child: _buildTabContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDebugHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.bug_report, color: Colors.white, size: 24),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Debug Panel',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          IconButton(
            onPressed: _toggleOverlay,
            icon: const Icon(Icons.close, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildTabSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          _buildTabButton('Performance', _showPerformanceStats, () {
            setState(() {
              _showPerformanceStats = true;
              _showSystemHealth = false;
              _showLogs = false;
            });
          }),
          _buildTabButton('Health', _showSystemHealth, () {
            setState(() {
              _showPerformanceStats = false;
              _showSystemHealth = true;
              _showLogs = false;
            });
          }),
          _buildTabButton('Logs', _showLogs, () {
            setState(() {
              _showPerformanceStats = false;
              _showSystemHealth = false;
              _showLogs = true;
            });
          }),
        ],
      ),
    );
  }

  Widget _buildTabButton(String title, bool selected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? Colors.blue : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.blue : Colors.grey,
              fontSize: 14,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabContent() {
    if (_showPerformanceStats) {
      return _buildPerformanceTab();
    } else if (_showSystemHealth) {
      return _buildHealthTab();
    } else if (_showLogs) {
      return _buildLogsTab();
    }
    
    return const SizedBox.shrink();
  }

  Widget _buildPerformanceTab() {
    return StreamBuilder<void>(
      stream: Stream.periodic(const Duration(seconds: 1)),
      builder: (context, snapshot) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle('Performance Metrics'),
              const SizedBox(height: 12),
              _buildPerformanceMetrics(),
              
              const SizedBox(height: 20),
              _buildSectionTitle('Frame Processing'),
              const SizedBox(height: 12),
              _buildFrameProcessingStats(),
              
              const SizedBox(height: 20),
              _buildSectionTitle('System Resources'),
              const SizedBox(height: 12),
              _buildResourceStats(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHealthTab() {
    return FutureBuilder<SystemHealthReport>(
      future: diagnostics.getSystemHealth(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }
        
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error loading health data:\n${snapshot.error}',
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
          );
        }
        
        final healthReport = snapshot.data!;
        
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle('Overall Health'),
              const SizedBox(height: 12),
              _buildOverallHealthIndicator(healthReport.overallHealth),
              
              const SizedBox(height: 20),
              _buildSectionTitle('Health Checks'),
              const SizedBox(height: 12),
              ...healthReport.healthChecks.entries.map((entry) =>
                _buildHealthCheckItem(entry.key, entry.value),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLogsTab() {
    final recentLogs = logger.getRecentLogs(count: 50);
    
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _buildSectionTitle('Recent Logs'),
              const Spacer(),
              IconButton(
                onPressed: () {
                  setState(() {}); // Refresh logs
                },
                icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
              ),
              IconButton(
                onPressed: _exportLogs,
                icon: const Icon(Icons.file_download, color: Colors.white, size: 20),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: recentLogs.length,
            itemBuilder: (context, index) {
              final log = recentLogs[index];
              return _buildLogItem(log);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildPerformanceMetrics() {
    final perfSummary = logger.getPerformanceSummary();
    
    return Column(
      children: [
        _buildMetricRow('Session ID', perfSummary['session_id'].toString()),
        _buildMetricRow('Performance Logs', perfSummary['total_performance_logs'].toString()),
        
        if (perfSummary['frame_processing'] != null) ...[
          const SizedBox(height: 8),
          const Text('Frame Processing:', style: TextStyle(color: Colors.grey, fontSize: 12)),
          _buildNestedMetrics(perfSummary['frame_processing']),
        ],
        
        if (perfSummary['inference_times'] != null) ...[
          const SizedBox(height: 8),
          const Text('Inference Times:', style: TextStyle(color: Colors.grey, fontSize: 12)),
          _buildNestedMetrics(perfSummary['inference_times']),
        ],
      ],
    );
  }

  Widget _buildFrameProcessingStats() {
    // This would integrate with actual services
    // For now, show placeholder data
    return Column(
      children: [
        _buildMetricRow('Target FPS', '240'),
        _buildMetricRow('Actual FPS', '180'),
        _buildMetricRow('Drop Rate', '25%'),
        _buildMetricRow('Avg Processing Time', '4.2ms'),
        _buildProgressBar('FPS Target', 180 / 240),
        const SizedBox(height: 8),
        _buildProgressBar('Processing Efficiency', 0.75),
      ],
    );
  }

  Widget _buildResourceStats() {
    return Column(
      children: [
        _buildMetricRow('Memory Usage', '${diagnostics.getMetricValue('memory_usage_mb')?.toStringAsFixed(1) ?? 'N/A'} MB'),
        _buildMetricRow('CPU Usage', '${diagnostics.getMetricValue('cpu_usage_percent')?.toStringAsFixed(1) ?? 'N/A'}%'),
        _buildProgressBar('Memory', (diagnostics.getMetricValue('memory_usage_mb') ?? 0) / 512), // Assume 512MB limit
        const SizedBox(height: 8),
        _buildProgressBar('CPU', (diagnostics.getMetricValue('cpu_usage_percent') ?? 0) / 100),
      ],
    );
  }

  Widget _buildNestedMetrics(Map<String, dynamic> metrics) {
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Column(
        children: metrics.entries.map((entry) {
          final value = entry.value;
          final displayValue = value is double ? value.toStringAsFixed(2) : value.toString();
          return _buildMetricRow(entry.key, displayValue, isNested: true);
        }).toList(),
      ),
    );
  }

  Widget _buildMetricRow(String label, String value, {bool isNested = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: isNested ? 2 : 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: isNested ? Colors.grey : Colors.white,
                fontSize: isNested ? 11 : 12,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: isNested ? Colors.grey : Colors.white,
              fontSize: isNested ? 11 : 12,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(String label, double progress) {
    final clampedProgress = progress.clamp(0.0, 1.0);
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label (${(clampedProgress * 100).toStringAsFixed(0)}%)',
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
          const SizedBox(height: 2),
          LinearProgressIndicator(
            value: clampedProgress,
            backgroundColor: Colors.grey[700],
            valueColor: AlwaysStoppedAnimation<Color>(
              clampedProgress < 0.7 ? Colors.green : 
              clampedProgress < 0.9 ? Colors.orange : Colors.red,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverallHealthIndicator(double healthScore) {
    final healthPercent = (healthScore * 100).toStringAsFixed(0);
    Color healthColor;
    String healthStatus;
    
    if (healthScore >= 0.8) {
      healthColor = Colors.green;
      healthStatus = 'Healthy';
    } else if (healthScore >= 0.6) {
      healthColor = Colors.orange;
      healthStatus = 'Warning';
    } else {
      healthColor = Colors.red;
      healthStatus = 'Critical';
    }
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: healthColor.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: healthColor, width: 1),
      ),
      child: Row(
        children: [
          Icon(
            healthScore >= 0.8 ? Icons.check_circle :
            healthScore >= 0.6 ? Icons.warning : Icons.error,
            color: healthColor,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  healthStatus,
                  style: TextStyle(
                    color: healthColor,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '$healthPercent% of checks passing',
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHealthCheckItem(String name, HealthCheckResult result) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: result.healthy ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: result.healthy ? Colors.green : Colors.red,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                result.healthy ? Icons.check_circle : Icons.error,
                color: result.healthy ? Colors.green : Colors.red,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                '${result.responseTime.inMilliseconds}ms',
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            result.message,
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogItem(LogEntry log) {
    Color levelColor;
    switch (log.level) {
      case LogLevel.error:
      case LogLevel.fatal:
        levelColor = Colors.red;
        break;
      case LogLevel.warning:
        levelColor = Colors.orange;
        break;
      case LogLevel.info:
        levelColor = Colors.blue;
        break;
      case LogLevel.debug:
        levelColor = Colors.green;
        break;
      case LogLevel.verbose:
        levelColor = Colors.grey;
        break;
    }
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: levelColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                log.level.emoji,
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(width: 4),
              Text(
                log.tag,
                style: TextStyle(
                  color: levelColor,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                '${log.timestamp.hour.toString().padLeft(2, '0')}:'
                '${log.timestamp.minute.toString().padLeft(2, '0')}:'
                '${log.timestamp.second.toString().padLeft(2, '0')}',
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            log.message,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  void _toggleOverlay() {
    setState(() {
      _showOverlay = !_showOverlay;
    });
    
    if (_showOverlay) {
      _animationController.forward();
    } else {
      _animationController.reverse();
    }
  }

  void _exportLogs() {
    // Export logs functionality
    final exportedLogs = logger.exportLogs(
      minLevel: LogLevel.debug,
      since: DateTime.now().subtract(const Duration(hours: 1)),
    );
    
    // In a real implementation, this would save to file or share
    logger.info('DebugOverlay', 'Logs exported: ${exportedLogs.length} characters');
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Logs exported successfully'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}

/// Debug information display widget
class DebugInfoWidget extends StatelessWidget {
  final String title;
  final Map<String, dynamic> data;
  
  const DebugInfoWidget({
    Key? key,
    required this.title,
    required this.data,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          ...data.entries.map((entry) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    entry.key,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
                Text(
                  entry.value.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }
}