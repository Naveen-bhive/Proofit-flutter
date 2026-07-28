import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/utils/ui_feedback.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_service.dart';
import '../../../shared/widgets/empty_state.dart';
import '../controllers/staff_controller.dart';

class StaffJobsScreen extends ConsumerStatefulWidget {
  const StaffJobsScreen({super.key});
  @override ConsumerState<StaffJobsScreen> createState() => StaffJobsScreenState();
}

class StaffJobsScreenState extends ConsumerState<StaffJobsScreen> {
  List<Map<String, dynamic>> _jobs = [];
  bool _loading = true;
  String _statusFilter = 'all';

  static const _filters = [
    ('all', 'All'),
    ('pending', 'Pending'),
    ('in_progress', 'Active'),
    ('completed', 'Done'),
    ('cancelled', 'Cancelled'),
  ];

  @override
  void initState() {
    super.initState();
    refresh();
  }

  String _jobId(Map<String, dynamic> j) =>
      j['_id']?.toString() ?? j['id']?.toString() ?? '';

  Future<void> refresh() => _load(_statusFilter);

  Future<void> _load(String statusFilter) async {
    if (mounted) setState(() => _loading = true);
    try {
      final api = ref.read(apiServiceProvider);
      final params = <String, dynamic>{'limit': 100};
      if (statusFilter != 'all') params['status'] = statusFilter;
      final res = await api.get('/jobs', params: params);
      if (res.data['success'] == true && mounted) {
        setState(() => _jobs = List<Map<String, dynamic>>.from(res.data['data']['jobs'] ?? []));
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, e, fallback: 'Could not load jobs. Please try again.');
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  void _setFilter(String filter) {
    if (_statusFilter == filter) return;
    setState(() => _statusFilter = filter);
    _load(filter);
  }

  Future<void> _updateStatus(String jobId, String status) async {
    try {
      final api = ref.read(apiServiceProvider);
      await api.put('/jobs/$jobId/status', data: {'status': status});
      refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(status == 'completed' ? 'âœ… Job marked complete' : 'Status updated'),
        backgroundColor: status == 'completed' ? AppColors.green : AppColors.brand));
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, e, fallback: 'Could not update the job. Please try again.');
    }
  }

  Color _priorityColor(String p) => switch (p) { 'urgent' => AppColors.red, 'high' => AppColors.yellow, 'low' => AppColors.muted, _ => AppColors.brand };

  Color _statusColor(String s) => switch (s) {
    'completed' => AppColors.green,
    'in_progress' => AppColors.brand,
    'cancelled' => AppColors.muted,
    _ => AppColors.yellow,
  };

  Map<String, dynamic>? _linkedReport(Map<String, dynamic> j) {
    final r = j['reportId'];
    if (r is Map<String, dynamic>) return r;
    return null;
  }

  bool get _isActiveFilter => _statusFilter == 'pending' || _statusFilter == 'in_progress' || _statusFilter == 'all';

  @override
  Widget build(BuildContext context) {
    // Refresh when a report is saved/submitted from another screen.
    ref.listen(staffControllerProvider.select((s) => s.jobsEpoch), (prev, next) {
      if (prev != next) refresh();
    });

    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(title: const Text('My Jobs')),
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
                      color: _statusFilter == f.$1 ? AppColors.brand : AppColors.dark3,
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(color: _statusFilter == f.$1 ? AppColors.brand : AppColors.border),
                    ),
                    child: Text(f.$2,
                      style: TextStyle(
                        color: _statusFilter == f.$1 ? Colors.white : AppColors.silver,
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
              : _jobs.isEmpty
                  ? EmptyState(
                      type: EmptyType.reports,
                      title: 'No ${_statusFilter == 'all' ? '' : _statusFilter.replaceAll('_', ' ')} jobs',
                      subtitle: 'Your manager will assign jobs here',
                    )
                  : RefreshIndicator(
                      color: AppColors.brand,
                      onRefresh: refresh,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _jobs.length,
                        itemBuilder: (_, i) {
                          final j        = _jobs[i];
                          final jobId    = _jobId(j);
                          final priority = j['priority'] ?? 'normal';
                          final status   = j['status'] ?? 'pending';
                          final report   = _linkedReport(j);
                          final draftId  = report?['status'] == 'draft'
                              ? (report!['_id']?.toString() ?? report['id']?.toString())
                              : null;
                          final canSubmit = status != 'completed' && status != 'cancelled';
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(color: AppColors.dark2, borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: priority == 'urgent' ? AppColors.red.withValues(alpha: 0.5) : AppColors.border)),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Expanded(child: Text(j['title'] ?? '', style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 15))),
                                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(color: _statusColor(status).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(100)),
                                  child: Text(status.replaceAll('_', ' '), style: TextStyle(color: _statusColor(status), fontSize: 11, fontWeight: FontWeight.w700))),
                                const SizedBox(width: 6),
                                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(color: _priorityColor(priority).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(100)),
                                  child: Text(priority[0].toUpperCase() + priority.substring(1), style: TextStyle(color: _priorityColor(priority), fontSize: 11, fontWeight: FontWeight.w700))),
                              ]),
                              if (j['description'] != null && (j['description'] as String).isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(j['description'], style: const TextStyle(color: AppColors.silver, fontSize: 13)),
                              ],
                              if (j['location']?['address'] != null) ...[
                                const SizedBox(height: 6),
                                Row(children: [
                                  const Icon(Icons.location_on_outlined, color: AppColors.muted, size: 14),
                                  const SizedBox(width: 4),
                                  Expanded(child: Text(j['location']['address'], style: const TextStyle(color: AppColors.muted, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                ]),
                              ],
                              if (draftId != null) ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(color: AppColors.yellow.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.yellow.withValues(alpha: 0.3))),
                                  child: const Row(children: [
                                    Icon(Icons.drafts_outlined, color: AppColors.yellow, size: 14),
                                    SizedBox(width: 6),
                                    Text('Report saved as draft', style: TextStyle(color: AppColors.yellow, fontSize: 12)),
                                  ]),
                                ),
                              ],
                              if (_isActiveFilter && canSubmit) ...[
                                const SizedBox(height: 12),
                                Row(children: [
                                  if (status == 'pending')
                                    Expanded(child: OutlinedButton(
                                      onPressed: jobId.isEmpty ? null : () => _updateStatus(jobId, 'in_progress'),
                                      style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.brand), foregroundColor: AppColors.brand),
                                      child: const Text('Start Job'))),
                                  if (status == 'pending') const SizedBox(width: 10),
                                  Expanded(child: ElevatedButton.icon(
                                    onPressed: () {
                                      if (draftId != null) {
                                        context.push('/staff/submit?reportId=$draftId&jobId=$jobId&jobTitle=${Uri.encodeComponent(j['title'] ?? '')}');
                                      } else {
                                        context.push('/staff/submit?jobId=$jobId&jobTitle=${Uri.encodeComponent(j['title'] ?? '')}');
                                      }
                                    },
                                    icon: Icon(draftId != null ? Icons.drafts_outlined : Icons.camera_alt_outlined, size: 16),
                                    label: Text(draftId != null ? 'Continue Draft' : 'Submit Report'),
                                    style: ElevatedButton.styleFrom(backgroundColor: draftId != null ? AppColors.yellow : AppColors.brand))),
                                ]),
                              ],
                            ]),
                          );
                        },
                      ),
                    ),
        ),
      ]),
    );
  }
}
