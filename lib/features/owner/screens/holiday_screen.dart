import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_service.dart';
import '../../../core/utils/ui_feedback.dart';

final _apiDay = DateFormat('yyyy-MM-dd');

// Server weekday numbering: 0 = Sunday … 6 = Saturday.
const _weekdayNames = [(1, 'Mon'), (2, 'Tue'), (3, 'Wed'), (4, 'Thu'), (5, 'Fri'), (6, 'Sat'), (0, 'Sun')];

class _Holiday {
  final String? id; // null for weekly-off days, which are a setting rather than records
  final DateTime date;
  final String occasion;
  final bool weekly;
  const _Holiday(this.id, this.date, this.occasion, {this.weekly = false});

  factory _Holiday.fromJson(Map<String, dynamic> j) => _Holiday(
        j['_id']?.toString(),
        DateTime.parse(j['date'].toString()),
        (j['occasion'] ?? 'Holiday').toString(),
        weekly: j['weekly'] == true,
      );
}

/// Owner screen for organisation holidays: recurring weekly offs (e.g. every
/// Sunday) plus custom dated holidays. Only these days count as holidays in
/// attendance and the staff app.
class HolidayScreen extends ConsumerStatefulWidget {
  const HolidayScreen({super.key});

  @override
  ConsumerState<HolidayScreen> createState() => _HolidayScreenState();
}

