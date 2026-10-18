import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/report_card.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../shared/services/socket_service.dart';
import '../controllers/owner_controller.dart';

class OwnerDashboardScreen extends ConsumerStatefulWidget {
  const OwnerDashboardScreen({super.key});
  @override ConsumerState<OwnerDashboardScreen> createState() => _OwnerDashboardScreenState();
}

class _OwnerDashboardScreenState extends ConsumerState<OwnerDashboardScreen> with WidgetsBindingObserver {
  int _unreadCount = 0;
  bool _loading = true;
  bool _loadFailed = false;
  Timer? _refreshTimer;
  final List<SocketListenerId> _socketIds = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _loadDashboard() async {
    if (mounted) setState(() { _loading = true; _loadFailed = false; });
    try {
      final ok = await ref.read(ownerControllerProvider.notifier).loadDashboard()
          .timeout(const Duration(seconds: 15));
      if (mounted) setState(() => _loadFailed = !ok);
    } on TimeoutException {
      if (mounted) setState(() => _loadFailed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _init() async {
    await _loadDashboard();
    _loadUnreadCount();
    _startAutoRefresh();
    _connectSocket();
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) _loadDashboard();
    });
  }

  void _connectSocket() {
    SocketService.connect();
    _socketIds.add(SocketService.onNewReport((data) {
      if (!mounted) return;
      _loadDashboard();
      setState(() => _unreadCount++);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.assignment_outlined, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text('New: ${data['staffName'] ?? ''} - ${data['jobTitle'] ?? ''}')),
        ]),
        backgroundColor: AppColors.brand, duration: const Duration(seconds: 3),
        action: SnackBarAction(label: 'View', textColor: Colors.white,
          onPressed: () { if (data['reportId'] != null) context.push('/owner/report/${data['reportId']}'); }),
      ));
    }));
    _socketIds.add(SocketService.onFlaggedReport((data) {
      if (!mounted) return;
      _loadDashboard();
      setState(() => _unreadCount++);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('! Flagged: ${data['staffName'] ?? ''}'),
        backgroundColor: AppColors.red, duration: const Duration(seconds: 5)));
    }));
    _socketIds.add(SocketService.onStaffCheckIn((_) { if (mounted) _loadDashboard(); }));
    _socketIds.add(SocketService.onStaffCheckOut((_) { if (mounted) _loadDashboard(); }));
  }

  Future<void> _loadUnreadCount() async {
    final c = await ref.read(ownerControllerProvider.notifier).getUnreadNotifCount();
    if (mounted) setState(() => _unreadCount = c);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      _loadDashboard();
      ref.read(ownerControllerProvider.notifier).loadSubscriptionStatus();
      _loadUnreadCount();
      if (!SocketService.isConnected) _connectSocket();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    for (final id in _socketIds) {
      SocketService.off(id);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ownerControllerProvider);
    final today = DateFormat('EEEE, d MMM').format(DateTime.now()).toUpperCase();

    return Scaffold(
      backgroundColor: AppColors.dark,
      body: SafeArea(child: RefreshIndicator(
        color: AppColors.brand,
        onRefresh: () async { await _loadDashboard(); await _loadUnreadCount(); },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [SliverPadding(padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
          sliver: SliverList(delegate: SliverChildListDelegate([

            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(state.orgName, maxLines: 1,
                      style: AppTextStyles.h2.copyWith(fontSize: 21)),
                  ),
                  const SizedBox(height: 4),
                  Row(children: [
                    Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text(today, style: const TextStyle(color: AppColors.silver, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.6)),
                  ]),
                ]),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => context.push('/owner/subscription'),
                child: Container(
                  margin: const EdgeInsets.only(top: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: const Color(0xFFC7D2FE)),
                    boxShadow: AppColors.softShadow,
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.star_rounded, size: 12, color: AppColors.indigo),
                    const SizedBox(width: 3),
                    Text(state.plan.toUpperCase(), style: const TextStyle(color: AppColors.indigo, fontWeight: FontWeight.w700, fontSize: 10, letterSpacing: 0.5)),
                  ]),
                ),
              ),
              const SizedBox(width: 6),
              HeaderIconButton(
                icon: Icons.notifications_none_rounded,
                badge: _unreadCount,
                onTap: () async { await context.push('/owner/notifications'); _loadUnreadCount(); },
              ),
              const SizedBox(width: 8),
              HeaderIconButton(icon: Icons.settings_outlined, onTap: () => context.push('/owner/settings')),
            ]),
            const SizedBox(height: 18),

            Row(children: [
              _tile(Icons.groups_2_outlined, 'Staff', 'Manage your team members', const Color(0xFF2563EB), const Color(0xFFEFF6FF), () => context.push('/owner/staff')),
              const SizedBox(width: 12),
              _tile(Icons.map_outlined, 'Live Map', 'Track staff in real-time', const Color(0xFF7C3AED), const Color(0xFFF5F3FF), () => context.push('/owner/map')),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              _tile(Icons.event_note_outlined, 'Leave management', 'Approve & track time off', const Color(0xFF059669), const Color(0xFFECFDF5), () => context.push('/owner/leaves')),
              const SizedBox(width: 12),
              _tile(Icons.summarize_outlined, 'Reports', 'View and download reports', const Color(0xFFEA580C), const Color(0xFFFFF7ED), () => context.push('/owner/history')),
            ]),
            const SizedBox(height: 12),
            _wideTile(),
            const SizedBox(height: 22),

            if (_loading && state.staffStatuses.isEmpty && state.recentReports.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: AppColors.brand, strokeWidth: 2.5),
                      const SizedBox(height: 14),
                      Text(
                        _loadFailed ? 'Could not load dashboard' : 'Loading dashboard...',
                        style: const TextStyle(color: AppColors.silver, fontSize: 14),
                      ),
                      if (_loadFailed) ...[
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: _loadDashboard,
                          child: const Text('Retry', style: TextStyle(color: AppColors.brand)),
                        ),
                      ],
                    ],
                  ),
                ),
              )
            else ...[
              _sectionHeader('Staff Status', 'Manage', () => context.push('/owner/staff')),
              const SizedBox(height: 12),
              ...state.staffStatuses.map((s) {
                final staffId = s['_id']?.toString() ?? '';
                final name = _asString(s['name']);
                final lastReport = _asString(s['lastReport']);
                final status = _staffBadgeStatus(s['status']);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SurfaceCard(
                    color: AppColors.dark3,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    onTap: staffId.isEmpty ? null : () => context.push('/owner/staff/$staffId'),
                    child: Row(children: [
                      InitialAvatar(name: name.isEmpty ? 'Staff' : name, size: 42, color: AppColors.brand,
                        online: status == StaffStatus.active),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(name.isEmpty ? 'Staff' : name, style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 15)),
                        const SizedBox(height: 2),
                        Text(lastReport.isEmpty ? 'No report yet' : lastReport, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.silver, fontSize: 12.5)),
                      ])),
                      StatusBadge(status: status),
                    ]),
                  ),
                );
              }),
              const SizedBox(height: 18),

              _sectionHeader('Recent Reports', 'View All', () => context.push('/owner/history')),
              const SizedBox(height: 12),
              if (state.recentReports.isEmpty)
                SurfaceCard(
                  color: const Color(0xFFF1F5F9),
                  radius: 22,
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 26),
                  child: SoftEmptyState(
                    icon: Icons.assignment_outlined,
                    title: 'No reports yet',
                    subtitle: 'Reports your staff submit will appear here so you can track field activity in real-time.',
                    action: SizedBox(
                      width: 220,
                      child: PrimaryButton(
                        label: 'Assign New Job',
                        icon: Icons.add_rounded,
                        height: 46,
                        gradient: AppColors.brandGradient,
                        onPressed: () => context.push('/owner/jobs'),
                      ),
                    ),
                  ),
                )
              else ...state.recentReports.map((r) => ReportCard(
                report: r,
                showStaffName: true,
                actionLabel: 'View',
                onTap: () => context.push('/owner/report/${r.id}'),
              )),
            ],
          ])))
        ]),
      )),
    );
  }

  Widget _sectionHeader(String title, String action, VoidCallback onTap) {
    return Row(children: [
      Expanded(child: Text(title, style: AppTextStyles.h3.copyWith(fontWeight: FontWeight.w700))),
      GestureDetector(
        onTap: onTap,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(action, style: const TextStyle(color: AppColors.brand, fontSize: 13.5, fontWeight: FontWeight.w600)),
          const Icon(Icons.chevron_right_rounded, color: AppColors.brand, size: 18),
        ]),
      ),
    ]);
  }

  /// Pastel quick-action tile with a coloured icon disc and a status dot.
  Widget _tile(IconData icon, String title, String subtitle, Color color, Color tint, VoidCallback onTap) {
    return Expanded(
      child: SurfaceCard(
        radius: 22,
        padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
        borderColor: color.withValues(alpha: 0.14),
        gradient: LinearGradient(
          colors: [tint, Color.lerp(tint, AppColors.white, 0.35)!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        onTap: onTap,
        child: SizedBox(
          height: 108,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: AppColors.glow(color)),
                child: Icon(icon, color: AppColors.white, size: 22),
              ),
              const Spacer(),
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color.withValues(alpha: 0.45), shape: BoxShape.circle)),
            ]),
            const Spacer(),
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: AppTextStyles.h3.copyWith(fontSize: 14.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.silver, fontSize: 11.5, height: 1.3)),
          ]),
        ),
      ),
    );
  }

  Widget _wideTile() {
    const color = Color(0xFFEA580C);
    return SurfaceCard(
      radius: 22,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      borderColor: color.withValues(alpha: 0.16),
      gradient: const LinearGradient(colors: [Color(0xFFFFF1F2), Color(0xFFFFF7ED), Color(0xFFFEFCE8)]),
      onTap: () => context.push('/owner/staff-attendance'),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: AppColors.glow(color)),
          child: const Icon(Icons.how_to_reg_outlined, color: AppColors.white, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Attendance management', style: AppTextStyles.h3.copyWith(fontSize: 14.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          const Text('Daily presence & monthly attendance matrix', maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppColors.silver, fontSize: 11.5)),
        ])),
        Container(
          width: 30,
          height: 30,
          decoration: const BoxDecoration(color: AppColors.white, shape: BoxShape.circle, boxShadow: AppColors.softShadow),
          child: const Icon(Icons.chevron_right_rounded, color: color, size: 20),
        ),
      ]),
    );
  }

  String _asString(dynamic value) => value?.toString().trim() ?? '';

  StaffStatus _staffBadgeStatus(dynamic raw) {
    final status = _asString(raw).toLowerCase();
    if (status == 'active') return StaffStatus.active;
    if (status == 'slow') return StaffStatus.slow;
    return StaffStatus.missing;
  }
}
