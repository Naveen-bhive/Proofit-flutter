import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_service.dart';
import '../../../core/utils/ui_feedback.dart';

/// A completed day shorter than this counts as a half day.
const _halfDayThresholdMinutes = 240;
const _orange = Color(0xFFF97316);
const _purple = Color(0xFF8B5CF6);

enum _Status { present, halfDay, leave, absent, holiday, pending, unmarked }

extension on _Status {
  Color get color => switch (this) {
        _Status.present => AppColors.green,
        _Status.halfDay => _orange,
        _Status.leave => _purple,
        _Status.absent => AppColors.red,
        _Status.holiday => AppColors.yellow,
        _Status.pending || _Status.unmarked => AppColors.muted,
      };

  String get label => switch (this) {
        _Status.present => 'Present',
        _Status.halfDay => 'Half Day',
        _Status.leave => 'Leave',
        _Status.absent => 'Absent',
        _Status.holiday => 'Holiday',
        _Status.pending => 'Pending',
        _Status.unmarked => 'Unmarked',
      };

  String get code => switch (this) {
        _Status.present => 'P',
        _Status.halfDay => 'HD',
        _Status.leave => 'L',
        _Status.absent => 'A',
        _Status.holiday => 'H',
        _Status.pending || _Status.unmarked => '-',
      };

  /// Symbol drawn in grid cells; null means a plain dash.
  IconData? get icon => switch (this) {
        _Status.present => Icons.check_rounded,
        _Status.halfDay => Icons.star_half_rounded,
        _Status.leave => Icons.priority_high_rounded,
        _Status.absent => Icons.close_rounded,
        _Status.holiday => Icons.star_outline_rounded,
        _Status.pending || _Status.unmarked => null,
      };
}

class _Staff {
  final String id;
  final String name;
  final String phone;
  final String? photoUrl;
  final DateTime? joined;
  const _Staff(this.id, this.name, this.phone, this.photoUrl, this.joined);

  factory _Staff.fromJson(Map<String, dynamic> j) {
    final created = DateTime.tryParse(j['createdAt']?.toString() ?? '');
    return _Staff(
      j['_id'].toString(),
      (j['name'] ?? 'Staff').toString(),
      (j['phone'] ?? j['email'] ?? '').toString(),
      j['photoUrl']?.toString(),
      created != null ? DateUtils.dateOnly(created.toLocal()) : null,
    );
  }
}

class StaffAttendanceScreen extends ConsumerStatefulWidget {
  final String? staffId;
  final String? staffName;
  const StaffAttendanceScreen({super.key, this.staffId, this.staffName});

  @override
  ConsumerState<StaffAttendanceScreen> createState() => _StaffAttendanceScreenState();
}

class _StaffAttendanceScreenState extends ConsumerState<StaffAttendanceScreen> {
  final _dayFmt = DateFormat('yyyy-MM-dd');
  List<_Staff> _staff = [];
  /// staffId -> yyyy-MM-dd -> check-in records for that day.
  Map<String, Map<String, List<Map<String, dynamic>>>> _byStaff = {};
  /// staffId -> yyyy-MM-dd -> approved leave type name for that day.
  Map<String, Map<String, String>> _leaves = {};
  /// yyyy-MM-dd -> occasion, for holidays the owner has added.
  Map<String, String> _holidays = {};
  String? _selectedId;
  late int _month;
  late int _year;
  bool _loading = true;
  bool _exporting = false;

  _Staff? get _selected => _staff.where((s) => s.id == _selectedId).firstOrNull;

  List<DateTime> get _days {
    final count = DateUtils.getDaysInMonth(_year, _month);
    return List.generate(count, (i) => DateTime(_year, _month, i + 1));
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = now.month;
    _year = now.year;
    _selectedId = widget.staffId;
    _loadStaff();
    _loadRecords();
  }

