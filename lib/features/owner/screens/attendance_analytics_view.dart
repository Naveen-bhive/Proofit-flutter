import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/api_error_utils.dart';
import '../../../shared/permissions/permission_session.dart';
import '../controllers/attendance_api.dart';
import '../models/attendance_analytics.dart';
import '../widgets/attendance_variance_chart.dart';
import '../widgets/attendance_widgets.dart';
import 'staff_month_attendance_screen.dart' show AttendanceDaySheet;

enum AnalyticsPeriod { daily, weekly, monthly }

/// Team attendance analytics for a day, week or month: attendance %,
/// late / overtime / deficit totals, a variance chart and per-person rows.
/// Lives inside the Attendance screen's "Analytics" tab.
class AttendanceAnalyticsView extends ConsumerStatefulWidget {
  final String? staffId;
  final String? staffName;
  final String? initialMonth;
  const AttendanceAnalyticsView(
      {super.key, this.staffId, this.staffName, this.initialMonth});

  @override
  ConsumerState<AttendanceAnalyticsView> createState() =>
      _AttendanceAnalyticsViewState();
}

class _AttendanceAnalyticsViewState
    extends ConsumerState<AttendanceAnalyticsView> {
  final _dayFmt = DateFormat('yyyy-MM-dd');
  AnalyticsPeriod _period = AnalyticsPeriod.monthly;
  DateTime _anchor = DateUtils.dateOnly(DateTime.now());
  AttendanceAnalytics? _data;
  bool _loading = true;
  Object? _error;
  StaffMonthAttendance? _staffData;

  @override
  void initState() {
    super.initState();
    if (widget.staffId != null && widget.staffId!.isNotEmpty) {
      final parsed = widget.initialMonth != null
          ? DateTime.tryParse('${widget.initialMonth}-01')
          : null;
      if (parsed != null) _anchor = parsed;
      _loadStaff();
    } else {
      _load();
    }
  }

  Future<void> _loadStaff() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final value = await ref
          .read(attendanceApiProvider)
          .staffMonth(widget.staffId!, DateFormat('yyyy-MM').format(_anchor));
      if (mounted) setState(() => _staffData = value);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ref
          .read(attendanceApiProvider)
          .analytics(period: _period.name, date: _dayFmt.format(_anchor));
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _shift(int delta) {
    setState(() {
      _anchor = switch (_period) {
        AnalyticsPeriod.daily =>
          DateTime(_anchor.year, _anchor.month, _anchor.day + delta),
        AnalyticsPeriod.weekly =>
          DateTime(_anchor.year, _anchor.month, _anchor.day + 7 * delta),
        AnalyticsPeriod.monthly =>
          DateTime(_anchor.year, _anchor.month + delta),
      };
    });
    widget.staffId != null ? _loadStaff() : _load();
  }

  bool get _atLatest {
    final today = DateUtils.dateOnly(DateTime.now());
    return switch (_period) {
      AnalyticsPeriod.daily => !_anchor.isBefore(today),
      AnalyticsPeriod.weekly =>
        !_anchor.add(Duration(days: 7 - _anchor.weekday)).isBefore(today),
      AnalyticsPeriod.monthly =>
        _anchor.year == today.year && _anchor.month == today.month,
    };
  }

  String get _rangeLabel {
    final d = _data;
    if (d == null || d.from.isEmpty) return '';
    final from = DateTime.parse(d.from), to = DateTime.parse(d.to);
    return switch (_period) {
      AnalyticsPeriod.daily => DateFormat('EEE, d MMM yyyy').format(from),
      AnalyticsPeriod.weekly =>
        '${DateFormat('d MMM').format(from)} – ${DateFormat('d MMM yyyy').format(to)}',
      AnalyticsPeriod.monthly => DateFormat('MMMM yyyy').format(from),
    };
  }

  List<VariancePoint> _points(AttendanceAnalytics d) {
    if (_period == AnalyticsPeriod.daily) {
      return [
        for (final s in d.staff)
          VariancePoint(s.name.split(' ').first, s.totals.overtimeMinutes,
              s.totals.deficitMinutes),
      ];
    }
    return [
      for (final p in d.series)
        VariancePoint(
            _period == AnalyticsPeriod.weekly
                ? DateFormat('E').format(DateTime.parse(p.date))
                : '${DateTime.parse(p.date).day}',
            p.overtimeMinutes,
            p.deficitMinutes),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (widget.staffId != null && widget.staffId!.isNotEmpty) {
      return _buildStaffAnalytics();
    }
    final d = _data;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _card(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SegmentedButton<AnalyticsPeriod>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: AnalyticsPeriod.daily, label: Text('Daily')),
            ButtonSegment(value: AnalyticsPeriod.weekly, label: Text('Weekly')),
            ButtonSegment(
                value: AnalyticsPeriod.monthly, label: Text('Monthly')),
          ],
          selected: {_period},
          onSelectionChanged: (s) {
            setState(() {
              _period = s.first;
              _anchor = DateUtils.dateOnly(DateTime.now());
            });
            _load();
          },
        ),
        const SizedBox(height: 8),
        Row(children: [
          IconButton(
              tooltip: 'Previous',
              onPressed: _loading ? null : () => _shift(-1),
              icon: const Icon(Icons.chevron_left_rounded)),
          Expanded(
            child: Text(_rangeLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 15)),
          ),
          IconButton(
              tooltip: 'Next',
              onPressed: _loading || _atLatest ? null : () => _shift(1),
              icon: const Icon(Icons.chevron_right_rounded)),
        ]),
      ])),
      const SizedBox(height: 12),
      if (_loading && d == null)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 60),
          child:
              Center(child: CircularProgressIndicator(color: AppColors.brand)),
        )
      else if (_error != null && d == null)
        _card(Column(children: [
          Text(
              friendlyErrorMessage(_error,
                  fallback: 'Could not load analytics.'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.silver)),
          TextButton(onPressed: _load, child: const Text('Retry')),
        ]))
      else if (d != null) ...[
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        _teamOverview(d),
        const SizedBox(height: 12),
        _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              _period == AnalyticsPeriod.daily
                  ? 'Overtime / deficit by person'
                  : 'Team overtime / deficit by day',
              style: const TextStyle(
                  color: AppColors.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 14)),
          const SizedBox(height: 10),
          AttendanceVarianceChart(points: _points(d)),
        ])),
        const SizedBox(height: 16),
        const Text('BY PERSON',
            style: TextStyle(
                color: AppColors.silver,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1)),
        const SizedBox(height: 8),
        if (d.staff.isEmpty)
          _card(const Center(
              child: Text('No staff members yet',
                  style: TextStyle(color: AppColors.silver))))
        else
          for (final s in d.staff) ...[
            _staffRow(s, d),
            const SizedBox(height: 8),
          ],
      ],
    ]);
  }

  Widget _buildStaffAnalytics() {
    final data = _staffData;
    final latest = _anchor.year == DateTime.now().year &&
        _anchor.month == DateTime.now().month;
    final label = DateFormat('MMMM yyyy').format(_anchor);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _card(Column(children: [
        Row(children: [
          IconButton(
              onPressed: _loading ? null : () => _shift(-1),
              icon: const Icon(Icons.chevron_left_rounded)),
          Expanded(
              child: Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15))),
          IconButton(
              onPressed: _loading || latest ? null : () => _shift(1),
              icon: const Icon(Icons.chevron_right_rounded)),
        ]),
      ])),
      const SizedBox(height: 12),
      if (_loading && data == null)
        const Padding(
            padding: EdgeInsets.all(48),
            child: Center(
                child: CircularProgressIndicator(color: AppColors.brand)))
      else if (_error != null && data == null)
        _card(Column(children: [
          Text(
              friendlyErrorMessage(_error,
                  fallback: 'Could not load analytics.'),
              textAlign: TextAlign.center),
          TextButton(onPressed: _loadStaff, child: const Text('Retry'))
        ]))
      else if (data != null) ...[
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF173B85), Color(0xFF2563EB)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(22)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                (data.name.isNotEmpty
                        ? data.name
                        : widget.staffName ?? 'Employee')
                    .toUpperCase(),
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1)),
            const SizedBox(height: 10),
            Text(formatPercent(data.totals.attendancePercent),
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 42)),
            const Text('Monthly attendance',
                style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 14),
            Text('Office hours ${data.officeHours.label}',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 14),
            AttendanceTotalsGrid(data.totals, onDark: true),
          ]),
        ),
        const SizedBox(height: 12),
        _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Daily overtime / deficit',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 10),
          AttendanceVarianceChart(points: [
            for (final day in data.days)
              VariancePoint(
                  '${day.day.day}', day.overtimeMinutes, day.deficitMinutes)
          ]),
        ])),
        const SizedBox(height: 16),
        const Text('DAY BY DAY',
            style: TextStyle(
                color: AppColors.silver,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1)),
        const SizedBox(height: 8),
        for (final day in data.days) ...[
          AttendanceDayRow(day: day, onTap: () => _openDay(day)),
          const SizedBox(height: 8)
        ],
      ],
    ]);
  }

  Future<void> _openDay(AttendanceDay day) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.dark2,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => AttendanceDaySheet(
          day: day,
          canEdit: ref.read(permissionSessionProvider).role == 'owner'),
    );
    if (changed == true) _loadStaff();
  }

  Widget _card(Widget child) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
          boxShadow: AppColors.cardShadow,
        ),
        child: child,
      );

  Widget _teamOverview(AttendanceAnalytics data) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF173B85), Color(0xFF2563EB)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
                color: AppColors.brand.withValues(alpha: .2),
                blurRadius: 22,
                offset: const Offset(0, 10))
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            const Expanded(
                child: Text('TEAM PERFORMANCE',
                    style: TextStyle(
                        color: Colors.white70,
                        letterSpacing: 1,
                        fontSize: 11,
                        fontWeight: FontWeight.w700))),
            const Icon(Icons.groups_rounded, color: Colors.white70),
          ]),
          const SizedBox(height: 8),
          AttendancePercentHeader(
              totals: data.totals, definition: data.definition, onDark: true),
          Text('Office hours ${data.officeHours.label}',
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 14),
          AttendanceTotalsGrid(data.totals, onDark: true),
        ]),
      );

  Widget _staffRow(StaffAttendanceRow s, AttendanceAnalytics d) {
    final t = s.totals;
    final month = d.from.length >= 7 ? d.from.substring(0, 7) : '';
    final day = s.day;
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push(
            '/owner/staff-attendance/${s.staffId}/month?month=$month&name=${Uri.encodeComponent(s.name)}'),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(s.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppColors.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
              ),
              const SizedBox(width: 8),
              Text(formatPercent(t.attendancePercent),
                  style: const TextStyle(
                      color: AppColors.brand,
                      fontWeight: FontWeight.w800,
                      fontSize: 15)),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ]),
            if (day != null) ...[
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                AttendanceChip(dayStatusStyle(day.status).label,
                    dayStatusStyle(day.status).color),
                if (day.checkoutStatus != null)
                  CheckoutBadge(day.checkoutStatus),
                if (day.sessions.isNotEmpty || day.firstCheckInLabel != null)
                  Text(
                      'In ${day.firstCheckInLabel ?? '—'} · Out ${day.inProgress ? 'in progress' : (day.lastCheckOutLabel ?? '—')}',
                      style: const TextStyle(
                          color: AppColors.light, fontSize: 12)),
              ]),
            ],
            const SizedBox(height: 6),
            Wrap(spacing: 14, runSpacing: 4, children: [
              _fact('Worked', formatMinutes(t.workedMinutes)),
              _fact('Late', formatMinutes(t.lateMinutes), AppColors.orange),
              _fact(
                  'OT', formatMinutes(t.overtimeMinutes), AppColors.greenDark),
              _fact('Deficit', formatMinutes(t.deficitMinutes), AppColors.red),
              if (t.autoCheckouts > 0)
                _fact('Auto', '${t.autoCheckouts}', AppColors.orange),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _fact(String label, String value, [Color color = AppColors.text]) =>
      Text.rich(TextSpan(children: [
        TextSpan(
            text: '$label ',
            style: const TextStyle(color: AppColors.silver, fontSize: 12)),
        TextSpan(
            text: value,
            style: TextStyle(
                color: color, fontSize: 12.5, fontWeight: FontWeight.w700)),
      ]));
}
