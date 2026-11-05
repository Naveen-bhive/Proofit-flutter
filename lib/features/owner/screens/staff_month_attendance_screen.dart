import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/api_error_utils.dart';
import '../../../core/utils/ui_feedback.dart';
import '../../../shared/permissions/permission_session.dart';
import '../../../shared/widgets/ui_kit.dart' show PageHeader;
import '../controllers/attendance_api.dart';
import '../models/attendance_analytics.dart';
import '../widgets/attendance_variance_chart.dart';
import '../widgets/attendance_widgets.dart';

/// One staff member's month: worked vs scheduled hours, late minutes,
/// overtime / deficit and how each day was checked out.
class StaffMonthAttendanceScreen extends ConsumerStatefulWidget {
  final String staffId;
  final String? staffName;

  /// yyyy-MM; defaults to the current month.
  final String? month;
  const StaffMonthAttendanceScreen(
      {super.key, required this.staffId, this.staffName, this.month});

  @override
  ConsumerState<StaffMonthAttendanceScreen> createState() =>
      _StaffMonthAttendanceScreenState();
}

class _StaffMonthAttendanceScreenState
    extends ConsumerState<StaffMonthAttendanceScreen> {
  final _monthFmt = DateFormat('yyyy-MM');
  late DateTime _month;
  StaffMonthAttendance? _data;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    final parsed =
        widget.month != null ? DateTime.tryParse('${widget.month}-01') : null;
    final now = DateTime.now();
    _month = parsed ?? DateTime(now.year, now.month);
    _load();
  }

  bool get _isOwner => ref.read(permissionSessionProvider).role == 'owner';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ref
          .read(attendanceApiProvider)
          .staffMonth(widget.staffId, _monthFmt.format(_month));
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final atCurrent = _month.year == now.year && _month.month == now.month;
    final data = _data;
    return Scaffold(
      backgroundColor: AppColors.dark,
      body: SafeArea(
        child: Column(children: [
          PageHeader(
              title: data?.name ?? widget.staffName ?? 'Monthly attendance',
              titleSize: 19),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.brand,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                children: [
                  _monthSwitcher(atCurrent),
                  const SizedBox(height: 12),
                  if (_loading && data == null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 60),
                      child: Center(
                          child: CircularProgressIndicator(
                              color: AppColors.brand)),
                    )
                  else if (_error != null && data == null)
                    _errorCard()
                  else if (data != null) ...[
                    _analyticsOverview(data),
                    const SizedBox(height: 12),
                    _varianceCard(data),
                    const SizedBox(height: 20),
                    const Text('DAY BY DAY',
                        style: TextStyle(
                            color: AppColors.silver,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1)),
                    const SizedBox(height: 8),
                    for (final d in data.days) ...[
                      AttendanceDayRow(day: d, onTap: () => _openDay(d)),
                      const SizedBox(height: 8),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _card(Widget child) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
          boxShadow: AppColors.cardShadow,
        ),
        child: child,
      );

  Widget _analyticsOverview(StaffMonthAttendance data) => Container(
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
          Row(children: [
            const Expanded(
                child: Text('MONTHLY PERFORMANCE',
                    style: TextStyle(
                        color: Colors.white70,
                        letterSpacing: 1,
                        fontSize: 11,
                        fontWeight: FontWeight.w700))),
            const Icon(Icons.insights_rounded, color: Colors.white70),
          ]),
          const SizedBox(height: 8),
          Text(formatPercent(data.totals.attendancePercent),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 42,
                  height: 1,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('Attendance · Office hours ${data.officeHours.label}',
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 18),
          AttendanceTotalsGrid(data.totals, onDark: true),
        ]),
      );

  Widget _varianceCard(StaffMonthAttendance data) => _card(
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Daily overtime and deficit',
              style: TextStyle(
                  color: AppColors.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 14)),
          const SizedBox(height: 8),
          AttendanceVarianceChart(points: [
            for (final d in data.days)
              VariancePoint(
                  '${d.day.day}', d.overtimeMinutes, d.deficitMinutes),
          ]),
        ]),
      );

  Widget _errorCard() => _card(Column(children: [
        Text(
            friendlyErrorMessage(_error,
                fallback: 'Could not load attendance.'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.silver)),
        TextButton(onPressed: _load, child: const Text('Retry')),
      ]));

  Widget _monthSwitcher(bool atCurrent) => Row(children: [
        IconButton(
          tooltip: 'Previous month',
          onPressed: _loading ? null : () => _shiftMonth(-1),
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: Text(DateFormat('MMMM yyyy').format(_month),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 16)),
        ),
        IconButton(
          tooltip: 'Next month',
          onPressed: _loading || atCurrent ? null : () => _shiftMonth(1),
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ]);

  Future<void> _openDay(AttendanceDay day) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.dark2,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => AttendanceDaySheet(day: day, canEdit: _isOwner),
    );
    if (changed == true) _load();
  }
}

/// Sessions of one day with geofence pauses, the checkout audit trail and,
/// for owners, a checkout correction. Pops `true` after a successful edit.
class AttendanceDaySheet extends ConsumerStatefulWidget {
  final AttendanceDay day;
  final bool canEdit;
  const AttendanceDaySheet(
      {super.key, required this.day, this.canEdit = false});

  @override
  ConsumerState<AttendanceDaySheet> createState() => _AttendanceDaySheetState();
}

class _AttendanceDaySheetState extends ConsumerState<AttendanceDaySheet> {
  String? _savingId;

