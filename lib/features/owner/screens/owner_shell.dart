import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/services/socket_service.dart';
import '../controllers/owner_controller.dart';
import 'owner_dashboard_screen.dart';
import 'owner_reports_screen.dart';
import 'jobs_screen.dart';
import 'owner_profile_screen.dart';

class OwnerShell extends ConsumerStatefulWidget {
  const OwnerShell({super.key});
  @override ConsumerState<OwnerShell> createState() => _OwnerShellState();
}

class _OwnerShellState extends ConsumerState<OwnerShell> {
  int _tab = 0;
  SocketListenerId? _orgSocketId;

  @override
  void initState() {
    super.initState();
    ref.read(ownerControllerProvider.notifier).syncOrgFromServer();
    ref.read(ownerControllerProvider.notifier).loadDashboard();
    _connectSocket();
  }

  /// Returns true if back was handled (switched to Dashboard). False = already on Dashboard.
  bool _onShellBack() {
    if (_tab == 0) return false;
    setState(() => _tab = 0);
    return true;
  }

  void _connectSocket() {
    SocketService.connect();
    _orgSocketId = SocketService.onOrgUpdated((data) {
      if (!mounted) return;
      final name = data['name'] as String?;
      if (name != null && name.isNotEmpty) {
        ref.read(ownerControllerProvider.notifier).applyOrgName(name);
      } else {
        ref.read(ownerControllerProvider.notifier).syncOrgFromServer();
      }
    });
  }

  @override
  void dispose() {
    if (_orgSocketId != null) SocketService.off(_orgSocketId!);
    super.dispose();
  }

  Widget _body() {
    // Rebuild the active tab each time — cached shells kept a GoogleMap platform
    // view grey overlay in release builds after visiting Live Map.
    return switch (_tab) {
      0 => const OwnerDashboardScreen(key: ValueKey('dashboard')),
      1 => const OwnerReportsScreen(key: ValueKey('reports')),
      3 => const JobsScreen(key: ValueKey('jobs')),
      4 => const OwnerProfileScreen(key: ValueKey('profile')),
      _ => const OwnerDashboardScreen(key: ValueKey('dashboard')),
    };
  }

  @override
  Widget build(BuildContext context) {
    final state  = ref.watch(ownerControllerProvider);
    final unread = state.ownerNotifications.where((n) => n['isRead'] != true).length;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_onShellBack()) return;
        SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: AppColors.dark,
        body: ColoredBox(
          color: AppColors.dark,
          child: _body(),
        ),
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(color: AppColors.dark2, border: Border(top: BorderSide(color: AppColors.border))),
          child: SafeArea(
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.2,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  _item(0, Icons.dashboard_outlined,  Icons.dashboard_rounded,  'Dashboard'),
                  _item(1, Icons.assignment_outlined, Icons.assignment_rounded, 'Reports'),
                  _item(2, Icons.map_outlined,        Icons.map_rounded,        'Map'),
                  _item(3, Icons.work_outline,        Icons.work_rounded,       'Jobs'),
                  _item(4, Icons.person_outline,      Icons.person_rounded,     'Profile',
                    badge: unread > 0 ? unread : null),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(int index, IconData icon, IconData activeIcon, String label, {int? badge}) {
    final active = _tab == index;
    return Expanded(child: GestureDetector(
      onTap: () {
        if (index == 2) {
          context.push('/owner/map');
          return;
        }
        setState(() => _tab = index);
      },
      behavior: HitTestBehavior.opaque,
      child: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
        Stack(clipBehavior: Clip.none, children: [
          Icon(active ? activeIcon : icon, color: active ? AppColors.brand : AppColors.muted, size: 24),
          if (badge != null) Positioned(top: -2, right: -6,
            child: Container(width: 14, height: 14, decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle),
              child: Center(child: Text(badge > 9 ? '9+' : '$badge',
                style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800))))),
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
