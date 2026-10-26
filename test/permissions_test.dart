import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proofit/shared/permissions/app_permissions.dart';
import 'package:proofit/shared/permissions/permission_editor.dart';
import 'package:proofit/shared/permissions/permission_session.dart';
import 'package:proofit/shared/permissions/team_tools_section.dart';

String? redirect(String path, String? role, Set<String> perms) => AppPermissions.redirectFor(
      path: path,
      role: role,
      can: (p) => role == 'owner' || perms.contains(p),
    );

void main() {
  group('AppPermissions registry', () {
    test('ids are unique and feature.action shaped', () {
      final ids = AppPermissions.all.map((a) => a.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final id in ids) {
        expect(RegExp(r'^[a-zA-Z]+\.[a-zA-Z]+$').hasMatch(id), isTrue, reason: id);
      }
    });

    test('normalize drops unknown ids and adds prerequisites', () {
      expect(AppPermissions.normalize(['jobs.edit', 'billing.manage']), ['jobs.view', 'jobs.edit']);
      expect(AppPermissions.normalize(['staff.permissions']), ['staff.view', 'staff.permissions']);
    });

    test('turning a permission off clears what depends on it', () {
      final next = AppPermissions.withoutPermission({'jobs.view', 'jobs.create', 'jobs.edit', 'leaves.view'}, 'jobs.view');
      expect(next, {'leaves.view'});
    });
  });

  group('route guard', () {
    test('owners are never redirected', () {
      expect(redirect('/owner/subscription', 'owner', {}), isNull);
      expect(redirect('/owner/staff', 'owner', {}), isNull);
    });

    test('staff are kept out of owner-only areas whatever they hold', () {
      final everything = AppPermissions.ids;
      for (final path in ['/owner', '/owner/subscription', '/owner/settings', '/owner/account-deletion', '/owner/unknown']) {
        expect(redirect(path, 'staff', everything), '/no-access', reason: path);
      }
    });

    test('staff reach a feature only with its permission', () {
      expect(redirect('/owner/staff', 'staff', {}), '/no-access');
      expect(redirect('/owner/staff', 'staff', {'staff.view'}), isNull);
      expect(redirect('/owner/staff/abc123', 'staff', {'staff.view'}), isNull);
      expect(redirect('/owner/staff-attendance', 'staff', {'staff.view'}), '/no-access');
      expect(redirect('/owner/staff-attendance', 'staff', {'attendance.view'}), isNull);
      expect(redirect('/owner/holidays', 'staff', {'holidays.delete'}), isNull);
      expect(redirect('/owner/export-pdf/r1', 'staff', {'reports.view'}), '/no-access');
    });

    test('Media and Storage opens for staff with storage.view only', () {
      expect(redirect('/owner/storage', 'staff', {}), '/no-access');
      expect(redirect('/owner/storage', 'staff', {'storage.view'}), isNull);
      expect(AppPermissions.normalize(['storage.delete']), ['storage.view', 'storage.delete']);
    });

    test('staff screens are unaffected', () {
      expect(redirect('/staff/jobs', 'staff', {}), isNull);
    });
  });

  group('PermissionSession', () {
    tearDown(() => PermissionSession.instance.clear());

    test('owner can everything; staff only granted ids', () {
      final s = PermissionSession.instance;
      s.apply(role: 'owner', permissions: const []);
      expect(s.can('staff.delete'), isTrue);
      s.apply(role: 'staff', permissions: const ['customers.edit']);
      expect(s.can('customers.view'), isTrue, reason: 'prerequisite added');
      expect(s.can('customers.delete'), isFalse);
      expect(s.canAny(AppPermissions.holidaysAny), isFalse);
    });

    test('notifies listeners only when access actually changes', () {
      final s = PermissionSession.instance;
      var calls = 0;
      void listener() => calls++;
      s.addListener(listener);
      s.apply(role: 'staff', permissions: const ['jobs.view']);
      s.apply(role: 'staff', permissions: const ['jobs.view']);
      s.apply(role: 'staff', permissions: const ['jobs.view', 'jobs.edit']);
      s.removeListener(listener);
      expect(calls, 2);
    });
  });

  group('permission-aware UI', () {
    tearDown(() => PermissionSession.instance.clear());

    Widget host(Widget child) => ProviderScope(
          child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))),
        );

    testWidgets('Team tools lists only granted, plan-enabled features', (tester) async {
      PermissionSession.instance.apply(role: 'staff', permissions: const ['jobs.view', 'staff.view', 'customers.view']);
      await tester.pumpWidget(host(TeamToolsSection(featureEnabled: (f) => f != 'customers')));
      expect(find.text('Jobs'), findsOneWidget);
      expect(find.text('Staff Management'), findsOneWidget);
      expect(find.text('Customers'), findsNothing, reason: 'plan feature off');
      expect(find.text('Live Map'), findsNothing, reason: 'not granted');
    });

    testWidgets('Team tools is hidden for staff without delegated access', (tester) async {
      PermissionSession.instance.apply(role: 'staff', permissions: const []);
      await tester.pumpWidget(host(TeamToolsSection(featureEnabled: (_) => true)));
      expect(find.text('Team tools'.toUpperCase()), findsNothing);
    });

    testWidgets('editor locks permissions the user cannot delegate', (tester) async {
      Set<String>? changed;
      await tester.pumpWidget(host(PermissionEditor(
        selected: const {},
        grantable: const {'jobs.view', 'jobs.create'},
        featureEnabled: (_) => true,
        onChanged: (v) => changed = v,
      )));
      await tester.tap(find.text('Assign jobs'));
      expect(changed, {'jobs.view', 'jobs.create'});
      changed = null;
      await tester.ensureVisible(find.text('Remove staff'));
      await tester.tap(find.text('Remove staff'));
      expect(changed, isNull, reason: 'not grantable');
    });
  });
}
