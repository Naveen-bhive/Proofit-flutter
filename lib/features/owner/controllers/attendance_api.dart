import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_service.dart';
import '../models/attendance_analytics.dart';

final attendanceApiProvider = Provider<AttendanceApi>(
    (ref) => AttendanceApi(ref.read(apiServiceProvider)));

/// Owner attendance analytics, office hours and checkout corrections.
/// All maths is done by the server; this only fetches and posts.
class AttendanceApi {
  final ApiService _api;
  AttendanceApi(this._api);

  Map<String, dynamic> _data(dynamic res) =>
      Map<String, dynamic>.from(res.data['data'] ?? const {});

  /// [period]: daily | weekly | monthly, anchored on [date] (yyyy-MM-dd).
  Future<AttendanceAnalytics> analytics(
      {required String period, required String date, String? staffId}) async {
    final res = await _api.get('/attendance/analytics', params: {
      'period': period,
      'date': date,
      if (staffId != null) 'staffId': staffId,
    });
    return AttendanceAnalytics.fromJson(_data(res));
  }

  /// [month] is yyyy-MM.
  Future<StaffMonthAttendance> staffMonth(String staffId, String month) async {
    final res = await _api
        .get('/attendance/staff/$staffId/month', params: {'month': month});
    return StaffMonthAttendance.fromJson(_data(res));
  }

  /// [time] is HH:mm in the organisation's timezone, on the session's date.
  Future<AttendanceSession> editCheckout(String recordId,
      {required String time, String reason = ''}) async {
    final res = await _api.put('/attendance/records/$recordId/checkout',
        data: {'time': time, 'reason': reason});
    return AttendanceSession.fromJson(
        Map<String, dynamic>.from(_data(res)['record'] ?? const {}));
  }

  Future<({OfficeHours hours, String timezone})> officeHours() async {
    final d = _data(await _api.get('/owner/office-hours'));
    return (
      hours: OfficeHours.fromJson(d['officeHours'] is Map
          ? Map<String, dynamic>.from(d['officeHours'])
          : null),
      timezone: (d['timezone'] ?? '').toString(),
    );
  }

  Future<OfficeHours> saveOfficeHours(String start, String end) async {
    final d = _data(await _api
        .put('/owner/office-hours', data: {'start': start, 'end': end}));
    return OfficeHours.fromJson(d['officeHours'] is Map
        ? Map<String, dynamic>.from(d['officeHours'])
        : null);
  }
}
