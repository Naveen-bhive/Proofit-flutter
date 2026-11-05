import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proofit/features/owner/models/attendance_analytics.dart';
import 'package:proofit/features/owner/screens/staff_month_attendance_screen.dart';
import 'package:proofit/features/owner/widgets/attendance_variance_chart.dart';
import 'package:proofit/features/owner/widgets/attendance_widgets.dart';
import 'package:proofit/shared/permissions/app_permissions.dart';

Map<String, dynamic> _dayJson({
  String date = '2026-10-05',
  String status = 'present',
  int late = 30,
  int ot = 30,
  int deficit = 0,
  String checkout = 'auto',
}) =>
    {
      'date': date,
      'status': status,
      'scheduledMinutes': 540,
      'workedMinutes': 570,
      'pausedMinutes': 15,
      'lateMinutes': late,
      'overtimeMinutes': ot,
      'deficitMinutes': deficit,
      'varianceMinutes': ot - deficit,
      'checkoutStatus': checkout,
      'autoCheckout': checkout == 'auto',
      'firstCheckInLabel': '10:30 AM',
      'lastCheckOutLabel': '8:00 PM',
      'scheduledStartLabel': '10:00 AM',
      'scheduledEndLabel': '7:00 PM',
      'sessions': [
        {
          '_id': 's1',
          'date': date,
          'attendanceWorkLocation': 'wfo',
          'checkInTimeLabel': '10:30 AM',
          'checkOutTimeLabel': '8:00 PM',
          'checkoutStatus': checkout,
          'calc': {'workedMinutes': 570, 'pausedMinutes': 15},
          'pauses': [
            {'startLabel': '1:00 PM', 'endLabel': '1:15 PM', 'minutes': 15}
          ],
          'checkoutEdits': [
            {
              'editedByName': 'Owner',
              'previousCheckOutLabel': '7:00 PM',
              'newCheckOutLabel': '8:00 PM',
              'previousWorkedMinutes': 510,
              'newWorkedMinutes': 570,
              'previousCheckoutSource': 'auto',
              'reason': 'Forgot',
            }
          ],
        }
      ],
    };

