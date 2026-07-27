import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../core/constants/app_colors.dart';
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(staffControllerProvider);
    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (state.notifications.isNotEmpty)
            TextButton(
              onPressed: () => ref.read(staffControllerProvider.notifier).markAllRead(),
              child: const Text('Mark all read', style: TextStyle(color: AppColors.brand, fontSize: 13)),
            ),
        ],
      ),
      body: state.notificationsLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
          : state.notifications.isEmpty
              ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.notifications_none_outlined, color: AppColors.muted, size: 56),
                  SizedBox(height: 12),
                  Text('No notifications yet', style: TextStyle(color: AppColors.silver, fontSize: 16)),
                ]))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: state.notifications.length,
                  separatorBuilder: (_, __) => const Divider(color: AppColors.border, height: 1),
                  itemBuilder: (_, i) {
                    final n = state.notifications[i];
                    final isRead = n['isRead'] == true;
                    return GestureDetector(
                      onTap: () {
                        if (n['type'] == 'target_update') {}
                        if (n['type'] == 'draft_reminder' && n['reportId'] != null) {
                          context.push('/staff/draft/${n['reportId']}');
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        color: Colors.transparent,
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          _notifIcon(n['type'] ?? ''),
                          const SizedBox(width: 14),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(n['title'] ?? '', style: TextStyle(
                              color: isRead ? AppColors.silver : AppColors.white,
                              fontWeight: isRead ? FontWeight.w400 : FontWeight.w600,
                              fontSize: 14,
                            )),
                            const SizedBox(height: 3),
                            Text(n['body'] ?? '', style: const TextStyle(color: AppColors.silver, fontSize: 13)),
                            const SizedBox(height: 4),
                            Text(
                              n['createdAt'] != null ? timeago.format(DateTime.parse(n['createdAt'])) : '',
                              style: const TextStyle(color: AppColors.muted, fontSize: 11),
                            ),
                          ])),
                          if (!isRead)
                            Container(width: 8, height: 8, margin: const EdgeInsets.only(top: 5),
                                decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle)),
                        ]),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _notifIcon(String type) {
    final (icon, color) = switch (type) {
      'draft_reminder'  => (Icons.warning_amber_rounded,      AppColors.yellow),
      'target_update'   => (Icons.flag_outlined,              AppColors.blue),
      'broadcast'       => (Icons.campaign_outlined,          AppColors.brand),
      'streak'          => (Icons.local_fire_department_outlined, AppColors.brand),
      _                 => (Icons.notifications_outlined,     AppColors.muted),
    };
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle),
      child: Icon(icon, color: color, size: 20),
    );
  }
}