import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/network/api_service.dart';
import '../../../core/utils/api_error_utils.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../controllers/owner_controller.dart';

class OwnerNotificationsScreen extends ConsumerStatefulWidget {
  const OwnerNotificationsScreen({super.key});
  @override
  ConsumerState<OwnerNotificationsScreen> createState() =>
      _OwnerNotificationsScreenState();
}

class _OwnerNotificationsScreenState
    extends ConsumerState<OwnerNotificationsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() =>
        ref.read(ownerControllerProvider.notifier).loadOwnerNotifications());
  }

  static const _activityTypes = {
    'staff_login', 'staff_logout', 'checkin', 'checkout', 'tracking_stale', 'tracking_impaired',
  };
  String _filter = 'all';
  final Map<String, String> _leaveDecisions = {};
  final Set<String> _deciding = {};

  bool _isActivity(Map n) => _activityTypes.contains(n['type']);
  bool _isRequest(Map n) => n['type'] == 'leave_request';

  void _open(Map<String, dynamic> n) {
    if (n['type'] == 'new_report' && n['reportId'] != null) {
      context.push('/owner/report/${n['reportId']}');
    }
    if (n['type'] == 'flagged' && n['reportId'] != null) {
      context.push('/owner/report/${n['reportId']}');
    }
    if (n['type'] == 'leave_request') {
      context.push('/owner/leaves');
    }
    if (n['type'] == 'staff_login' || n['type'] == 'staff_logout') {
      _openMap(n);
    }
  }

  void _openMap(Map<String, dynamic> n) {
    final data = n['data'] is Map ? n['data'] as Map : const {};
    final staffId = (data['staffId'] ?? n['staffId'])?.toString();
    context.push(staffId == null || staffId.isEmpty
        ? '/owner/map'
        : '/owner/map?staffId=${Uri.encodeComponent(staffId)}');
  }

  String? _leaveId(Map<String, dynamic> n) {
    final data = n['data'] is Map ? n['data'] as Map : const {};
    return (data['leaveId'] ?? n['leaveId'])?.toString();
  }

  Future<void> _decideLeave(String leaveId, String status) async {
    setState(() => _deciding.add(leaveId));
    try {
      final res = await ref.read(apiServiceProvider).put('/leaves/status', data: {'ids': [leaveId], 'status': status});
      final ok = res.data is Map && res.data['success'] == true;
      if (!mounted) return;
      if (ok) {
        setState(() => _leaveDecisions[leaveId] = status);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(res.data is Map && res.data['message'] is String ? res.data['message'] : 'Could not update leave'),
          backgroundColor: AppColors.red,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(friendlyErrorMessage(e, fallback: 'Could not update leave')),
          backgroundColor: AppColors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _deciding.remove(leaveId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ownerControllerProvider);
    final all = state.ownerNotifications;
    final unread = all.where((n) => n['isRead'] != true).length;
    final visible = switch (_filter) {
      'unread' => all.where((n) => n['isRead'] != true).toList(),
      'activity' => all.where(_isActivity).toList(),
      'requests' => all.where(_isRequest).toList(),
      _ => all,
    };
    // "All" keeps account/system notices first, then a Staff Activity section.
    final general = _filter == 'all' ? visible.where((n) => !_isActivity(n) && !_isRequest(n)).toList() : visible;
    final activity = _filter == 'all' ? visible.where((n) => _isActivity(n) || _isRequest(n)).toList() : <Map<String, dynamic>>[];

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
                  onTap: () => ref.read(ownerControllerProvider.notifier).markOwnerNotificationsRead(),
                  child: const Text('Mark all read',
                      style: TextStyle(color: AppColors.brand, fontSize: 13.5, fontWeight: FontWeight.w600)),
                ),
            ],
          ),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.brand,
              onRefresh: () => ref.read(ownerControllerProvider.notifier).loadOwnerNotifications(),
              child: ListView(padding: const EdgeInsets.fromLTRB(0, 4, 0, 24), children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SurfaceCard(
                    radius: 18,
                    padding: const EdgeInsets.all(14),
                    onTap: () => _showBroadcastSheet(context),
                    child: Row(children: [
                      const IconTile(icon: Icons.campaign_outlined, color: AppColors.brand, size: 44, iconSize: 22),
                      const SizedBox(width: 14),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Send Message to All Staff', style: AppTextStyles.h3.copyWith(fontSize: 15.5)),
                        const SizedBox(height: 2),
                        const Text('Instant push notification broadcast', style: TextStyle(color: AppColors.silver, fontSize: 12.5)),
                      ])),
                    ]),
                  ),
                ),
                const SizedBox(height: 14),
                PillChipBar(chips: [
                  PillChip(label: 'All (${all.length})', selected: _filter == 'all', onTap: () => setState(() => _filter = 'all')),
                  PillChip(label: 'Unread', dot: unread > 0, selected: _filter == 'unread', onTap: () => setState(() => _filter = 'unread')),
                  PillChip(label: 'Activity', selected: _filter == 'activity', onTap: () => setState(() => _filter = 'activity')),
                  PillChip(label: 'Requests', selected: _filter == 'requests', onTap: () => setState(() => _filter = 'requests')),
                ]),
                const SizedBox(height: 10),
                if (state.isLoading && all.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 80),
                    child: Center(child: CircularProgressIndicator(color: AppColors.brand)),
                  )
                else if (visible.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 60),
                    child: SoftEmptyState(
                      icon: Icons.notifications_none_rounded,
                      title: 'All caught up!',
                      subtitle: 'New reports, staff activity and requests will appear here.',
                    ),
                  )
                else ...[
                  ...general.map(_tile),
                  if (activity.isNotEmpty) ...[
                    const SectionLabel('Staff Activity', rule: true, padding: EdgeInsets.fromLTRB(16, 14, 16, 4)),
                    ...activity.map(_tile),
                  ],
                ],
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _tile(Map<String, dynamic> n) {
    final type = (n['type'] ?? '').toString();
    if (type == 'leave_request') return _leaveTile(n);
    final isRead = n['isRead'] == true;
    final activity = _isActivity(n);
    final highlight = !isRead && !activity;
    final (icon, color) = _notifIcon(type);
    final time = n['createdAt'] != null ? timeago.format(DateTime.parse(n['createdAt'])) : '';
    final tag = _tag(type);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: highlight ? AppColors.brandSoft : AppColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: highlight ? AppColors.brandBorder : AppColors.border),
          boxShadow: AppColors.cardShadow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _open(n),
              child: Container(
                decoration: BoxDecoration(
                  border: highlight ? const Border(left: BorderSide(color: AppColors.brand, width: 3)) : null,
                ),
                padding: const EdgeInsets.fromLTRB(16, 16, 14, 14),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  IconTile(
                    icon: icon,
                    color: activity ? AppColors.silver : color,
                    background: activity ? AppColors.dark3 : null,
                    size: 40,
                    iconSize: 20,
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: Text(n['title'] ?? '',
                        style: TextStyle(
                          color: AppColors.text,
                          fontWeight: isRead ? FontWeight.w600 : FontWeight.w700,
                          fontSize: 15,
                        ))),
                      if (!isRead)
                        Container(
                          width: 9,
                          height: 9,
                          margin: const EdgeInsets.only(left: 8, top: 4),
                          decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle),
                        ),
                    ]),
                    const SizedBox(height: 4),
                    Text(n['body'] ?? '', style: const TextStyle(color: AppColors.silver, fontSize: 13, height: 1.45)),
                    const SizedBox(height: 10),
                    if (type == 'staff_login')
                      Row(children: [
                        GestureDetector(
                          onTap: () => _openMap(n),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: AppColors.brandSoft,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.brandBorder),
                            ),
                            child: const Row(mainAxisSize: MainAxisSize.min, children: [
                              Text('View on map', style: TextStyle(color: AppColors.brand, fontSize: 12.5, fontWeight: FontWeight.w600)),
                              SizedBox(width: 6),
                              Icon(Icons.arrow_forward_rounded, size: 14, color: AppColors.brand),
                            ]),
                          ),
                        ),
                        const Spacer(),
                        Text(time, style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
                      ])
                    else
                      Row(children: [
                        Text(time, style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
                        if (tag != null) ...[
                          Container(
                            width: 4,
                            height: 4,
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: const BoxDecoration(color: AppColors.muted, shape: BoxShape.circle),
                          ),
                          Text(tag, style: const TextStyle(color: AppColors.brand, fontSize: 11.5, fontWeight: FontWeight.w600)),
                        ],
                      ]),
                  ])),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _leaveTile(Map<String, dynamic> n) {
    final leaveId = _leaveId(n);
    final decision = leaveId == null ? null : _leaveDecisions[leaveId];
    final busy = leaveId != null && _deciding.contains(leaveId);
    final time = n['createdAt'] != null ? timeago.format(DateTime.parse(n['createdAt'])) : '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: SurfaceCard(
        radius: 16,
        color: const Color(0xFFFFFBEB),
        borderColor: const Color(0xFFFDE68A),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        onTap: () => _open(n),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const IconTile(icon: Icons.event_busy_outlined, color: AppColors.yellow, background: Color(0xFFFEF3C7), size: 40, iconSize: 20),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(n['title'] ?? 'New leave request',
                style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 15))),
              if (decision == null)
                const SoftBadge(label: 'Action required', color: AppColors.amberDark, background: Color(0xFFFEF3C7), fontSize: 11)
              else
                SoftBadge(
                  label: decision == 'approved' ? 'Approved' : 'Declined',
                  color: decision == 'approved' ? AppColors.greenDark : AppColors.red,
                  fontSize: 11,
                ),
            ]),
            const SizedBox(height: 4),
            Text(n['body'] ?? '', style: const TextStyle(color: AppColors.light, fontSize: 13, height: 1.45)),
            if (leaveId != null && decision == null) ...[
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: SizedBox(
                    height: 36,
                    child: ElevatedButton(
                      onPressed: busy ? null : () => _decideLeave(leaveId, 'approved'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.greenDark,
                        minimumSize: const Size(0, 36),
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 13.5, fontWeight: FontWeight.w600),
                      ),
                      child: busy
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white))
                          : const Text('Approve'),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 36,
                    child: OutlinedButton(
                      onPressed: busy ? null : () => _decideLeave(leaveId, 'rejected'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.red,
                        minimumSize: const Size(0, 36),
                        padding: EdgeInsets.zero,
                        side: BorderSide(color: AppColors.red.withValues(alpha: 0.35)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 13.5, fontWeight: FontWeight.w600),
                      ),
                      child: const Text('Decline'),
                    ),
                  ),
                ),
              ]),
            ],
            const SizedBox(height: 10),
            Text(time, style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
          ])),
        ]),
      ),
    );
  }

  String? _tag(String type) => switch (type) {
        'payment' || 'enterprise_approved' || 'enterprise_rejected' || 'enterprise_deactivated' || 'account_deletion_approved' || 'account_deletion_rejected' => 'Account',
        'enterprise_request' => 'Support',
        'new_report' || 'flagged' || 'draft' || 'draft_reminder' => 'Reports',
        'job_completed' || 'job_assigned' => 'Jobs',
        _ => null,
      };

  void _showBroadcastSheet(BuildContext context) {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    final activeStaff = ref.read(ownerControllerProvider).staffList
        .where((s) => s['invitePending'] != true && s['inviteStatus'] != 'pending')
        .length;
    AppSheet.show(
      context,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheet) => AppSheet(
          title: 'Broadcast Message',
          subtitle: 'Sends an instant push notification to all staff members.',
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SoftBadge(
                    label: activeStaff > 0 ? 'Recipients:  All Active Staff ($activeStaff)' : 'Recipients:  All Active Staff',
                    color: AppColors.brand,
                    dot: true,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 18),
                FieldLabel('Notification Title', required: true, hint: '${titleCtrl.text.length}/50'),
                TextField(
                  controller: titleCtrl,
                  maxLength: 50,
                  onChanged: (_) => setSheet(() {}),
                  style: const TextStyle(color: AppColors.text),
                  decoration: const InputDecoration(
                    counterText: '',
                    fillColor: AppColors.white,
                    hintText: 'e.g., Urgent: Site Update or Team Meeting',
                  ),
                ),
                const SizedBox(height: 16),
                FieldLabel('Message Body', required: true, hint: '${bodyCtrl.text.length}/250'),
                TextField(
                  controller: bodyCtrl,
                  minLines: 4,
                  maxLines: 6,
                  maxLength: 250,
                  onChanged: (_) => setSheet(() {}),
                  style: const TextStyle(color: AppColors.text),
                  decoration: const InputDecoration(
                    counterText: '',
                    fillColor: AppColors.white,
                    hintText: 'Write your broadcast message here...',
                  ),
                ),
                const SizedBox(height: 22),
                PrimaryButton(
                  label: 'Send to All Staff',
                  icon: Icons.near_me_outlined,
                  onPressed: titleCtrl.text.trim().isEmpty || bodyCtrl.text.trim().isEmpty
                      ? null
                      : () async {
                          Navigator.pop(sheetCtx);
                          await ref
                              .read(ownerControllerProvider.notifier)
                              .broadcastNotification(titleCtrl.text.trim(), bodyCtrl.text.trim());
                        },
                ),
              ]),
        ),
      ),
    );
  }

  (IconData, Color) _notifIcon(String type) => switch (type) {
        'new_report' => (Icons.assignment_outlined, AppColors.brand),
        'flagged' => (Icons.warning_amber_rounded, AppColors.red),
        'draft' || 'draft_reminder' => (Icons.drafts_outlined, AppColors.yellow),
        'payment' => (Icons.receipt_long_outlined, AppColors.greenDark),
        'tracking_stale' => (Icons.location_off_outlined, AppColors.yellow),
        'tracking_impaired' => (Icons.gpp_maybe_outlined, AppColors.red),
        'checkin' => (Icons.login_rounded, AppColors.greenDark),
        'checkout' => (Icons.logout_rounded, AppColors.silver),
        'leave_request' => (Icons.event_busy_outlined, AppColors.yellow),
        'staff_login' => (Icons.location_on_outlined, AppColors.silver),
        'staff_logout' => (Icons.login_rounded, AppColors.silver),
        'enterprise_approved' => (Icons.verified_user_outlined, AppColors.brand),
        'enterprise_request' => (Icons.send_outlined, const Color(0xFF0891B2)),
        _ => (Icons.notifications_outlined, AppColors.brand),
      };
}