void main() {
  group('formatting (server minutes → display)', () {
    test('formatMinutes keeps minute precision', () {
      expect(formatMinutes(0), '0m');
      expect(formatMinutes(30), '30m');
      expect(formatMinutes(90), '1h 30m');
      expect(formatMinutes(120), '2h');
      expect(formatMinutes(-75), '1h 15m');
    });

    test('formatVariance is signed', () {
      expect(formatVariance(30), '+30m');
      expect(formatVariance(-90), '−1h 30m');
      expect(formatVariance(0), '0m');
    });

    test('formatPercent handles empty ranges', () {
      expect(formatPercent(null), '—');
      expect(formatPercent(100), '100%');
      expect(formatPercent(92.5), '92.5%');
    });

    test('office hours label in 12-hour time', () {
      expect(const OfficeHours().label, '10:00 AM – 7:00 PM');
      expect(OfficeHours.fromJson({'start': '00:30', 'end': '12:15'}).label,
          '12:30 AM – 12:15 PM');
    });
  });

  group('parsing', () {
    test('analytics payload', () {
      final a = AttendanceAnalytics.fromJson({
        'range': {'from': '2026-10-05', 'to': '2026-10-11', 'period': 'weekly'},
        'officeHours': {'start': '09:30', 'end': '18:30'},
        'definition': 'Attendance % = …',
        'totals': {'attendancePercent': 87.5, 'workingDays': 4, 'presentDays': 3.5, 'overtimeMinutes': 45},
        'series': [
          {'date': '2026-10-05', 'overtimeMinutes': 30, 'deficitMinutes': 0},
          {'date': '2026-10-06', 'overtimeMinutes': 0, 'deficitMinutes': 20},
        ],
        'staff': [
          {'staffId': 'a', 'name': 'Ravi Kumar', 'totals': {'lateMinutes': 30}},
        ],
      });
      expect(a.period, 'weekly');
      expect(a.officeHours.start, '09:30');
      expect(a.totals.attendancePercent, 87.5);
      expect(a.totals.presentDays, 3.5);
      expect(a.series.map((p) => p.deficitMinutes), [0, 20]);
      expect(a.staff.single.totals.lateMinutes, 30);
    });

    test('day with sessions, pauses and an owner edit', () {
      final d = AttendanceDay.fromJson(_dayJson(checkout: 'edited'));
      expect(d.varianceMinutes, 30);
      final s = d.sessions.single;
      expect(s.checkoutStatus, 'edited');
      expect(s.pauses.single.minutes, 15);
      expect(s.edits.single.previousCheckOutLabel, '7:00 PM');
      expect(s.edits.single.newWorkedMinutes, 570);
      expect(s.isOpen, isFalse);
    });

    test('missing fields fall back safely', () {
      final d = AttendanceDay.fromJson({'date': '2026-10-05'});
      expect(d.status, 'pending');
      expect(d.sessions, isEmpty);
      expect(AttendanceTotals.fromJson(null).attendancePercent, isNull);
    });
  });

  test('month page route is open to staff with attendance.view only', () {
    String? redirect(Set<String> perms) => AppPermissions.redirectFor(
        path: '/owner/staff-attendance/abc/month',
        role: 'staff',
        can: perms.contains);
    expect(redirect({'attendance.view'}), isNull);
    expect(redirect({}), '/no-access');
  });

  Widget harness(Widget child, {double width = 320, double textScale = 2}) =>
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
              size: Size(width, 800),
              textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: SizedBox(
                width: width, child: SingleChildScrollView(child: child)),
          ),
        ),
      );

  testWidgets('day row shows worked, scheduled, late, overtime and auto badge '
      'without overflow on a small phone at 200% text', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness(
        AttendanceDayRow(day: AttendanceDay.fromJson(_dayJson()))));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('9h 30m', findRichText: true), findsOneWidget);
    expect(find.textContaining('9h', findRichText: true), findsWidgets);
    expect(find.textContaining('30m', findRichText: true), findsWidgets);
    expect(find.textContaining('+30m', findRichText: true), findsOneWidget);
    expect(find.text('Auto checkout'), findsOneWidget);
  });

  testWidgets('deficit day shows a negative variance', (tester) async {
    await tester.pumpWidget(harness(AttendanceDayRow(
        day: AttendanceDay.fromJson(
            _dayJson(ot: 0, deficit: 45, checkout: 'staff'))),
        textScale: 1));
    expect(find.textContaining('−45m', findRichText: true), findsOneWidget);
    expect(find.text('Manual checkout'), findsOneWidget);
  });

  testWidgets('variance chart renders positive and negative bars and scrolls '
      'when a month does not fit', (tester) async {
    final points = [
      for (var i = 1; i <= 31; i++)
        VariancePoint('$i', i.isEven ? 30 : 0, i % 3 == 0 ? 45 : 0),
    ];
    await tester.pumpWidget(
        harness(AttendanceVarianceChart(points: points), textScale: 1.6));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsNWidgets(2));
    expect(find.textContaining('Overtime'), findsOneWidget);
    expect(find.textContaining('Deficit'), findsOneWidget);
  });

  testWidgets('variance chart empty state', (tester) async {
    await tester.pumpWidget(harness(
        const AttendanceVarianceChart(points: [VariancePoint('1', 0, 0)])));
    expect(find.text('No overtime or deficit in this range'), findsOneWidget);
  });

  testWidgets('totals grid wraps at large text', (tester) async {
    await tester.pumpWidget(harness(const AttendanceTotalsGrid(
        AttendanceTotals(overtimeMinutes: 90, lateMinutes: 30, autoCheckouts: 2))));
    expect(tester.takeException(), isNull);
    expect(find.text('1h 30m'), findsOneWidget);
  });
}