class _HolidayScreenState extends ConsumerState<HolidayScreen> {
  late DateTime _month; // first day of the month shown in the calendar
  bool _calendarView = true;
  bool _loading = true;
  int? _loadedYear;
  Map<String, _Holiday> _byDate = {};
  Set<int> _weeklyOffs = {};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _load();
  }

  /// Custom (dated) holidays only, sorted.
  List<_Holiday> get _custom =>
      _byDate.values.where((h) => !h.weekly).toList()..sort((a, b) => a.date.compareTo(b.date));

  String get _weeklyLabel => _weeklyOffs.isEmpty
      ? 'Set Weekly Off'
      : 'Weekly Off: ${_weekdayNames.where((d) => _weeklyOffs.contains(d.$1)).map((d) => d.$2).join(', ')}';

  Future<void> _load() async {
    final year = _month.year;
    setState(() => _loading = true);
    try {
      final api = ref.read(apiServiceProvider);
      final results = await Future.wait([
        api.get('/holidays', params: {'from': '$year-01-01', 'to': '$year-12-31'}),
        api.get('/holidays/weekly-offs'),
      ]);
      final res = results[0];
      final offs = results[1].data['data']?['weeklyOffs'];
      if (res.data['success'] == true && mounted) {
        final rows = List<Map<String, dynamic>>.from(res.data['data'] ?? []);
        setState(() {
          _byDate = {for (final h in rows.map(_Holiday.fromJson)) _apiDay.format(h.date): h};
          _weeklyOffs = offs is List ? offs.map((d) => (d as num).toInt()).toSet() : {};
          _loadedYear = year;
        });
      }
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e, fallback: 'Could not load holidays.');
    }
    if (mounted) setState(() => _loading = false);
  }

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    if (_month.year != _loadedYear) _load();
  }

  void _shiftYear(int delta) {
    setState(() => _month = DateTime(_month.year + delta, _month.month));
    _load();
  }

  void _goToday() {
    final now = DateTime.now();
    setState(() => _month = DateTime(now.year, now.month));
    if (_month.year != _loadedYear) _load();
  }

  void _toast(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg), backgroundColor: AppColors.green));

  // ─── Actions ────────────────────────────────────────────────────────────

  Future<void> _openAdd([DateTime? date]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.dark2,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AddHolidaySheet(initialDate: date ?? DateTime.now()),
    );
    if (saved == true) _load();
  }

  Future<void> _openWeeklyOffs() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.dark2,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _WeeklyOffSheet(initial: _weeklyOffs),
    );
    if (saved == true) _load();
  }

  Future<void> _openHoliday(_Holiday h) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.dark2,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.celebration_outlined, color: AppColors.yellow),
              const SizedBox(width: 10),
              Expanded(
                child: Text(h.occasion,
                    style: const TextStyle(color: AppColors.white, fontSize: 17, fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 4),
            Text(DateFormat('EEEE, d MMM yyyy').format(h.date),
                style: const TextStyle(color: AppColors.silver, fontSize: 13)),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.edit_outlined, color: AppColors.brand),
              title: const Text('Edit', style: TextStyle(color: AppColors.white)),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.delete_outline, color: AppColors.red),
              title: const Text('Delete', style: TextStyle(color: AppColors.red)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ]),
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'edit') await _edit(h);
    if (action == 'delete') await _delete(h);
  }

  Future<void> _edit(_Holiday h) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.dark2,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AddHolidaySheet(initialDate: h.date, editing: h),
    );
    if (saved == true) _load();
  }

  Future<void> _delete(_Holiday h) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.dark2,
        title: const Text('Delete holiday?', style: TextStyle(color: AppColors.white)),
        content: Text('${h.occasion} on ${DateFormat('d MMM yyyy').format(h.date)} will be removed.',
            style: const TextStyle(color: AppColors.silver)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiServiceProvider).delete('/holidays/${h.id}');
      if (!mounted) return;
      _toast('Holiday deleted');
      _load();
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e, fallback: 'Could not delete holiday.');
    }
  }

  // ─── UI ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        titleSpacing: 0,
        title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Holiday', style: TextStyle(color: AppColors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          SizedBox(height: 2),
          Text('Home • Holiday', style: TextStyle(color: AppColors.silver, fontSize: 12)),
        ]),
        actions: [
          _viewToggle(Icons.calendar_month_outlined, _calendarView, () => setState(() => _calendarView = true)),
          _viewToggle(Icons.format_list_bulleted_rounded, !_calendarView, () => setState(() => _calendarView = false)),
          const SizedBox(width: 8),
        ],
        bottom: const PreferredSize(preferredSize: Size.fromHeight(1), child: Divider(height: 1, color: AppColors.border)),
      ),
      body: RefreshIndicator(
        color: AppColors.brand,
        backgroundColor: AppColors.dark2,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
          children: [
            Wrap(spacing: 10, runSpacing: 10, children: [
              ElevatedButton.icon(
                onPressed: () => _openAdd(),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 46),
                  backgroundColor: AppColors.brand,
                  foregroundColor: AppColors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('Add Holiday', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              OutlinedButton.icon(
                onPressed: _openWeeklyOffs,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 46),
                  foregroundColor: AppColors.white,
                  side: const BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.event_repeat_rounded, size: 20),
                label: Text(_weeklyLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ]),
            const SizedBox(height: 16),
            if (_loading && _byDate.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 60),
                child: Center(child: CircularProgressIndicator(color: AppColors.brand)),
              )
            else if (_calendarView) ...[
              _calendarCard(),
              const SizedBox(height: 16),
              _monthList(),
            ] else
              _yearList(),
          ],
        ),
      ),
    );
  }

  Widget _viewToggle(IconData icon, bool on, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Material(
          color: on ? AppColors.brand : AppColors.dark3,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: SizedBox(
              width: 40,
              height: 36,
              child: Icon(icon, size: 20, color: on ? AppColors.white : AppColors.silver),
            ),
          ),
        ),
      );

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.dark2,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: child,
      );

  Widget _navButton(IconData icon, VoidCallback onTap) => InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppColors.white, size: 20),
        ),
      );

  Widget _calendarCard() {
    final daysInMonth = DateUtils.getDaysInMonth(_month.year, _month.month);
    final leading = _month.weekday - 1; // Monday-first grid
    final cells = <DateTime?>[
      for (var i = 0; i < leading; i++) null,
      for (var d = 1; d <= daysInMonth; d++) DateTime(_month.year, _month.month, d),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    final today = DateUtils.dateOnly(DateTime.now());
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return _card(
      child: Column(children: [
        Row(children: [
          _navButton(Icons.chevron_left_rounded, () => _shiftMonth(-1)),
          const SizedBox(width: 6),
          _navButton(Icons.chevron_right_rounded, () => _shiftMonth(1)),
          Expanded(
            child: Text(DateFormat('MMMM yyyy').format(_month),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 15)),
          ),
          TextButton(onPressed: _goToday, child: const Text('Today')),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          for (final w in weekdays)
            Expanded(
              child: Center(
                child: Text(w,
                    style: const TextStyle(color: AppColors.silver, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ),
        ]),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          childAspectRatio: 0.72,
          children: [
            for (final d in cells)
              if (d == null) const SizedBox() else _dayCell(d, isToday: d == today),
          ],
        ),
      ]),
    );
  }

  Widget _dayCell(DateTime d, {required bool isToday}) {
    final h = _byDate[_apiDay.format(d)];
    final weekly = h?.weekly ?? false;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => h != null && !weekly ? _openHoliday(h) : _openAdd(d),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: h == null
              ? AppColors.dark3
              : AppColors.yellow.withValues(alpha: weekly ? 0.05 : 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isToday
                ? AppColors.brand
                : (h == null ? AppColors.border : AppColors.yellow.withValues(alpha: weekly ? 0.25 : 0.5)),
            width: isToday ? 1.5 : 1,
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${d.day}',
              style: TextStyle(
                color: h != null ? AppColors.yellow : AppColors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              )),
          if (h != null) ...[
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: Text(weekly ? 'Weekly Off' : h.occasion,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.yellow.withValues(alpha: weekly ? 0.6 : 1),
                    fontSize: 8.5,
                    height: 1.15,
                  )),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _monthList() {
    final items = _custom.where((h) => h.date.year == _month.year && h.date.month == _month.month).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('HOLIDAYS IN ${DateFormat('MMMM').format(_month).toUpperCase()}',
          style: const TextStyle(color: AppColors.silver, fontSize: 12, letterSpacing: 1, fontWeight: FontWeight.w600)),
      const SizedBox(height: 10),
      if (items.isEmpty) _empty('No custom holidays this month') else ...items.map(_holidayTile),
    ]);
  }

  Widget _yearList() {
    final items = _custom;
    final byMonth = <int, List<_Holiday>>{};
    for (final h in items) {
      byMonth.putIfAbsent(h.date.month, () => []).add(h);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        _navButton(Icons.chevron_left_rounded, () => _shiftYear(-1)),
        Expanded(
          child: Text('${_month.year}  ·  ${items.length} holiday${items.length == 1 ? '' : 's'}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 15)),
        ),
        _navButton(Icons.chevron_right_rounded, () => _shiftYear(1)),
      ]),
      const SizedBox(height: 16),
      _weeklySummary(),
      const SizedBox(height: 16),
      if (items.isEmpty) _empty('No custom holidays added for ${_month.year}'),
      for (final entry in byMonth.entries) ...[
        Text(DateFormat('MMMM').format(DateTime(_month.year, entry.key)).toUpperCase(),
            style: const TextStyle(color: AppColors.silver, fontSize: 12, letterSpacing: 1, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        ...entry.value.map(_holidayTile),
        const SizedBox(height: 10),
      ],
    ]);
  }

  Widget _weeklySummary() => Container(
        decoration: BoxDecoration(
          color: AppColors.dark2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: ListTile(
          onTap: _openWeeklyOffs,
          leading: const Icon(Icons.event_repeat_rounded, color: AppColors.yellow),
          title: const Text('Weekly Off', style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w600)),
          subtitle: Text(
            _weeklyOffs.isEmpty ? 'Not set — every day is a working day' : 'Every ${_weeklyLabel.substring(12)}',
            style: const TextStyle(color: AppColors.silver, fontSize: 12),
          ),
          trailing: const Icon(Icons.edit_outlined, color: AppColors.silver, size: 20),
        ),
      );

  Widget _holidayTile(_Holiday h) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppColors.dark2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: ListTile(
          onTap: () => _openHoliday(h),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.yellow.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('${h.date.day}',
                  style: const TextStyle(color: AppColors.yellow, fontWeight: FontWeight.w800, fontSize: 15)),
              Text(DateFormat('EEE').format(h.date),
                  style: const TextStyle(color: AppColors.yellow, fontSize: 10)),
            ]),
          ),
          title: Text(h.occasion, style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w600)),
          subtitle: Text(DateFormat('d MMM yyyy').format(h.date),
              style: const TextStyle(color: AppColors.silver, fontSize: 12)),
          trailing: const Icon(Icons.more_vert_rounded, color: AppColors.silver),
        ),
      );

  Widget _empty(String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 28),
        decoration: BoxDecoration(
          color: AppColors.dark2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(children: [
          const Icon(Icons.event_available_outlined, color: AppColors.muted, size: 36),
          const SizedBox(height: 8),
          Text(text, style: const TextStyle(color: AppColors.silver)),
        ]),
      );
}

