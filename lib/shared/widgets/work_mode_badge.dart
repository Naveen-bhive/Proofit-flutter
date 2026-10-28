import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

/// Shared work-mode label and optional plain-language attendance explanation.
class WorkModeBadge extends StatelessWidget {
  final String mode;
  final bool showPolicy;
  final bool compact;

  const WorkModeBadge({
    super.key,
    required this.mode,
    this.showPolicy = false,
    this.compact = false,
  });

  String get _mode => mode == 'office' ? 'wfo' : mode;
  String get _label => switch (_mode) {
        'wfh' => compact ? 'WFH' : 'Work from home',
        'hybrid' => 'Hybrid',
        _ => compact ? 'WFO' : 'Work from office',
      };
  IconData get _icon => switch (_mode) {
        'wfh' => Icons.home_work_outlined,
        'hybrid' => Icons.swap_horiz_rounded,
        _ => Icons.business_outlined,
      };
  Color get _color => switch (_mode) {
        'wfh' => AppColors.purple,
        'hybrid' => AppColors.blue,
        _ => AppColors.greenDark,
      };

  @override
  Widget build(BuildContext context) {
    final color = _color;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: EdgeInsets.symmetric(
              horizontal: compact ? 9 : 11, vertical: compact ? 5 : 7),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: color.withValues(alpha: 0.28)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(_icon, size: compact ? 14 : 16, color: color),
            const SizedBox(width: 6),
            Text(_label,
                style: TextStyle(
                    color: color,
                    fontSize: compact ? 11 : 12,
                    fontWeight: FontWeight.w700)),
          ]),
        ),
        if (showPolicy) ...[
          const SizedBox(height: 6),
          Text(
            _mode == 'wfo'
                ? 'Attendance is limited to the office area.'
                : 'Attendance location is not restricted.',
            style: const TextStyle(
                color: AppColors.silver, fontSize: 12, height: 1.35),
          ),
        ],
      ],
    );
  }
}
