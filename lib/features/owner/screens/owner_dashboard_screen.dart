import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/report_card.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/empty_state.dart';
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
          Expanded(child: Text('New: ${data['staffName'] ?? ''} â€” ${data['jobTitle'] ?? ''}')),
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
        content: Text('âš  Flagged: ${data['staffName'] ?? ''}'),
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
    final today = DateFormat('EEEE, d MMM').format(DateTime.now());

    return Scaffold(
      backgroundColor: AppColors.dark,
      body: SafeArea(child: RefreshIndicator(
        color: AppColors.brand,
        onRefresh: () async { await _loadDashboard(); await _loadUnreadCount(); },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [SliverPadding(padding: const EdgeInsets.all(20),
          sliver: SliverList(delegate: SliverChildListDelegate([

            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(state.orgName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.white)),
                Text(today, style: const TextStyle(color: AppColors.silver, fontSize: 13)),
              ]),
              Row(children: [
                Stack(children: [
                  IconButton(icon: const Icon(Icons.notifications_outlined, color: AppColors.white),
                    onPressed: () async { await context.push('/owner/notifications'); _loadUnreadCount(); }),
                  if (_unreadCount > 0) Positioned(top: 8, right: 8,
                    child: Container(width: 16, height: 16,
                      decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle),
                      child: Center(child: Text(_unreadCount > 9 ? '9+' : '$_unreadCount',
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800))))),
                ]),
                GestureDetector(onTap: () => context.push('/owner/subscription'),
                  child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: AppColors.brand.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(100), border: Border.all(color: AppColors.brand.withValues(alpha: 0.3))),
                    child: Text(state.plan.toUpperCase(), style: const TextStyle(color: AppColors.brand, fontWeight: FontWeight.w700, fontSize: 11)))),
                const SizedBox(width: 6),
                GestureDetector(onTap: () => context.push('/owner/settings'),
                  child: const Icon(Icons.settings_outlined, color: AppColors.silver, size: 22)),
              ]),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              _shortcut(Icons.people_outline, 'Staff', () => context.push('/owner/staff')),
              const SizedBox(width: 10),
              _shortcut(Icons.history, 'History', () => context.push('/owner/history')),
              const SizedBox(width: 10),
              _shortcut(Icons.map_outlined, 'Live Map', () => context.push('/owner/map')),
            ]),
            const SizedBox(height: 20),

            Row(children: [
              _statCard('Reports', '${state.totalReportsToday}', AppColors.brand, Icons.assignment_outlined),
              const SizedBox(width: 10),
              _statCard('Active', '${state.activeStaffCount}/${state.totalStaff}', AppColors.green, Icons.people_outline),
              const SizedBox(width: 10),
              _statCard(
                'Drafts',
                '${state.pendingDraftCount}',
                AppColors.yellow,
                Icons.drafts_outlined,
                onTap: () => context.push('/owner/history?status=draft'),
              ),
            ]),
            const SizedBox(height: 20),

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
                        _loadFailed ? 'Could not load dashboard' : 'Loading dashboardâ€¦',
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
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Staff Status', style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                GestureDetector(onTap: () => context.push('/owner/staff'),
                  child: const Text('Manage', style: TextStyle(color: AppColors.brand, fontSize: 13))),
              ]),
              const SizedBox(height: 12),
              ...state.staffStatuses.map((s) {
                final staffId = s['_id']?.toString() ?? '';
                final name = _asString(s['name']);
                final lastReport = _asString(s['lastReport']);
                return Container(
                margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.dark2, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
                child: Row(children: [
                  GestureDetector(onTap: staffId.isEmpty ? null : () => context.push('/owner/staff/$staffId'),
                    child: CircleAvatar(backgroundColor: AppColors.brand.withValues(alpha: 0.2), radius: 18,
                      child: Text(_nameInitial(name),
                        style: const TextStyle(color: AppColors.brand, fontWeight: FontWeight.w700)))),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name.isEmpty ? 'Staff' : name, style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w600)),
                    Text(lastReport.isEmpty ? 'No report yet' : lastReport, style: const TextStyle(color: AppColors.silver, fontSize: 12)),
                  ])),
                  StatusBadge(status: _staffBadgeStatus(s['status'])),
                ]));
              }),
              const SizedBox(height: 20),

              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Recent Reports', style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                GestureDetector(onTap: () => context.push('/owner/history'),
                  child: const Text('View All', style: TextStyle(color: AppColors.brand, fontSize: 13))),
              ]),
              const SizedBox(height: 12),
              if (state.recentReports.isEmpty) const EmptyState(type: EmptyType.reports)
              else ...state.recentReports.map((r) => ReportCard(
                report: r,
                showStaffName: true,
                onTap: () => context.push('/owner/report/${r.id}'),
              )),
            ],
          ])))
        ]),
      )),
    );
  }

  String _nameInitial(String? raw) {
    final name = raw?.trim();
    if (name == null || name.isEmpty) return '?';
    return name[0].toUpperCase();
  }

  String _asString(dynamic value) => value?.toString().trim() ?? '';

  StaffStatus _staffBadgeStatus(dynamic raw) {
    final status = _asString(raw).toLowerCase();
    if (status == 'active') return StaffStatus.active;
    if (status == 'slow') return StaffStatus.slow;
    return StaffStatus.missing;
  }

  Widget _statCard(
    String label,
    String value,
    Color color,
    IconData icon, {
    VoidCallback? onTap,
  }) {
    final card = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w800)),
          Text(label, style: const TextStyle(color: AppColors.silver, fontSize: 11)),
        ],
      ),
    );
    return Expanded(
      child: onTap == null
          ? card
          : GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: card),
    );
  }

  Widget _shortcut(IconData icon, String label, VoidCallback onTap) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.dark2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(children: [
          Icon(icon, color: AppColors.brand, size: 22),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(color: AppColors.white, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      ),
    ),
  );
}