// ─── Shared form bits ────────────────────────────────────────────────────

InputDecoration _input(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.muted),
      filled: true,
      fillColor: AppColors.dark3,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
      enabledBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
      focusedBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.brand)),
    );

Widget _label(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text.rich(TextSpan(children: [
        TextSpan(text: text, style: const TextStyle(color: AppColors.silver, fontSize: 12)),
        const TextSpan(text: ' *', style: TextStyle(color: AppColors.red, fontSize: 12)),
      ])),
    );

Future<DateTime?> _pickDate(BuildContext context, DateTime initial) => showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

Widget _dateField(BuildContext context, DateTime value, ValueChanged<DateTime> onChanged) => InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        final picked = await _pickDate(context, value);
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: _input('').copyWith(
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18, color: AppColors.silver),
        ),
        child: Text(DateFormat('dd-MM-yyyy').format(value), style: const TextStyle(color: AppColors.white)),
      ),
    );

Widget _sheetHeader(BuildContext context, String title) => Column(children: [
      Center(
        child: Container(
          width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
        ),
      ),
      Row(children: [
        Expanded(
          child: Text(title, style: const TextStyle(color: AppColors.white, fontSize: 18, fontWeight: FontWeight.w700)),
        ),
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close_rounded, color: AppColors.silver),
        ),
      ]),
      const Divider(color: AppColors.border, height: 20),
    ]);

