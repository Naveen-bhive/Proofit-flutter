import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proofit/features/owner/models/attendance_analytics.dart';
import 'package:proofit/features/owner/widgets/attendance_widgets.dart';

// Layout guards for the attendance summary widgets: they must render without
// overflow or parent-data errors on narrow phones (a failed layout shows up
// as a grey box in release builds).

const _totals = AttendanceTotals(
  workingDays: 4,
  presentDays: 1.5,
  attendancePercent: 37.5,
  scheduledMinutes: 54000,
  workedMinutes: 1234,
  lateMinutes: 64,
  overtimeMinutes: 30,
  deficitMinutes: 540,
  pausedMinutes: 15,
  autoCheckouts: 2,
);

AttendanceDay _day(String date, String status,
        {int scheduled = 540,
        int worked = 0,
        int late = 0,
        int variance = 0,
        String? checkout,
        String? inLabel,
        String? outLabel}) =>
    AttendanceDay(
      date: date,
      status: status,
      scheduledMinutes: scheduled,
      workedMinutes: worked,
      lateMinutes: late,
      varianceMinutes: variance,
      checkoutStatus: checkout,
      firstCheckInLabel: inLabel,
      lastCheckOutLabel: outLabel,
    );

final _days = [
  _day('2026-10-01', 'leave_worked',
      scheduled: 0,
      checkout: 'staff',
      inLabel: '11:25 AM',
      outLabel: '11:25 AM'),
  _day('2026-10-02', 'absent', variance: -540),
  _day('2026-10-04', 'holiday', scheduled: 0),
  _day('2026-10-05', 'half_day',
      late: 64,
      variance: -540,
      checkout: 'auto',
      inLabel: '11:04 AM',
      outLabel: '11:05 AM'),
  _day('2026-10-06', 'present',
      worked: 570, variance: 30, inLabel: '9:58 AM', outLabel: '7:30 PM'),
];

Widget _host(double width, Widget child) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Center(child: SizedBox(width: width, child: child)),
        ),
      ),
    );

void main() {
  for (final width in [288.0, 360.0]) {
    testWidgets('totals grid + percent header on dark card at $width px',
        (tester) async {
      await tester.pumpWidget(_host(
        width,
        Container(
          color: const Color(0xFF173B85),
          padding: const EdgeInsets.all(20),
          child: const Column(children: [
            AttendancePercentHeader(
                totals: _totals, definition: 'Present days', onDark: true),
            AttendanceTotalsGrid(_totals, onDark: true),
          ]),
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(find.text('AUTO CHECKOUTS'), findsOneWidget);
      // All tiles in a row share the same width (equal-width grid).
      final worked = tester.getSize(find.ancestor(
          of: find.text('WORKED'), matching: find.byType(MetricTile)));
      final scheduled = tester.getSize(find.ancestor(
          of: find.text('SCHEDULED'), matching: find.byType(MetricTile)));
      expect(worked.width, scheduled.width);
    });

    testWidgets('day rows render without errors at $width px',
        (tester) async {
      await tester.pumpWidget(_host(
        width,
        Column(children: [
          for (final d in _days) AttendanceDayRow(day: d, onTap: () {}),
        ]),
      ));
      expect(tester.takeException(), isNull);
      // Holidays don't show meaningless zero totals.
      expect(find.text('Holiday · no scheduled hours'), findsOneWidget);
      expect(find.text('In 11:04 AM  ·  Out 11:05 AM'), findsOneWidget);
    });
  }
}
