import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

enum StaffStatus { active, slow, missing }

class StatusBadge extends StatelessWidget {
  final StaffStatus status;

  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      StaffStatus.active  => (AppColors.green,  'Active'),
      StaffStatus.slow    => (AppColors.yellow, 'Slow'),
      StaffStatus.missing => (AppColors.red,    'No Report'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      ]),
    );
  }
}