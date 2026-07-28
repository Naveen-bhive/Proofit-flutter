import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/services/socket_service.dart';
import '../controllers/staff_controller.dart';
import 'staff_home_screen.dart';
import 'staff_jobs_screen.dart';
import 'staff_history_screen.dart';
import 'staff_profile_screen.dart';

class StaffShell extends ConsumerStatefulWidget {
  const StaffShell({super.key});
  @override ConsumerState<StaffShell> createState() => _StaffShellState();
}

class _StaffShellState extends ConsumerState<StaffShell> {
  int _tab = 0;
  SocketListenerId? _orgSocketId;
  final _jobsKey = GlobalKey<StaffJobsScreenState>();
  final _historyKey = GlobalKey<StaffHistoryScreenState>();

  @override
  void initState() {
    super.initState();
    unawaited(ref.read(staffControllerProvider.notifier).bootstrapHome());
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

  @override
  void dispose() {
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

  void _onTabTap(int index) {
    if (index == 2) {
      context.push('/staff/jobs');
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
            color: AppColors.dark2,
            border: Border(top: BorderSide(color: AppColors.border, width: 1)),
          ),
          child: SafeArea(
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.2,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  _navItem(0, Icons.home_outlined,          Icons.home_rounded,         'Home'),
                  _navItem(1, Icons.work_outline,           Icons.work_rounded,         'Jobs'),
                  Expanded(child: GestureDetector(
                    onTap: () => context.push('/staff/jobs'),
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                      height: 44,
                      decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: AppColors.brand.withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 4))]),
                      child: const Center(child: Icon(Icons.add_a_photo_rounded, color: Colors.white, size: 26))),
                  )),
                  _navItem(3, Icons.history_outlined,       Icons.history_rounded,      'History'),
                  _navItem(4, Icons.person_outline_rounded, Icons.person_rounded,       'Profile',
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
          Icon(active ? activeIcon : icon, color: active ? AppColors.brand : AppColors.muted, size: 24),
          if (badge != null) Positioned(top: -2, right: -6,
            child: Container(width: 14, height: 14, decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle),
              child: Center(child: Text(badge > 9 ? '9+' : '$badge', style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800))))),
        ]),
        const SizedBox(height: 3),
        Text(
          label,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: active ? AppColors.brand : AppColors.muted, fontSize: 10, fontWeight: active ? FontWeight.w700 : FontWeight.w400),
        ),
      ]),
    ));
  }
}
