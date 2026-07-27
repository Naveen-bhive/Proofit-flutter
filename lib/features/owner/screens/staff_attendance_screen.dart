import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_service.dart';

class StaffAttendanceScreen extends ConsumerStatefulWidget {
  final String? staffId;
  final String? staffName;
  const StaffAttendanceScreen({super.key, this.staffId, this.staffName});

  @override
  ConsumerState<StaffAttendanceScreen> createState() => _StaffAttendanceScreenState();
}

class _StaffAttendanceScreenState extends ConsumerState<StaffAttendanceScreen> {
  List<Map<String, dynamic>> _records = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final api = ref.read(apiServiceProvider);
      final res = await api.get('/location/staff-attendance', params: {
        if (widget.staffId != null) 'staffId': widget.staffId!,
        'limit': '50',
      });
      if (res.data['success'] == true) {
        setState(() {
          _records = List<Map<String, dynamic>>.from(res.data['data']['records'] ?? []);
        });
      }
    } catch (_) {}
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.staffName != null ? '${widget.staffName} — Attendance' : 'Staff Attendance';
    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(title: Text(title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
          : _records.isEmpty
              ? const Center(child: Text('No attendance records', style: TextStyle(color: AppColors.silver)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _records.length,
                  itemBuilder: (_, i) {
                    final r = _records[i];
                    final staff = r['staffId'];
                    final name = staff is Map ? (staff['name'] ?? '') : '';
                    final checkIn = r['checkInTime'] != null ? DateTime.tryParse(r['checkInTime']) : null;
                    final checkOut = r['checkOutTime'] != null ? DateTime.tryParse(r['checkOutTime']) : null;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.dark2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (widget.staffId == null)
                          Text(name, style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
                        if (widget.staffId == null) const SizedBox(height: 8),
                        Text(r['date'] ?? '', style: const TextStyle(color: AppColors.silver, fontSize: 12)),
                        const SizedBox(height: 6),
                        Text(
                          'In: ${checkIn != null ? DateFormat('d MMM, h:mm a').format(checkIn) : '—'}',
                          style: const TextStyle(color: AppColors.light, fontSize: 13),
                        ),
                        Text(
                          'Out: ${checkOut != null ? DateFormat('d MMM, h:mm a').format(checkOut) : '—'}',
                          style: const TextStyle(color: AppColors.light, fontSize: 13),
                        ),
                        if (r['durationMinutes'] != null)
                          Text('Duration: ${r['durationMinutes']} min',
                              style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                      ]),
                    );
                  },
                ),
    );
  }
}
