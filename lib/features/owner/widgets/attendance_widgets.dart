import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../models/attendance_analytics.dart';

/// Label and colour for an AttendanceDay.status from the server.
({String label, Color color}) dayStatusStyle(String status) => switch (status) {
      'present' => (label: 'Present', color: AppColors.green),
      'half_day' => (label: 'Half Day', color: AppColors.orange),
      'absent' => (label: 'Absent', color: AppColors.red),
      'leave' => (label: 'Leave', color: AppColors.purple),
      'holiday' => (label: 'Holiday', color: AppColors.yellow),
      'holiday_worked' => (label: 'Worked holiday', color: AppColors.yellow),
      'leave_worked' => (label: 'Worked on leave', color: AppColors.purple),
      'not_joined' => (label: 'Not joined', color: AppColors.muted),
      _ => (label: 'Pending', color: AppColors.muted),
    };

/// Rounded label chip, e.g. a day status or checkout source.
class AttendanceChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  const AttendanceChip(this.label, this.color, {super.key, this.icon});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: color, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        ]),
      );
}

/// How a day or session was closed: open, staff (manual), auto, edited.
class CheckoutBadge extends StatelessWidget {
  final String? status;
  const CheckoutBadge(this.status, {super.key});

  @override
  Widget build(BuildContext context) => switch (status) {
        'auto' => const AttendanceChip('Auto checkout', AppColors.orange,
            icon: Icons.schedule_rounded),
        'edited' => const AttendanceChip('Edited by owner', AppColors.blue,
            icon: Icons.edit_rounded),
        'open' => const AttendanceChip('Checked in', AppColors.green,
            icon: Icons.radio_button_checked_rounded),
        'staff' => const AttendanceChip('Manual checkout', AppColors.silver,
            icon: Icons.logout_rounded),
        _ => const SizedBox.shrink(),
      };
}

/// Geofence state of a WFO session as the owner sees it.
class GeofenceBadge extends StatelessWidget {
  final String? status;
  const GeofenceBadge(this.status, {super.key});

  @override
  Widget build(BuildContext context) => switch (status) {
        'outside' => const AttendanceChip(
            'Outside office · paused', AppColors.red,
            icon: Icons.pause_circle_outline_rounded),
        'unknown' => const AttendanceChip('Location unknown', AppColors.yellow,
            icon: Icons.help_outline_rounded),
        'inside' => const AttendanceChip('In office', AppColors.green,
            icon: Icons.location_on_outlined),
        _ => const SizedBox.shrink(),
      };
}

/// Compact metric used in summary grids. Fills the width it is given.
/// [onDark] switches to white text on a translucent tile for the blue
/// gradient overview cards.
class MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool onDark;
  const MetricTile(this.label, this.value, this.color,
      {super.key, this.onDark = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: onDark
              ? Colors.white.withValues(alpha: 0.12)
              : color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: onDark
                  ? Colors.white.withValues(alpha: 0.2)
                  : color.withValues(alpha: 0.3)),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                      color: onDark ? Color.lerp(color, Colors.white, 0.35) : color,
                      shape: BoxShape.circle),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(label.toUpperCase(),
                        maxLines: 1,
                        style: TextStyle(
                            color: onDark
                                ? Colors.white.withValues(alpha: 0.82)
                                : color,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5)),
                  ),
                ),
              ]),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value,
                    maxLines: 1,
                    style: TextStyle(
                        color: onDark ? Colors.white : AppColors.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
              ),
            ]),
      );
}

/// Summary tiles shared by the team analytics and the staff month page.
/// Laid out as equal-width rows (3 columns, 2 on narrow cards); a short last
/// row stretches so the grid always fills the card edge to edge.
class AttendanceTotalsGrid extends StatelessWidget {
  final AttendanceTotals totals;
  final bool onDark;
  const AttendanceTotalsGrid(this.totals, {super.key, this.onDark = false});

  static const _gap = 8.0;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      MetricTile('Worked', formatMinutes(totals.workedMinutes), AppColors.brand,
          onDark: onDark),
      MetricTile('Scheduled', formatMinutes(totals.scheduledMinutes),
          AppColors.silver,
          onDark: onDark),
      MetricTile('Late', formatMinutes(totals.lateMinutes), AppColors.orange,
          onDark: onDark),
      MetricTile('Overtime', formatMinutes(totals.overtimeMinutes),
          AppColors.green,
          onDark: onDark),
      MetricTile('Deficit', formatMinutes(totals.deficitMinutes), AppColors.red,
          onDark: onDark),
      if (totals.pausedMinutes > 0)
        MetricTile('Paused', formatMinutes(totals.pausedMinutes),
            AppColors.yellow,
            onDark: onDark),
      MetricTile('Auto checkouts', '${totals.autoCheckouts}', AppColors.orange,
          onDark: onDark),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final cols = constraints.maxWidth >= 300 ? 3 : 2;
      return Column(children: [
        for (var start = 0; start < tiles.length; start += cols) ...[
          if (start > 0) const SizedBox(height: _gap),
          Row(children: [
            for (var i = start; i < start + cols && i < tiles.length; i++) ...[
              if (i > start) const SizedBox(width: _gap),
              Expanded(child: tiles[i]),
            ],
          ]),
        ],
      ]);
    });
  }
}