Widget _saveRow(BuildContext context, {required bool saving, required VoidCallback onSave}) => Row(children: [
      ElevatedButton.icon(
        onPressed: saving ? null : onSave,
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(0, 46),
          backgroundColor: AppColors.brand,
          foregroundColor: AppColors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        icon: saving
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white))
            : const Icon(Icons.check_rounded, size: 20),
        label: const Text('Save', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      const SizedBox(width: 12),
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel', style: TextStyle(color: AppColors.silver)),
      ),
    ]);

// ─── Add / edit holiday ──────────────────────────────────────────────────

class _Row {
  DateTime date;
  final TextEditingController occasion;
  _Row(this.date, [String text = '']) : occasion = TextEditingController(text: text);
}

class _AddHolidaySheet extends ConsumerStatefulWidget {
  final DateTime initialDate;
  final _Holiday? editing;
  const _AddHolidaySheet({required this.initialDate, this.editing});

  @override
  ConsumerState<_AddHolidaySheet> createState() => _AddHolidaySheetState();
}

class _AddHolidaySheetState extends ConsumerState<_AddHolidaySheet> {
  late final List<_Row> _rows;
  bool _saving = false;

  bool get _isEdit => widget.editing != null;

  @override
  void initState() {
    super.initState();
    _rows = [_Row(DateUtils.dateOnly(widget.initialDate), widget.editing?.occasion ?? '')];
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.occasion.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_rows.any((r) => r.occasion.text.trim().isEmpty)) {
      showErrorSnackBar(context, 'Occasion is required', fallback: 'Occasion is required');
      return;
    }
    setState(() => _saving = true);
    try {
      final api = ref.read(apiServiceProvider);
      if (_isEdit) {
        await api.put('/holidays/${widget.editing!.id}', data: {
          'date': _apiDay.format(_rows.first.date),
          'occasion': _rows.first.occasion.text.trim(),
        });
      } else {
        await api.post('/holidays', data: {
          'holidays': [
            for (final r in _rows) {'date': _apiDay.format(r.date), 'occasion': r.occasion.text.trim()},
          ],
        });
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_isEdit ? 'Holiday updated' : 'Holiday saved'),
        backgroundColor: AppColors.green,
      ));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showErrorSnackBar(context, e, fallback: 'Could not save holiday.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _sheetHeader(context, _isEdit ? 'Edit Holiday' : 'Add Holiday'),
            for (var i = 0; i < _rows.length; i++) _rowFields(i),
            if (!_isEdit)
              TextButton.icon(
                onPressed: () => setState(() => _rows.add(_Row(_rows.last.date.add(const Duration(days: 1))))),
                icon: const Icon(Icons.add_circle_outline, color: AppColors.brand),
                label: const Text('Add', style: TextStyle(color: AppColors.brand, fontWeight: FontWeight.w600)),
              ),
            const Divider(color: AppColors.border, height: 24),
            _saveRow(context, saving: _saving, onSave: _save),
          ]),
        ),
      ),
    );
  }

  Widget _rowFields(int i) {
    final r = _rows[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          flex: 5,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _label('Date'),
            _dateField(context, r.date, (d) => setState(() => r.date = d)),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 6,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _label('Occasion'),
            TextField(
              controller: r.occasion,
              maxLength: 80,
              textCapitalization: TextCapitalization.words,
              style: const TextStyle(color: AppColors.white),
              decoration: _input('Occasion').copyWith(counterText: ''),
            ),
          ]),
        ),
        if (_rows.length > 1)
          IconButton(
            onPressed: () => setState(() => _rows.removeAt(i).occasion.dispose()),
            icon: const Icon(Icons.remove_circle_outline, color: AppColors.red),
          ),
      ]),
    );
  }
}

