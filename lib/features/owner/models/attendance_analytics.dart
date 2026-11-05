// Models for /api/attendance analytics. Every total is computed on the server
// in minutes (org timezone); the app only formats them for display.

int _int(dynamic v) => (v as num?)?.round() ?? 0;
double _double(dynamic v) => (v as num?)?.toDouble() ?? 0;
String? _str(dynamic v) => v?.toString();
DateTime? _date(dynamic v) =>
    v == null ? null : DateTime.tryParse(v.toString());

/// 0 → "0m", 90 → "1h 30m", 120 → "2h". Uses the absolute value.
String formatMinutes(int minutes) {
  final m = minutes.abs();
  final h = m ~/ 60, r = m % 60;
  if (h == 0) return '${r}m';
  return r == 0 ? '${h}h' : '${h}h ${r}m';
}

/// Signed variance: +30m overtime, −1h 15m deficit, 0m.
String formatVariance(int minutes) {
  if (minutes == 0) return '0m';
  return '${minutes > 0 ? '+' : '−'}${formatMinutes(minutes)}';
}

/// "92.5%" or "—" when no working day falls in the range.
String formatPercent(double? percent) {
  if (percent == null) return '—';
  return percent == percent.roundToDouble()
      ? '${percent.toInt()}%'
      : '${percent.toStringAsFixed(1)}%';
}

class OfficeHours {
  final String start;
  final String end;
  const OfficeHours({this.start = '10:00', this.end = '19:00'});

  factory OfficeHours.fromJson(Map<String, dynamic>? j) => OfficeHours(
        start: _str(j?['start']) ?? '10:00',
        end: _str(j?['end']) ?? '19:00',
      );

  /// "10:00 AM – 7:00 PM".
  String get label => '${_hm12(start)} – ${_hm12(end)}';

  static String _hm12(String hm) {
    final parts = hm.split(':');
    final h = int.tryParse(parts.first) ?? 0;
    final m = parts.length > 1 ? parts[1] : '00';
    final suffix = h < 12 ? 'AM' : 'PM';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:$m $suffix';
  }
}

class AttendanceTotals {
  final double workingDays;
  final double presentDays;
  final double? attendancePercent;
  final int absentDays, halfDays, leaveDays, holidayWorkedDays, lateDays;
  final int scheduledMinutes, workedMinutes, pausedMinutes, lateMinutes;
  final int overtimeMinutes, deficitMinutes, varianceMinutes;
  final int autoCheckouts, editedCheckouts;

  const AttendanceTotals({
    this.workingDays = 0,
    this.presentDays = 0,
    this.attendancePercent,
    this.absentDays = 0,
    this.halfDays = 0,
    this.leaveDays = 0,
    this.holidayWorkedDays = 0,
    this.lateDays = 0,
    this.scheduledMinutes = 0,
    this.workedMinutes = 0,
    this.pausedMinutes = 0,
    this.lateMinutes = 0,
    this.overtimeMinutes = 0,
    this.deficitMinutes = 0,
    this.varianceMinutes = 0,
    this.autoCheckouts = 0,
    this.editedCheckouts = 0,
  });

  factory AttendanceTotals.fromJson(Map<String, dynamic>? j) {
    j ??= const {};
    return AttendanceTotals(
      workingDays: _double(j['workingDays']),
      presentDays: _double(j['presentDays']),
      attendancePercent: (j['attendancePercent'] as num?)?.toDouble(),
      absentDays: _int(j['absentDays']),
      halfDays: _int(j['halfDays']),
      leaveDays: _int(j['leaveDays']),
      holidayWorkedDays: _int(j['holidayWorkedDays']),
      lateDays: _int(j['lateDays']),
      scheduledMinutes: _int(j['scheduledMinutes']),
      workedMinutes: _int(j['workedMinutes']),
      pausedMinutes: _int(j['pausedMinutes']),
      lateMinutes: _int(j['lateMinutes']),
      overtimeMinutes: _int(j['overtimeMinutes']),
      deficitMinutes: _int(j['deficitMinutes']),
      varianceMinutes: _int(j['varianceMinutes']),
      autoCheckouts: _int(j['autoCheckouts']),
      editedCheckouts: _int(j['editedCheckouts']),
    );
  }
}