  TimeOfDay _initialTime(AttendanceSession s) {
    final label = s.checkOutLabel;
    if (label != null) {
      try {
        return TimeOfDay.fromDateTime(DateFormat('h:mm a').parse(label));
      } catch (_) {}
    }
    return const TimeOfDay(hour: 19, minute: 0);
  }

  Future<void> _edit(AttendanceSession s) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _initialTime(s),
      helpText: 'NEW CHECKOUT TIME (OFFICE TIMEZONE)',
    );
    if (picked == null || !mounted) return;
    final reason = await _askReason();
    if (reason == null || !mounted) return;
    final hm =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    setState(() => _savingId = s.id);
    try {
      await ref
          .read(attendanceApiProvider)
          .editCheckout(s.id, time: hm, reason: reason);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Checkout updated and totals recalculated')));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, e, fallback: 'Could not update checkout.');
      }
    } finally {
      if (mounted) setState(() => _savingId = null);
    }
  }

  Future<String?> _askReason() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reason for the change'),
        content: TextField(
          controller: controller,
          maxLength: 300,
          maxLines: 3,
          minLines: 1,
          decoration: const InputDecoration(
              hintText: 'Optional, e.g. forgot to check out'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Save')),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  @override
  Widget build(BuildContext context) {
    final day = widget.day;
    final style = dayStatusStyle(day.status);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(DateFormat('EEEE, d MMM yyyy').format(day.day),
                      style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                  AttendanceChip(style.label, style.color),
                ]),
            const SizedBox(height: 6),
            Text(
                day.scheduledMinutes > 0
                    ? 'Scheduled ${day.scheduledStartLabel} – ${day.scheduledEndLabel} (${formatMinutes(day.scheduledMinutes)})'
                    : 'No scheduled hours (holiday or leave) — counted time is overtime',
                style:
                    const TextStyle(color: AppColors.silver, fontSize: 12.5)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              MetricTile(
                  'Worked', formatMinutes(day.workedMinutes), AppColors.brand),
              MetricTile(
                  'Late', formatMinutes(day.lateMinutes), AppColors.orange),
              MetricTile(
                  day.varianceMinutes >= 0 ? 'Overtime' : 'Deficit',
                  formatVariance(day.varianceMinutes),
                  day.varianceMinutes >= 0 ? AppColors.green : AppColors.red),
              if (day.earlyLeaveMinutes > 0)
                MetricTile('Left early', formatMinutes(day.earlyLeaveMinutes),
                    AppColors.red),
            ]),
            const SizedBox(height: 16),
            if (day.sessions.isEmpty)
              const Text('No check-in recorded',
                  style: TextStyle(color: AppColors.muted))
            else
              for (final s in day.sessions) _session(s),
          ],
        ),
      ),
    );
  }

  Widget _session(AttendanceSession s) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.dark3,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                    '${s.checkInLabel ?? '—'} → ${s.isOpen ? 'now' : (s.checkOutLabel ?? '—')}',
                    style: const TextStyle(
                        color: AppColors.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
                if (s.workLocation != null)
                  AttendanceChip(
                      s.workLocation!.toUpperCase(),
                      s.workLocation == 'wfh'
                          ? AppColors.purple
                          : AppColors.green),
                CheckoutBadge(s.checkoutStatus),
                if (s.isOpen) GeofenceBadge(s.geofenceStatus),
              ]),
          const SizedBox(height: 6),
          Text(
              'Counted ${formatMinutes(s.workedMinutes)}'
              '${s.pausedMinutes > 0 ? ' · paused ${formatMinutes(s.pausedMinutes)}' : ''}',
              style: const TextStyle(color: AppColors.light, fontSize: 12.5)),
          if (s.checkoutStatus == 'auto' ||
              s.edits.any((e) => e.previousCheckoutSource == 'auto'))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                  'No checkout by end of day — closed automatically at the office end time'
                  '${s.autoClosedAtLabel != null ? ' (processed ${s.autoClosedAtLabel})' : ''}.',
                  style:
                      const TextStyle(color: AppColors.orange, fontSize: 12)),
            ),
          for (final p in s.pauses)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.pause_circle_outline_rounded,
                    size: 15, color: AppColors.yellow),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                      'Outside office ${p.startLabel ?? '—'} – ${p.endLabel ?? 'now'} (${formatMinutes(p.minutes)})',
                      style: const TextStyle(
                          color: AppColors.light, fontSize: 12)),
                ),
              ]),
            ),
          for (final e in s.edits)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.blue.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: AppColors.blue.withValues(alpha: 0.25)),
                ),
                child: Text(
                    'Checkout changed ${e.previousCheckOutLabel ?? '—'} → ${e.newCheckOutLabel ?? '—'} '
                    '(${formatMinutes(e.previousWorkedMinutes)} → ${formatMinutes(e.newWorkedMinutes)}) '
                    'by ${e.editedByName.isEmpty ? 'owner' : e.editedByName} on ${e.editedAtLabel ?? ''}'
                    '${e.reason.isNotEmpty ? '\nReason: ${e.reason}' : ''}',
                    style: const TextStyle(
                        color: AppColors.light, fontSize: 12, height: 1.4)),
              ),
            ),
          if (widget.canEdit && !s.isOpen)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _savingId == null ? () => _edit(s) : null,
                icon: _savingId == s.id
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.edit_calendar_rounded, size: 18),
                label: const Text('Edit checkout'),
              ),
            ),
        ]),
      );
}
