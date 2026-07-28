import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import 'app_button.dart';

enum EmptyType {
  reports,
  staff,
  notifications,
  search,
  drafts,
  flagged,
  history,
}

class EmptyState extends StatelessWidget {
  final EmptyType type;
  final String? title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.type,
    this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final config = _config();
    return Center(child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Illustrated icon container
        Container(
          width: 100, height: 100,
          decoration: BoxDecoration(
            color: AppColors.brand.withValues(alpha: 0.08),
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.brand.withValues(alpha: 0.15), width: 2),
          ),
          child: Icon(config['icon'] as IconData, color: AppColors.brand.withValues(alpha: 0.7), size: 44),
        ),
        const SizedBox(height: 20),
        Text(
          title ?? config['title'] as String,
          style: const TextStyle(color: AppColors.white, fontSize: 18, fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          subtitle ?? config['subtitle'] as String,
          style: const TextStyle(color: AppColors.silver, fontSize: 14, height: 1.5),
          textAlign: TextAlign.center,
        ),
        if (onAction != null && actionLabel != null) ...[
          const SizedBox(height: 28),
          SizedBox(
            width: 200,
            child: AppButton(label: actionLabel!, onPressed: onAction, icon: config['actionIcon'] as IconData?),
          ),
        ],
      ]),
    ));
  }

  Map<String, dynamic> _config() {
    return switch (type) {
      EmptyType.reports       => {'icon': Icons.assignment_outlined,       'title': 'No reports yet',            'subtitle': 'Submit your first report\nto get started.',           'actionIcon': Icons.add_a_photo_outlined},
      EmptyType.staff         => {'icon': Icons.people_outline,            'title': 'No staff added',            'subtitle': 'Add your first team member\nto start tracking work.',    'actionIcon': Icons.person_add_outlined},
      EmptyType.notifications => {'icon': Icons.notifications_none_outlined,'title': 'All caught up!',           'subtitle': 'No notifications yet.\nNew reports will appear here.', 'actionIcon': null},
      EmptyType.search        => {'icon': Icons.search_outlined,           'title': 'No results found',          'subtitle': 'Try different keywords\nor check the spelling.',        'actionIcon': null},
      EmptyType.drafts        => {'icon': Icons.drafts_outlined,           'title': 'No drafts',                 'subtitle': 'Saved drafts will\nappear here.',                      'actionIcon': null},
      EmptyType.flagged       => {'icon': Icons.verified_user_outlined,    'title': 'All clear!',                'subtitle': 'No flagged reports.\nAll locations verified.',         'actionIcon': null},
      EmptyType.history       => {'icon': Icons.history_outlined,          'title': 'No history found',          'subtitle': 'Reports you submit will\nappear here.',                 'actionIcon': null},
    };
  }
}