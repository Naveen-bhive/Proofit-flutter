import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/models/app_feature.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../../../core/network/api_service.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../../shared/services/socket_service.dart';
import '../../../shared/services/live_location_tracker.dart';
import '../../../shared/services/google_auth_service.dart';
import '../../../shared/services/review_service.dart';
import '../controllers/staff_controller.dart';
import '../utils/attendance_gates.dart';
import '../../../shared/permissions/team_tools_section.dart';

class StaffProfileScreen extends ConsumerStatefulWidget {
  const StaffProfileScreen({super.key});
  @override ConsumerState<StaffProfileScreen> createState() => _StaffProfileScreenState();
}

class _StaffProfileScreenState extends ConsumerState<StaffProfileScreen> {
  bool _driveLinked   = false;
  bool _checkingDrive = true;
  bool _connectingDrive = false;
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    ref.read(staffControllerProvider.notifier).loadProfileStats();
    ref.read(staffControllerProvider.notifier).syncOrgFromServer();
    _checkDriveStatus();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _appVersion = info.version);
  }

  Future<void> _checkDriveStatus() async {
    // Silent-only check — never prompts. Just reflects whether a session
    // from a previous interactive connect can still be resumed.
    final result = await GoogleAuthService.ensureDriveAccess();
    if (!mounted) return;
    setState(() { _driveLinked = result.ok; _checkingDrive = false; });
  }

  Future<void> _connectDrive() async {
    setState(() => _connectingDrive = true);
    final result = await GoogleAuthService.ensureDriveAccess(interactive: true);
    if (!mounted) return;
    setState(() { _connectingDrive = false; _driveLinked = result.ok; });

    if (result.ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Google Drive connected. Report photos will now upload to your Drive.'),
        backgroundColor: AppColors.green,
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.error ?? 'Could not connect Google Drive. Please try again.'),
        backgroundColor: AppColors.red,
        duration: const Duration(seconds: 6),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(staffControllerProvider);
    final unread = state.notifications.where((n) => n['isRead'] != true).length;
    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
          PageHeader(
            title: 'Profile',
            showBack: canPop,
            titleSize: 24,
            padding: const EdgeInsets.fromLTRB(4, 8, 0, 16),
            actions: [
              PopupMenuButton<String>(
                tooltip: 'More',
                offset: const Offset(0, 44),
                onSelected: (v) {
                  if (v == 'notifications') context.push('/staff/notifications');
                  if (v == 'password') context.push('/change-password');
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'notifications',
                    child: Text(unread > 0 ? 'Notifications ($unread)' : 'Notifications',
                        style: const TextStyle(color: AppColors.text)),
                  ),
                  const PopupMenuItem(value: 'password', child: Text('Change Password', style: TextStyle(color: AppColors.text))),
                ],
                child: const IgnorePointer(child: HeaderIconButton(icon: Icons.more_vert_rounded)),
              ),
            ],
          ),

          // Staff card
          SurfaceCard(
            radius: 20,
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              InitialAvatar(
                name: state.userName.isNotEmpty ? state.userName.substring(0, 1) : '?',
                size: 58,
                square: true,
                color: AppColors.brand,
                online: state.isCheckedIn,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(state.userName, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.text, fontSize: 15.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(state.orgName, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.w600)),
                  if (state.streak > 0) ...[
                    const SizedBox(height: 6),
                    SoftBadge(label: '${state.streak}-day streak', color: AppColors.brand, icon: Icons.local_fire_department_rounded, fontSize: 11),
                  ],
                ]),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ]),
          ),
          const SizedBox(height: 14),

          // Stats
          Row(children: [
            _stat('Today', '${state.submittedToday}', AppColors.brand),
            const SizedBox(width: 10),
            _stat('Week', '${state.weekCount}', AppColors.indigo),
            const SizedBox(width: 10),
            _stat('Month', '${state.monthCount}', AppColors.greenDark),
            const SizedBox(width: 10),
            _stat('Total', '${state.totalCount}', const Color(0xFFF59E0B)),
          ]),

          if (state.dailyTarget > 0) ...[
            const SizedBox(height: 14),
            SurfaceCard(
              radius: 16,
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Daily Target', style: TextStyle(color: AppColors.silver, fontSize: 13)),
                  Text('${state.submittedToday}/${state.dailyTarget}',
                      style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: (state.submittedToday / state.dailyTarget).clamp(0.0, 1.0),
                    backgroundColor: AppColors.dark4,
                    valueColor: AlwaysStoppedAnimation(
                        state.submittedToday >= state.dailyTarget ? AppColors.green : AppColors.brand),
                    minHeight: 8,
                  ),
                ),
              ]),
            ),
          ],

          const SectionLabel('Storage'),
          MenuGroup(children: [
            MenuRow(
              icon: _driveLinked ? Icons.cloud_done_outlined : Icons.cloud_outlined,
              color: _driveLinked ? AppColors.greenDark : AppColors.brand,
              label: _checkingDrive
                  ? 'Checking Google Drive...'
                  : _connectingDrive
                      ? 'Connecting...'
                      : _driveLinked
                          ? 'Google Drive Connected'
                          : 'Connect Google Drive',
              onTap: (_checkingDrive || _connectingDrive)
                  ? null
                  : _driveLinked
                      ? _checkDriveStatus // re-verify — catches silent token expiry
                      : _connectDrive,
            ),
          ]),

          if (state.isEnabled(AppFeature.attendance) || state.isEnabled(AppFeature.leaves)) ...[
            const SectionLabel('Attendance'),
            MenuGroup(children: [
              if (state.isEnabled(AppFeature.attendance)) ...[
                MenuRow(
                  icon: state.isCheckedIn ? Icons.logout_rounded : Icons.login_rounded,
                  color: AppColors.greenDark,
                  label: state.isCheckedIn ? 'Check Out' : 'Check In',
                  onTap: () => _onCheckInOutTap(context, ref, state.isCheckedIn),
                ),
                MenuRow(icon: Icons.schedule_rounded, color: AppColors.brand, label: 'Check-in History',
                    onTap: () => context.push('/staff/checkin-history')),
              ],
              if (state.isEnabled(AppFeature.leaves))
                MenuRow(icon: Icons.event_note_outlined, color: const Color(0xFFF59E0B), label: 'Leave Requests',
                    onTap: () => context.push('/staff/leaves')),
            ]),
          ],

          TeamToolsSection(featureEnabled: state.isEnabled),

          const SectionLabel('Account'),
          MenuGroup(children: [
            MenuRow(icon: Icons.lock_outline_rounded, color: AppColors.brand, label: 'Change Password',
                onTap: () => context.push('/change-password')),
            MenuRow(icon: Icons.logout_rounded, color: AppColors.red, label: 'Logout', labelColor: AppColors.red,
                onTap: () => _logout(context, ref)),
          ]),

          const SectionLabel('Support'),
          MenuGroup(children: [
            MenuRow(icon: Icons.star_rounded, color: const Color(0xFFF59E0B), label: 'Rate ProofIt',
                onTap: () => ReviewService.requestManualReview(ref.read(apiServiceProvider))),
            MenuRow(
              icon: Icons.info_outline_rounded,
              color: AppColors.light,
              label: 'App Version',
              chevron: false,
              trailing: _appVersion.isEmpty
                  ? null
                  : Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.dark4,
                        borderRadius: BorderRadius.circular(100),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(_appVersion,
                          style: const TextStyle(color: AppColors.light, fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _stat(String label, String value, Color color) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
            boxShadow: AppColors.cardShadow,
          ),
          child: Column(children: [
            Text(value, style: AppTextStyles.h3.copyWith(color: color, fontSize: 19, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(label.toUpperCase(),
                style: const TextStyle(color: AppColors.silver, fontSize: 10.5, fontWeight: FontWeight.w500, letterSpacing: 0.4)),
          ]),
        ),
      );

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

    final confirm = await showConfirmSheet(
      context,
      icon: Icons.logout_rounded,
      title: 'Are you sure you want to log out?',
      message: 'You will need to sign in again to submit reports and check in.',
      confirmLabel: 'Yes',
    );
    if (!confirm || !context.mounted) return;

    SocketService.disconnect();
    LiveLocationTracker.stop();
    await ref.read(authControllerProvider.notifier).logout();
    ref.invalidate(staffControllerProvider);
    if (!context.mounted) return;
    context.go('/signin');
  }
}