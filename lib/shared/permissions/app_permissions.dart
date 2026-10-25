/// Owner features that can be delegated to staff. Mirrors
/// backend/src/config/permissions.js — ids are stored on the server, so never
/// rename one; add a new id instead. A new feature registers by adding a
/// [PermissionGroup] to [AppPermissions.groups] and, if it has screens, an
/// entry in [AppPermissions.routeRules].
library;

class PermissionAction {
  final String id;
  final String label;
  final List<String> requires;
  const PermissionAction(this.id, this.label, {this.requires = const []});
}

class PermissionGroup {
  final String feature;
  final String label;
  final String description;

  /// Plan feature (see [AppFeature]) the whole group depends on, if any.
  final String? planFeature;
  final List<PermissionAction> actions;
  const PermissionGroup({
    required this.feature,
    required this.label,
    required this.description,
    required this.actions,
    this.planFeature,
  });
}

abstract final class AppPermissions {
  static const dashboardView = 'dashboard.view';
  static const staffView = 'staff.view';
  static const staffCreate = 'staff.create';
  static const staffEdit = 'staff.edit';
  static const staffDelete = 'staff.delete';
  static const staffPermissions = 'staff.permissions';
  static const reportsView = 'reports.view';
  static const reportsExport = 'reports.export';
  static const reportsShare = 'reports.share';
  static const jobsView = 'jobs.view';
  static const jobsCreate = 'jobs.create';
  static const jobsEdit = 'jobs.edit';
  static const jobsDelete = 'jobs.delete';
  static const customersView = 'customers.view';
  static const customersCreate = 'customers.create';
  static const customersEdit = 'customers.edit';
  static const customersDelete = 'customers.delete';
  static const leavesView = 'leaves.view';
  static const leavesCreate = 'leaves.create';
  static const leavesApprove = 'leaves.approve';
  static const leavesDelete = 'leaves.delete';
  static const leavesConfigure = 'leaves.configure';
  static const holidaysCreate = 'holidays.create';
  static const holidaysEdit = 'holidays.edit';
  static const holidaysDelete = 'holidays.delete';
  static const attendanceView = 'attendance.view';
  static const workingHoursView = 'workingHours.view';
  static const liveMapView = 'liveMap.view';
  static const notificationsSend = 'notifications.send';

  static const holidaysAny = [holidaysCreate, holidaysEdit, holidaysDelete];

  static const groups = <PermissionGroup>[
    PermissionGroup(
      feature: 'dashboard', label: 'Dashboard', description: 'Team overview and recent activity',
      actions: [PermissionAction(dashboardView, 'View team dashboard')],
    ),
    PermissionGroup(
      feature: 'staff', label: 'Staff management', description: 'Team members, invites and targets',
      actions: [
        PermissionAction(staffView, 'View staff'),
        PermissionAction(staffCreate, 'Invite staff'),
        PermissionAction(staffEdit, 'Edit daily targets'),
        PermissionAction(staffDelete, 'Remove staff'),
        PermissionAction(staffPermissions, 'Manage permissions', requires: [staffView]),
      ],
    ),
    PermissionGroup(
      feature: 'reports', label: 'Reports', description: "Everyone's submitted work reports",
      actions: [
        PermissionAction(reportsView, 'View all reports'),
        PermissionAction(reportsExport, 'Export reports', requires: [reportsView]),
        PermissionAction(reportsShare, 'Share report PDFs', requires: [reportsView]),
      ],
    ),
    PermissionGroup(
      feature: 'jobs', label: 'Jobs', description: 'Assigning and tracking jobs', planFeature: 'jobs',
      actions: [
        PermissionAction(jobsView, 'View all jobs'),
        PermissionAction(jobsCreate, 'Assign jobs', requires: [jobsView]),
        PermissionAction(jobsEdit, 'Edit jobs', requires: [jobsView]),
        PermissionAction(jobsDelete, 'Cancel jobs', requires: [jobsView]),
      ],
    ),
    PermissionGroup(
      feature: 'customers', label: 'Customers', description: 'Customer directory', planFeature: 'customers',
      actions: [
        PermissionAction(customersView, 'View customers'),
        PermissionAction(customersCreate, 'Add customers', requires: [customersView]),
        PermissionAction(customersEdit, 'Edit customers', requires: [customersView]),
        PermissionAction(customersDelete, 'Remove customers', requires: [customersView]),
      ],
    ),
    PermissionGroup(
      feature: 'leaves', label: 'Leave management', description: "The team's leave requests", planFeature: 'leaves',
      actions: [
        PermissionAction(leavesView, "View everyone's leave"),
        PermissionAction(leavesCreate, 'Assign leave', requires: [leavesView]),
        PermissionAction(leavesApprove, 'Approve / reject leave', requires: [leavesView]),
        PermissionAction(leavesDelete, 'Delete leave', requires: [leavesView]),
        PermissionAction(leavesConfigure, 'Manage leave types', requires: [leavesView]),
      ],
    ),
    PermissionGroup(
      feature: 'holidays', label: 'Holidays & weekly offs', description: 'Company holiday calendar', planFeature: 'holidays',
      actions: [
        PermissionAction(holidaysCreate, 'Add holidays'),
        PermissionAction(holidaysEdit, 'Edit holidays & weekly offs'),
        PermissionAction(holidaysDelete, 'Delete holidays'),
      ],
    ),
    PermissionGroup(
      feature: 'attendance', label: 'Staff attendance', description: 'Check-in records for the team', planFeature: 'attendance',
      actions: [PermissionAction(attendanceView, 'View staff attendance')],
    ),
    PermissionGroup(
      feature: 'workingHours', label: 'Working hours', description: 'Hours worked per member', planFeature: 'workingHours',
      actions: [PermissionAction(workingHoursView, 'View working hours')],
    ),
    PermissionGroup(
      feature: 'liveMap', label: 'Live map', description: 'Real-time staff locations', planFeature: 'liveMap',
      actions: [PermissionAction(liveMapView, 'View live staff map')],
    ),
    PermissionGroup(
      feature: 'notifications', label: 'Notifications', description: 'Messages to the whole team',
      actions: [PermissionAction(notificationsSend, 'Broadcast & send reminders')],
    ),
  ];

