import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_service.dart';
import '../../../shared/services/auth_storage.dart';

class WorkingHoursScreen extends ConsumerStatefulWidget {
  const WorkingHoursScreen({super.key});
  @override ConsumerState<WorkingHoursScreen> createState() => _WorkingHoursScreenState();
}

class _WorkingHoursScreenState extends ConsumerState<WorkingHoursScreen> {
  List<Map<String, dynamic>> _summary = [];
  bool _loading = true;
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to   = DateTime.now();

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final api = ref.read(apiServiceProvider);
      final res = await api.get('/location/working-hours', params: {
        'from': DateFormat('yyyy-MM-dd').format(_from),
        'to':   DateFormat('yyyy-MM-dd').format(_to),
      });
      if (res.data['success'] == true) {
        setState(() { _summary = List<Map<String,dynamic>>.from(res.data['data']['summary'] ?? []); });
      }
    } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate:  DateTime.now(),
      initialDateRange: DateTimeRange(start: _from, end: _to),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: AppColors.brand)),
        child: child!),
    );
    if (picked != null) {
      setState(() { _from = picked.start; _to = picked.end; });
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        title: const Text('Working Hours'),
        actions: [
          TextButton.icon(
            onPressed: _pickDateRange,
            icon: const Icon(Icons.date_range_outlined, color: AppColors.brand, size: 18),
            label: Text(
              '${DateFormat('d MMM').format(_from)} – ${DateFormat('d MMM').format(_to)}',
              style: const TextStyle(color: AppColors.brand, fontSize: 13)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
          : _summary.isEmpty
              ? const Center(child: Text('No attendance data', style: TextStyle(color: AppColors.silver)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _summary.length,
                  itemBuilder: (_, i) {
                    final s = _summary[i];
                    return GestureDetector(
                      onTap: () => context.push('/owner/staff-attendance/${s['staffId']}?name=${Uri.encodeComponent(s['name'])}'),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: AppColors.dark2, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            CircleAvatar(radius: 20, backgroundColor: AppColors.brand.withOpacity(0.2),
                              child: Text((s['name'] as String? ?? '?')[0].toUpperCase(),
                                style: const TextStyle(color: AppColors.brand, fontWeight: FontWeight.w700))),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(s['name'] ?? '', style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
                              Text('${s['days']} days worked', style: const TextStyle(color: AppColors.silver, fontSize: 12)),
                            ])),
                            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Text('${s['totalHours']}h', style: const TextStyle(color: AppColors.brand, fontSize: 20, fontWeight: FontWeight.w800)),
                              const Text('total', style: TextStyle(color: AppColors.muted, fontSize: 11)),
                            ]),
                          ]),
                          const SizedBox(height: 12),
                          Row(children: [
                            _stat('Avg/day', '${s['avgHoursPerDay']}h', AppColors.blue),
                            const SizedBox(width: 10),
                            _stat('Reports', '${s['totalReports']}', AppColors.green),
                            const SizedBox(width: 10),
                            _stat('Days', '${s['days']}', AppColors.yellow),
                          ]),
                        ]),
                      ),
                    );
                  }),
    );
  }

  Widget _stat(String label, String value, Color color) => Expanded(child: Container(
    padding: const EdgeInsets.symmetric(vertical: 8),
    decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
    child: Column(children: [
      Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w700)),
      Text(label, style: const TextStyle(color: AppColors.silver, fontSize: 10)),
    ])));
}