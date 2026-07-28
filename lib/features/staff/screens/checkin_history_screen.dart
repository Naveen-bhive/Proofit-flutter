import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/date_utils.dart';
import '../../../shared/widgets/empty_state.dart';
import '../controllers/staff_controller.dart';

class CheckinHistoryScreen extends ConsumerStatefulWidget {
  const CheckinHistoryScreen({super.key});
  @override ConsumerState<CheckinHistoryScreen> createState() => _CheckinHistoryScreenState();
}

class _CheckinHistoryScreenState extends ConsumerState<CheckinHistoryScreen> {
  List<Map<String, dynamic>> _records = [];
  bool _loading = true;
  String _filter = 'all';

  static const _filters = [
    ('all', 'All'),
    ('today', 'Today'),
    ('week', 'Week'),
    ('month', 'Month'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await ref.read(staffControllerProvider.notifier).loadCheckinHistory(filter: _filter);
    if (mounted) setState(() { _records = data; _loading = false; });
  }

  void _setFilter(String filter) {
    if (_filter == filter) return;
    setState(() => _filter = filter);
    _load();
  }

  String _duration(Map r) {
    final mins = r['durationMinutes'] ?? 0;
    if (mins == 0) return 'No checkout';
    final h = mins ~/ 60;
    final m = mins % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  String _dateLabel(Map r) {
    if (r['dateLabel'] != null) return r['dateLabel'].toString();
    if (r['date'] != null) return r['date'].toString();
    return formatApiDate(r['checkInTime'], pattern: 'EEE, d MMM yyyy');
  }

  String _timeLabel(Map r, String labelKey, String rawKey) {
    if (r[labelKey] != null) return r[labelKey].toString();
    return formatApiTime(r[rawKey]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(title: const Text('Check-in History')),
      body: Column(children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(children: [
            for (final f in _filters)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => _setFilter(f.$1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: _filter == f.$1 ? AppColors.brand : AppColors.dark3,
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(color: _filter == f.$1 ? AppColors.brand : AppColors.border),
                    ),
                    child: Text(f.$2,
                      style: TextStyle(
                        color: _filter == f.$1 ? Colors.white : AppColors.silver,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      )),
                  ),
                ),
              ),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
              : _records.isEmpty
                  ? const EmptyState(type: EmptyType.history)
                  : RefreshIndicator(
                      color: AppColors.brand,
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _records.length,
                        itemBuilder: (_, i) {
                          final r = _records[i];
                          final hasCheckout = r['checkOutTime'] != null || r['checkOutTimeLabel'] != null;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.dark2,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: hasCheckout ? AppColors.border : AppColors.yellow.withValues(alpha: 0.4)),
                            ),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Text(_dateLabel(r), style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: hasCheckout ? AppColors.green.withValues(alpha: 0.12) : AppColors.yellow.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(100),
                                  ),
                                  child: Text(_duration(r),
                                    style: TextStyle(color: hasCheckout ? AppColors.green : AppColors.yellow, fontSize: 12, fontWeight: FontWeight.w700)),
                                ),
                              ]),
                              const SizedBox(height: 12),
                              Row(children: [
                                _timeBox('Check In', _timeLabel(r, 'checkInTimeLabel', 'checkInTime'), AppColors.green),
                                const SizedBox(width: 10),
                                _timeBox('Check Out', hasCheckout ? _timeLabel(r, 'checkOutTimeLabel', 'checkOutTime') : '--:--', AppColors.brand),
                              ]),
                              const SizedBox(height: 10),
                              Row(children: [
                                const Icon(Icons.assignment_outlined, color: AppColors.muted, size: 14),
                                const SizedBox(width: 6),
                                Text('${r['reportsSubmitted'] ?? 0} reports submitted', style: const TextStyle(color: AppColors.silver, fontSize: 13)),
                                if (r['checkInLocation']?['address'] != null) ...[
                                  const SizedBox(width: 12),
                                  const Icon(Icons.location_on_outlined, color: AppColors.muted, size: 14),
                                  const SizedBox(width: 4),
                                  Expanded(child: Text(r['checkInLocation']['address'], style: const TextStyle(color: AppColors.muted, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                ],
                              ]),
                            ]),
                          );
                        },
                      ),
                    ),
        ),
      ]),
    );
  }

  Widget _timeBox(String label, String time, Color color) => Expanded(child: Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withValues(alpha: 0.2))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      Text(time, style: TextStyle(color: time == '--:--' ? AppColors.muted : AppColors.white, fontSize: 16, fontWeight: FontWeight.w700)),
    ]),
  ));
}
