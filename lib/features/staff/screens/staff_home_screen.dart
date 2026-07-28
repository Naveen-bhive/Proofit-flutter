import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/date_utils.dart';
import '../../../shared/widgets/report_card.dart';
import '../../../shared/widgets/shimmer_loader.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/services/socket_service.dart';
import '../../../shared/services/location_service.dart';
import '../../../shared/services/battery_optimization_service.dart';
import '../controllers/staff_controller.dart';
import '../utils/attendance_gates.dart';

class StaffHomeScreen extends ConsumerStatefulWidget {
  const StaffHomeScreen({super.key});
  @override ConsumerState<StaffHomeScreen> createState() => _StaffHomeScreenState();
}

class _StaffHomeScreenState extends ConsumerState<StaffHomeScreen> with WidgetsBindingObserver {
  Timer? _refreshTimer;
  int _unreadCount = 0;
  bool _backgroundLocationPrompted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    final notifier = ref.read(staffControllerProvider.notifier);
    // Shell already loads today's reports; only refresh check-in / unread here.
    unawaited(notifier.loadCheckInStatus());
    unawaited(_loadUnreadCount());
    _startAutoRefresh();
    SocketService.connect();
    // Defer permission dialogs so the home screen paints first.
    Future<void>.delayed(const Duration(milliseconds: 800), () {
      if (mounted) _ensureBackgroundLocationIfCheckedIn();
    });
  }

  /// If already checked in without "Allow all the time", guide staff to enable it,
  /// then report tracking health so owners get impaired alerts when it fails.
  Future<void> _ensureBackgroundLocationIfCheckedIn() async {
    final checkedIn = ref.read(staffControllerProvider).isCheckedIn;
    if (!checkedIn || !mounted) return;
    if (await LocationService.hasAlwaysPermission()) {
      await ref.read(staffControllerProvider.notifier).evaluateTrackingHealth();
      return;
    }
    // Avoid re-showing the full guide on every resume; still re-check silently.
    if (_backgroundLocationPrompted) {
      await ref.read(staffControllerProvider.notifier).evaluateTrackingHealth();
      return;
    }
    _backgroundLocationPrompted = true;
    if (!mounted) return;
    await LocationService.ensureAlwaysLocationPermission(context);
    if (!mounted) return;
    await ref.read(staffControllerProvider.notifier).evaluateTrackingHealth();
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      ref.read(staffControllerProvider.notifier).loadTodayReports(silent: true);
    });
  }

  Future<void> _loadUnreadCount() async {
    final c = await ref.read(staffControllerProvider.notifier).getUnreadCount();
    if (mounted) setState(() => _unreadCount = c);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(staffControllerProvider.notifier).loadTodayReports(silent: true);
      ref.read(staffControllerProvider.notifier).loadCheckInStatus();
      _loadUnreadCount();
      if (!SocketService.isConnected) SocketService.connect();
      _ensureBackgroundLocationIfCheckedIn();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(staffControllerProvider);
    final today = DateFormat('EEEE, d MMM yyyy').format(DateTime.now());

    return Scaffold(
      backgroundColor: AppColors.dark,
      body: SafeArea(child: RefreshIndicator(
        color: AppColors.brand,
        onRefresh: () async {
          await ref.read(staffControllerProvider.notifier).loadTodayReports();
          await ref.read(staffControllerProvider.notifier).loadCheckInStatus();
          await _loadUnreadCount();
        },
        child: CustomScrollView(slivers: [SliverPadding(padding: const EdgeInsets.all(20),
          sliver: SliverList(delegate: SliverChildListDelegate([

            // Header
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Hi, ${state.userName}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.white)),
                Text(today, style: const TextStyle(color: AppColors.silver, fontSize: 13)),
              ]),
              Row(children: [
                Stack(children: [
                  IconButton(icon: const Icon(Icons.notifications_outlined, color: AppColors.white),
                    onPressed: () => context.push('/staff/notifications')),
                  if (_unreadCount > 0) Positioned(top: 8, right: 8,
                    child: Container(width: 16, height: 16,
                      decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle),
                      child: Center(child: Text(_unreadCount > 9 ? '9+' : '$_unreadCount',
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800))))),
                ]),
                GestureDetector(onTap: () => context.push('/staff/profile'),
                  child: CircleAvatar(radius: 18, backgroundColor: AppColors.brand.withValues(alpha: 0.2),
                    child: Text(state.userName.isNotEmpty ? state.userName[0].toUpperCase() : '?',
                      style: const TextStyle(color: AppColors.brand, fontWeight: FontWeight.w700)))),
              ]),
            ]),
            const SizedBox(height: 20),

            // FIX #5 Check-in row
            _checkInRow(state, context),
            if (state.isCheckedIn &&
                state.trackingHealth != TrackingHealthStatus.unknown) ...[
              const SizedBox(height: 10),
              _trackingHealthBanner(state),
            ],
            const SizedBox(height: 16),

            if (state.draftCount > 0)
              GestureDetector(
                onTap: () => context.push('/staff/history?filter=drafts'),
                child: Container(margin: const EdgeInsets.only(bottom: 16), padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: AppColors.yellow.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.yellow.withValues(alpha: 0.4))),
                  child: Row(children: [
                    const Icon(Icons.drafts_outlined, color: AppColors.yellow, size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: Text(
                      state.draftCount > 1
                          ? '${state.draftCount} draft reports â€” tap to view & complete'
                          : 'You have an unsent draft â€” tap to view & complete',
                      style: const TextStyle(color: AppColors.yellow, fontSize: 13))),
                    const Icon(Icons.chevron_right, color: AppColors.yellow, size: 18),
                  ])),
              ),

            if (state.dailyTarget > 0) ...[
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text("Today's Target", style: TextStyle(color: AppColors.silver, fontSize: 13)),
                Text('${state.submittedToday}/${state.dailyTarget} jobs', style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 8),
              ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(
                value: (state.submittedToday / state.dailyTarget).clamp(0.0, 1.0),
                backgroundColor: AppColors.dark3,
                valueColor: AlwaysStoppedAnimation(state.submittedToday >= state.dailyTarget ? AppColors.green : AppColors.brand),
                minHeight: 10)),
              const SizedBox(height: 16),
            ],

            ElevatedButton.icon(
              onPressed: () => context.push('/staff/jobs'),
              icon: const Icon(Icons.work_outline_rounded, size: 22),
              label: const Text('My Assigned Jobs'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.brand, minimumSize: const Size(double.infinity, 60),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
            const SizedBox(height: 28),

            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text("Today's Reports", style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 16)),
              GestureDetector(onTap: () => context.push('/staff/history'),
                child: const Text('View All', style: TextStyle(color: AppColors.brand, fontSize: 13))),
            ]),
            const SizedBox(height: 12),

            if (state.todayLoading) const ReportListShimmer()
            else if (state.todayReports.isEmpty)
              EmptyState(type: EmptyType.reports, actionLabel: 'View Assigned Jobs',
                onAction: () => context.push('/staff/jobs'))
            else ...state.todayReports.map((r) => ReportCard(
              key: ValueKey(r.id ?? r.jobTitle),
              report: r,
              onTap: () {
                if (r.status == 'draft') {
                  context.push('/staff/draft/${r.id}');
                } else {
                  context.push('/staff/report/${r.id}');
                }
              },
            )),

          ])))
        ]),
      )),
    );
  }

  Widget _checkInRow(StaffState state, BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: state.isCheckedIn ? AppColors.green.withValues(alpha: 0.08) : AppColors.dark2,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: state.isCheckedIn ? AppColors.green.withValues(alpha: 0.3) : AppColors.border)),
    child: Row(children: [
      Container(width: 40, height: 40,
        decoration: BoxDecoration(color: state.isCheckedIn ? AppColors.green.withValues(alpha: 0.15) : AppColors.muted.withValues(alpha: 0.1), shape: BoxShape.circle),
        child: Icon(state.isCheckedIn ? Icons.login_rounded : Icons.logout_rounded,
          color: state.isCheckedIn ? AppColors.green : AppColors.muted, size: 20)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(state.isCheckedIn ? 'Checked In' : 'Not Checked In',
          style: TextStyle(color: state.isCheckedIn ? AppColors.green : AppColors.silver, fontWeight: FontWeight.w600, fontSize: 14)),
        Text(state.isCheckedIn && state.checkInTime != null
          ? 'Since ${formatApiTime(state.checkInTime)}'
          : 'Tap to check in for today',
          style: const TextStyle(color: AppColors.muted, fontSize: 12)),
      ])),
      GestureDetector(
        onTap: () async {
          if (!state.isCheckedIn) {
            context.push('/staff/checkin');
            return;
          }
          final allowed = await AttendanceGates.allowCheckOut(context, ref);
          if (!context.mounted || !allowed) return;
          context.push('/staff/checkout');
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(color: state.isCheckedIn ? AppColors.brand : AppColors.green, borderRadius: BorderRadius.circular(100)),
          child: Text(state.isCheckedIn ? 'Check Out' : 'Check In',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)))),
    ]),
  );

  Widget _trackingHealthBanner(StaffState state) {
    final health = state.trackingHealth;

    late final IconData icon;
    late final Color color;
    late final String title;
    String? actionLabel;
    Future<void> Function()? onAction;

    switch (health) {
      case TrackingHealthStatus.active:
        icon = Icons.sensors_rounded;
        color = AppColors.green;
        title = 'Live tracking active';
      case TrackingHealthStatus.gpsOff:
        icon = Icons.location_off_outlined;
        color = AppColors.red;
        title = 'GPS off â€” turn on Location';
        actionLabel = 'Fix';
        onAction = () async {
          await Geolocator.openLocationSettings();
          if (!mounted) return;
          await ref.read(staffControllerProvider.notifier).evaluateTrackingHealth();
        };
      case TrackingHealthStatus.permissionMissing:
        icon = Icons.my_location_rounded;
        color = AppColors.yellow;
        title = 'Location permission missing';
        actionLabel = 'Fix';
        onAction = () async {
          if (!mounted) return;
          await LocationService.ensureAlwaysLocationPermission(context);
          if (!mounted) return;
          if (!await LocationService.hasPreciseLocation()) {
            if (!mounted) return;
            await LocationService.ensurePreciseLocation(context);
          }
          if (!mounted) return;
          await ref.read(staffControllerProvider.notifier).evaluateTrackingHealth();
        };
      case TrackingHealthStatus.batteryRisk:
        icon = Icons.battery_alert_rounded;
        color = AppColors.yellow;
        title = 'Battery optimization may stop tracking';
        actionLabel = 'Fix';
        onAction = () async {
          if (!mounted) return;
          await BatteryOptimizationService.ensureWarningShownBeforeCheckIn(context);
          if (!mounted) return;
          await ref.read(staffControllerProvider.notifier).evaluateTrackingHealth();
        };
      case TrackingHealthStatus.trackerFailed:
        icon = Icons.error_outline_rounded;
        color = AppColors.red;
        title = 'Live tracking failed to start';
        actionLabel = 'Retry';
        onAction = () async {
          await ref.read(staffControllerProvider.notifier).evaluateTrackingHealth();
        };
      case TrackingHealthStatus.unknown:
        icon = Icons.hourglass_empty_rounded;
        color = AppColors.muted;
        title = 'Checking live trackingâ€¦';
    }

    return GestureDetector(
      onTap: onAction == null ? null : () => onAction!(),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600))),
          if (actionLabel != null)
            Text(actionLabel, style: const TextStyle(color: AppColors.brand, fontWeight: FontWeight.w700, fontSize: 12)),
        ]),
      ),
    );
  }
}
