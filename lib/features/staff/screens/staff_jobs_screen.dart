import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/utils/ui_feedback.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_service.dart';
import '../../../shared/services/review_service.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../shared/widgets/ui_kit.dart';
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
    ('cancelled', 'Cancel'),
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
      if (status == 'completed') ReviewService.maybePromptAfterSuccess();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(status == 'completed' ? 'Job marked complete' : 'Status updated'),
        backgroundColor: status == 'completed' ? AppColors.green : AppColors.brand));
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, e, fallback: 'Could not update the job. Please try again.');
    }
  }

  Map<String, dynamic>? _linkedReport(Map<String, dynamic> j) {
    final r = j['reportId'];
    if (r is Map<String, dynamic>) return r;
    return null;
  }

  bool get _isActiveFilter => _statusFilter == 'pending' || _statusFilter == 'in_progress' || _statusFilter == 'all';

  String _shortId(Map<String, dynamic> j) {
    final id = _jobId(j);
    return id.length >= 4 ? '#PF-${id.substring(id.length - 4).toUpperCase()}' : '#PF';
  }

  DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

  @override
  Widget build(BuildContext context) {
    // Refresh when a report is saved/submitted from another screen.
    ref.listen(staffControllerProvider.select((s) => s.jobsEpoch), (prev, next) {
      if (prev != next) refresh();
    });

    final drafts = _jobs.where((j) => _linkedReport(j)?['status'] == 'draft').length;
    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      backgroundColor: AppColors.dark,
      body: SafeArea(
        child: Column(children: [
          PageHeader(
            title: 'My Jobs',
            showBack: canPop,
            titleSize: 22,
            padding: EdgeInsets.fromLTRB(canPop ? 16 : 24, 14, 16, 10),
          ),
          PillChipBar(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            chips: [
              for (final f in _filters)
                PillChip(label: f.$2, selected: _statusFilter == f.$1, onTap: () => _setFilter(f.$1)),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
                : RefreshIndicator(
                    color: AppColors.brand,
                    onRefresh: refresh,
                    child: _jobs.isEmpty
                        ? ListView(children: [_emptyState()])
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                            children: [
                              if (drafts > 0 && _statusFilter != 'completed') _draftCacheBanner(drafts),
                              if (_statusFilter == 'completed') ..._completedHeader(),
                              for (final j in _jobs) _jobCard(j),
                            ],
                          ),
                  ),
          ),
        ]),
      ),
    );
  }

  Widget _draftCacheBanner(int count) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: GestureDetector(
          onTap: () => context.push('/staff/history?filter=drafts'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: AppColors.amberSoft,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.yellow.withValues(alpha: 0.4)),
            ),
            child: Row(children: [
              Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.yellow, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(
                child: Text('$count draft${count == 1 ? '' : 's'} saved • Ready to resume',
                    style: const TextStyle(color: AppColors.amberDark, fontSize: 12.5, fontWeight: FontWeight.w500)),
              ),
              const Text('View drafts', style: TextStyle(color: Color(0xFFD97706), fontSize: 12.5, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );

  List<Widget> _completedHeader() {
    final today = DateUtils.dateOnly(DateTime.now());
    final todayCount = _jobs.where((j) {
      final d = _date(j['completedAt'] ?? j['updatedAt']);
      return d != null && DateUtils.dateOnly(d) == today;
    }).length;
    return [
      Container(
        margin: const EdgeInsets.only(bottom: 22),
        padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(colors: [AppColors.white, Color(0xFFF0FDF4)]),
          border: Border.all(color: AppColors.border),
          boxShadow: AppColors.cardShadow,
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.greenDark, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                const Text('PROOF OF WORK',
                    style: TextStyle(color: AppColors.greenDark, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
              ]),
              const SizedBox(height: 6),
              Text('$todayCount Completed Job${todayCount == 1 ? '' : 's'} Today',
                  style: AppTextStyles.h3.copyWith(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.verified_rounded, size: 15, color: AppColors.greenDark),
                const SizedBox(width: 5),
                Text('${_jobs.length} completed in total', style: const TextStyle(color: AppColors.light, fontSize: 13)),
              ]),
            ]),
          ),
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFF065F46), width: 3)),
            child: const Icon(Icons.done_all_rounded, color: Color(0xFF065F46), size: 24),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          const Text('Completed Jobs', style: TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          SoftBadge(label: '${_jobs.length}', color: AppColors.greenDark, fontSize: 11.5),
        ]),
      ),
    ];
  }

  Widget _statusBadge(String status) {
    final (label, color, bg) = switch (status) {
      'completed' => ('Completed', AppColors.greenDark, AppColors.greenSoft),
      'in_progress' => ('Active', AppColors.brand, AppColors.brandSoft),
      'cancelled' => ('Cancelled', AppColors.silver, AppColors.dark4),
      _ => ('Pending', AppColors.amberDark, AppColors.amberSoft),
    };
    return SoftBadge(
      label: label,
      color: color,
      background: bg,
      icon: status == 'completed' ? Icons.check_circle_rounded : null,
      uppercase: status == 'pending',
      fontSize: 11.5,
    );
  }

  Widget _priorityBadge(String p) {
    final (color, bg) = switch (p) {
      'urgent' => (AppColors.red, AppColors.redSoft),
      'high' => (const Color(0xFFBE123C), AppColors.redSoft),
      'low' => (AppColors.silver, AppColors.dark4),
      _ => (AppColors.brandDark, const Color(0xFFEEF2FF)),
    };
    return SoftBadge(label: p[0].toUpperCase() + p.substring(1), color: color, background: bg, fontSize: 11.5);
  }

  Widget _jobCard(Map<String, dynamic> j) {
    final jobId = _jobId(j);
    final priority = (j['priority'] ?? 'normal').toString();
    final status = (j['status'] ?? 'pending').toString();
    final report = _linkedReport(j);
    final reportId = report?['_id']?.toString() ?? report?['id']?.toString() ??
        (j['reportId'] is String ? j['reportId'] as String : null);
    final draftId = report?['status'] == 'draft' ? reportId : null;
    final canSubmit = status != 'completed' && status != 'cancelled';
    final address = j['location'] is Map ? j['location']['address']?.toString() : null;
    final description = (j['description'] ?? '').toString();
    final title = (j['title'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: priority == 'urgent' ? AppColors.red.withValues(alpha: 0.35) : AppColors.border),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: AppTextStyles.h2.copyWith(fontSize: 19, height: 1.2)),
              const SizedBox(height: 3),
              Text('Job ID: ${_shortId(j)}', style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
            ]),
          ),
          const SizedBox(width: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            if (status == 'completed') _priorityBadge(priority),
            _statusBadge(status),
            if (status != 'completed') _priorityBadge(priority),
          ]),
        ]),
        if (description.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(description, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.silver, fontSize: 13)),
        ],
        if (address != null && address.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(children: [
            Container(
              width: 26,
              height: 26,
              decoration: const BoxDecoration(color: AppColors.dark4, shape: BoxShape.circle),
              child: Icon(Icons.location_on_outlined,
                  color: status == 'completed' ? AppColors.brand : AppColors.silver, size: 15),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(address, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.light, fontSize: 13.5)),
            ),
          ]),
        ],
        if (draftId != null && canSubmit) ...[
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () => context.push('/staff/draft/$draftId'),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.amberSoft,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.yellow.withValues(alpha: 0.45)),
              ),
              child: Row(children: [
                const IconTile(icon: Icons.drafts_outlined, color: AppColors.yellow, background: Color(0xFFFEF3C7), size: 32, iconSize: 17, radius: 8),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Report saved as draft',
                        style: TextStyle(color: Color(0xFF78350F), fontSize: 13.5, fontWeight: FontWeight.w600)),
                    if (_date(report?['updatedAt']) != null)
                      Text('Updated ${DateFormat('d MMM, h:mm a').format(_date(report!['updatedAt'])!)}',
                          style: const TextStyle(color: AppColors.amberDark, fontSize: 11.5)),
                  ]),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.amberDark),
              ]),
            ),
          ),
        ],
        if (status == 'completed') ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.dark4,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(children: [
              Row(children: [
                const Icon(Icons.schedule_rounded, size: 16, color: AppColors.greenDark),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _date(j['completedAt']) != null
                        ? DateFormat('d MMM, h:mm a').format(_date(j['completedAt'])!)
                        : 'Completed',
                    style: const TextStyle(color: AppColors.light, fontSize: 13),
                  ),
                ),
                const Icon(Icons.photo_camera_outlined, size: 15, color: AppColors.silver),
                const SizedBox(width: 4),
                const Text('Geo-tagged photos', style: TextStyle(color: AppColors.silver, fontSize: 12)),
              ]),
              const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, color: AppColors.border)),
              Row(children: [
                const Icon(Icons.verified_user_rounded, size: 16, color: AppColors.greenDark),
                const SizedBox(width: 6),
                Text(reportId != null ? 'Proof report: Verified & Stamped' : 'Marked complete',
                    style: const TextStyle(color: AppColors.greenDark, fontSize: 13, fontWeight: FontWeight.w600)),
              ]),
            ]),
          ),
          if (reportId != null) ...[
            const SizedBox(height: 14),
            SecondaryButton(
              label: 'View Report',
              icon: Icons.visibility_outlined,
              color: AppColors.brand,
              fill: const Color(0xFFF1F5F9),
              onPressed: () => context.push('/staff/report/$reportId'),
            ),
          ],
        ],
        if (_isActiveFilter && canSubmit) ...[
          const SizedBox(height: 16),
          Row(children: [
            if (status == 'pending') ...[
              Expanded(
                child: _outlineAction(
                  draftId != null ? Icons.play_arrow_outlined : null,
                  'Start Job',
                  jobId.isEmpty ? null : () => _updateStatus(jobId, 'in_progress'),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: PrimaryButton(
                label: draftId != null ? 'Continue Draft' : 'Submit Report',
                icon: draftId != null ? Icons.drafts_outlined : Icons.photo_camera_outlined,
                color: draftId != null ? const Color(0xFFF59E0B) : AppColors.brand,
                height: 52,
                onPressed: () {
                  if (draftId != null) {
                    context.push('/staff/submit?reportId=$draftId&jobId=$jobId&jobTitle=${Uri.encodeComponent(title)}');
                  } else {
                    context.push('/staff/submit?jobId=$jobId&jobTitle=${Uri.encodeComponent(title)}');
                  }
                },
              ),
            ),
          ]),
        ],
      ]),
    );
  }

  Widget _outlineAction(IconData? icon, String label, VoidCallback? onTap) => Container(
        height: 52,
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.brand.withValues(alpha: 0.55), width: 1.2),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (icon != null) ...[Icon(icon, color: AppColors.brand, size: 19), const SizedBox(width: 6)],
              Text(label, style: const TextStyle(color: AppColors.brand, fontSize: 15, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );

  Widget _emptyState() {
    final label = switch (_statusFilter) {
      'in_progress' => 'active',
      'completed' => 'completed',
      'cancelled' => 'cancelled',
      'pending' => 'pending',
      _ => '',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 90, 36, 24),
      child: Column(children: [
        Stack(clipBehavior: Clip.none, children: [
          Container(
            width: 176,
            height: 176,
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: AppColors.borderSoft),
              boxShadow: const [BoxShadow(color: Color(0x1A0F172A), blurRadius: 28, offset: Offset(0, 10))],
            ),
            padding: const EdgeInsets.all(14),
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFFF1F5FF), Color(0xFFF8FAFC)]),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Stack(alignment: Alignment.center, children: [
                Icon(Icons.settings_rounded, size: 120, color: AppColors.brand.withValues(alpha: 0.12)),
                Container(
                  width: 70,
                  height: 90,
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF93C5FD), width: 2),
                    boxShadow: AppColors.softShadow,
                  ),
                  padding: const EdgeInsets.fromLTRB(9, 16, 9, 8),
                  child: Column(children: [
                    for (var i = 0; i < 4; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(children: [
                          const Icon(Icons.check_circle_rounded, size: 10, color: AppColors.blue),
                          const SizedBox(width: 4),
                          Expanded(child: Container(height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)))),
                        ]),
                      ),
                  ]),
                ),
              ]),
            ),
          ),
          Positioned(
            right: -6,
            bottom: -10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: AppColors.border),
                boxShadow: AppColors.cardShadow,
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.green, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                const Text('Live Sync', style: TextStyle(color: AppColors.text, fontSize: 11.5, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 34),
        Text(label.isEmpty ? 'No jobs yet' : 'No $label jobs',
            textAlign: TextAlign.center, style: AppTextStyles.h1.copyWith(fontSize: 23)),
        const SizedBox(height: 12),
        const Text(
          'Your manager will assign jobs here. Pull down to refresh for new assignments.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.silver, fontSize: 14.5, height: 1.55),
        ),
      ]),
    );
  }
}
