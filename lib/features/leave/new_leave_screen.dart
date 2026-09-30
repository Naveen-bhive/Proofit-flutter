import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../core/network/api_service.dart';
import '../../core/utils/ui_feedback.dart';
import 'leave_common.dart';

/// "New Leave" form. Owners assign leave to a member (and can set its status
/// and add leave types); staff request leave for themselves.
/// Pops `true` once a leave is saved.
class NewLeaveScreen extends ConsumerStatefulWidget {
  final bool isOwner;
  const NewLeaveScreen({super.key, required this.isOwner});

  @override
  ConsumerState<NewLeaveScreen> createState() => _NewLeaveScreenState();
}

class _NewLeaveScreenState extends ConsumerState<NewLeaveScreen> {
  final _reasonCtrl = TextEditingController();
  final _dateFmt = DateFormat('dd-MM-yyyy');

  List<LeaveMember> _members = [];
  List<LeaveType> _types = [];
  LeaveMember? _member;
  LeaveType? _type;
  String _status = 'pending';
  String _duration = 'full_day';
  DateTime _start = DateUtils.dateOnly(DateTime.now());
  DateTime? _end;
  File? _file;
  bool _saving = false;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _loadTypes();
    if (widget.isOwner) _loadMembers();
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTypes() async {
    try {
      final res = await ref.read(apiServiceProvider).get('/leaves/types');
      if (res.data['success'] == true && mounted) {
        setState(() => _types = List<Map<String, dynamic>>.from(res.data['data']).map(LeaveType.fromJson).toList());
      }
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e, fallback: 'Could not load leave types.');
    }
  }

  Future<void> _loadMembers() async {
    try {
      final res = await ref.read(apiServiceProvider).get('/staff');
      if (res.data['success'] == true && mounted) {
        final rows = List<Map<String, dynamic>>.from(res.data['data'] ?? []);
        setState(() => _members = rows.where((r) => r['kind'] != 'invite').map(LeaveMember.fromJson).toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())));
      }
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e, fallback: 'Could not load staff.');
    }
  }

  // ─── Pickers ────────────────────────────────────────────────────────────

  Future<void> _pickMember() async {
    final picked = await showLeavePicker<LeaveMember>(
      context,
      title: 'Choose Member',
      values: _members,
      current: _member,
      label: (m) => m.name,
      subtitle: (m) => m.phone,
      leading: (m) => LeaveAvatar(name: m.name, photoUrl: m.photoUrl, size: 34),
    );
    if (picked != null) setState(() => _member = picked);
  }

  Future<void> _pickType() async {
    if (_types.isEmpty) return;
    final picked = await showLeavePicker<LeaveType>(
      context,
      title: 'Leave Type',
      values: _types,
      current: _type,
      label: (t) => t.name,
      subtitle: (t) => t.description,
      leading: (t) => Container(width: 10, height: 10, decoration: BoxDecoration(color: t.color, shape: BoxShape.circle)),
    );
    if (picked != null) setState(() => _type = picked);
  }

  Future<void> _pickStatus() async {
    final picked = await showLeavePicker<String>(
      context,
      title: 'Status',
      values: const ['pending', 'approved', 'rejected'],
      current: _status,
      label: (s) => leaveStatuses[s]!,
      leading: (s) => Container(
          width: 10, height: 10, decoration: BoxDecoration(color: leaveStatusColor(s), shape: BoxShape.circle)),
    );
    if (picked != null) setState(() => _status = picked);
  }

  Future<DateTime?> _pickDate(DateTime initial, {DateTime? first}) {
    final today = DateUtils.dateOnly(DateTime.now());
    final firstDate = first ?? today.subtract(const Duration(days: 90));
    return showDatePicker(
      context: context,
      initialDate: initial.isBefore(firstDate) ? firstDate : initial,
      firstDate: firstDate,
      lastDate: today.add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: AppColors.brand)),
        child: child!,
      ),
    );
  }

  Future<void> _addType() async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final created = await showDialog<LeaveType>(
      context: context,
      builder: (ctx) {
        var busy = false;
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            backgroundColor: AppColors.dark2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Add Leave Type', style: TextStyle(color: AppColors.white, fontSize: 17)),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                maxLength: 40,
                style: const TextStyle(color: AppColors.white),
                decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Maternity'),
              ),
              TextField(
                controller: descCtrl,
                maxLength: 60,
                style: const TextStyle(color: AppColors.white),
                decoration: const InputDecoration(labelText: 'Description (optional)', hintText: 'e.g. Paid'),
              ),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              TextButton(
                onPressed: busy
                    ? null
                    : () async {
                        if (nameCtrl.text.trim().isEmpty) return;
                        setLocal(() => busy = true);
                        try {
                          final res = await ref.read(apiServiceProvider).post('/leaves/types', data: {
                            'name': nameCtrl.text.trim(),
                            'description': descCtrl.text.trim(),
                          });
                          if (ctx.mounted) {
                            Navigator.pop(ctx, LeaveType.fromJson(Map<String, dynamic>.from(res.data['data'])));
                          }
                        } catch (e) {
                          setLocal(() => busy = false);
                          if (ctx.mounted) showErrorSnackBar(ctx, e, fallback: 'Could not add leave type.');
                        }
                      },
                child: const Text('Add', style: TextStyle(color: AppColors.brand, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        );
      },
    );
    if (created != null && mounted) {
      setState(() {
        _types = [..._types.where((t) => t.id != created.id), created];
        _type = created;
      });
    }
  }

  Future<void> _pickFile() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 75, maxWidth: 1800);
    if (x != null) setState(() => _file = File(x.path));
  }

  // ─── Save ───────────────────────────────────────────────────────────────

  String? get _validationError {
    if (widget.isOwner && _member == null) return 'Please choose a member';
    if (_type == null) return 'Please choose a leave type';
    if (_duration == 'multiple') {
      if (_end == null) return 'Please select an end date';
      if (_end!.isBefore(_start)) return 'End date must be on or after the start date';
    }
    if (_reasonCtrl.text.trim().isEmpty) return 'Please enter a reason for absence';
    return null;
  }

  Future<void> _save() async {
    setState(() => _submitted = true);
    final err = _validationError;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err), backgroundColor: AppColors.red));
      return;
    }
    setState(() => _saving = true);
    final api = ref.read(apiServiceProvider);
    try {
      String? attachmentUrl;
      if (_file != null) {
        final ext = _file!.path.split('.').last.toLowerCase();
        final mime = switch (ext) { 'png' => 'image/png', 'webp' => 'image/webp', _ => 'image/jpeg' };
        final up = await api.uploadMultipart('/reports/upload-photo', file: _file!, mimeType: mime);
        attachmentUrl = up.data['data']?['publicUrl']?.toString();
      }
      final day = DateFormat('yyyy-MM-dd');
      final res = await api.post('/leaves', data: {
        if (widget.isOwner) 'staffId': _member!.id,
        if (widget.isOwner) 'status': _status,
        'leaveTypeId': _type!.id,
        'duration': _duration,
        'startDate': day.format(_start),
        'endDate': day.format(_duration == 'multiple' ? _end! : _start),
        'reason': _reasonCtrl.text.trim(),
        if (attachmentUrl != null) 'attachmentUrl': attachmentUrl,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res.data['message']?.toString() ?? 'Saved'),
        backgroundColor: AppColors.green,
      ));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e, fallback: 'Could not save leave. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ─── UI ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('New Leave', style: TextStyle(color: AppColors.white, fontSize: 20, fontWeight: FontWeight.w800)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: InkWell(
              onTap: () => Navigator.pop(context),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 34, height: 34,
                decoration: BoxDecoration(color: AppColors.red, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.close_rounded, color: AppColors.white, size: 20),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.dark2,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: Text(widget.isOwner ? 'Assign Leave' : 'Request Leave',
                    style: const TextStyle(color: AppColors.white, fontSize: 18, fontWeight: FontWeight.w800)),
              ),
              const Divider(height: 1, color: AppColors.border),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: _fields()),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  List<Widget> _fields() => [
        if (widget.isOwner) ...[
          _label('Choose Member', required: true, error: _submitted && _member == null),
          LeaveSelectBox(
            value: _member?.name,
            onTap: _pickMember,
            leading: _member == null ? null : LeaveAvatar(name: _member!.name, photoUrl: _member!.photoUrl, size: 28),
          ),
          const SizedBox(height: 18),
        ],
        _label('Leave Type', required: true, error: _submitted && _type == null),
        Row(children: [
          Expanded(
            child: LeaveSelectBox(
              value: _type?.name,
              onTap: _pickType,
              leading: _type == null
                  ? null
                  : Container(width: 10, height: 10, decoration: BoxDecoration(color: _type!.color, shape: BoxShape.circle)),
              borderRadius: widget.isOwner
                  ? const BorderRadius.horizontal(left: Radius.circular(12))
                  : BorderRadius.circular(12),
            ),
          ),
          if (widget.isOwner)
            InkWell(
              onTap: _addType,
              borderRadius: const BorderRadius.horizontal(right: Radius.circular(12)),
              child: Container(
                height: 50,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.dark4,
                  borderRadius: BorderRadius.horizontal(right: Radius.circular(12)),
                  border: Border(
                    top: BorderSide(color: AppColors.border),
                    right: BorderSide(color: AppColors.border),
                    bottom: BorderSide(color: AppColors.border),
                  ),
                ),
                child: const Text('Add', style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w600)),
              ),
            ),
        ]),
        if (widget.isOwner) ...[
          const SizedBox(height: 18),
          _label('Status'),
          LeaveSelectBox(
            value: leaveStatuses[_status],
            onTap: _pickStatus,
            leading: Container(
                width: 10, height: 10, decoration: BoxDecoration(color: leaveStatusColor(_status), shape: BoxShape.circle)),
          ),
        ],
        const SizedBox(height: 18),
        _label('Select Duration'),
        for (final e in leaveDurations.entries) _radio(e.key, e.value),
        const SizedBox(height: 14),
        if (_duration == 'multiple')
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _label('Start Date'),
                _dateBox(_start, () async {
                  final d = await _pickDate(_start);
                  if (d != null) {
                    setState(() {
                      _start = d;
                      if (_end != null && _end!.isBefore(d)) _end = null;
                    });
                  }
                }),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _label('End Date', required: true, error: _submitted && _end == null),
                _dateBox(_end, () async {
                  final d = await _pickDate(_end ?? _start.add(const Duration(days: 1)), first: _start);
                  if (d != null) setState(() => _end = d);
                }),
              ]),
            ),
          ])
        else ...[
          _label('Date'),
          _dateBox(_start, () async {
            final d = await _pickDate(_start);
            if (d != null) setState(() => _start = d);
          }),
        ],
        const SizedBox(height: 18),
        _label('Reason for absence', required: true, error: _submitted && _reasonCtrl.text.trim().isEmpty),
        TextField(
          controller: _reasonCtrl,
          minLines: 3,
          maxLines: 5,
          maxLength: 1000,
          onChanged: (_) {
            if (_submitted) setState(() {});
          },
          style: const TextStyle(color: AppColors.white, fontSize: 15),
          decoration: InputDecoration(
            hintText: 'e.g. Feeling not well',
            hintStyle: const TextStyle(color: AppColors.muted),
            counterText: '',
            filled: true,
            fillColor: AppColors.dark3,
            contentPadding: const EdgeInsets.all(14),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.brand)),
          ),
        ),
        const SizedBox(height: 18),
        Row(children: [
          _label('Add File', bottom: 0),
          const SizedBox(width: 6),
          Tooltip(
            message: 'Attach an image such as a medical certificate',
            triggerMode: TooltipTriggerMode.tap,
            child: Container(
              width: 16, height: 16,
              decoration: const BoxDecoration(color: AppColors.muted, shape: BoxShape.circle),
              child: const Icon(Icons.question_mark_rounded, size: 11, color: AppColors.dark),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        _fileBox(),
        const SizedBox(height: 24),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            style: TextButton.styleFrom(
              backgroundColor: AppColors.dark4,
              foregroundColor: AppColors.light,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brand,
              foregroundColor: AppColors.white,
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white))
                : Text(widget.isOwner ? 'Save' : 'Submit', style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ]),
      ];

  Widget _label(String text, {bool required = false, bool error = false, double bottom = 8}) => Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: Text.rich(TextSpan(children: [
          TextSpan(
              text: text,
              style: TextStyle(color: error ? AppColors.red : AppColors.light, fontSize: 13, fontWeight: FontWeight.w500)),
          if (required) const TextSpan(text: ' *', style: TextStyle(color: AppColors.red)),
        ])),
      );

  Widget _radio(String value, String label) {
    final selected = _duration == value;
    return InkWell(
      onTap: () => setState(() => _duration = value),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 20, height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.dark3,
              border: Border.all(color: selected ? AppColors.brand : AppColors.border, width: selected ? 6 : 1.5),
            ),
          ),
          const SizedBox(width: 12),
          Text(label,
              style: TextStyle(
                color: selected ? AppColors.white : AppColors.light,
                fontSize: 14,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              )),
        ]),
      ),
    );
  }

  Widget _dateBox(DateTime? value, VoidCallback onTap) => LeaveSelectBox(
        value: value == null ? null : _dateFmt.format(value),
        placeholder: 'dd-mm-yyyy',
        onTap: onTap,
        trailingIcon: Icons.calendar_today_outlined,
      );

  Widget _fileBox() {
    if (_file != null) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.dark3,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(_file!, width: 64, height: 64, fit: BoxFit.cover),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(_file!.path.split('/').last,
                maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.light, fontSize: 13)),
          ),
          IconButton(
            onPressed: () => setState(() => _file = null),
            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.red),
          ),
        ]),
      );
    }
    return InkWell(
      onTap: _pickFile,
      borderRadius: BorderRadius.circular(12),
      child: CustomPaint(
        painter: _DashedBorderPainter(),
        child: const SizedBox(
          height: 120,
          width: double.infinity,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.cloud_upload_outlined, color: AppColors.silver, size: 26),
            SizedBox(height: 6),
            Text('Choose a file', style: TextStyle(color: AppColors.light, fontSize: 14)),
            SizedBox(height: 2),
            Text('JPG, PNG up to 10 MB', style: TextStyle(color: AppColors.muted, fontSize: 11)),
          ]),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12));
    canvas.drawRRect(rrect, Paint()..color = AppColors.dark3);
    final paint = Paint()
      ..color = AppColors.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      for (double d = 0; d < metric.length; d += 10) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