  static final List<PermissionAction> all = [for (final g in groups) ...g.actions];
  static final Set<String> ids = {for (final a in all) a.id};
  static final Map<String, List<String>> _requires = {for (final a in all) a.id: a.requires};

  /// Drops unknown ids and adds each permission's prerequisites, in registry order.
  static List<String> normalize(Iterable<String> requested) {
    final out = <String>{};
    void add(String id) {
      if (!ids.contains(id) || !out.add(id)) return;
      _requires[id]!.forEach(add);
    }
    requested.forEach(add);
    return [for (final a in all) if (out.contains(a.id)) a.id];
  }

  /// Turns a permission off, along with anything that depends on it.
  static Set<String> withoutPermission(Set<String> current, String id) {
    final out = {...current}..remove(id);
    var changed = true;
    while (changed) {
      changed = false;
      for (final p in [...out]) {
        if (_requires[p]!.any((r) => !out.contains(r))) changed = out.remove(p);
      }
    }
    return out;
  }

  /// Owner-only screens: never reachable by staff whatever they're granted.
  static const ownerOnlyRoutes = {
    '/owner',
    '/owner/settings',
    '/owner/profile',
    '/owner/subscription',
    '/owner/enterprise-request',
    '/owner/payment-history',
    '/owner/storage',
    '/owner/account-deletion',
  };

  /// Owner routes staff may open with any one of the listed permissions.
  /// Matched by path prefix; anything under /owner not listed is owner-only.
  static const routeRules = <String, List<String>>{
    '/owner/dashboard': [dashboardView],
    '/owner/staff-attendance': [attendanceView],
    '/owner/staff': [staffView],
    '/owner/history': [reportsView],
    '/owner/report': [reportsView],
    '/owner/photo-viewer': [reportsView],
    '/owner/flagged': [reportsView],
    '/owner/search': [reportsView],
    '/owner/export-pdf': [reportsShare],
    '/owner/map': [liveMapView],
    '/owner/jobs': [jobsView],
    '/owner/customers': [customersView],
    '/owner/leaves': [leavesView],
    '/owner/holidays': holidaysAny,
    '/owner/working-hours': [workingHoursView],
    '/owner/notifications': [notificationsSend],
  };

  /// The permissions that unlock [path] for staff, or null if staff can never
  /// open it. Returns an empty list for paths outside the owner area.
  static List<String>? requiredFor(String path) {
    if (!path.startsWith('/owner')) return const [];
    if (ownerOnlyRoutes.contains(path)) return null;
    String? best;
    for (final prefix in routeRules.keys) {
      final matches = path == prefix || path.startsWith('$prefix/');
      if (matches && (best == null || prefix.length > best.length)) best = prefix;
    }
    return best == null ? null : routeRules[best];
  }

  /// Where to send a user opening [path], or null to let them through.
  static String? redirectFor({
    required String path,
    required String? role,
    required bool Function(String permission) can,
  }) {
    if (role != 'staff') return null;
    final required = requiredFor(path);
    if (required == null) return '/no-access';
    if (required.isEmpty || required.any(can)) return null;
    return '/no-access';
  }
}