class AttendancePause {
  final String? startLabel, endLabel;
  final int minutes;
  final String? endReason;
  const AttendancePause(
      {this.startLabel, this.endLabel, this.minutes = 0, this.endReason});

  factory AttendancePause.fromJson(Map<String, dynamic> j) => AttendancePause(
        startLabel: _str(j['startLabel']),
        endLabel: _str(j['endLabel']),
        minutes: _int(j['minutes']),
        endReason: _str(j['endReason']),
      );
}

class CheckoutEdit {
  final String editedByName;
  final String? editedAtLabel, previousCheckOutLabel, newCheckOutLabel;
  final String previousCheckoutSource;
  final int previousWorkedMinutes, newWorkedMinutes;
  final String reason;

  const CheckoutEdit({
    this.editedByName = '',
    this.editedAtLabel,
    this.previousCheckOutLabel,
    this.newCheckOutLabel,
    this.previousCheckoutSource = 'staff',
    this.previousWorkedMinutes = 0,
    this.newWorkedMinutes = 0,
    this.reason = '',
  });

  factory CheckoutEdit.fromJson(Map<String, dynamic> j) => CheckoutEdit(
        editedByName: _str(j['editedByName']) ?? '',
        editedAtLabel: _str(j['editedAtLabel']),
        previousCheckOutLabel: _str(j['previousCheckOutLabel']),
        newCheckOutLabel: _str(j['newCheckOutLabel']),
        previousCheckoutSource: _str(j['previousCheckoutSource']) ?? 'staff',
        previousWorkedMinutes: _int(j['previousWorkedMinutes']),
        newWorkedMinutes: _int(j['newWorkedMinutes']),
        reason: _str(j['reason']) ?? '',
      );
}

/// One check-in / check-out session with its audit trail.
class AttendanceSession {
  final String id;
  final String date;
  final String? workLocation;
  final DateTime? checkInTime, checkOutTime;
  final String? checkInLabel, checkOutLabel;

  /// open | staff | auto | edited
  final String checkoutStatus;
  final String? autoClosedAtLabel;
  final int workedMinutes, pausedMinutes, lateMinutes, overtimeMinutes;

  /// inside | outside | unknown, or null when not geofenced.
  final String? geofenceStatus;
  final List<AttendancePause> pauses;
  final List<CheckoutEdit> edits;

  const AttendanceSession({
    required this.id,
    required this.date,
    this.workLocation,
    this.checkInTime,
    this.checkOutTime,
    this.checkInLabel,
    this.checkOutLabel,
    this.checkoutStatus = 'staff',
    this.autoClosedAtLabel,
    this.workedMinutes = 0,
    this.pausedMinutes = 0,
    this.lateMinutes = 0,
    this.overtimeMinutes = 0,
    this.geofenceStatus,
    this.pauses = const [],
    this.edits = const [],
  });

  bool get isOpen => checkoutStatus == 'open';

  factory AttendanceSession.fromJson(Map<String, dynamic> j) {
    final calc = j['calc'] is Map
        ? Map<String, dynamic>.from(j['calc'])
        : const <String, dynamic>{};
    final auto = j['autoCheckout'] is Map ? j['autoCheckout'] as Map : null;
    return AttendanceSession(
      id: _str(j['_id']) ?? '',
      date: _str(j['date']) ?? '',
      workLocation: _str(j['attendanceWorkLocation']),
      checkInTime: _date(j['checkInTime']),
      checkOutTime: _date(j['checkOutTime']),
      checkInLabel: _str(j['checkInTimeLabel']),
      checkOutLabel: _str(j['checkOutTimeLabel']),
      checkoutStatus: _str(j['checkoutStatus']) ?? 'staff',
      autoClosedAtLabel: _str(auto?['closedAtLabel']),
      workedMinutes: _int(calc['workedMinutes'] ?? j['durationMinutes']),
      pausedMinutes: _int(calc['pausedMinutes']),
      lateMinutes: _int(calc['lateMinutes']),
      overtimeMinutes: _int(calc['overtimeMinutes']),
      geofenceStatus: _str(j['geofenceStatus']),
      pauses: [
        for (final p in (j['pauses'] as List? ?? const []))
          if (p is Map) AttendancePause.fromJson(Map<String, dynamic>.from(p)),
      ],
      edits: [
        for (final e in (j['checkoutEdits'] as List? ?? const []))
          if (e is Map) CheckoutEdit.fromJson(Map<String, dynamic>.from(e)),
      ],
    );
  }
}

