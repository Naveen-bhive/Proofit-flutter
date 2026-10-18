import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../../../core/network/api_service.dart';

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
        data: Theme.of(ctx),
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
      body: SafeArea(
        child: Column(children: [
          PageHeader(
            title: 'Working Hours',
            actions: [
              GestureDetector(
                onTap: _pickDateRange,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.brandSoft,
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: AppColors.brandBorder),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.calendar_today_outlined, color: AppColors.brand, size: 15),
                    const SizedBox(width: 6),
                    Text('${DateFormat('d MMM').format(_from)} - ${DateFormat('d MMM').format(_to)}',
                        style: const TextStyle(color: AppColors.brand, fontSize: 12.5, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            ],
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
                : _summary.isEmpty
                    ? const SoftEmptyState(
                        icon: Icons.schedule_rounded,
                        title: 'No attendance data',
                        subtitle: 'Check-ins for the selected range will appear here.',
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                        itemCount: _summary.length,
                        itemBuilder: (_, i) => _card(_summary[i]),
                      ),
          ),
        ]),
      ),
    );
  }

  Widget _card(Map<String, dynamic> s) {
    final name = (s['name'] as String?) ?? '';
    final id = s['staffId']?.toString() ?? '';
    final shortId = id.length > 4 ? id.substring(id.length - 4).toUpperCase() : id.toUpperCase();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: SurfaceCard(
        radius: 22,
        padding: const EdgeInsets.all(18),
        onTap: () => context.push('/owner/staff-attendance/${s['staffId']}?name=${Uri.encodeComponent(name)}'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            InitialAvatar(name: name.isEmpty ? '?' : name, size: 48, square: true, color: AppColors.brand),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                    child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.h3.copyWith(fontSize: 16.5, fontWeight: FontWeight.w600)),
                  ),
                  if (shortId.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: AppColors.dark4, borderRadius: BorderRadius.circular(6)),
                      child: Text('ID: $shortId', style: const TextStyle(color: AppColors.silver, fontSize: 11, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.event_available_outlined, size: 14, color: AppColors.silver),
                  const SizedBox(width: 5),
                  Text('${s['days']} days worked', style: const TextStyle(color: AppColors.silver, fontSize: 13)),
                ]),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${s['totalHours']}h',
                  style: AppTextStyles.h2.copyWith(color: AppColors.brand, fontSize: 24, fontWeight: FontWeight.w700)),
              const Text('TOTAL', style: TextStyle(color: AppColors.muted, fontSize: 10.5, fontWeight: FontWeight.w600, letterSpacing: 1)),
            ]),
          ]),
          const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1, color: AppColors.borderSoft)),
          Row(children: [
            _stat('Avg/day', '${s['avgHoursPerDay']}h', AppColors.brand, AppColors.dark3),
            const SizedBox(width: 10),
            _stat('Reports', '${s['totalReports']}', AppColors.greenDark, AppColors.greenSoft),
            const SizedBox(width: 10),
            _stat('Days', '${s['days']}', const Color(0xFFD97706), AppColors.amberSoft),
          ]),
        ]),
      ),
    );
  }

  Widget _stat(String label, String value, Color color, Color bg) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(children: [
        Text(value, style: AppTextStyles.h3.copyWith(color: color, fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: AppColors.silver, fontSize: 12)),
      ]),
    ),
  );
}