// ─── Weekly off days ─────────────────────────────────────────────────────

class _WeeklyOffSheet extends ConsumerStatefulWidget {
  final Set<int> initial;
  const _WeeklyOffSheet({required this.initial});

  @override
  ConsumerState<_WeeklyOffSheet> createState() => _WeeklyOffSheetState();
}

class _WeeklyOffSheetState extends ConsumerState<_WeeklyOffSheet> {
  late final Set<int> _selected = {...widget.initial};
  bool _saving = false;

  Future<void> _save() async {
    if (_selected.length == 7) {
      showErrorSnackBar(context, 'At least one working day is required', fallback: 'Invalid selection');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(apiServiceProvider).put('/holidays/weekly-offs', data: {'weekdays': _selected.toList()});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Weekly off days saved'), backgroundColor: AppColors.green));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showErrorSnackBar(context, e, fallback: 'Could not save weekly off days.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sheetHeader(context, 'Weekly Off'),
          const Text(
              'The selected days are holidays every week, with no end date. '
              'Add custom holidays (festivals etc.) separately with Add Holiday.',
              style: TextStyle(color: AppColors.silver, fontSize: 12)),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (n, name) in _weekdayNames)
              FilterChip(
                label: Text(name),
                selected: _selected.contains(n),
                onSelected: (on) => setState(() => on ? _selected.add(n) : _selected.remove(n)),
                showCheckmark: false,
                backgroundColor: AppColors.dark3,
                selectedColor: AppColors.brand,
                side: BorderSide(color: _selected.contains(n) ? AppColors.brand : AppColors.border),
                labelStyle: TextStyle(color: _selected.contains(n) ? AppColors.white : AppColors.silver),
              ),
          ]),
          const SizedBox(height: 8),
          Text(
            _selected.isEmpty ? 'No weekly off — every day is a working day.' : '',
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          const Divider(color: AppColors.border, height: 24),
          _saveRow(context, saving: _saving, onSave: _save),
        ]),
      ),
    );
  }
}