/// One staff member's totals for one org-local date.
class AttendanceDay {
  final String date;

  /// present | half_day | absent | leave | holiday | holiday_worked |
  /// leave_worked | pending | not_joined
  final String status;
  final String? leave;
  final int scheduledMinutes, workedMinutes, pausedMinutes, lateMinutes;
  final int earlyLeaveMinutes, overtimeMinutes, deficitMinutes, varianceMinutes;
  final bool inProgress, autoCheckout, edited;

  /// open | staff | auto | edited, or null with no sessions.
  final String? checkoutStatus;
  final String? firstCheckInLabel, lastCheckOutLabel;
  final String? scheduledStartLabel, scheduledEndLabel;
  final List<AttendanceSession> sessions;

  const AttendanceDay({
    required this.date,
    this.status = 'pending',
    this.leave,
    this.scheduledMinutes = 0,
    this.workedMinutes = 0,
    this.pausedMinutes = 0,
    this.lateMinutes = 0,
    this.earlyLeaveMinutes = 0,
    this.overtimeMinutes = 0,
    this.deficitMinutes = 0,
    this.varianceMinutes = 0,
    this.inProgress = false,
    this.autoCheckout = false,
    this.edited = false,
    this.checkoutStatus,
    this.firstCheckInLabel,
    this.lastCheckOutLabel,
    this.scheduledStartLabel,
    this.scheduledEndLabel,
    this.sessions = const [],
  });

  DateTime get day => DateTime.parse(date);

  factory AttendanceDay.fromJson(Map<String, dynamic> j) => AttendanceDay(
        date: _str(j['date']) ?? '',
        status: _str(j['status']) ?? 'pending',
        leave: _str(j['leave']),
        scheduledMinutes: _int(j['scheduledMinutes']),
        workedMinutes: _int(j['workedMinutes']),
        pausedMinutes: _int(j['pausedMinutes']),
        lateMinutes: _int(j['lateMinutes']),
        earlyLeaveMinutes: _int(j['earlyLeaveMinutes']),
        overtimeMinutes: _int(j['overtimeMinutes']),
        deficitMinutes: _int(j['deficitMinutes']),
        varianceMinutes: _int(j['varianceMinutes']),
        inProgress: j['inProgress'] == true,
        autoCheckout: j['autoCheckout'] == true,
        edited: j['edited'] == true,
        checkoutStatus: _str(j['checkoutStatus']),
        firstCheckInLabel: _str(j['firstCheckInLabel']),
        lastCheckOutLabel: _str(j['lastCheckOutLabel']),
        scheduledStartLabel: _str(j['scheduledStartLabel']),
        scheduledEndLabel: _str(j['scheduledEndLabel']),
        sessions: [
          for (final s in (j['sessions'] as List? ?? const []))
            if (s is Map)
              AttendanceSession.fromJson(Map<String, dynamic>.from(s)),
        ],
      );
}

/// One bar in a variance chart: overtime above zero, deficit below.
class VariancePoint {
  final String label;
  final int overtimeMinutes;
  final int deficitMinutes;
  const VariancePoint(this.label, this.overtimeMinutes, this.deficitMinutes);

  int get varianceMinutes => overtimeMinutes - deficitMinutes;
}

class StaffAttendanceRow {
  final String staffId, name, phone, workLocation;
  final String? photoUrl;
  final AttendanceTotals totals;
  final AttendanceDay? day;

  const StaffAttendanceRow({
    required this.staffId,
    required this.name,
    this.phone = '',
    this.workLocation = 'wfo',
    this.photoUrl,
    this.totals = const AttendanceTotals(),
    this.day,
  });

  factory StaffAttendanceRow.fromJson(Map<String, dynamic> j) =>
      StaffAttendanceRow(
        staffId: _str(j['staffId']) ?? '',
        name: _str(j['name']) ?? 'Staff',
        phone: _str(j['phone']) ?? '',
        workLocation: _str(j['workLocation']) ?? 'wfo',
        photoUrl: _str(j['photoUrl']),
        totals: AttendanceTotals.fromJson(
            j['totals'] is Map ? Map<String, dynamic>.from(j['totals']) : null),
        day: j['day'] is Map
            ? AttendanceDay.fromJson(Map<String, dynamic>.from(j['day']))
            : null,
      );
}

