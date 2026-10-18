import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../shared/widgets/ui_kit.dart';
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
      backgroundColor: AppColors.page,
      body: SafeArea(
        child: Column(children: [
          Container(
            color: AppColors.white,
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: AppColors.text),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(width: 4),
                Text('Check-in History', style: AppTextStyles.pageTitle.copyWith(fontSize: 21)),
              ]),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Row(children: [
                  for (final f in _filters) ...[
                    GestureDetector(
                      onTap: () => _setFilter(f.$1),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                        decoration: BoxDecoration(
                          color: _filter == f.$1 ? AppColors.brand : AppColors.dark4,
                          borderRadius: BorderRadius.circular(100),
                          boxShadow: _filter == f.$1 ? AppColors.glow(AppColors.brand) : null,
                        ),
                        child: Text(f.$2,
                            style: TextStyle(
                              color: _filter == f.$1 ? AppColors.white : AppColors.light,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            )),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ]),
              ),
            ]),
          ),
          const Divider(height: 1, color: AppColors.border),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
                : _records.isEmpty
                    ? const SoftEmptyState(
                        icon: Icons.history_rounded,
                        title: 'No check-ins yet',
                        subtitle: 'Your check-in and check-out times will appear here.',
                      )
                    : RefreshIndicator(
                        color: AppColors.brand,
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                          itemCount: _records.length,
                          itemBuilder: (_, i) => _card(_records[i]),
                        ),
                      ),
          ),
        ]),
      ),
    );
  }

  Widget _card(Map<String, dynamic> r) {
    final hasCheckout = r['checkOutTime'] != null || r['checkOutTimeLabel'] != null;
    final address = r['checkInLocation'] is Map ? r['checkInLocation']['address']?.toString() : null;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: hasCheckout ? AppColors.border : const Color(0xFFFDE68A)),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(_dateLabel(r), style: AppTextStyles.h3.copyWith(fontSize: 15.5, fontWeight: FontWeight.w700)),
          ),
          hasCheckout
              ? SoftBadge(label: _duration(r), color: AppColors.greenDark, background: AppColors.greenSoft, fontSize: 12)
              : const SoftBadge(label: 'No checkout', color: AppColors.amberDark, background: AppColors.amberSoft, fontSize: 12),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          _timeBox('CHECK IN', _timeLabel(r, 'checkInTimeLabel', 'checkInTime'), AppColors.greenDark, AppColors.greenSoft),
          const SizedBox(width: 10),
          hasCheckout
              ? _timeBox('CHECK OUT', _timeLabel(r, 'checkOutTimeLabel', 'checkOutTime'), AppColors.brand, AppColors.brandSoft)
              : _timeBox('CHECK OUT', '--:--', AppColors.silver, AppColors.dark3),
        ]),
        const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1, color: AppColors.borderSoft)),
        Row(children: [
          const Icon(Icons.description_outlined, color: AppColors.muted, size: 15),
          const SizedBox(width: 6),
          Text('${r['reportsSubmitted'] ?? 0} reports submitted', style: const TextStyle(color: AppColors.light, fontSize: 12.5)),
          if (address != null) ...[
            const SizedBox(width: 12),
            const Spacer(),
            const Icon(Icons.location_on_outlined, color: AppColors.muted, size: 15),
            const SizedBox(width: 4),
            Flexible(
              flex: 3,
              child: Text(address, style: const TextStyle(color: AppColors.light, fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ]),
      ]),
    );
  }

  Widget _timeBox(String label, String time, Color color, Color bg) => Expanded(child: Container(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: 0.18))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
      const SizedBox(height: 6),
      Text(time,
          style: AppTextStyles.h3.copyWith(
              color: time == '--:--' ? AppColors.muted : AppColors.text, fontSize: 17, fontWeight: FontWeight.w700)),
    ]),
  ));
}
