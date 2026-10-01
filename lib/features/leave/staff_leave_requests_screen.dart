import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_colors.dart';
import '../../core/network/api_service.dart';
import '../../core/utils/ui_feedback.dart';
import 'leave_common.dart';
import 'new_leave_screen.dart';

/// Staff "Leave Requests": the signed-in staff member's own requests and
/// their approval status. The API scopes `/leaves` to the caller for staff,
/// so other members' requests are never returned.
class StaffLeaveRequestsScreen extends ConsumerStatefulWidget {
  const StaffLeaveRequestsScreen({super.key});

  @override
  ConsumerState<StaffLeaveRequestsScreen> createState() => _StaffLeaveRequestsScreenState();
}

class _StaffLeaveRequestsScreenState extends ConsumerState<StaffLeaveRequestsScreen> {
  List<LeaveRecord> _leaves = [];
  Map<String, Color> _typeColors = {};
  bool _loading = true;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(apiServiceProvider);
    try {
      final results = await Future.wait([
        api.get('/leaves', params: {'limit': '100'}),
        api.get('/leaves/types'),
      ]);
      if (!mounted) return;
      setState(() {
        _leaves = List<Map<String, dynamic>>.from(results[0].data['data']['leaves'] ?? [])
            .map(LeaveRecord.fromJson)
            .toList()
          // Most recently applied first.
          ..sort((a, b) => (b.createdAt ?? b.start).compareTo(a.createdAt ?? a.start));
        _typeColors = {
          for (final t in List<Map<String, dynamic>>.from(results[1].data['data'] ?? []).map(LeaveType.fromJson))
            t.id: t.color,
        };
      });
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e, fallback: 'Could not load your leave requests.');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _requestLeave() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const NewLeaveScreen(isOwner: false), fullscreenDialog: true),
    );
    if (saved == true) _load();
  }

  Future<void> _cancel(LeaveRecord l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.dark2,
        title: const Text('Cancel request?', style: TextStyle(color: AppColors.white)),
        content: const Text('Your leave request will be withdrawn.', style: TextStyle(color: AppColors.silver)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel Request', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiServiceProvider).delete('/leaves/${l.id}');
      _load();
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e, fallback: 'Could not cancel the request.');
    }
  }

  LeaveRecord? get _todayLeave {
    final today = DateUtils.dateOnly(DateTime.now());
    return _leaves
        .where((l) => l.status == 'approved' && !today.isBefore(l.start) && !today.isAfter(l.end))
        .firstOrNull;
  }

  int _count(String status) => _leaves.where((l) => l.status == status).length;

  @override
  Widget build(BuildContext context) {
    final visible = _filter == 'all' ? _leaves : _leaves.where((l) => l.status == _filter).toList();
    final today = _todayLeave;

    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        titleSpacing: 0,
        title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Leave Requests', style: TextStyle(color: AppColors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          SizedBox(height: 2),
          Text('Home • Leaves', style: TextStyle(color: AppColors.silver, fontSize: 12)),
        ]),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Tooltip(
              message: 'Request leave',
              child: InkWell(
                onTap: _requestLeave,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.add_rounded, color: AppColors.white, size: 24),
                ),
              ),
            ),
          ),
        ],
        bottom: const PreferredSize(preferredSize: Size.fromHeight(1), child: Divider(height: 1, color: AppColors.border)),
      ),
      body: RefreshIndicator(
        color: AppColors.brand,
        backgroundColor: AppColors.dark2,
        onRefresh: _load,
        child: _loading
            ? ListView(children: const [
                SizedBox(height: 240, child: Center(child: CircularProgressIndicator(color: AppColors.brand))),
              ])
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  if (today != null) ...[_todayBanner(today), const SizedBox(height: 14)],
                  Row(children: [
                    _summaryTile('PENDING', _count('pending'), AppColors.yellow),
                    const SizedBox(width: 8),
                    _summaryTile('APPROVED', _count('approved'), AppColors.green),
                    const SizedBox(width: 8),
                    _summaryTile('REJECTED', _count('rejected'), AppColors.red),
                  ]),
                  const SizedBox(height: 16),
                  _chips(),
                  const SizedBox(height: 18),
                  const Text('RECENT REQUESTS',
                      style: TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
                  const SizedBox(height: 10),
                  if (visible.isEmpty) _empty() else ...visible.map(_card),
                ],
              ),
      ),
    );
  }

  Widget _todayBanner(LeaveRecord l) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.green.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.green.withValues(alpha: 0.45)),
        ),
        child: Row(children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(color: AppColors.green.withValues(alpha: 0.18), shape: BoxShape.circle),
            child: const Icon(Icons.beach_access_rounded, color: AppColors.green, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Today is your leave',
                  style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 2),
              Text(
                '${l.leaveTypeName} leave${l.isHalfDay ? ' · ${leaveDurations[l.duration]}' : ''}'
                '${DateUtils.isSameDay(l.start, l.end) ? '' : ' · until ${DateFormat('d MMM').format(l.end)}'}',
                style: const TextStyle(color: AppColors.light, fontSize: 12.5),
              ),
            ]),
          ),
        ]),
      );

  Widget _summaryTile(String label, int value, Color color) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Column(children: [
            Text(label, style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
            const SizedBox(height: 4),
            Text('$value', style: const TextStyle(color: AppColors.white, fontSize: 20, fontWeight: FontWeight.w800)),
          ]),
        ),
      );

  Widget _chips() {
    const chips = [('all', 'All'), ('pending', 'Pending'), ('approved', 'Approved'), ('rejected', 'Rejected')];
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final (key, label) = chips[i];
          final on = _filter == key;
          return InkWell(
            onTap: () => setState(() => _filter = key),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
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

  Widget _empty() => Container(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        decoration: BoxDecoration(
          color: AppColors.dark2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(children: [
          const Icon(Icons.event_available_outlined, color: AppColors.muted, size: 44),
          const SizedBox(height: 10),
          Text(_filter == 'all' ? 'No leave requests yet' : 'No ${leaveStatuses[_filter]?.toLowerCase()} requests',
              style: const TextStyle(color: AppColors.silver)),
          if (_filter == 'all') ...[
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: _requestLeave,
              icon: const Icon(Icons.add_rounded, color: AppColors.brand),
              label: const Text('Request Leave', style: TextStyle(color: AppColors.brand, fontWeight: FontWeight.w700)),
            ),
          ],
        ]),
      );

  Widget _card(LeaveRecord l) {
    final typeColor = _typeColors[l.leaveTypeId] ?? AppColors.brand;
    final statusColor = leaveStatusColor(l.status);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.dark2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            width: 4,
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(14)),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(width: 9, height: 9, decoration: BoxDecoration(color: typeColor, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('${l.leaveTypeName} Leave',
                        style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                  LeaveStatusBadge(l.status),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  const Icon(Icons.calendar_today_outlined, size: 14, color: AppColors.silver),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(l.dateLabel, style: const TextStyle(color: AppColors.light, fontSize: 13)),
                  ),
                  const SizedBox(width: 10),
                  Text('· ${l.daysLabel} · ${leaveDurations[l.duration] ?? ''}',
                      style: const TextStyle(color: AppColors.silver, fontSize: 12)),
                ]),
                const SizedBox(height: 8),
                Text(l.reason,
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.silver, fontSize: 13)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: Text(
                      [
                        if (l.createdAt != null) 'Applied ${timeago.format(l.createdAt!)}',
                        if (l.reviewedBy != null && (l.status == 'approved' || l.status == 'rejected'))
                          '${leaveStatuses[l.status]} by ${l.reviewedBy}',
                      ].join(' · '),
                      style: const TextStyle(color: AppColors.muted, fontSize: 11.5),
                    ),
                  ),
                  if (l.attachmentUrl != null)
                    InkWell(
                      onTap: () => launchUrl(Uri.parse(l.attachmentUrl!), mode: LaunchMode.externalApplication),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.attach_file_rounded, color: AppColors.brand, size: 18),
                      ),
                    ),
                  if (l.status == 'pending')
                    TextButton(
                      onPressed: () => _cancel(l),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 30),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Cancel', style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w600)),
                    ),
                ]),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
