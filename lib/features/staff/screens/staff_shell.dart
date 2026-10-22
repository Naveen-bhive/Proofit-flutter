import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/models/app_feature.dart';
import '../../../shared/services/socket_service.dart';
import '../controllers/staff_controller.dart';
import '../../../core/network/api_service.dart';
import '../../../shared/permissions/permission_session.dart';
import 'staff_home_screen.dart';
import 'staff_jobs_screen.dart';
import 'staff_history_screen.dart';
import 'staff_profile_screen.dart';

class StaffShell extends ConsumerStatefulWidget {
  const StaffShell({super.key});
  @override ConsumerState<StaffShell> createState() => _StaffShellState();
}

class _StaffShellState extends ConsumerState<StaffShell> with WidgetsBindingObserver {
  int _tab = 0;
  SocketListenerId? _orgSocketId;
  final _jobsKey = GlobalKey<StaffJobsScreenState>();
  final _historyKey = GlobalKey<StaffHistoryScreenState>();

  @override
  void initState() {
    super.initState();
    unawaited(ref.read(staffControllerProvider.notifier).bootstrapHome());
    WidgetsBinding.instance.addObserver(this);
    _refreshPermissions();
    _connectSocket();
  }

  /// Returns true if back was handled (switched to Home). False = already on Home.
  bool _onShellBack() {
    if (_tab == 0) return false;
    setState(() => _tab = 0);
    ref.read(staffControllerProvider.notifier).loadTodayReports(silent: true);
    return true;
  }

  void _connectSocket() {
    SocketService.connect();
    _orgSocketId = SocketService.onOrgUpdated((data) {
      if (!mounted) return;
      final name = data['name'] as String?;
      if (name != null && name.isNotEmpty) {
        ref.read(staffControllerProvider.notifier).applyOrgName(name);
      } else {
        ref.read(staffControllerProvider.notifier).syncOrgFromServer();
      }
    });
  }

  // Delegated access can change at any time; re-check whenever the app opens.
  void _refreshPermissions() =>
      unawaited(PermissionSession.instance.refresh(ref.read(apiServiceProvider)));

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_orgSocketId != null) SocketService.off(_orgSocketId!);
    super.dispose();
  }

  List<Widget> get _screens => [
    const StaffHomeScreen(key: ValueKey('staff-tab-home')),
    StaffJobsScreen(key: _jobsKey),
    const SizedBox.shrink(key: ValueKey('staff-tab-submit')),
    StaffHistoryScreen(key: _historyKey, autoLoad: false),
    const StaffProfileScreen(key: ValueKey('staff-tab-profile')),
  ];

  /// The camera button starts from the job list, or straight into a report
  /// when the org doesn't use jobs.
  void _startReport() {
    final usesJobs = ref.read(staffControllerProvider).isEnabled(AppFeature.jobs);
    context.push(usesJobs ? '/staff/jobs' : '/staff/submit');
  }

  void _onTabTap(int index) {
    if (index == 2) {
      _startReport();
      return;
    }
    setState(() => _tab = index);
    if (index == 0) ref.read(staffControllerProvider.notifier).loadTodayReports(silent: true);
    if (index == 1) _jobsKey.currentState?.refresh();
    if (index == 3) _historyKey.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(staffControllerProvider);
    final unread = state.notifications.where((n) => n['isRead'] != true).length;

    // Keep My Jobs list in sync after draft save / submit from other screens.
    ref.listen(staffControllerProvider.select((s) => s.jobsEpoch), (prev, next) {
      if (prev != next) _jobsKey.currentState?.refresh();
    });

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_onShellBack()) return;
        SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: AppColors.dark,
        body: IndexedStack(index: _tab == 2 ? 0 : _tab, children: _screens),
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            color: AppColors.white,
            border: Border(top: BorderSide(color: AppColors.border, width: 1)),
            boxShadow: [BoxShadow(color: Color(0x0A0F172A), blurRadius: 12, offset: Offset(0, -2))],
          ),
          child: SafeArea(
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.2,
              child: Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  _navItem(0, Icons.home_outlined,            Icons.home_rounded,            'Home'),
                  if (state.isEnabled(AppFeature.jobs))
                    _navItem(1, Icons.business_center_outlined, Icons.business_center_rounded, 'Jobs'),
                  Expanded(child: GestureDetector(
                    onTap: _startReport,
                    behavior: HitTestBehavior.opaque,
                    child: SizedBox(
                      height: 46,
                      child: OverflowBox(
                        maxHeight: 80,
                        alignment: Alignment.bottomCenter,
                        child: Transform.translate(
                          offset: const Offset(0, -14),
                          child: Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: AppColors.white, width: 3),
                              boxShadow: AppColors.glow(AppColors.brand),
                            ),
                            child: const Icon(Icons.camera_alt_outlined, color: Colors.white, size: 26),
                          ),
                        ),
                      ),
                    ),
                  )),
                  _navItem(3, Icons.history_toggle_off_rounded, Icons.history_rounded,        'History'),
                  _navItem(4, Icons.person_outline_rounded,   Icons.person_rounded,          'Profile',
                    badge: unread > 0 ? unread : null),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData icon, IconData activeIcon, String label, {int? badge}) {
    final active = _tab == index;
    return Expanded(child: GestureDetector(
      onTap: () => _onTabTap(index),
      behavior: HitTestBehavior.opaque,
      child: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
        Stack(clipBehavior: Clip.none, children: [
          Icon(active ? activeIcon : icon, color: active ? AppColors.brand : AppColors.muted, size: 25),
          if (badge != null) Positioned(top: -3, right: -6,
            child: Container(width: 15, height: 15, decoration: BoxDecoration(color: AppColors.red, shape: BoxShape.circle, border: Border.all(color: AppColors.white, width: 1.5)),
              child: Center(child: Text(badge > 9 ? '9+' : '$badge', style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800))))),
        ]),
        const SizedBox(height: 5),
        Text(
          label,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: active ? AppColors.brand : AppColors.muted, fontSize: 11, fontWeight: active ? FontWeight.w600 : FontWeight.w500),
        ),
      ]),
    ));
  }
}
