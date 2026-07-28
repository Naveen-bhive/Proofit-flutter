import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/app_button.dart';
import '../controllers/owner_controller.dart';

class OwnerNotificationsScreen extends ConsumerStatefulWidget {
  const OwnerNotificationsScreen({super.key});
  @override
  ConsumerState<OwnerNotificationsScreen> createState() => _OwnerNotificationsScreenState();
}

class _OwnerNotificationsScreenState extends ConsumerState<OwnerNotificationsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(ownerControllerProvider.notifier).loadOwnerNotifications());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ownerControllerProvider);
    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (state.ownerNotifications.isNotEmpty)
            TextButton(
              onPressed: () => ref.read(ownerControllerProvider.notifier).markOwnerNotificationsRead(),
              child: const Text('Mark all read', style: TextStyle(color: AppColors.brand, fontSize: 13)),
            ),
        ],
      ),
      body: Column(children: [
        // Broadcast button
        Padding(padding: const EdgeInsets.all(16), child: OutlinedButton.icon(
          onPressed: () => _showBroadcastSheet(context),
          icon: const Icon(Icons.campaign_outlined, color: AppColors.brand),
          label: const Text('Send Message to All Staff', style: TextStyle(color: AppColors.brand)),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
            side: const BorderSide(color: AppColors.brand),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        )),
        Expanded(child: state.isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
            : state.ownerNotifications.isEmpty
                ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.notifications_none_outlined, color: AppColors.muted, size: 56),
                    SizedBox(height: 12),
                    Text('No notifications yet', style: TextStyle(color: AppColors.silver)),
                  ]))
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: state.ownerNotifications.length,
                    separatorBuilder: (_, __) => const Divider(color: AppColors.border, height: 1),
                    itemBuilder: (_, i) {
                      final n = state.ownerNotifications[i];
                      final isRead = n['isRead'] == true;
                      return GestureDetector(
                        onTap: () {
                          if (n['type'] == 'new_report' && n['reportId'] != null) {
                            context.push('/owner/report/${n['reportId']}');
                          }
                          if (n['type'] == 'flagged' && n['reportId'] != null) {
                            context.push('/owner/report/${n['reportId']}');
                          }
                        },
                        child: Container(
                          color: Colors.transparent,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            _notifIcon(n['type'] ?? ''),
                            const SizedBox(width: 14),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(n['title'] ?? '', style: TextStyle(
                                color: isRead ? AppColors.silver : AppColors.white,
                                fontWeight: isRead ? FontWeight.w400 : FontWeight.w600, fontSize: 14,
                              )),
                              const SizedBox(height: 3),
                              Text(n['body'] ?? '', style: const TextStyle(color: AppColors.silver, fontSize: 13)),
                              const SizedBox(height: 4),
                              Text(n['createdAt'] != null ? timeago.format(DateTime.parse(n['createdAt'])) : '',
                                  style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                            ])),
                            if (!isRead)
                              Container(width: 8, height: 8, margin: const EdgeInsets.only(top: 5),
                                  decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle)),
                          ]),
                        ),
                      );
                    },
                  )),
      ]),
    );
  }

  void _showBroadcastSheet(BuildContext context) {
    final titleCtrl = TextEditingController();
    final bodyCtrl  = TextEditingController();
    showModalBottomSheet(
      context: context, backgroundColor: AppColors.dark2, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Broadcast Message', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.white)),
          const SizedBox(height: 4),
          const Text('Sends a push notification to all staff', style: TextStyle(color: AppColors.silver, fontSize: 13)),
          const SizedBox(height: 20),
          TextField(controller: titleCtrl, style: const TextStyle(color: AppColors.white),
              decoration: const InputDecoration(labelText: 'Title')),
          const SizedBox(height: 12),
          TextField(controller: bodyCtrl, maxLines: 3, style: const TextStyle(color: AppColors.white),
              decoration: const InputDecoration(labelText: 'Message')),
          const SizedBox(height: 20),
          AppButton(label: 'Send to All Staff', icon: Icons.send_outlined, onPressed: () async {
            if (titleCtrl.text.isEmpty || bodyCtrl.text.isEmpty) return;
            Navigator.pop(context);
            await ref.read(ownerControllerProvider.notifier)
                .broadcastNotification(titleCtrl.text.trim(), bodyCtrl.text.trim());
          }),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }

  Widget _notifIcon(String type) {
    final (icon, color) = switch (type) {
      'new_report'         => (Icons.assignment_outlined,     AppColors.brand),
      'flagged'            => (Icons.warning_amber_rounded,   AppColors.red),
      'draft'              => (Icons.drafts_outlined,         AppColors.yellow),
      'payment'            => (Icons.receipt_long_outlined,   AppColors.green),
      'tracking_stale'     => (Icons.location_off_outlined,   AppColors.yellow),
      'tracking_impaired'  => (Icons.gpp_maybe_outlined,      AppColors.red),
      'checkin'            => (Icons.login_rounded,           AppColors.green),
      'checkout'           => (Icons.logout_rounded,          AppColors.muted),
      _                    => (Icons.notifications_outlined,  AppColors.muted),
    };
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
      child: Icon(icon, color: color, size: 20),
    );
  }
}