  Future<void> _loadStaff() async {
    try {
      final res = await ref.read(apiServiceProvider).get('/staff');
      if (res.data['success'] == true) {
        final rows = List<Map<String, dynamic>>.from(res.data['data'] ?? []);
        final staff = rows.where((r) => r['kind'] != 'invite').map(_Staff.fromJson).toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        if (mounted) setState(() => _staff = staff);
      }
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e, fallback: 'Could not load staff.');
    }
  }

  Future<void> _loadRecords() async {
    setState(() => _loading = true);
    try {
      final days = _days;
      final api = ref.read(apiServiceProvider);
      final range = {'from': _dayFmt.format(days.first), 'to': _dayFmt.format(days.last)};
      // Leaves are optional context — never let them block attendance.
      final leavesFuture = api
          .get('/leaves', params: {...range, 'status': 'approved', 'limit': '1000'})
          .then<dynamic>((r) => r)
          .catchError((_) => null);
      final holidaysFuture = api.get('/holidays', params: range).then<dynamic>((r) => r).catchError((_) => null);
      final res = await api.get('/location/staff-attendance', params: {...range, 'limit': '5000'});
      _leaves = _groupLeaves(await leavesFuture);
      _holidays = _groupHolidays(await holidaysFuture);
      if (res.data['success'] == true) {
        final records = List<Map<String, dynamic>>.from(res.data['data']['records'] ?? []);
        final grouped = <String, Map<String, List<Map<String, dynamic>>>>{};
        for (final r in records) {
          final staff = r['staffId'];
          final id = staff is Map ? staff['_id']?.toString() : staff?.toString();
          final date = r['date']?.toString();
          if (id == null || date == null) continue;
          grouped.putIfAbsent(id, () => {}).putIfAbsent(date, () => []).add(r);
        }
        if (mounted) setState(() => _byStaff = grouped);
      }
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e, fallback: 'Could not load attendance.');
    }
    if (mounted) setState(() => _loading = false);
  }

  Map<String, Map<String, String>> _groupLeaves(dynamic res) {
    final out = <String, Map<String, String>>{};
    final data = res?.data is Map ? res.data['data'] : null;
    final leaves = data is Map ? data['leaves'] : null;
    if (leaves is! List) return out;
    for (final l in leaves) {
      final staff = l['staffId'];
      final id = staff is Map ? staff['_id']?.toString() : staff?.toString();
      final start = DateTime.tryParse(l['startDate']?.toString() ?? '');
      final end = DateTime.tryParse(l['endDate']?.toString() ?? '') ?? start;
      if (id == null || start == null || end == null) continue;
      for (var d = start; !d.isAfter(end); d = DateTime(d.year, d.month, d.day + 1)) {
        out.putIfAbsent(id, () => {})[_dayFmt.format(d)] = (l['leaveTypeName'] ?? 'Leave').toString();
      }
    }
    return out;
  }

  Map<String, String> _groupHolidays(dynamic res) {
    final rows = res?.data is Map ? res.data['data'] : null;
    if (rows is! List) return {};
    return {
      for (final h in rows)
        if (h is Map && h['date'] != null) h['date'].toString(): (h['occasion'] ?? 'Holiday').toString(),
    };
  }

  bool _isHoliday(DateTime day) => _holidays.containsKey(_dayFmt.format(day));

  List<Map<String, dynamic>> _recordsFor(String staffId, DateTime day) =>
      _byStaff[staffId]?[_dayFmt.format(day)] ?? const [];

  _Status _statusFor(_Staff s, DateTime day) {
    final recs = _recordsFor(s.id, day);
    final today = DateUtils.dateOnly(DateTime.now());
    if (recs.isNotEmpty) {
      final ongoing = recs.any((r) => r['checkOutTime'] == null);
      final minutes = recs.fold<int>(0, (a, r) => a + ((r['durationMinutes'] as num?)?.toInt() ?? 0));
      return ongoing || minutes >= _halfDayThresholdMinutes ? _Status.present : _Status.halfDay;
    }
    if (s.joined != null && day.isBefore(s.joined!)) return _Status.unmarked;
    if (_isHoliday(day)) return _Status.holiday;
    if (_leaves[s.id]?.containsKey(_dayFmt.format(day)) ?? false) return _Status.leave;
    if (!day.isBefore(today)) return _Status.pending;
    return _Status.absent;
  }

  // ─── Pickers ────────────────────────────────────────────────────────────

  Future<T?> _pick<T>({
    required String title,
    required List<T> values,
    required T? current,
    required Widget Function(T value, bool selected) itemBuilder,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: AppColors.dark2,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40, height: 4, margin: const EdgeInsets.only(top: 12, bottom: 12),
            decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(title, style: const TextStyle(color: AppColors.white, fontSize: 17, fontWeight: FontWeight.w700)),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              children: values
                  .map((v) => InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.pop(ctx, v),
                        child: itemBuilder(v, v == current),
                      ))
                  .toList(),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _pickerRow({Widget? leading, required String title, String? subtitle, required bool selected}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: selected ? AppColors.brand.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: selected ? AppColors.brand.withValues(alpha: 0.5) : Colors.transparent),
      ),
      child: Row(children: [
        if (leading != null) ...[leading, const SizedBox(width: 12)],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w600, fontSize: 15)),
            if (subtitle != null && subtitle.isNotEmpty)
              Text(subtitle, style: const TextStyle(color: AppColors.silver, fontSize: 12)),
          ]),
        ),
        if (selected) const Icon(Icons.check_circle_rounded, color: AppColors.brand, size: 20),
      ]),
    );
  }

  Future<void> _pickEmployee() async {
    // '' stands for "All employees".
    final picked = await _pick<String>(
      title: 'Select Employee',
      values: ['', ..._staff.map((s) => s.id)],
      current: _selectedId ?? '',
      itemBuilder: (id, selected) {
        if (id.isEmpty) {
          return _pickerRow(
            leading: const _AllAvatar(),
            title: 'All Employees',
            subtitle: 'Monthly attendance matrix',
            selected: selected,
          );
        }
        final s = _staff.firstWhere((s) => s.id == id);
        return _pickerRow(leading: _Avatar(s, size: 36), title: s.name, subtitle: s.phone, selected: selected);
      },
    );
    if (picked != null) setState(() => _selectedId = picked.isEmpty ? null : picked);
  }

  Future<void> _pickMonth() async {
    final picked = await _pick<int>(
      title: 'Select Month',
      values: List.generate(12, (i) => i + 1),
      current: _month,
      itemBuilder: (m, selected) =>
          _pickerRow(title: DateFormat('MMMM').format(DateTime(2000, m)), selected: selected),
    );
    if (picked != null && picked != _month) {
      setState(() => _month = picked);
      _loadRecords();
    }
  }

  Future<void> _pickYear() async {
    final now = DateTime.now().year;
    final picked = await _pick<int>(
      title: 'Select Year',
      values: [for (var y = now; y >= 2024; y--) y],
      current: _year,
      itemBuilder: (y, selected) => _pickerRow(title: '$y', selected: selected),
    );
    if (picked != null && picked != _year) {
      setState(() => _year = picked);
      _loadRecords();
    }
  }

  // ─── Export ─────────────────────────────────────────────────────────────

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final days = _days;
      final buf = StringBuffer();
      String esc(String v) => '"${v.replaceAll('"', '""')}"';
      final selected = _selected;
      if (selected == null) {
        buf.writeln(['Employee', 'Phone', ...days.map((d) => DateFormat('d EEE').format(d)), 'Present', 'Half Day', 'Leave', 'Absent']
            .map(esc).join(','));
        for (final s in _staff) {
          final statuses = days.map((d) => _statusFor(s, d)).toList();
          buf.writeln([
            s.name, s.phone, ...statuses.map((st) => st.code),
            '${statuses.where((st) => st == _Status.present).length}',
            '${statuses.where((st) => st == _Status.halfDay).length}',
            '${statuses.where((st) => st == _Status.leave).length}',
            '${statuses.where((st) => st == _Status.absent).length}',
          ].map(esc).join(','));
        }
      } else {
        buf.writeln(['Date', 'Day', 'Status', 'Check In', 'Check Out', 'Minutes'].map(esc).join(','));
        for (final d in days) {
          final recs = _recordsFor(selected.id, d);
          final minutes = recs.fold<int>(0, (a, r) => a + ((r['durationMinutes'] as num?)?.toInt() ?? 0));
          buf.writeln([
            _dayFmt.format(d), DateFormat('EEE').format(d), _statusFor(selected, d).label,
            recs.isEmpty ? '' : (recs.last['checkInTimeLabel'] ?? '').toString(),
            recs.isEmpty ? '' : (recs.first['checkOutTimeLabel'] ?? '').toString(),
            recs.isEmpty ? '' : '$minutes',
          ].map(esc).join(','));
        }
      }
      final who = selected == null ? 'all' : selected.name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-').toLowerCase();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/attendance-$who-$_year-${_month.toString().padLeft(2, '0')}.csv');
      await file.writeAsString(buf.toString());
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path)],
        subject: 'Attendance ${DateFormat('MMMM yyyy').format(DateTime(_year, _month))}',
      ));
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e, fallback: 'Could not export attendance.');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        titleSpacing: 0,
        title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Attendance', style: TextStyle(color: AppColors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          SizedBox(height: 2),
          Text('Home • Attendance', style: TextStyle(color: AppColors.silver, fontSize: 12)),
        ]),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.border),
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.brand,
        backgroundColor: AppColors.dark2,
        onRefresh: () async {
          await Future.wait([_loadStaff(), _loadRecords()]);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _filtersCard(),
            const SizedBox(height: 16),
            _legendCard(),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(child: CircularProgressIndicator(color: AppColors.brand)),
              )
            else if (selected == null)
              _matrix()
            else ...[
              _summaryCard(selected),
              const SizedBox(height: 16),
              _calendarCard(selected),
              const SizedBox(height: 16),
              _exceptionsCard(selected),
            ],
          ],
        ),
      ),
    );
  }

  Widget _card({required Widget child, EdgeInsets padding = const EdgeInsets.all(16)}) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: AppColors.dark2,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: child,
      );

  Widget _fieldLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(color: AppColors.silver, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
      );

  Widget _selectBox({required Widget child, required VoidCallback onTap, double vPad = 14}) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: vPad),
          decoration: BoxDecoration(
            color: AppColors.dark3,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(children: [
            Expanded(child: child),
            const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.silver),
          ]),
        ),
      );

  Widget _filtersCard() {
    final selected = _selected;
    const valueStyle = TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 15);
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _fieldLabel('EMPLOYEE'),
        _selectBox(
          onTap: _pickEmployee,
          vPad: selected == null ? 14 : 10,
          child: selected == null
              ? const Text('All', style: valueStyle)
              : Row(children: [
                  _Avatar(selected, size: 34),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(selected.name, style: valueStyle, overflow: TextOverflow.ellipsis),
                      if (selected.phone.isNotEmpty)
                        Text(selected.phone, style: const TextStyle(color: AppColors.silver, fontSize: 11)),
                    ]),
                  ),
                ]),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _fieldLabel('MONTH'),
              _selectBox(
                onTap: _pickMonth,
                child: Text(DateFormat('MMMM').format(DateTime(2000, _month)), style: valueStyle),
              ),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _fieldLabel('YEAR'),
              _selectBox(onTap: _pickYear, child: Text('$_year', style: valueStyle)),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        const Divider(height: 1, color: AppColors.border),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: _exporting || _loading ? null : _export,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.white,
            side: const BorderSide(color: AppColors.border),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          icon: _exporting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brand))
              : const Icon(Icons.upload_rounded, size: 18),
          label: const Text('Export', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }

  Widget _legendCard() {
    const items = [_Status.holiday, _Status.absent, _Status.present, _Status.halfDay, _Status.leave, _Status.pending];
    return _card(
      padding: const EdgeInsets.fromLTRB(16, 14, 0, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.only(right: 16),
          child: Row(children: [
            Expanded(
              child: Text('Status Legend',
                  style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 14)),
            ),
            Text('Swipe for all', style: TextStyle(color: AppColors.muted, fontSize: 11)),
          ]),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 30,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(right: 16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => _StatusChip(items[i]),
          ),
        ),
      ]),
    );
  }

  // ─── All employees: monthly matrix ──────────────────────────────────────

  static const _nameColWidth = 150.0;
  static const _cellWidth = 34.0;
  static const _rowHeight = 58.0;
  static const _headerHeight = 50.0;

  Widget _matrix() {
    final days = _days;
    final today = DateUtils.dateOnly(DateTime.now());
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('Monthly Attendance Matrix',
            style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 14)),
        const SizedBox(width: 6),
        Expanded(
          child: Text('(${DateFormat('MMM yyyy').format(days.first)})',
              style: const TextStyle(color: AppColors.silver, fontSize: 11, fontWeight: FontWeight.w600)),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: AppColors.dark3, borderRadius: BorderRadius.circular(20)),
          child: const Text('Scroll horizontally →', style: TextStyle(color: AppColors.muted, fontSize: 10)),
        ),
      ]),
      const SizedBox(height: 12),
      if (_staff.isEmpty)
        _card(
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('No staff members yet', style: TextStyle(color: AppColors.silver))),
          ),
        )
      else
        _card(
          padding: EdgeInsets.zero,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Fixed employee column.
              SizedBox(
                width: _nameColWidth,
                child: Column(children: [
                  Container(
                    height: _headerHeight,
                    color: AppColors.dark3,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.only(left: 14),
                    child: const Text('Employee',
                        style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                  for (final s in _staff)
                    InkWell(
                      onTap: () => setState(() => _selectedId = s.id),
                      child: Container(
                        height: _rowHeight,
                        padding: const EdgeInsets.only(left: 10, right: 6),
                        decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
                        child: Row(children: [
                          _Avatar(s, size: 32),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                                if (s.phone.isNotEmpty)
                                  Text(s.phone,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: AppColors.silver, fontSize: 10.5)),
                              ],
                            ),
                          ),
                        ]),
                      ),
                    ),
                ]),
              ),
              // Scrollable day columns.
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Column(children: [
                    Container(
                      height: _headerHeight,
                      color: AppColors.dark3,
                      child: Row(children: [
                        for (final d in days)
                          SizedBox(
                            width: _cellWidth,
                            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Text('${d.day}',
                                  style: TextStyle(
                                    color: d == today ? AppColors.brand : AppColors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  )),
                              const SizedBox(height: 2),
                              Text(DateFormat('E').format(d).substring(0, 2),
                                  style: TextStyle(
                                    color: _isHoliday(d) ? AppColors.yellow : AppColors.muted,
                                    fontSize: 10,
                                  )),
                            ]),
                          ),
                        const SizedBox(width: 8),
                      ]),
                    ),
                    for (final s in _staff)
                      Container(
                        height: _rowHeight,
                        decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
                        child: Row(children: [
                          for (final d in days)
                            SizedBox(width: _cellWidth, child: Center(child: _StatusMark(_statusFor(s, d)))),
                          const SizedBox(width: 8),
                        ]),
                      ),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      if (_staff.isNotEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 10, left: 4),
          child: Text('Tap an employee to view their monthly calendar',
              style: TextStyle(color: AppColors.muted, fontSize: 11)),
        ),
    ]);
  }

  // ─── Individual employee ────────────────────────────────────────────────

  Widget _summaryCard(_Staff s) {
    final statuses = _days.map((d) => _statusFor(s, d)).toList();
    int count(_Status st) => statuses.where((x) => x == st).length;
    final present = count(_Status.present);
    final half = count(_Status.halfDay);
    final leave = count(_Status.leave);
    final absent = count(_Status.absent);
    final pending = count(_Status.pending) + count(_Status.unmarked);
    final workingDays = statuses.length - count(_Status.holiday);
    final score = present + half * 0.5;
    final scoreText = score == score.roundToDouble() ? score.toInt().toString() : score.toStringAsFixed(1);

    return _card(
      child: Column(children: [
        Row(children: [
          _Avatar(s, size: 46),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 2),
              Text(s.joined != null ? 'Joined ${DateFormat('d MMM yyyy').format(s.joined!)}' : s.phone,
                  style: const TextStyle(color: AppColors.silver, fontSize: 11, fontWeight: FontWeight.w600)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            const Text('TOTAL SCORE',
                style: TextStyle(color: AppColors.silver, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
            const SizedBox(height: 4),
            Text.rich(TextSpan(children: [
              TextSpan(
                  text: scoreText,
                  style: const TextStyle(color: AppColors.white, fontSize: 20, fontWeight: FontWeight.w800)),
              TextSpan(text: ' / $workingDays', style: const TextStyle(color: AppColors.silver, fontSize: 13)),
            ])),
          ]),
        ]),
        const SizedBox(height: 14),
        const Divider(height: 1, color: AppColors.border),
        const SizedBox(height: 14),
        Row(children: [
          _statTile('PRESENT', present, AppColors.green),
          const SizedBox(width: 6),
          _statTile('HALF DAY', half, _orange),
          const SizedBox(width: 6),
          _statTile('LEAVE', leave, _purple),
          const SizedBox(width: 6),
          _statTile('ABSENT', absent, AppColors.red),
          const SizedBox(width: 6),
          _statTile('PENDING', pending, AppColors.silver),
        ]),
      ]),
    );
  }

  Widget _statTile(String label, int value, Color color) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Column(children: [
            FittedBox(
              child: Text(label,
                  style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
            ),
            const SizedBox(height: 4),
            Text('$value', style: const TextStyle(color: AppColors.white, fontSize: 18, fontWeight: FontWeight.w800)),
          ]),
        ),
      );

  Widget _calendarCard(_Staff s) {
    final days = _days;
    final first = days.first;
    final leading = first.weekday % 7; // Sunday-first grid
    final cells = <DateTime?>[
      for (var i = leading; i > 0; i--) first.subtract(Duration(days: i)),
      ...days,
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    const weekdays = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];

    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('${DateFormat('MMMM yyyy').format(first).toUpperCase()} GRID',
                style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 0.8)),
          ),
          Text('${days.length} Days',
              style: const TextStyle(color: AppColors.silver, fontWeight: FontWeight.w700, fontSize: 12)),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          for (final w in weekdays)
            Expanded(
              child: Center(
                child: Text(w,
                    style: const TextStyle(color: AppColors.muted, fontSize: 10, fontWeight: FontWeight.w700)),
              ),
            ),
        ]),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 0.9,
          children: [
            for (final d in cells)
              if (d == null)
                const SizedBox()
              else if (d.month != _month)
                Center(
                  child: Text('${d.day}', style: const TextStyle(color: AppColors.dark4, fontWeight: FontWeight.w600)),
                )
              else
                _dayCell(s, d),
          ],
        ),
      ]),
    );
  }

  Widget _dayCell(_Staff s, DateTime d) {
    final st = _statusFor(s, d);
    final isToday = d == DateUtils.dateOnly(DateTime.now());
    final tinted = st != _Status.pending && st != _Status.unmarked;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _showDayDetails(s, d, st),
      child: Container(
        decoration: BoxDecoration(
          color: tinted ? st.color.withValues(alpha: 0.12) : AppColors.dark3,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isToday ? AppColors.brand : (tinted ? st.color.withValues(alpha: 0.45) : AppColors.border),
            width: isToday ? 1.5 : 1,
          ),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('${d.day}',
              style: TextStyle(
                color: tinted ? st.color : AppColors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              )),
          const SizedBox(height: 2),
          _StatusMark(st, size: 13),
        ]),
      ),
    );
  }

  void _showDayDetails(_Staff s, DateTime d, _Status st) {
    final recs = _recordsFor(s.id, d);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.dark2,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(
            child: Container(
              width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Row(children: [
            Expanded(
              child: Text(DateFormat('EEEE, d MMM yyyy').format(d),
                  style: const TextStyle(color: AppColors.white, fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            _StatusChip(st),
          ]),
          const SizedBox(height: 4),
          Text(s.name, style: const TextStyle(color: AppColors.silver, fontSize: 12)),
          const SizedBox(height: 16),
          if (recs.isEmpty)
            Text(
              _leaves[s.id]?[_dayFmt.format(d)] != null
                  ? 'Approved ${_leaves[s.id]![_dayFmt.format(d)]} leave'
                  : _holidays[_dayFmt.format(d)] != null
                      ? 'Holiday: ${_holidays[_dayFmt.format(d)]}'
                      : 'No check-in recorded',
              style: const TextStyle(color: AppColors.muted),
            )
          else
            for (final r in recs.reversed)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.dark3,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(children: [
                  const Icon(Icons.login_rounded, color: AppColors.green, size: 16),
                  const SizedBox(width: 6),
                  Text(_timeOnly(r['checkInTimeLabel']), style: const TextStyle(color: AppColors.light, fontSize: 13)),
                  const SizedBox(width: 16),
                  const Icon(Icons.logout_rounded, color: AppColors.red, size: 16),
                  const SizedBox(width: 6),
                  Text(_timeOnly(r['checkOutTimeLabel']), style: const TextStyle(color: AppColors.light, fontSize: 13)),
                  const Spacer(),
                  Text(_duration(r), style: const TextStyle(color: AppColors.silver, fontSize: 12)),
                ]),
              ),
        ]),
      ),
    );
  }

  /// Labels arrive as "d MMM, h:mm A" in org time; show only the time part.
  String _timeOnly(dynamic label) {
    if (label == null) return 'Active';
    final parts = label.toString().split(', ');
    return parts.length > 1 ? parts.last : parts.first;
  }

  String _duration(Map<String, dynamic> r) {
    if (r['checkOutTime'] == null) return 'In progress';
    final m = (r['durationMinutes'] as num?)?.toInt() ?? 0;
    return m >= 60 ? '${m ~/ 60}h ${m % 60}m' : '${m}m';
  }

  Widget _exceptionsCard(_Staff s) {
    final today = DateUtils.dateOnly(DateTime.now());
    final runs = <({_Status status, DateTime start, DateTime end, int count})>[];
    _Status? runStatus;
    DateTime? runStart, runEnd;
    var runCount = 0;

    void close() {
      if (runStatus != null) runs.add((status: runStatus!, start: runStart!, end: runEnd!, count: runCount));
      runStatus = null;
      runCount = 0;
    }

    for (final d in _days) {
      if (d.isAfter(today)) break;
      var st = _statusFor(s, d);
      if (st == _Status.pending) st = _Status.unmarked;
      // Holidays neither break nor extend a run.
      if (st == _Status.holiday) continue;
      if (st == _Status.present) {
        close();
        continue;
      }
      if (st != runStatus) {
        close();
        runStatus = st;
        runStart = d;
      }
      runEnd = d;
      runCount++;
    }
    close();

    final fmt = DateFormat('MMM dd');
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('RECORDED EXCEPTIONS',
            style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 0.8)),
        const SizedBox(height: 12),
        if (runs.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('No exceptions this month', style: TextStyle(color: AppColors.muted, fontSize: 13)),
          )
        else
          for (final r in runs.reversed)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: r.status == _Status.unmarked ? AppColors.dark3 : r.status.color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: r.status == _Status.unmarked ? AppColors.border : r.status.color.withValues(alpha: 0.35)),
              ),
              child: Row(children: [
                Container(
                  width: 26, height: 26,
                  decoration: BoxDecoration(
                    color: r.status == _Status.unmarked ? AppColors.dark4 : r.status.color,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(r.status.icon ?? Icons.circle, color: AppColors.white, size: r.status.icon == null ? 6 : 15),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      r.count == 1
                          ? '${fmt.format(r.start)}, ${r.start.year}'
                          : '${fmt.format(r.start)} – ${fmt.format(r.end)}, ${r.end.year}',
                      style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      switch (r.status) {
                        _Status.absent => r.count > 1 ? 'Consecutive Absences (${r.count} Days)' : 'Absent (1 Day)',
                        _Status.leave => 'On ${_leaves[s.id]?[_dayFmt.format(r.start)] ?? ''} Leave (${r.count} Day${r.count > 1 ? 's' : ''})',
                        _Status.halfDay => 'Short day${r.count > 1 ? 's' : ''} (${r.count} Day${r.count > 1 ? 's' : ''})',
                        _ => s.joined != null && !r.end.isBefore(today) ? 'No entry logged yet' : 'No entry logged',
                      },
                      style: const TextStyle(color: AppColors.silver, fontSize: 11),
                    ),
                  ]),
                ),
                _StatusChip(r.status, compact: true),
              ]),
            ),
      ]),
    );
  }
}

