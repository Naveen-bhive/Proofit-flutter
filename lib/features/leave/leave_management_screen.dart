import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_colors.dart';
import '../../core/network/api_service.dart';
import '../../core/utils/ui_feedback.dart';
import 'leave_common.dart';
import 'new_leave_screen.dart';

/// Owner: "Leaves" management table for the whole organisation.
/// Staff:  the same screen scoped to their own leave requests.
class LeaveManagementScreen extends ConsumerStatefulWidget {
  final bool isOwner;
  const LeaveManagementScreen({super.key, required this.isOwner});

  @override
  ConsumerState<LeaveManagementScreen> createState() => _LeaveManagementScreenState();
}

class _LeaveManagementScreenState extends ConsumerState<LeaveManagementScreen> {
  final _searchCtrl = TextEditingController();
  final _apiDay = DateFormat('yyyy-MM-dd');
  Timer? _debounce;

  List<LeaveRecord> _leaves = [];
  List<LeaveType> _types = [];
  List<LeaveMember> _members = [];
  bool _loading = true;
  bool _exporting = false;
  int _page = 1;
  int _pageSize = 10;
  int _total = 0;
  final Set<String> _selected = {};

  // Filters
  DateTimeRange? _range;
  String? _staffId;
  Set<String> _typeIds = {};
  Set<String> _statuses = {};
  bool _halfDay = false;

  int get _pages => (_total / _pageSize).ceil().clamp(1, 1 << 30);
  int get _activeFilterCount =>
      (_staffId != null ? 1 : 0) + (_typeIds.isNotEmpty ? 1 : 0) + (_statuses.isNotEmpty ? 1 : 0);

