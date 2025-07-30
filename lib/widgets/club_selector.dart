import 'package:flutter/material.dart';

class ClubSelector extends StatefulWidget {
  final String selectedClub;
  final Function(String) onClubSelected;
  final bool isVisible;

  const ClubSelector({
    super.key,
    required this.selectedClub,
    required this.onClubSelected,
    this.isVisible = true,
  });

  @override
  State<ClubSelector> createState() => _ClubSelectorState();
}

class _ClubSelectorState extends State<ClubSelector>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  final List<ClubOption> _clubs = [
    ClubOption('driver', 'Driver', Icons.sports_golf, Colors.red),
    ClubOption('3wood', '3 Wood', Icons.sports_golf, Colors.brown),
    ClubOption('5wood', '5 Wood', Icons.sports_golf, Colors.brown),
    ClubOption('3iron', '3 Iron', Icons.golf_course, Colors.blue),
    ClubOption('4iron', '4 Iron', Icons.golf_course, Colors.blue),
    ClubOption('5iron', '5 Iron', Icons.golf_course, Colors.blue),
    ClubOption('6iron', '6 Iron', Icons.golf_course, Colors.blue),
    ClubOption('7iron', '7 Iron', Icons.golf_course, Colors.blue),
    ClubOption('8iron', '8 Iron', Icons.golf_course, Colors.blue),
    ClubOption('9iron', '9 Iron', Icons.golf_course, Colors.blue),
    ClubOption('pw', 'PW', Icons.sports, Colors.orange),
    ClubOption('sw', 'SW', Icons.sports, Colors.orange),
    ClubOption('lw', 'LW', Icons.sports, Colors.orange),
    ClubOption('putter', 'Putter', Icons.flag, Colors.green),
  ];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutBack,
    ));

    if (widget.isVisible) {
      _animationController.forward();
    }
  }

  @override
  void didUpdateWidget(ClubSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible != oldWidget.isVisible) {
      if (widget.isVisible) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Visibility(
          visible: _animationController.value > 0,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildHeader(),
                    _buildClubGrid(),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.sports_golf, color: Colors.white, size: 24),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Select Club',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Text(
            _getSelectedClubDisplayName(),
            style: const TextStyle(
              color: Colors.blue,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClubGrid() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.2,
        ),
        itemCount: _clubs.length,
        itemBuilder: (context, index) {
          final club = _clubs[index];
          final isSelected = club.value == widget.selectedClub;
          
          return GestureDetector(
            onTap: () => widget.onClubSelected(club.value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: isSelected ? club.color.withOpacity(0.3) : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? club.color : Colors.grey.withOpacity(0.3),
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    club.icon,
                    color: isSelected ? club.color : Colors.white70,
                    size: 24,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    club.displayName,
                    style: TextStyle(
                      color: isSelected ? club.color : Colors.white70,
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _getSelectedClubDisplayName() {
    final club = _clubs.firstWhere(
      (club) => club.value == widget.selectedClub,
      orElse: () => _clubs.first,
    );
    return club.displayName;
  }
}

class ClubOption {
  final String value;
  final String displayName;
  final IconData icon;
  final Color color;

  const ClubOption(this.value, this.displayName, this.icon, this.color);
}

class ClubSelectorButton extends StatelessWidget {
  final String selectedClub;
  final VoidCallback onTap;

  const ClubSelectorButton({
    super.key,
    required this.selectedClub,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _getClubIcon(selectedClub),
              color: _getClubColor(selectedClub),
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              _getClubDisplayName(selectedClub),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.keyboard_arrow_down,
              color: Colors.white70,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  IconData _getClubIcon(String clubValue) {
    if (clubValue.contains('wood') || clubValue == 'driver') {
      return Icons.sports_golf;
    } else if (clubValue.contains('iron')) {
      return Icons.golf_course;
    } else if (clubValue.contains('w')) { // wedges
      return Icons.sports;
    } else if (clubValue == 'putter') {
      return Icons.flag;
    }
    return Icons.sports_golf;
  }

  Color _getClubColor(String clubValue) {
    if (clubValue == 'driver') return Colors.red;
    if (clubValue.contains('wood')) return Colors.brown;
    if (clubValue.contains('iron')) return Colors.blue;
    if (clubValue.contains('w')) return Colors.orange;
    if (clubValue == 'putter') return Colors.green;
    return Colors.grey;
  }

  String _getClubDisplayName(String clubValue) {
    final clubs = {
      'driver': 'Driver',
      '3wood': '3 Wood',
      '5wood': '5 Wood',
      '3iron': '3 Iron',
      '4iron': '4 Iron',
      '5iron': '5 Iron',
      '6iron': '6 Iron',
      '7iron': '7 Iron',
      '8iron': '8 Iron',
      '9iron': '9 Iron',
      'pw': 'PW',
      'sw': 'SW',
      'lw': 'LW',
      'putter': 'Putter',
    };
    return clubs[clubValue] ?? clubValue.toUpperCase();
  }
}