// ─── Small widgets ────────────────────────────────────────────────────────

class _StatusMark extends StatelessWidget {
  final _Status status;
  final double size;
  const _StatusMark(this.status, {this.size = 15});

  @override
  Widget build(BuildContext context) {
    final icon = status.icon;
    if (icon == null) return Text('-', style: TextStyle(color: AppColors.muted, fontSize: size - 1));
    return Icon(icon, size: size, color: status.color);
  }
}

class _StatusChip extends StatelessWidget {
  final _Status status;
  final bool compact;
  const _StatusChip(this.status, {this.compact = false});

  @override
  Widget build(BuildContext context) {
    final c = status == _Status.pending || status == _Status.unmarked ? AppColors.silver : status.color;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 4 : 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(compact ? 6 : 20),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (!compact) ...[
          status.icon != null
              ? Icon(status.icon, size: 13, color: c)
              : Text('-', style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(width: 4),
        ],
        Text(status.label, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _Avatar extends StatelessWidget {
  final _Staff staff;
  final double size;
  const _Avatar(this.staff, {this.size = 36});

  @override
  Widget build(BuildContext context) {
    final url = staff.photoUrl;
    final parts = staff.name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final initials = parts.isEmpty
        ? '?'
        : (parts.length == 1 ? parts.first[0] : '${parts.first[0]}${parts.last[0]}').toUpperCase();
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: AppColors.brand.withValues(alpha: 0.18),
      foregroundImage: url != null && url.startsWith('http') ? CachedNetworkImageProvider(url) : null,
      child: Text(initials,
          style: TextStyle(color: AppColors.brand, fontWeight: FontWeight.w800, fontSize: size * 0.36)),
    );
  }
}

class _AllAvatar extends StatelessWidget {
  const _AllAvatar();

  @override
  Widget build(BuildContext context) => CircleAvatar(
        radius: 18,
        backgroundColor: AppColors.brand.withValues(alpha: 0.18),
        child: const Icon(Icons.groups_rounded, color: AppColors.brand, size: 20),
      );
}