  @override
  void initState() {
    super.initState();
    _loadTypes();
    if (widget.isOwner) _loadMembers();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTypes() async {
    try {
      final res = await ref.read(apiServiceProvider).get('/leaves/types');
      if (res.data['success'] == true && mounted) {
        setState(() => _types = List<Map<String, dynamic>>.from(res.data['data']).map(LeaveType.fromJson).toList());
      }
    } catch (_) {}
  }

  Future<void> _loadMembers() async {
    try {
      final res = await ref.read(apiServiceProvider).get('/staff');
      if (res.data['success'] == true && mounted) {
        final rows = List<Map<String, dynamic>>.from(res.data['data'] ?? []);
        setState(() => _members = rows.where((r) => r['kind'] != 'invite').map(LeaveMember.fromJson).toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())));
      }
    } catch (_) {}
  }

  Map<String, dynamic> _query({int? page, int? limit}) => {
        'page': '${page ?? _page}',
        'limit': '${limit ?? _pageSize}',
        if (_searchCtrl.text.trim().isNotEmpty) 'search': _searchCtrl.text.trim(),
        if (_range != null) 'from': _apiDay.format(_range!.start),
        if (_range != null) 'to': _apiDay.format(_range!.end),
        if (_staffId != null) 'staffId': _staffId!,
        if (_typeIds.isNotEmpty) 'leaveTypeId': _typeIds.join(','),
        if (_statuses.isNotEmpty) 'status': _statuses.join(','),
        if (_halfDay) 'halfDay': 'true',
      };

  Future<void> _load({bool resetPage = false}) async {
    if (resetPage) _page = 1;
    setState(() => _loading = true);
    try {
      final res = await ref.read(apiServiceProvider).get('/leaves', params: _query());
      if (res.data['success'] == true && mounted) {
        final data = res.data['data'];
        setState(() {
          _leaves = List<Map<String, dynamic>>.from(data['leaves'] ?? []).map(LeaveRecord.fromJson).toList();
          _total = (data['pagination']?['total'] as num?)?.toInt() ?? _leaves.length;
          _selected.removeWhere((id) => !_leaves.any((l) => l.id == id));
        });
      }
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e, fallback: 'Could not load leaves.');
    }
    if (mounted) setState(() => _loading = false);
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _load(resetPage: true));
  }

  // ─── Actions ────────────────────────────────────────────────────────────

  Future<void> _openNewLeave() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => NewLeaveScreen(isOwner: widget.isOwner), fullscreenDialog: true),
    );
    if (saved == true) _load(resetPage: true);
  }

  Future<void> _setStatus(List<String> ids, String status) async {
    try {
      final res = await ref.read(apiServiceProvider).put('/leaves/status', data: {'ids': ids, 'status': status});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res.data['message']?.toString() ?? 'Updated'),
        backgroundColor: leaveStatusColor(status),
      ));
      _selected.clear();
      _load();
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e, fallback: 'Could not update leave.');
    }
  }

  Future<void> _delete(LeaveRecord l) async {
    final isOwner = widget.isOwner;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.dark2,
        title: Text(isOwner ? 'Delete leave?' : 'Cancel request?', style: const TextStyle(color: AppColors.white)),
        content: Text(
          isOwner ? 'This leave record will be removed permanently.' : 'Your leave request will be withdrawn.',
          style: const TextStyle(color: AppColors.silver),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isOwner ? 'Delete' : 'Cancel Request', style: const TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiServiceProvider).delete('/leaves/${l.id}');
      _load();
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e, fallback: 'Could not remove leave.');
    }
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _range,
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: AppColors.brand)),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _range = picked);
      _load(resetPage: true);
    }
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final res = await ref.read(apiServiceProvider).get('/leaves', params: _query(page: 1, limit: 1000));
      final rows = List<Map<String, dynamic>>.from(res.data['data']['leaves'] ?? []).map(LeaveRecord.fromJson);
      String esc(Object? v) => '"${(v ?? '').toString().replaceAll('"', '""')}"';
      final buf = StringBuffer()
        ..writeln(['Employee', 'Phone', 'Leave Type', 'Duration', 'Start Date', 'End Date', 'Days', 'Status', 'Reason', 'Attachment']
            .map(esc)
            .join(','));
      for (final l in rows) {
        buf.writeln([
          l.staff?.name, l.staff?.phone, l.leaveTypeName, leaveDurations[l.duration],
          _apiDay.format(l.start), _apiDay.format(l.end), l.days, leaveStatuses[l.status], l.reason, l.attachmentUrl,
        ].map(esc).join(','));
      }
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/leaves-${_apiDay.format(DateTime.now())}.csv');
      await file.writeAsString(buf.toString());
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], subject: 'Leave Records'));
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e, fallback: 'Could not export leaves.');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // ─── Quick chips ────────────────────────────────────────────────────────

  String? get _activeChip {
    if (_halfDay && _statuses.isEmpty) return 'half';
    if (!_halfDay && _statuses.length == 1) return _statuses.first;
    if (!_halfDay && _statuses.isEmpty) return 'all';
    return null;
  }

  void _applyChip(String chip) {
    setState(() {
      _halfDay = chip == 'half';
      _statuses = switch (chip) { 'all' || 'half' => {}, _ => {chip} };
    });
    _load(resetPage: true);
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.isOwner ? 'Leave Management' : 'My Leaves',
              style: const TextStyle(color: AppColors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          const Text('Home • Leaves', style: TextStyle(color: AppColors.silver, fontSize: 12)),
        ]),
        bottom: const PreferredSize(preferredSize: Size.fromHeight(1), child: Divider(height: 1, color: AppColors.border)),
      ),
      body: RefreshIndicator(
        color: AppColors.brand,
        backgroundColor: AppColors.dark2,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
          children: [
            _durationRow(),
            const SizedBox(height: 14),
            _searchRow(),
            const SizedBox(height: 12),
            _chips(),
            const SizedBox(height: 18),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              const Text('Leaves', style: TextStyle(color: AppColors.white, fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(width: 10),
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text('Home · Leaves', style: TextStyle(color: AppColors.muted, fontSize: 12)),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('$_total total', style: const TextStyle(color: AppColors.silver, fontSize: 12)),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              ElevatedButton.icon(
                onPressed: _openNewLeave,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brand,
                  foregroundColor: AppColors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.add_rounded, size: 20),
                label: Text(widget.isOwner ? 'New Leave' : 'Request Leave',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _exporting ? null : _export,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.white,
                  side: const BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: _exporting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brand))
                    : const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('Export'),
              ),
            ]),
            if (widget.isOwner && _selected.isNotEmpty) ...[
              const SizedBox(height: 12),
              _bulkBar(),
            ],
            const SizedBox(height: 18),
            _table(),
          ],
        ),
      ),
    );
  }

  Widget _durationRow() {
    final fmt = DateFormat('d MMM yyyy');
    return Row(children: [
      const Text('Duration', style: TextStyle(color: AppColors.silver, fontSize: 13)),
      const SizedBox(width: 10),
      Expanded(
        child: InkWell(
          onTap: _pickRange,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              const Icon(Icons.date_range_outlined, color: AppColors.brand, size: 16),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  _range == null ? 'Start Date To End Date' : '${fmt.format(_range!.start)}  To  ${fmt.format(_range!.end)}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _range == null ? AppColors.light : AppColors.brand,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
      if (_range != null)
        InkWell(
          onTap: () {
            setState(() => _range = null);
            _load(resetPage: true);
          },
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(Icons.close_rounded, color: AppColors.silver, size: 18),
          ),
        ),
    ]);
  }

  Widget _searchRow() => Row(children: [
        Expanded(
          child: SizedBox(
            height: 46,
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              style: const TextStyle(color: AppColors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Start typing to search...',
                hintStyle: const TextStyle(color: AppColors.muted, fontSize: 14),
                prefixIcon: const Icon(Icons.search_rounded, color: AppColors.silver, size: 20),
                filled: true,
                fillColor: AppColors.dark2,
                contentPadding: EdgeInsets.zero,
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.brand)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        InkWell(
          onTap: _openFilters,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: _activeFilterCount > 0 ? AppColors.brand.withValues(alpha: 0.12) : AppColors.dark2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _activeFilterCount > 0 ? AppColors.brand : AppColors.border),
            ),
            child: Row(children: [
              Icon(Icons.filter_alt_outlined,
                  size: 18, color: _activeFilterCount > 0 ? AppColors.brand : AppColors.light),
              const SizedBox(width: 6),
              Text(_activeFilterCount > 0 ? 'Filters ($_activeFilterCount)' : 'Filters',
                  style: TextStyle(
                    color: _activeFilterCount > 0 ? AppColors.brand : AppColors.light,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  )),
            ]),
          ),
        ),
      ]);

  Widget _chips() {
    const chips = [('all', 'All Leaves'), ('half', 'Half Day'), ('approved', 'Approved'), ('pending', 'Pending'), ('rejected', 'Rejected')];
    final active = _activeChip;
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final (key, label) = chips[i];
          final on = active == key;
          return InkWell(
            onTap: () => _applyChip(key),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? AppColors.brand : AppColors.dark2,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: on ? AppColors.brand : AppColors.border),
              ),
              child: Text(label,
                  style: TextStyle(
                    color: on ? AppColors.white : AppColors.light,
                    fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 13,
                  )),
            ),
          );
        },
      ),
    );
  }

  Widget _bulkBar() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.brand.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.brand.withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          Expanded(
            child: Text('${_selected.length} selected',
                style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
          ),
          TextButton(
            onPressed: () => _setStatus(_selected.toList(), 'approved'),
            child: const Text('Approve', style: TextStyle(color: AppColors.green, fontWeight: FontWeight.w700)),
          ),
          TextButton(
            onPressed: () => _setStatus(_selected.toList(), 'rejected'),
            child: const Text('Reject', style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w700)),
          ),
        ]),
      );

  // ─── Table ──────────────────────────────────────────────────────────────

  static const _rowHeight = 68.0;
  static const _headerHeight = 48.0;

  Widget _table() {
    final isOwner = widget.isOwner;
    final columns = <(String, double)>[
      ('Leave Type', 120),
      ('Date', isOwner ? 190 : 170),
      ('Days', 80),
      ('Duration', 110),
      ('Status', 120),
      ('Reason', 180),
      ('Actions', isOwner ? 120 : 80),
    ];
    final leftWidth = isOwner ? 190.0 : 110.0;
    final allSelected = _leaves.isNotEmpty && _leaves.every((l) => _selected.contains(l.id));

    Widget headerCell(String text) => Text(text,
        style: const TextStyle(color: AppColors.silver, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.3));
    const rowBorder = BoxDecoration(border: Border(top: BorderSide(color: AppColors.border)));

    return Container(
      decoration: BoxDecoration(
        color: AppColors.dark2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(children: [
          if (_loading)
            const SizedBox(height: 220, child: Center(child: CircularProgressIndicator(color: AppColors.brand)))
          else if (_leaves.isEmpty)
            SizedBox(
              height: 220,
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.event_available_outlined, color: AppColors.muted, size: 44),
                  const SizedBox(height: 10),
                  Text(isOwner ? 'No leave records found' : 'No leave requests yet',
                      style: const TextStyle(color: AppColors.silver)),
                ]),
              ),
            )
          else
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Fixed first column.
              SizedBox(
                width: leftWidth,
                child: Column(children: [
                  Container(
                    height: _headerHeight,
                    color: AppColors.dark3,
                    padding: const EdgeInsets.only(left: 6),
                    child: Row(children: [
                      if (isOwner)
                        _checkbox(allSelected, (v) => setState(() {
                              if (v) {
                                _selected.addAll(_leaves.map((l) => l.id));
                              } else {
                                _selected.clear();
                              }
                            })),
                      Padding(
                        padding: EdgeInsets.only(left: isOwner ? 4 : 10),
                        child: headerCell(isOwner ? 'Employee' : 'Applied'),
                      ),
                    ]),
                  ),
                  for (final l in _leaves)
                    InkWell(
                      onTap: () => _showDetails(l),
                      child: Container(
                        height: _rowHeight,
                        decoration: rowBorder,
                        padding: const EdgeInsets.only(left: 6, right: 6),
                        child: isOwner
                            ? Row(children: [
                                _checkbox(_selected.contains(l.id), (v) => setState(() {
                                      v ? _selected.add(l.id) : _selected.remove(l.id);
                                    })),
                                const SizedBox(width: 4),
                                LeaveAvatar(name: l.staff?.name ?? '?', photoUrl: l.staff?.photoUrl, size: 34),
                                const SizedBox(width: 8),
                                Expanded(child: _twoLine(l.staff?.name ?? 'Removed staff', l.staff?.phone ?? '')),
                              ])
                            : Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: _twoLine(
                                  l.createdAt != null ? DateFormat('d MMM').format(l.createdAt!) : '—',
                                  l.createdAt != null ? DateFormat('h:mm a').format(l.createdAt!) : '',
                                ),
                              ),
                      ),
                    ),
                ]),
              ),
              // Scrollable columns.
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      height: _headerHeight,
                      color: AppColors.dark3,
                      child: Row(children: [
                        for (final (label, w) in columns)
                          SizedBox(width: w, child: Padding(padding: const EdgeInsets.only(left: 8), child: headerCell(label))),
                      ]),
                    ),
                    for (final l in _leaves)
                      InkWell(
                        onTap: () => _showDetails(l),
                        child: Container(
                          height: _rowHeight,
                          decoration: rowBorder,
                          child: Row(children: [
                            _cell(columns[0].$2, _typeLabel(l)),
                            _cell(columns[1].$2, Text(l.dateLabel, style: const TextStyle(color: AppColors.light, fontSize: 13))),
                            _cell(columns[2].$2, Text(l.daysLabel, style: const TextStyle(color: AppColors.light, fontSize: 13))),
                            _cell(columns[3].$2,
                                Text(leaveDurations[l.duration] ?? l.duration, style: const TextStyle(color: AppColors.light, fontSize: 13))),
                            _cell(columns[4].$2, Align(alignment: Alignment.centerLeft, child: LeaveStatusBadge(l.status))),
                            _cell(columns[5].$2, Text(l.reason,
                                maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.silver, fontSize: 12.5))),
                            _cell(columns[6].$2, _rowActions(l)),
                          ]),
                        ),
                      ),
                  ]),
                ),
              ),
            ]),
          _pager(),
        ]),
      ),
    );
  }

  Widget _checkbox(bool value, ValueChanged<bool> onChanged) => SizedBox(
        width: 32,
        child: Checkbox(
          value: value,
          onChanged: (v) => onChanged(v ?? false),
          activeColor: AppColors.brand,
          side: const BorderSide(color: AppColors.muted, width: 1.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
      );

  Widget _twoLine(String title, String subtitle) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 13.5)),
          if (subtitle.isNotEmpty)
            Text(subtitle,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.silver, fontSize: 11)),
        ],
      );

  Widget _cell(double width, Widget child) => SizedBox(
        width: width,
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Align(alignment: Alignment.centerLeft, child: child)),
      );

  Widget _typeLabel(LeaveRecord l) {
    final color = _types.where((t) => t.id == l.leaveTypeId).firstOrNull?.color ?? AppColors.brand;
    return Row(children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Flexible(
        child: Text(l.leaveTypeName,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.white, fontSize: 13, fontWeight: FontWeight.w600)),
      ),
    ]);
  }

  Widget _rowActions(LeaveRecord l) {
    Widget btn(IconData icon, Color c, String tip, VoidCallback onTap) => Tooltip(
          message: tip,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 32, height: 32,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: c, size: 18),
            ),
          ),
        );
    if (widget.isOwner) {
      return Row(children: [
        if (l.status != 'approved') btn(Icons.check_rounded, AppColors.green, 'Approve', () => _setStatus([l.id], 'approved')),
        if (l.status != 'rejected') btn(Icons.close_rounded, AppColors.red, 'Reject', () => _setStatus([l.id], 'rejected')),
        btn(Icons.more_horiz_rounded, AppColors.silver, 'Details', () => _showDetails(l)),
      ]);
    }
    return Row(children: [
      if (l.status == 'pending') btn(Icons.undo_rounded, AppColors.red, 'Cancel request', () => _delete(l)),
      btn(Icons.visibility_outlined, AppColors.silver, 'Details', () => _showDetails(l)),
    ]);
  }

  Widget _pager() {
    final from = _total == 0 ? 0 : (_page - 1) * _pageSize + 1;
    final to = ((_page - 1) * _pageSize + _leaves.length);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
      child: Row(children: [
        const Text('Show', style: TextStyle(color: AppColors.silver, fontSize: 13)),
        const SizedBox(width: 8),
        Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: AppColors.dark3,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _pageSize,
              dropdownColor: AppColors.dark3,
              iconEnabledColor: AppColors.silver,
              style: const TextStyle(color: AppColors.white, fontSize: 13),
              items: const [10, 25, 50, 100].map((n) => DropdownMenuItem(value: n, child: Text('$n'))).toList(),
              onChanged: (n) {
                if (n == null) return;
                setState(() => _pageSize = n);
                _load(resetPage: true);
              },
            ),
          ),
        ),
        const SizedBox(width: 8),
        const Text('entries', style: TextStyle(color: AppColors.silver, fontSize: 13)),
        const Spacer(),
        Text('$from–$to of $_total', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: _page > 1 && !_loading
              ? () {
                  _page--;
                  _load();
                }
              : null,
          icon: const Icon(Icons.chevron_left_rounded),
          color: AppColors.white,
          disabledColor: AppColors.dark4,
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: _page < _pages && !_loading
              ? () {
                  _page++;
                  _load();
                }
              : null,
          icon: const Icon(Icons.chevron_right_rounded),
          color: AppColors.white,
          disabledColor: AppColors.dark4,
        ),
      ]),
    );
  }

  // ─── Details sheet ──────────────────────────────────────────────────────

  void _showDetails(LeaveRecord l) {
    final isOwner = widget.isOwner;
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 96, child: Text(k, style: const TextStyle(color: AppColors.silver, fontSize: 13))),
            Expanded(child: Text(v, style: const TextStyle(color: AppColors.white, fontSize: 13.5, fontWeight: FontWeight.w500))),
          ]),
        );

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.dark2,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Center(child: SheetHandle()),
            Row(children: [
              LeaveAvatar(name: l.staff?.name ?? '?', photoUrl: l.staff?.photoUrl, size: 44),
              const SizedBox(width: 12),
              Expanded(child: _twoLine(l.staff?.name ?? 'Leave', l.staff?.phone ?? '')),
              LeaveStatusBadge(l.status),
            ]),
            const SizedBox(height: 16),
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 16),
            row('Leave Type', l.leaveTypeName),
            row('Duration', leaveDurations[l.duration] ?? l.duration),
            row('Date', l.dateLabel),
            row('Days', l.daysLabel),
            row('Reason', l.reason),
            if (l.createdAt != null) row('Applied', DateFormat('d MMM yyyy, h:mm a').format(l.createdAt!)),
            if (l.reviewedBy != null) row('Reviewed by', l.reviewedBy!),
            if (l.attachmentUrl != null) ...[
              const SizedBox(height: 4),
              const Text('Attachment', style: TextStyle(color: AppColors.silver, fontSize: 13)),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => launchUrl(Uri.parse(l.attachmentUrl!), mode: LaunchMode.externalApplication),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    l.attachmentUrl!,
                    height: 160,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      height: 60,
                      color: AppColors.dark3,
                      alignment: Alignment.center,
                      child: const Text('Open attachment', style: TextStyle(color: AppColors.brand)),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            if (isOwner)
              Row(children: [
                if (l.status != 'rejected' && l.status != 'cancelled')
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _setStatus([l.id], 'rejected');
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.red,
                        side: const BorderSide(color: AppColors.red),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Reject', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                if (l.status != 'rejected' && l.status != 'approved' && l.status != 'cancelled') const SizedBox(width: 10),
                if (l.status != 'approved' && l.status != 'cancelled')
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _setStatus([l.id], 'approved');
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.green,
                        foregroundColor: AppColors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Approve', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
              ]),
            const SizedBox(height: 6),
            if (isOwner || l.status == 'pending')
              Center(
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _delete(l);
                  },
                  icon: Icon(isOwner ? Icons.delete_outline_rounded : Icons.undo_rounded, color: AppColors.red, size: 18),
                  label: Text(isOwner ? 'Delete leave' : 'Cancel request', style: const TextStyle(color: AppColors.red)),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  // ─── Filter sheet ───────────────────────────────────────────────────────

  Future<void> _openFilters() async {
    String? staffId = _staffId;
    final typeIds = {..._typeIds};
    final statuses = {..._statuses};

    final applied = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.dark2,
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Widget sectionLabel(String text, {String? hint}) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  Expanded(
                    child: Text(text, style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                  ),
                  if (hint != null) Text(hint, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                ]),
              );

          final member = _members.where((m) => m.id == staffId).firstOrNull;
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const SheetHandle(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Row(children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                          color: AppColors.brand.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.filter_alt_outlined, color: AppColors.brand, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Filter Leaves', style: TextStyle(color: AppColors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                        SizedBox(height: 2),
                        Text('Refine leave records & approvals', style: TextStyle(color: AppColors.silver, fontSize: 12)),
                      ]),
                    ),
                  ]),
                ),
                const Divider(height: 1, color: AppColors.border),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (widget.isOwner) ...[
                        sectionLabel('Employee'),
                        LeaveSelectBox(
                          value: member?.name ?? 'All',
                          leading: member == null ? null : LeaveAvatar(name: member.name, photoUrl: member.photoUrl, size: 26),
                          onTap: () async {
                            final picked = await showLeavePicker<String>(
                              ctx,
                              title: 'Employee',
                              values: ['', ..._members.map((m) => m.id)],
                              current: staffId ?? '',
                              label: (id) => id.isEmpty ? 'All' : _members.firstWhere((m) => m.id == id).name,
                              subtitle: (id) => id.isEmpty ? 'Every employee' : _members.firstWhere((m) => m.id == id).phone,
                            );
                            if (picked != null) setSheet(() => staffId = picked.isEmpty ? null : picked);
                          },
                        ),
                        const SizedBox(height: 20),
                      ],
                      sectionLabel('Leave Type', hint: 'Multi-select allowed'),
                      LayoutBuilder(builder: (_, c) {
                        final w = (c.maxWidth - 16) / 3;
                        return Wrap(spacing: 8, runSpacing: 8, children: [
                          for (final t in _types)
                            _typeCard(t, typeIds.contains(t.id), w, () => setSheet(() {
                                  typeIds.contains(t.id) ? typeIds.remove(t.id) : typeIds.add(t.id);
                                })),
                        ]);
                      }),
                      const SizedBox(height: 20),
                      sectionLabel('Approval Status'),
                      Row(children: [
                        for (final s in const ['approved', 'pending', 'rejected']) ...[
                          Expanded(
                            child: _statusToggle(s, statuses.contains(s), () => setSheet(() {
                                  statuses.contains(s) ? statuses.remove(s) : statuses.add(s);
                                })),
                          ),
                          if (s != 'rejected') const SizedBox(width: 8),
                        ],
                      ]),
                    ]),
                  ),
                ),
                const Divider(height: 1, color: AppColors.border),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  child: Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => setSheet(() {
                          staffId = null;
                          typeIds.clear();
                          statuses.clear();
                        }),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.white,
                          side: const BorderSide(color: AppColors.border),
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Reset Filters', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 3,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brand,
                          foregroundColor: AppColors.white,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Apply Filters', style: TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
          );
        },
      ),
    );

    if (applied == true) {
      setState(() {
        _staffId = staffId;
        _typeIds = typeIds;
        _statuses = statuses;
        if (statuses.isNotEmpty) _halfDay = false;
      });
      _load(resetPage: true);
    }
  }

  Widget _typeCard(LeaveType t, bool on, double width, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: width,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          decoration: BoxDecoration(
            color: on ? t.color.withValues(alpha: 0.14) : AppColors.dark3,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: on ? t.color : AppColors.border, width: on ? 1.5 : 1),
          ),
          child: Column(children: [
            Container(width: 9, height: 9, decoration: BoxDecoration(color: t.color, shape: BoxShape.circle)),
            const SizedBox(height: 8),
            Text(t.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: on ? t.color : AppColors.white, fontWeight: FontWeight.w700, fontSize: 13.5)),
            const SizedBox(height: 2),
            Text(t.description.isEmpty ? ' ' : t.description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: on ? t.color.withValues(alpha: 0.85) : AppColors.muted, fontSize: 10.5)),
          ]),
        ),
      );

  Widget _statusToggle(String status, bool on, VoidCallback onTap) {
    final c = leaveStatusColor(status);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 42,
        decoration: BoxDecoration(
          color: on ? c.withValues(alpha: 0.14) : AppColors.dark3,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: on ? c : AppColors.border, width: on ? 1.5 : 1),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(leaveStatuses[status]!,
              style: TextStyle(color: on ? c : AppColors.light, fontWeight: on ? FontWeight.w700 : FontWeight.w500, fontSize: 13)),
        ]),
      ),
    );
  }
}
