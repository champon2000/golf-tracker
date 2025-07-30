import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final DatabaseService _dbService = DatabaseService();
  List<Map<String, dynamic>> _shots = [];
  List<Map<String, dynamic>> _sessions = [];
  bool _isLoading = true;
  String _selectedFilter = 'All';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
      final shots = await _dbService.getAllShots();
      final sessions = await _dbService.getAllSessions();
      
      setState(() {
        _shots = shots;
        _sessions = sessions;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filteredShots {
    if (_selectedFilter == 'All') return _shots;
    return _shots.where((shot) => shot['club_type'] == _selectedFilter).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shot History'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) => setState(() => _selectedFilter = value),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'All', child: Text('All Clubs')),
              const PopupMenuItem(value: 'driver', child: Text('Driver')),
              const PopupMenuItem(value: 'iron', child: Text('Iron')),
              const PopupMenuItem(value: 'wedge', child: Text('Wedge')),
              const PopupMenuItem(value: 'putter', child: Text('Putter')),
            ],
            child: const Icon(Icons.filter_list),
          ),
          IconButton(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildStatsCard(),
                _buildSessionsList(),
                Expanded(child: _buildShotsList()),
              ],
            ),
    );
  }

  Widget _buildStatsCard() {
    if (_filteredShots.isEmpty) return const SizedBox.shrink();

    final totalShots = _filteredShots.length;
    final avgDistance = _filteredShots
        .map((s) => s['carry_distance'] as double? ?? 0.0)
        .reduce((a, b) => a + b) / totalShots;
    final avgSpeed = _filteredShots
        .map((s) => s['ball_speed'] as double? ?? 0.0)
        .reduce((a, b) => a + b) / totalShots;

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStatItem('Total Shots', totalShots.toString()),
            _buildStatItem('Avg Distance', '${avgDistance.toStringAsFixed(1)} yds'),
            _buildStatItem('Avg Speed', '${avgSpeed.toStringAsFixed(1)} mph'),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.blue,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildSessionsList() {
    if (_sessions.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 120,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recent Sessions',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _sessions.length,
              itemBuilder: (context, index) {
                final session = _sessions[index];
                return _buildSessionCard(session);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionCard(Map<String, dynamic> session) {
    final startTime = DateTime.parse(session['start_time']);
    final endTime = session['end_time'] != null 
        ? DateTime.parse(session['end_time']) 
        : DateTime.now();
    final duration = endTime.difference(startTime);

    return Card(
      margin: const EdgeInsets.only(right: 12),
      child: Container(
        width: 140,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${startTime.month}/${startTime.day}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              '${duration.inMinutes} min',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            Text(
              '${session['total_shots'] ?? 0} shots',
              style: const TextStyle(color: Colors.blue, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShotsList() {
    if (_filteredShots.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.golf_course, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No shots recorded yet',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            SizedBox(height: 8),
            Text(
              'Start practicing to see your shot history here',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _filteredShots.length,
      itemBuilder: (context, index) {
        final shot = _filteredShots[index];
        return _buildShotCard(shot);
      },
    );
  }

  Widget _buildShotCard(Map<String, dynamic> shot) {
    final timestamp = DateTime.parse(shot['timestamp']);
    final clubType = shot['club_type'] ?? 'Unknown';
    final ballSpeed = shot['ball_speed'] as double? ?? 0.0;
    final launchAngle = shot['launch_angle'] as double? ?? 0.0;
    final carryDistance = shot['carry_distance'] as double? ?? 0.0;
    final spinRate = shot['spin_rate'] as double? ?? 0.0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getClubColor(clubType),
          child: Text(
            _getClubIcon(clubType),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(
          '${carryDistance.toStringAsFixed(0)} yds • ${ballSpeed.toStringAsFixed(0)} mph',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${clubType.toUpperCase()} • ${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}',
              style: const TextStyle(fontSize: 12),
            ),
            Text(
              'Launch: ${launchAngle.toStringAsFixed(1)}° • Spin: ${spinRate.toStringAsFixed(0)} rpm',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        onTap: () => _showShotDetails(shot),
      ),
    );
  }

  Color _getClubColor(String clubType) {
    switch (clubType.toLowerCase()) {
      case 'driver': return Colors.red;
      case 'iron': return Colors.blue;
      case 'wedge': return Colors.orange;
      case 'putter': return Colors.green;
      default: return Colors.grey;
    }
  }

  String _getClubIcon(String clubType) {
    switch (clubType.toLowerCase()) {
      case 'driver': return 'D';
      case 'iron': return 'I';
      case 'wedge': return 'W';
      case 'putter': return 'P';
      default: return '?';
    }
  }

  void _showShotDetails(Map<String, dynamic> shot) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Shot Details - ${shot['club_type']?.toUpperCase() ?? 'Unknown'}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('Ball Speed', '${(shot['ball_speed'] as double? ?? 0.0).toStringAsFixed(1)} mph'),
            _buildDetailRow('Launch Angle', '${(shot['launch_angle'] as double? ?? 0.0).toStringAsFixed(1)}°'),
            _buildDetailRow('Carry Distance', '${(shot['carry_distance'] as double? ?? 0.0).toStringAsFixed(1)} yards'),
            _buildDetailRow('Spin Rate', '${(shot['spin_rate'] as double? ?? 0.0).toStringAsFixed(0)} rpm'),
            _buildDetailRow('Confidence', '${((shot['confidence'] as double? ?? 0.0) * 100).toStringAsFixed(0)}%'),
            const SizedBox(height: 8),
            Text(
              'Recorded: ${DateTime.parse(shot['timestamp']).toString().substring(0, 19)}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value, style: const TextStyle(color: Colors.blue)),
        ],
      ),
    );
  }
}