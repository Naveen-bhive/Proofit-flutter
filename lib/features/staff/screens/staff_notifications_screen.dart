import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../controllers/staff_controller.dart';

class StaffNotificationsScreen extends ConsumerStatefulWidget {
  const StaffNotificationsScreen({super.key});
  @override
  ConsumerState<StaffNotificationsScreen> createState() => _StaffNotificationsScreenState();
}

class _StaffNotificationsScreenState extends ConsumerState<StaffNotificationsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(staffControllerProvider.notifier).loadNotifications());
  }

  String _filter = 'all';

  static const _groups = {
    'jobs': {'job_assigned', 'job_completed', 'draft_reminder'},
    'targets': {'target_update', 'streak'},
    'leaves': {'leave_update', 'holiday'},
  };

  void _open(Map<String, dynamic> n) {
    if (n['type'] == 'draft_reminder' && n['reportId'] != null) {
      context.push('/staff/draft/${n['reportId']}');
    }
    if (n['type'] == 'leave_update') context.push('/staff/leaves');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(staffControllerProvider);
    final all = state.notifications;
    final visible = _filter == 'all' ? all : all.where((n) => _groups[_filter]!.contains(n['type'])).toList();

    return Scaffold(
      backgroundColor: AppColors.dark,
      body: SafeArea(
        child: Column(children: [
          PageHeader(
            title: 'Notifications',
            titleSize: 21,
            actions: [
              if (all.isNotEmpty)
                GestureDetector(
                  onTap: () => ref.read(staffControllerProvider.notifier).markAllRead(),
                  child: const Text('Mark all read',
                      style: TextStyle(color: AppColors.brand, fontSize: 13.5, fontWeight: FontWeight.w600)),
                ),
            ],
          ),
          PillChipBar(chips: [
            _chip('all', 'All', count: all.length),
            _chip('jobs', 'Jobs'),
            _chip('targets', 'Targets'),
            _chip('leaves', 'Leaves'),
          ]),
          const SizedBox(height: 10),
          const Divider(height: 1, color: AppColors.borderSoft),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.brand,
              onRefresh: () => ref.read(staffControllerProvider.notifier).loadNotifications(),
              child: state.notificationsLoading && all.isEmpty
                  ? ListView(children: const [
                      SizedBox(height: 200, child: Center(child: CircularProgressIndicator(color: AppColors.brand))),
                    ])
                  : visible.isEmpty
                      ? ListView(children: const [
                          SizedBox(height: 100),
                          SoftEmptyState(
                            icon: Icons.notifications_none_rounded,
                            title: 'No notifications yet',
                            subtitle: 'Job assignments, targets and leave updates will appear here.',
                          ),
                        ])
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: AppColors.dark3,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: AppColors.borderSoft),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Column(children: [
                                for (var i = 0; i < visible.length; i++) ...[
                                  if (i > 0) const Divider(height: 1, color: AppColors.border),
                                  _row(visible[i]),
                                ],
                              ]),
                            ),
                          ],
                        ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _chip(String key, String label, {int? count}) {
    final on = _filter == key;
    return GestureDetector(
      onTap: () => setState(() => _filter = key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: on ? AppColors.brand : AppColors.white,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: on ? AppColors.brand : AppColors.border),
          boxShadow: on ? AppColors.glow(AppColors.brand) : AppColors.softShadow,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: TextStyle(color: on ? AppColors.white : AppColors.light, fontSize: 13.5, fontWeight: FontWeight.w600)),
          if (count != null && count > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: on ? AppColors.white.withValues(alpha: 0.25) : AppColors.dark4,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text('$count',
                  style: TextStyle(color: on ? AppColors.white : AppColors.silver, fontSize: 11.5, fontWeight: FontWeight.w700)),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _row(Map<String, dynamic> n) {
    final isRead = n['isRead'] == true;
    final (icon, color) = _notifIcon((n['type'] ?? '').toString(), n['title']?.toString() ?? '');
    return Material(
      color: isRead ? AppColors.white : AppColors.dark3,
      child: InkWell(
        onTap: () => _open(n),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            IconTile(icon: icon, color: color, size: 42, iconSize: 21, radius: 14),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(n['title'] ?? '',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: AppColors.text,
                      fontWeight: isRead ? FontWeight.w500 : FontWeight.w600,
                      fontSize: 15,
                    )),
                const SizedBox(height: 2),
                Text(n['body'] ?? '', style: const TextStyle(color: AppColors.light, fontSize: 13.5, height: 1.4)),
                const SizedBox(height: 4),
                Text(
                  n['createdAt'] != null ? timeago.format(DateTime.parse(n['createdAt'])) : '',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ]),
            ),
            if (!isRead)
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(left: 8, top: 6),
                decoration: BoxDecoration(
                  color: AppColors.brand,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.brandSoft, width: 2),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  (IconData, Color) _notifIcon(String type, String title) {
    final t = title.toLowerCase();
    return switch (type) {
      'job_assigned' || 'job_completed' => (Icons.assignment_turned_in_outlined, AppColors.brand),
      'draft_reminder' => (Icons.warning_amber_rounded, const Color(0xFFF59E0B)),
      'target_update' => (Icons.flag_outlined, AppColors.indigo),
      'broadcast' => (Icons.campaign_outlined, AppColors.brand),
      'streak' => (Icons.trending_up_rounded, AppColors.indigo),
      'leave_update' => t.contains('reject')
          ? (Icons.event_busy_outlined, AppColors.red)
          : (Icons.event_available_outlined, AppColors.greenDark),
      'holiday' => (Icons.notifications_active_outlined, const Color(0xFFF59E0B)),
      _ => (Icons.notifications_outlined, AppColors.silver),
    };
  }
}