/// Attendance % with a tappable explanation of which days count.
class AttendancePercentHeader extends StatelessWidget {
  final AttendanceTotals totals;
  final String definition;
  final bool onDark;
  const AttendancePercentHeader(
      {super.key,
      required this.totals,
      required this.definition,
      this.onDark = false});

  String _days(double d) =>
      d == d.roundToDouble() ? d.toInt().toString() : d.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final strong = onDark ? Colors.white : AppColors.text;
    final soft = onDark ? Colors.white.withValues(alpha: 0.78) : AppColors.silver;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('ATTENDANCE',
                style: TextStyle(
                    color: soft,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1)),
            const SizedBox(height: 4),
            Text(formatPercent(totals.attendancePercent),
                style: TextStyle(
                    color: strong,
                    fontSize: 34,
                    height: 1.1,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(
                '${_days(totals.presentDays)} of ${_days(totals.workingDays)} working days',
                style: TextStyle(color: soft, fontSize: 12.5)),
          ]),
        ),
        IconButton(
          tooltip: 'How attendance is calculated',
          icon: Icon(Icons.info_outline_rounded, color: soft),
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            backgroundColor: AppColors.dark2,
            shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            builder: (_) => SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('How attendance is calculated',
                          style: TextStyle(
                              color: AppColors.text,
                              fontSize: 16,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 10),
                      Text(definition,
                          style: const TextStyle(
                              color: AppColors.light, height: 1.45)),
                      const SizedBox(height: 10),
                      const Text(
                          'Late = first check-in after the office start time. '
                          'Overtime = counted time from the office start (or a later check-in) beyond the scheduled hours. '
                          'Deficit = scheduled hours not worked, once the day is checked out. '
                          'Time outside the office area during office (WFO) attendance is paused and not counted.',
                          style: TextStyle(
                              color: AppColors.silver,
                              height: 1.45,
                              fontSize: 13)),
                    ]),
              ),
            ),
          ),
        ),
      ]);
  }
}

/// One day in a staff member's month: a date badge tinted by status, the
/// status and checkout chips, in/out times and only the numbers that matter
/// for that day (no "Worked 0m · Scheduled 0m" on holidays).
class AttendanceDayRow extends StatelessWidget {
  final AttendanceDay day;
  final VoidCallback? onTap;
  const AttendanceDayRow({super.key, required this.day, this.onTap});

  String get _subtitle {
    if (day.sessions.isNotEmpty || day.firstCheckInLabel != null) {
      final out = day.inProgress ? 'in progress' : (day.lastCheckOutLabel ?? '—');
      return 'In ${day.firstCheckInLabel ?? '—'}  ·  Out $out';
    }
    return switch (day.status) {
      'leave' => day.leave != null && day.leave!.isNotEmpty
          ? 'On ${day.leave} leave'
          : 'On approved leave',
      'holiday' => 'Holiday · no scheduled hours',
      'absent' => 'No check-in recorded',
      'not_joined' => 'Before joining date',
      _ => 'No check-in yet',
    };
  }

  @override
  Widget build(BuildContext context) {
    final style = dayStatusStyle(day.status);
    final isToday = DateUtils.isSameDay(day.day, DateTime.now());
    final worked = day.sessions.isNotEmpty || day.workedMinutes > 0;
    final variance = day.varianceMinutes;
    final facts = <Widget>[
      if (worked || day.scheduledMinutes > 0)
        _Fact('Worked', formatMinutes(day.workedMinutes), AppColors.text),
      if (day.scheduledMinutes > 0)
        _Fact('Scheduled', formatMinutes(day.scheduledMinutes), AppColors.text),
      if (day.lateMinutes > 0)
        _Fact('Late', formatMinutes(day.lateMinutes), AppColors.orange),
      if (day.pausedMinutes > 0)
        _Fact('Paused', formatMinutes(day.pausedMinutes), AppColors.amberDark),
      if (variance != 0)
        _Fact(variance > 0 ? 'Overtime' : 'Deficit', formatVariance(variance),
            variance > 0 ? AppColors.greenDark : AppColors.red),
    ];

    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: isToday ? AppColors.brand : AppColors.border,
                width: isToday ? 1.5 : 1),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Date badge
            Container(
              width: 52,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: style.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: style.color.withValues(alpha: 0.3)),
              ),
              child: Column(children: [
                Text(DateFormat('EEE').format(day.day).toUpperCase(),
                    style: TextStyle(
                        color: style.color,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6)),
                Text('${day.day.day}',
                    style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 20,
                        height: 1.2,
                        fontWeight: FontWeight.w800)),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            AttendanceChip(style.label, style.color),
                            if (day.checkoutStatus != null)
                              CheckoutBadge(day.checkoutStatus),
                            if (isToday)
                              const AttendanceChip('Today', AppColors.brand),
                          ],
                        ),
                      ),
                      if (onTap != null)
                        const Icon(Icons.chevron_right_rounded,
                            size: 20, color: AppColors.muted),
                    ]),
                    const SizedBox(height: 6),
                    Text(_subtitle,
                        style: const TextStyle(
                            color: AppColors.light,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    if (facts.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(spacing: 6, runSpacing: 6, children: facts),
                    ],
                  ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Small label/value pill used in [AttendanceDayRow].
class _Fact extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Fact(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.dark3,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.borderSoft),
        ),
        child: Text.rich(TextSpan(children: [
          TextSpan(
              text: '$label ',
              style: const TextStyle(color: AppColors.silver, fontSize: 11.5)),
          TextSpan(
              text: value,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w800)),
        ])),
      );
}
