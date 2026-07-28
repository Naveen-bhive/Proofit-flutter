import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../../shared/services/socket_service.dart';
import '../../../shared/services/live_location_tracker.dart';
import '../controllers/staff_controller.dart';
import '../utils/attendance_gates.dart';

class StaffProfileScreen extends ConsumerStatefulWidget {
  const StaffProfileScreen({super.key});
  @override ConsumerState<StaffProfileScreen> createState() => _StaffProfileScreenState();
}

class _StaffProfileScreenState extends ConsumerState<StaffProfileScreen> {
  @override
  void initState() {
    super.initState();
    ref.read(staffControllerProvider.notifier).loadProfileStats();
    ref.read(staffControllerProvider.notifier).syncOrgFromServer();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(staffControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(children: [
        // Staff info
        Container(margin: const EdgeInsets.all(16), padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: AppColors.dark2, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
          child: Column(children: [
            CircleAvatar(radius: 36, backgroundColor: AppColors.brand.withValues(alpha: 0.15),
              child: Text(state.userName.isNotEmpty ? state.userName[0].toUpperCase() : '?',
                style: const TextStyle(color: AppColors.brand, fontSize: 28, fontWeight: FontWeight.w800))),
            const SizedBox(height: 12),
            Text(state.userName, style: const TextStyle(color: AppColors.white, fontSize: 20, fontWeight: FontWeight.w700)),
            Text(state.orgName,  style: const TextStyle(color: AppColors.silver, fontSize: 14)),
            if (state.streak > 0) ...[
              const SizedBox(height: 10),
              Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(color: AppColors.brand.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(100)),
                child: Text('Streak: ${state.streak}-day streak', style: const TextStyle(color: AppColors.brand, fontWeight: FontWeight.w700))),
            ],
          ])),

        // Stats
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            _stat('Today',  '${state.submittedToday}',  AppColors.brand),
            const SizedBox(width: 8),
            _stat('Week',   '${state.weekCount}',        AppColors.blue),
            const SizedBox(width: 8),
            _stat('Month',  '${state.monthCount}',       AppColors.green),
            const SizedBox(width: 8),
            _stat('Total',  '${state.totalCount}',       AppColors.yellow),
          ])),
        const SizedBox(height: 8),

        // Target
        if (state.dailyTarget > 0)
          Container(margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.dark2, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Daily Target', style: TextStyle(color: AppColors.silver, fontSize: 13)),
                Text('${state.submittedToday}/${state.dailyTarget}', style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 10),
              ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(
                value: (state.submittedToday / state.dailyTarget).clamp(0.0, 1.0),
                backgroundColor: AppColors.dark3,
                valueColor: AlwaysStoppedAnimation(state.submittedToday >= state.dailyTarget ? AppColors.green : AppColors.brand),
                minHeight: 8)),
            ])),

        _section('ATTENDANCE', [
          _tile(Icons.login_rounded,   state.isCheckedIn ? AppColors.green : AppColors.muted,
            state.isCheckedIn ? 'Check Out' : 'Check In',
            () => _onCheckInOutTap(context, ref, state.isCheckedIn)),
          _tile(Icons.history_rounded, AppColors.blue, 'Check-in History', () => context.push('/staff/checkin-history')),
        ]),

        _section('ACCOUNT', [
          _tile(Icons.lock_outline_rounded, AppColors.brand, 'Change Password',
              () => context.push('/change-password')),
          _tile(Icons.logout_rounded, AppColors.red, 'Logout', () => _logout(context, ref), textColor: AppColors.red),
        ]),

        const SizedBox(height: 40),
      ]),
    );
  }

  Widget _stat(String label, String value, Color color) => Expanded(child: Container(
    padding: const EdgeInsets.symmetric(vertical: 12),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
    child: Column(children: [
      Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w800)),
      Text(label,  style: const TextStyle(color: AppColors.silver, fontSize: 11)),
    ])));

  Widget _section(String title, List<Widget> tiles) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(title, style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.2))),
    Container(margin: const EdgeInsets.symmetric(horizontal: 16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
      child: Material(
        color: AppColors.dark2,
        child: Column(children: tiles),
      )),
  ]);

  Widget _tile(IconData icon, Color color, String label, VoidCallback onTap, {Color? textColor, int? badge}) =>
    ListTile(
      leading: Container(width: 36, height: 36, decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
        child: Stack(children: [
          Center(child: Icon(icon, color: color, size: 20)),
          if (badge != null) Positioned(top: 0, right: 0,
            child: Container(width: 14, height: 14, decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle),
              child: Center(child: Text('$badge', style: const TextStyle(color: Colors.white, fontSize: 8))))),
        ])),
      title: Text(label, style: TextStyle(color: textColor ?? AppColors.white, fontSize: 14)),
      trailing: Icon(Icons.chevron_right_rounded, color: AppColors.muted.withValues(alpha: 0.5), size: 20),
      onTap: onTap, dense: true);

  Future<void> _onCheckInOutTap(BuildContext context, WidgetRef ref, bool isCheckedIn) async {
    if (!isCheckedIn) {
      context.push('/staff/checkin');
      return;
    }
    final allowed = await AttendanceGates.allowCheckOut(context, ref);
    if (!context.mounted || !allowed) return;
    context.push('/staff/checkout');
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final allowed = await AttendanceGates.allowLogout(context, ref);
    if (!context.mounted || !allowed) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.dark2,
        title: const Text('Log Out?', style: TextStyle(color: AppColors.white)),
        content: const Text('You will need to sign in again.', style: TextStyle(color: AppColors.silver)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.silver)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Log Out', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    SocketService.disconnect();
    LiveLocationTracker.stop();
    await ref.read(authControllerProvider.notifier).logout();
    ref.invalidate(staffControllerProvider);
    if (!context.mounted) return;
    context.go('/signin');
  }
}