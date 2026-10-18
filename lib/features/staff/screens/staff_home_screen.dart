import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_service.dart';
import '../../../core/utils/date_utils.dart';
import '../../../shared/widgets/report_card.dart';
import '../../../shared/widgets/shimmer_loader.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../shared/services/socket_service.dart';
import '../../../shared/services/location_service.dart';
import '../../../shared/services/battery_optimization_service.dart';
import '../controllers/staff_controller.dart';
import '../utils/attendance_gates.dart';

class StaffHomeScreen extends ConsumerStatefulWidget {
  const StaffHomeScreen({super.key});
  @override
  ConsumerState<StaffHomeScreen> createState() => _StaffHomeScreenState();
}

class _StaffHomeScreenState extends ConsumerState<StaffHomeScreen>
    with WidgetsBindingObserver {
  Timer? _refreshTimer;
  int _unreadCount = 0;
  /// Today's org holiday ({date, occasion}) when the owner has marked one.
  Map<String, dynamic>? _holiday;
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
    unawaited(_loadHoliday());
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

  Future<void> _loadHoliday() async {
    try {
      final res = await ref.read(apiServiceProvider).get('/holidays/today');
      final data = res.data['success'] == true ? res.data['data'] : null;
      if (mounted) setState(() => _holiday = data is Map ? Map<String, dynamic>.from(data) : null);
    } catch (_) {
      // Holiday banner is informational only — never block the home screen.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(staffControllerProvider.notifier).loadTodayReports(silent: true);
      ref.read(staffControllerProvider.notifier).loadCheckInStatus();
      _loadUnreadCount();
      _loadHoliday();
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
      body: SafeArea(
          child: RefreshIndicator(
        color: AppColors.brand,
        onRefresh: () async {
          await ref.read(staffControllerProvider.notifier).loadTodayReports();
          await ref.read(staffControllerProvider.notifier).loadCheckInStatus();
          await _loadUnreadCount();
          await _loadHoliday();
        },
        child: CustomScrollView(slivers: [
          SliverPadding(
              padding: const EdgeInsets.all(20),
              sliver: SliverList(
                  delegate: SliverChildListDelegate([
                // Header
                Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Hi, ${state.userName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.h1.copyWith(fontSize: 24)),
                      const SizedBox(height: 2),
                      Text(today, style: const TextStyle(color: AppColors.silver, fontSize: 13)),
                    ]),
                  ),
                  HeaderIconButton(
                    icon: Icons.notifications_none_rounded,
                    badge: _unreadCount,
                    onTap: () => context.push('/staff/notifications'),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () => context.push('/staff/profile'),
                    child: InitialAvatar(
                      name: state.userName.isNotEmpty ? state.userName.substring(0, 1) : '?',
                      size: 42,
                      color: AppColors.brand,
                    ),
                  ),
                ]),
                const SizedBox(height: 22),

                if (_holiday != null) ...[
                  _holidayBanner(_holiday!),
                  const SizedBox(height: 16),
                ],

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
                    child: Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                            color: AppColors.amberSoft,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color:
                                    AppColors.yellow.withValues(alpha: 0.4))),
                        child: Row(children: [
                          const IconTile(icon: Icons.drafts_outlined, color: AppColors.yellow, size: 34, iconSize: 18, radius: 10),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Text(
                                  state.draftCount > 1
                                      ? '${state.draftCount} draft reports - tap to view & complete'
                                      : 'You have an unsent draft - tap to view & complete',
                                  style: const TextStyle(
                                      color: AppColors.amberDark, fontSize: 13, fontWeight: FontWeight.w500))),
                          const Icon(Icons.chevron_right_rounded,
                              color: AppColors.amberDark, size: 20),
                        ])),
                  ),

                if (state.dailyTarget > 0) ...[
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Today's Target",
                            style: TextStyle(
                                color: AppColors.silver, fontSize: 13)),
                        Text(
                            '${state.submittedToday}/${state.dailyTarget} jobs',
                            style: const TextStyle(
                                color: AppColors.text,
                                fontWeight: FontWeight.w700)),
                      ]),
                  const SizedBox(height: 8),
                  ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                          value: (state.submittedToday / state.dailyTarget)
                              .clamp(0.0, 1.0),
                          backgroundColor: AppColors.dark4,
                          valueColor: AlwaysStoppedAnimation(
                              state.submittedToday >= state.dailyTarget
                                  ? AppColors.green
                                  : AppColors.brand),
                          minHeight: 10)),
                  const SizedBox(height: 16),
                ],

                PrimaryButton(
                  label: 'My Assigned Jobs',
                  icon: Icons.business_center_outlined,
                  height: 58,
                  onPressed: () => context.push('/staff/jobs'),
                ),
                const SizedBox(height: 28),

                Row(children: [
                  Expanded(
                    child: Text("Today's Reports",
                        style: AppTextStyles.h3.copyWith(fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                  GestureDetector(
                      onTap: () => context.push('/staff/history'),
                      child: const Text('View All',
                          style: TextStyle(color: AppColors.brand, fontSize: 14, fontWeight: FontWeight.w600))),
                ]),
                const SizedBox(height: 14),

                if (state.todayLoading)
                  const ReportListShimmer()
                else if (state.todayReports.isEmpty)
                  SurfaceCard(
                    radius: 24,
                    padding: const EdgeInsets.fromLTRB(20, 30, 20, 28),
                    child: Column(children: [
                      Stack(clipBehavior: Clip.none, children: [
                        Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.brandSoft,
                            border: Border.all(color: AppColors.brandBorder.withValues(alpha: 0.6)),
                          ),
                          child: Center(
                            child: Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.brand.withValues(alpha: 0.08)),
                              child: const Icon(Icons.assignment_outlined, color: AppColors.brand, size: 30),
                            ),
                          ),
                        ),
                        Positioned(
                          right: 4,
                          top: 4,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: AppColors.blue,
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.white, width: 2),
                            ),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 18),
                      Text('No reports yet', style: AppTextStyles.h3.copyWith(fontSize: 17, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      const Text('Submit your first report to get started.',
                          textAlign: TextAlign.center, style: TextStyle(color: AppColors.silver, fontSize: 13.5)),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: 250,
                        child: PrimaryButton(
                          label: 'View Assigned Jobs',
                          icon: Icons.photo_camera_outlined,
                          height: 46,
                          onPressed: () => context.push('/staff/jobs'),
                        ),
                      ),
                    ]),
                  )
                else
                  ...state.todayReports.map((r) => ReportCard(
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

  Widget _checkInRow(StaffState state, BuildContext context) {
    final checkedIn = state.isCheckedIn;
    return SurfaceCard(
      radius: 18,
      padding: const EdgeInsets.all(16),
      borderColor: checkedIn ? AppColors.green.withValues(alpha: 0.35) : null,
      color: checkedIn ? AppColors.greenSoft : null,
      child: Row(children: [
        IconTile(
          icon: checkedIn ? Icons.verified_user_outlined : Icons.login_rounded,
          color: checkedIn ? AppColors.greenDark : AppColors.light,
          background: checkedIn ? AppColors.white : AppColors.dark4,
          size: 44,
          iconSize: 22,
        ),
        const SizedBox(width: 14),
        Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(checkedIn ? 'Checked In' : 'Not Checked In',
              style: TextStyle(
                  color: checkedIn ? AppColors.greenDark : AppColors.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 15)),
          const SizedBox(height: 2),
          Text(
              checkedIn && state.checkInTime != null
                  ? 'Since ${formatApiTime(state.checkInTime)}'
                  : 'Tap to check in for today',
              style: const TextStyle(color: AppColors.silver, fontSize: 12.5)),
        ])),
        GestureDetector(
            onTap: () async {
              if (!checkedIn) {
                context.push('/staff/checkin');
                return;
              }
              final allowed = await AttendanceGates.allowCheckOut(context, ref);
              if (!context.mounted || !allowed) return;
              context.push('/staff/checkout');
            },
            child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                    color: checkedIn ? AppColors.brand : AppColors.green,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: AppColors.glow(checkedIn ? AppColors.brand : AppColors.green)),
                child: Text(checkedIn ? 'Check Out' : 'Check In',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13.5)))),
      ]),
    );
  }

  Widget _holidayBanner(Map<String, dynamic> holiday) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.amberSoft,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.yellow.withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
                color: AppColors.yellow.withValues(alpha: 0.18),
                shape: BoxShape.circle),
            child: const Icon(Icons.celebration_outlined,
                color: AppColors.yellow, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Text('Today is a holiday',
                    style: TextStyle(
                        color: AppColors.amberDark,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('${holiday['occasion'] ?? 'Holiday'} — enjoy your day off!',
                    style: const TextStyle(
                        color: AppColors.light, fontSize: 13)),
              ])),
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
        title = 'GPS off - turn on Location';
        actionLabel = 'Fix';
        onAction = () async {
          await Geolocator.openLocationSettings();
          if (!mounted) return;
          await ref
              .read(staffControllerProvider.notifier)
              .evaluateTrackingHealth();
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
          await ref
              .read(staffControllerProvider.notifier)
              .evaluateTrackingHealth();
        };
      case TrackingHealthStatus.batteryRisk:
        icon = Icons.battery_alert_rounded;
        color = AppColors.yellow;
        title = 'Battery optimization may stop tracking';
        actionLabel = 'Fix';
        onAction = () async {
          if (!mounted) return;
          await BatteryOptimizationService.showFixGuide(context);
          if (!mounted) return;
          await ref
              .read(staffControllerProvider.notifier)
              .evaluateTrackingHealth();
        };
      case TrackingHealthStatus.trackerFailed:
        icon = Icons.error_outline_rounded;
        color = AppColors.red;
        title = 'Live tracking failed to start';
        actionLabel = 'Retry';
        onAction = () async {
          await ref
              .read(staffControllerProvider.notifier)
              .evaluateTrackingHealth();
        };
      case TrackingHealthStatus.unknown:
        icon = Icons.hourglass_empty_rounded;
        color = AppColors.muted;
        title = 'Checking live tracking...';
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
          Expanded(
              child: Text(title,
                  style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w600))),
          if (actionLabel != null)
            Text(actionLabel,
                style: const TextStyle(
                    color: AppColors.brand,
                    fontWeight: FontWeight.w700,
                    fontSize: 12)),
        ]),
      ),
    );
  }
}
