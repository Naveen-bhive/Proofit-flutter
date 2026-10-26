import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../widgets/ui_kit.dart';
import 'app_permissions.dart';
import 'permission_session.dart';

class _TeamTool {
  final String label;
  final IconData icon;
  final Color color;
  final String route;
  final List<String> anyOf;
  final String? planFeature;
  const _TeamTool(this.label, this.icon, this.color, this.route, this.anyOf, {this.planFeature});
}

const _tools = [
  _TeamTool('Team Dashboard', Icons.grid_view_rounded, AppColors.brand, '/owner/dashboard', [AppPermissions.dashboardView]),
  _TeamTool('Staff Management', Icons.manage_accounts_outlined, AppColors.yellow, '/owner/staff', [AppPermissions.staffView]),
  _TeamTool('All Reports', Icons.summarize_outlined, Color(0xFFEA580C), '/owner/history', [AppPermissions.reportsView]),
  _TeamTool('Jobs', Icons.business_center_outlined, AppColors.brand, '/owner/jobs', [AppPermissions.jobsView], planFeature: 'jobs'),
  _TeamTool('Customers', Icons.groups_outlined, AppColors.brand, '/owner/customers', [AppPermissions.customersView], planFeature: 'customers'),
  _TeamTool('Leave Management', Icons.event_busy_outlined, AppColors.red, '/owner/leaves', [AppPermissions.leavesView], planFeature: 'leaves'),
  _TeamTool('Holidays', Icons.celebration_outlined, AppColors.purple, '/owner/holidays', AppPermissions.holidaysAny, planFeature: 'holidays'),
  _TeamTool('Staff Attendance', Icons.event_available_outlined, AppColors.greenDark, '/owner/staff-attendance', [AppPermissions.attendanceView], planFeature: 'attendance'),
  _TeamTool('Working Hours', Icons.schedule_rounded, AppColors.brand, '/owner/working-hours', [AppPermissions.workingHoursView], planFeature: 'workingHours'),
  _TeamTool('Live Map', Icons.map_outlined, AppColors.purple, '/owner/map', [AppPermissions.liveMapView], planFeature: 'liveMap'),
  _TeamTool('Broadcast', Icons.campaign_outlined, AppColors.brand, '/owner/notifications', [AppPermissions.notificationsSend]),
  _TeamTool('Media and Storage', Icons.sd_storage_outlined, AppColors.purple, '/owner/storage', [AppPermissions.storageView]),
];

/// The owner tools a staff member has been granted, shown on their profile.
/// Renders nothing for staff without delegated access.
class TeamToolsSection extends ConsumerWidget {
  /// Whether a plan feature is on for the org (see StaffState.isEnabled).
  final bool Function(String feature) featureEnabled;
  const TeamToolsSection({super.key, required this.featureEnabled});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(permissionSessionProvider);
    final tools = [
      for (final t in _tools)
        if (session.canAny(t.anyOf) && (t.planFeature == null || featureEnabled(t.planFeature!))) t,
    ];
    if (tools.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionLabel('Team tools'),
      MenuGroup(children: [
        for (final t in tools)
          MenuRow(icon: t.icon, color: t.color, label: t.label, onTap: () => context.push(t.route)),
      ]),
    ]);
  }
}