class SeriesPoint {
  final String date;
  final int overtimeMinutes, deficitMinutes, lateMinutes, workedMinutes;
  final int present, absent;

  const SeriesPoint({
    required this.date,
    this.overtimeMinutes = 0,
    this.deficitMinutes = 0,
    this.lateMinutes = 0,
    this.workedMinutes = 0,
    this.present = 0,
    this.absent = 0,
  });

  factory SeriesPoint.fromJson(Map<String, dynamic> j) => SeriesPoint(
        date: _str(j['date']) ?? '',
        overtimeMinutes: _int(j['overtimeMinutes']),
        deficitMinutes: _int(j['deficitMinutes']),
        lateMinutes: _int(j['lateMinutes']),
        workedMinutes: _int(j['workedMinutes']),
        present: _int(j['present']),
        absent: _int(j['absent']),
      );
}

/// GET /attendance/analytics
class AttendanceAnalytics {
  final String from, to, period, today;
  final OfficeHours officeHours;
  final String definition;
  final AttendanceTotals totals;
  final List<SeriesPoint> series;
  final List<StaffAttendanceRow> staff;

  const AttendanceAnalytics({
    required this.from,
    required this.to,
    required this.period,
    this.today = '',
    this.officeHours = const OfficeHours(),
    this.definition = '',
    this.totals = const AttendanceTotals(),
    this.series = const [],
    this.staff = const [],
  });

  factory AttendanceAnalytics.fromJson(Map<String, dynamic> j) {
    final range = j['range'] is Map
        ? Map<String, dynamic>.from(j['range'])
        : const <String, dynamic>{};
    return AttendanceAnalytics(
      from: _str(range['from']) ?? '',
      to: _str(range['to']) ?? '',
      period: _str(range['period']) ?? 'monthly',
      today: _str(range['today']) ?? '',
      officeHours: OfficeHours.fromJson(j['officeHours'] is Map
          ? Map<String, dynamic>.from(j['officeHours'])
          : null),
      definition: _str(j['definition']) ?? '',
      totals: AttendanceTotals.fromJson(
          j['totals'] is Map ? Map<String, dynamic>.from(j['totals']) : null),
      series: [
        for (final s in (j['series'] as List? ?? const []))
          if (s is Map) SeriesPoint.fromJson(Map<String, dynamic>.from(s)),
      ],
      staff: [
        for (final s in (j['staff'] as List? ?? const []))
          if (s is Map)
            StaffAttendanceRow.fromJson(Map<String, dynamic>.from(s)),
      ],
    );
  }
}

/// GET /attendance/staff/:id/month
class StaffMonthAttendance {
  final String staffId, name, phone, month;
  final String? photoUrl;
  final OfficeHours officeHours;
  final String definition;
  final AttendanceTotals totals;
  final List<AttendanceDay> days;

  const StaffMonthAttendance({
    required this.staffId,
    required this.name,
    required this.month,
    this.phone = '',
    this.photoUrl,
    this.officeHours = const OfficeHours(),
    this.definition = '',
    this.totals = const AttendanceTotals(),
    this.days = const [],
  });

  factory StaffMonthAttendance.fromJson(Map<String, dynamic> j) {
    final staff = j['staff'] is Map
        ? Map<String, dynamic>.from(j['staff'])
        : const <String, dynamic>{};
    return StaffMonthAttendance(
      staffId: _str(staff['_id']) ?? '',
      name: _str(staff['name']) ?? 'Staff',
      phone: _str(staff['phone']) ?? '',
      photoUrl: _str(staff['photoUrl']),
      month: _str(j['month']) ?? '',
      officeHours: OfficeHours.fromJson(j['officeHours'] is Map
          ? Map<String, dynamic>.from(j['officeHours'])
          : null),
      definition: _str(j['definition']) ?? '',
      totals: AttendanceTotals.fromJson(
          j['totals'] is Map ? Map<String, dynamic>.from(j['totals']) : null),
      days: [
        for (final d in (j['days'] as List? ?? const []))
          if (d is Map) AttendanceDay.fromJson(Map<String, dynamic>.from(d)),
      ],
    );
  }
}
