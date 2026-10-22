import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/utils/api_error_utils.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_service.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../../../shared/widgets/location_picker_field.dart';
import '../../../shared/widgets/searchable_selection_field.dart';
import '../../../shared/services/places_service.dart';
import '../../../shared/services/review_service.dart';
import '../controllers/owner_controller.dart';
import '../../../shared/permissions/app_permissions.dart';
import '../../../shared/permissions/permission_session.dart';

class JobsScreen extends ConsumerStatefulWidget {
  const JobsScreen({super.key});
  @override
  ConsumerState<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends ConsumerState<JobsScreen>
    with SingleTickerProviderStateMixin {
  static const _statuses = ['pending', 'in_progress', 'completed'];
  late TabController _tabs;
  List<Map<String, dynamic>> _jobs = [];
  final Map<String, int> _counts = {};
  bool _loading = true;
  String _statusFilter = 'pending';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tabs.addListener(() {
      if (_tabs.indexIsChanging) return;
      final next = _statuses[_tabs.index];
      if (next == _statusFilter) return;
      setState(() => _statusFilter = next);
      _load();
    });
    _load();
    _loadCounts();
    ref.read(ownerControllerProvider.notifier).loadStaff();
    ref.read(ownerControllerProvider.notifier).loadCustomers();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>?> _fetch(String status) async {
    try {
      final api = ref.read(apiServiceProvider);
      final res = await api.get('/jobs', params: {'status': status});
      if (res.data['success'] == true) {
        return List<Map<String, dynamic>>.from(res.data['data']['jobs'] ?? []);
      }
    } catch (_) {}
    return null;
  }

  Future<void> _load() async {
    final status = _statusFilter;
    setState(() => _loading = true);
    final jobs = await _fetch(status);
    if (!mounted || status != _statusFilter) return;
    setState(() {
      if (jobs != null) {
        _jobs = jobs;
        _counts[status] = jobs.length;
      }
      _loading = false;
    });
  }

  /// Tab badges show how many jobs each status holds.
  Future<void> _loadCounts() async {
    for (final status in _statuses) {
      if (status == _statusFilter) continue;
      final jobs = await _fetch(status);
      if (!mounted) return;
      if (jobs != null) setState(() => _counts[status] = jobs.length);
    }
  }

  Future<void> _reloadAll() async {
    await _load();
    await _loadCounts();
  }

  void _showAssignJob() {
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _AssignJobSheet(
        parentContext: context,
        onAssigned: _reloadAll,
      ),
    ));
  }

  Future<void> _call(String phone) async {
    await launchUrl(Uri(scheme: 'tel', path: phone));
  }

  @override
  Widget build(BuildContext context) {
    final count = _counts[_statusFilter] ?? 0;
    final (pillLabel, pillColor) = switch (_statusFilter) {
      'in_progress' => ('$count In Progress', AppColors.brand),
      'completed' => ('$count Completed', AppColors.greenDark),
      _ => ('$count Active', AppColors.brand),
    };
    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      backgroundColor: AppColors.dark,
      body: SafeArea(
        child: Column(children: [
          PageHeader(
            title: 'Jobs',
            showBack: canPop,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
            titleTrailing: SoftBadge(label: pillLabel, color: pillColor, fontSize: 12),
            actions: [
              if (ref.watch(permissionSessionProvider).can(AppPermissions.jobsCreate))
                RoundAddButton(onTap: _showAssignJob, size: 42),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: AnimatedBuilder(
              animation: _tabs,
              builder: (_, __) => TabBar(
                controller: _tabs,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelPadding: const EdgeInsets.symmetric(horizontal: 12),
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: const UnderlineTabIndicator(
                  borderSide: BorderSide(color: AppColors.brand, width: 2.5),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(3)),
                ),
                tabs: [
                  for (var i = 0; i < 3; i++)
                    CountTab(
                      label: const ['Pending', 'In Progress', 'Completed'][i],
                      count: _counts[_statuses[i]],
                      selected: _tabs.index == i,
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
                : RefreshIndicator(
                    color: AppColors.brand,
                    onRefresh: _reloadAll,
                    child: _jobs.isEmpty
                        ? ListView(children: [
                            const SizedBox(height: 90),
                            _JobsEmptyState(status: _statusFilter.replaceAll('_', ' ')),
                          ])
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                            itemCount: _jobs.length,
                            itemBuilder: (_, i) => _jobCard(_jobs[i]),
                          ),
                  ),
          ),
        ]),
      ),
    );
  }

  Widget _jobCard(Map<String, dynamic> j) {
    final priority = (j['priority'] ?? 'normal').toString();
    final status = (j['status'] ?? _statusFilter).toString();
    final completed = status == 'completed';
    final customer = j['customerId'] is Map ? j['customerId'] as Map : null;
    final assignee = j['assignedTo'] is Map ? j['assignedTo'] as Map : null;
    final id = (j['_id'] ?? '').toString();
    final code = id.length >= 6 ? '#JOB-${id.substring(id.length - 6).toUpperCase()}' : '#JOB';
    final address = j['location'] is Map ? j['location']['address']?.toString() : null;
    final createdAt = DateTime.tryParse(j['createdAt']?.toString() ?? '');
    final reportId = j['reportId'] is Map ? j['reportId']['_id']?.toString() : j['reportId']?.toString();
    final title = (j['title'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: priority == 'urgent' ? AppColors.red.withValues(alpha: 0.35) : AppColors.border),
        boxShadow: AppColors.cardShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 4, color: AppColors.brand),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (completed)
                    Row(children: [
                      Flexible(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.h3.copyWith(fontSize: 18, fontWeight: FontWeight.w700))),
                      const SizedBox(width: 10),
                      _priorityBadge(priority),
                      const Spacer(),
                      const SoftBadge(label: 'Completed', color: AppColors.greenDark, icon: Icons.check_rounded, fontSize: 12),
                    ])
                  else ...[
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.dark4,
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text(code, style: const TextStyle(color: AppColors.light, fontSize: 11.5, fontWeight: FontWeight.w600)),
                      ),
                      const Spacer(),
                      _priorityBadge(priority),
                    ]),
                    const SizedBox(height: 6),
                    Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.h3.copyWith(fontSize: 18, fontWeight: FontWeight.w700)),
                  ],
                  const SizedBox(height: 10),
                  if (customer != null)
                    _infoRow(
                      Icons.person_outline_rounded,
                      AppColors.brand,
                      Row(children: [
                        Flexible(child: Text(customer['name']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.brand, fontSize: 14, fontWeight: FontWeight.w600))),
                        if ((customer['phone'] ?? '').toString().isNotEmpty) ...[
                          const Padding(padding: EdgeInsets.symmetric(horizontal: 6),
                            child: Text('•', style: TextStyle(color: AppColors.muted))),
                          Text(customer['phone'].toString(), style: const TextStyle(color: AppColors.light, fontSize: 14)),
                        ],
                      ]),
                      trailing: (customer['phone'] ?? '').toString().isEmpty
                          ? null
                          : GestureDetector(
                              onTap: () => _call(customer['phone'].toString()),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.brandSoft,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppColors.brandBorder),
                                ),
                                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(Icons.call_outlined, size: 13, color: AppColors.brand),
                                  SizedBox(width: 4),
                                  Text('Call', style: TextStyle(color: AppColors.brand, fontSize: 12, fontWeight: FontWeight.w600)),
                                ]),
                              ),
                            ),
                    ),
                  if (assignee != null)
                    _infoRow(
                      Icons.engineering_outlined,
                      AppColors.silver,
                      Row(children: [
                        Flexible(child: Text(assignee['name']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.light, fontSize: 14))),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(color: AppColors.dark4, borderRadius: BorderRadius.circular(4)),
                          child: const Text('Assignee', style: TextStyle(color: AppColors.silver, fontSize: 11, fontWeight: FontWeight.w500)),
                        ),
                      ]),
                    ),
                  if (address != null && address.isNotEmpty)
                    _infoRow(Icons.location_on_outlined, AppColors.red,
                      Text(address, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.light, fontSize: 14))),
                  if (createdAt != null)
                    _infoRow(Icons.schedule_rounded, AppColors.muted,
                      Text(DateFormat('d MMM, h:mm a').format(createdAt.toLocal()),
                        style: const TextStyle(color: AppColors.muted, fontSize: 13.5))),
                  if (status == 'in_progress') ...[
                    const SizedBox(height: 8),
                    _progressPanel(reportId != null),
                  ],
                  if (completed) ...[
                    const SizedBox(height: 8),
                    _completedPanel(reportId, assignee?['name']?.toString()),
                  ],
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _priorityBadge(String p) {
    final color = _jobPriorityColor(p);
    return SoftBadge(
      label: p[0].toUpperCase() + p.substring(1),
      color: color == AppColors.yellow ? AppColors.amberDark : color,
      background: color == AppColors.yellow ? AppColors.amberSoft : null,
      dot: true,
      fontSize: 12.5,
    );
  }

  Widget _infoRow(IconData icon, Color color, Widget child, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Row(children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: 10),
      Expanded(child: child),
      if (trailing != null) trailing,
    ]),
  );

  /// Steps: assigned → started → proof draft → completed.
  Widget _progressPanel(bool hasDraft) {
    final done = hasDraft ? 3 : 2;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.dark3,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(children: [
        Row(children: [
          const Expanded(child: Text('Inspection & Proof Upload',
            style: TextStyle(color: AppColors.light, fontSize: 13, fontWeight: FontWeight.w500))),
          Text('$done of 4 Steps', style: const TextStyle(color: AppColors.brand, fontSize: 13, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(value: done / 4, minHeight: 7,
            color: AppColors.brand, backgroundColor: AppColors.border),
        ),
      ]),
    );
  }

  Widget _completedPanel(String? reportId, String? staffName) {
    return GestureDetector(
      onTap: reportId == null ? null : () => context.push('/owner/report/$reportId'),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.greenSoft,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.green.withValues(alpha: 0.30)),
        ),
        child: Row(children: [
          const Icon(Icons.photo_camera_outlined, size: 18, color: AppColors.greenDark),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              reportId == null
                  ? 'Job marked complete'
                  : 'Proof photos submitted${staffName == null ? '' : ' • by $staffName'}',
              style: const TextStyle(color: AppColors.greenDark, fontSize: 13, fontWeight: FontWeight.w500, height: 1.35),
            ),
          ),
          if (reportId != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.green.withValues(alpha: 0.45)),
              ),
              child: const Text('Verified', style: TextStyle(color: AppColors.greenDark, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
        ]),
      ),
    );
  }
}

class _JobsEmptyState extends StatelessWidget {
  final String status;
  const _JobsEmptyState({required this.status});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(children: [
        SizedBox(
          width: 200,
          height: 160,
          child: Stack(alignment: Alignment.center, children: [
            Positioned(
              bottom: 8,
              child: Container(
                width: 170,
                height: 120,
                decoration: BoxDecoration(color: AppColors.brandSoft, borderRadius: BorderRadius.circular(80)),
              ),
            ),
            Positioned(
              top: 18,
              child: Container(
                width: 92,
                height: 118,
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: AppColors.cardShadow,
                ),
                padding: const EdgeInsets.fromLTRB(14, 16, 14, 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Center(child: Icon(Icons.business_center_rounded, size: 34, color: AppColors.muted.withValues(alpha: 0.8))),
                  const SizedBox(height: 10),
                  for (final w in [56.0, 46.0, 38.0])
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      width: w,
                      height: 5,
                      decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(3)),
                    ),
                ]),
              ),
            ),
            Positioned(
              right: 38,
              bottom: 18,
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.silver, width: 4),
                ),
                child: const Icon(Icons.close_rounded, color: AppColors.silver, size: 24),
              ),
            ),
            const Positioned(
              right: 30,
              top: 6,
              child: Icon(Icons.send_rounded, color: AppColors.blue, size: 26),
            ),
          ]),
        ),
        const SizedBox(height: 20),
        Text('No $status jobs', textAlign: TextAlign.center,
          style: AppTextStyles.h3.copyWith(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        const Text.rich(
          TextSpan(children: [
            TextSpan(text: 'Assign jobs to staff from the '),
            TextSpan(text: '+', style: TextStyle(color: AppColors.brand, fontWeight: FontWeight.w700)),
            TextSpan(text: ' button to dispatch now.'),
          ]),
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.silver, fontSize: 14, height: 1.55),
        ),
      ]),
    );
  }
}

Color _jobPriorityColor(String p) => switch (p) {
      'urgent' => AppColors.red,
      'high' => AppColors.yellow,
      'low' => AppColors.silver,
      _ => AppColors.brand,
    };

class _AssignJobSheet extends ConsumerStatefulWidget {
  final BuildContext parentContext;
  final Future<void> Function() onAssigned;

  const _AssignJobSheet(
      {required this.parentContext, required this.onAssigned});

  @override
  ConsumerState<_AssignJobSheet> createState() => _AssignJobSheetState();
}

class _AssignJobSheetState extends ConsumerState<_AssignJobSheet> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  String? _selectedStaffId;
  String? _selectedCustomerId;
  SelectedPlace? _selectedPlace;
  String _priority = 'normal';
  bool _assigning = false;
  String? _assignError;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _showQuickAddCustomer() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    bool sending = false;
    String? formError;

    AppSheet.show(
      context,
      builder: (addCtx) => StatefulBuilder(
        builder: (ctx, setSheet) => AppSheet(
          title: 'Add Customer',
          subtitle: 'Add a new client record directly to this job',
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Divider(height: 1, color: AppColors.borderSoft),
                const SizedBox(height: 18),
                const FieldLabel('Customer Name', required: true),
                TextFormField(
                  controller: nameCtrl,
                  enabled: !sending,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  style: const TextStyle(color: AppColors.text),
                  decoration: const InputDecoration(
                    hintText: 'e.g. Acme Logistics or John Doe',
                    prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
                  ),
                ),
                const SizedBox(height: 16),
                const FieldLabel('Phone Number', required: true),
                TextFormField(
                  controller: phoneCtrl,
                  enabled: !sending,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: AppColors.text),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  decoration: const InputDecoration(
                    hintText: '10-digit mobile number',
                    prefixIcon: Icon(Icons.phone_outlined, size: 20),
                    prefixText: '+91 ',
                    prefixStyle: TextStyle(color: AppColors.silver),
                  ),
                ),
                const SizedBox(height: 16),
                const FieldLabel('Email Address', hint: 'Optional'),
                TextFormField(
                  controller: emailCtrl,
                  enabled: !sending,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: AppColors.text),
                  decoration: const InputDecoration(
                    hintText: 'client@organization.com',
                    prefixIcon: Icon(Icons.mail_outline_rounded, size: 20),
                  ),
                ),
                if (formError != null) ...[
                  const SizedBox(height: 12),
                  Text(formError!,
                      style:
                          const TextStyle(color: AppColors.red, fontSize: 13)),
                ],
                const SizedBox(height: 22),
                PrimaryButton(
                  label: 'Add Customer',
                  icon: Icons.add_rounded,
                  loading: sending,
                  onPressed: sending
                      ? null
                      : () async {
                          final name = nameCtrl.text.trim();
                          final email = emailCtrl.text.trim();
                          final digits =
                              phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
                          final phone =
                              digits.length == 12 && digits.startsWith('91')
                                  ? digits.substring(2)
                                  : digits;
                          if (name.isEmpty) {
                            setSheet(
                                () => formError = 'Customer name is required');
                            return;
                          }
                          if (!RegExp(r'^[6-9]\d{9}$').hasMatch(phone)) {
                            setSheet(() => formError =
                                'Enter a valid 10-digit Indian mobile number');
                            return;
                          }
                          if (email.isNotEmpty &&
                              !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
                            setSheet(() => formError = 'Enter a valid email address');
                            return;
                          }
                          setSheet(() {
                            sending = true;
                            formError = null;
                          });
                          final id = await ref
                              .read(ownerControllerProvider.notifier)
                              .addCustomer(name, phone, '', '', '', email: email);
                          if (!ctx.mounted) return;
                          if (id == null) {
                            setSheet(() {
                              sending = false;
                              formError =
                                  'Could not add customer. Check your plan limit.';
                            });
                            return;
                          }
                          Navigator.pop(addCtx);
                          setState(() => _selectedCustomerId = id);
                          if (widget.parentContext.mounted) {
                            ScaffoldMessenger.of(widget.parentContext)
                                .showSnackBar(const SnackBar(
                              content: Text('Customer added and selected'),
                              backgroundColor: AppColors.green,
                            ));
                          }
                        },
                ),
              ]),
        ),
      ),
    );
  }

  Future<void> _assignJob() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty || _selectedStaffId == null) {
      setState(() {
        _assignError = title.isEmpty && _selectedStaffId == null
            ? 'Enter a job title and select a staff member.'
            : title.isEmpty
                ? 'Enter a job title.'
                : 'Select a staff member to assign this job.';
      });
      return;
    }

    setState(() {
      _assigning = true;
      _assignError = null;
    });
    try {
      final api = ref.read(apiServiceProvider);
      final res = await api.post('/jobs', data: {
        'title': title,
        'description': _descCtrl.text.trim(),
        'assignedTo': _selectedStaffId,
        if (_selectedCustomerId != null) 'customerId': _selectedCustomerId,
        'priority': _priority,
        if (_selectedPlace != null)
          'location': {
            'address': _selectedPlace!.address,
            'latitude': _selectedPlace!.latitude,
            'longitude': _selectedPlace!.longitude,
          },
      });

      if (!mounted) return;
      if (res.data is! Map || res.data['success'] != true) {
        setState(() {
          _assigning = false;
          _assignError = res.data is Map && res.data['message'] is String
              ? res.data['message'] as String
              : 'Could not assign the job. Please try again.';
        });
        return;
      }

      if (!widget.parentContext.mounted) return;
      final messenger = ScaffoldMessenger.of(widget.parentContext);
      Navigator.pop(context);
      widget.onAssigned();
      messenger.showSnackBar(const SnackBar(
        content: Text('Job assigned successfully.'),
        backgroundColor: AppColors.green,
      ));
      ReviewService.maybePromptAfterSuccess();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _assigning = false;
        _assignError = friendlyErrorMessage(
          e,
          fallback: 'Could not assign the job. Please try again.',
        );
      });
    }
  }

  Widget _section(String label, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      Text(label, style: const TextStyle(color: AppColors.silver, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
      const Spacer(),
      if (trailing != null) trailing,
    ]),
  );

  Widget _priorityOption(String p) {
    final selected = _priority == p;
    final color = _jobPriorityColor(p);
    final fg = switch (p) {
      'low' => AppColors.light,
      'high' => AppColors.amberDark,
      _ => color,
    };
    return Expanded(
      child: GestureDetector(
        onTap: _assigning ? null : () => setState(() => _priority = p),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 42,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.08) : AppColors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? color : (p == 'low' ? AppColors.border : color.withValues(alpha: 0.30)),
              width: selected ? 1.6 : 1,
            ),
            boxShadow: AppColors.softShadow,
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (selected) ...[
              Container(width: 5, height: 5, decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
              const SizedBox(width: 5),
            ],
            Text(p[0].toUpperCase() + p.substring(1),
                style: TextStyle(color: fg, fontSize: 13.5, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ownerControllerProvider);

    return PopScope(
      canPop: !_assigning,
      child: Scaffold(
        backgroundColor: AppColors.dark,
        body: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
              child: Row(children: [
                IconButton(
                  onPressed: _assigning ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                  color: AppColors.text,
                  tooltip: 'Back',
                ),
                const SizedBox(width: 4),
                Text('Assign New Job', style: AppTextStyles.pageTitle.copyWith(fontSize: 21)),
              ]),
            ),
            const Divider(height: 1, color: AppColors.border),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _section('JOB INFORMATION'),
                    TextFormField(
                      controller: _titleCtrl,
                      enabled: !_assigning,
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w500),
                      decoration: const InputDecoration(
                        hintText: 'Job title',
                        fillColor: AppColors.white,
                        prefixIcon: Icon(Icons.business_center_outlined, size: 20),
                        suffixText: 'Required',
                        suffixStyle: TextStyle(color: AppColors.muted, fontSize: 12.5),
                      ),
                    ),
                    const SizedBox(height: 22),
                    SearchableSelectionField(
                      sectionLabel: 'CUSTOMER',
                      labelTrailing: const Text('Search or create', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                      helperTrailing: GestureDetector(
                        onTap: _assigning ? null : _showQuickAddCustomer,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: AppColors.brandSoft,
                            borderRadius: BorderRadius.circular(100),
                            border: Border.all(color: AppColors.brandBorder),
                            boxShadow: AppColors.softShadow,
                          ),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.person_add_alt_outlined, size: 16, color: AppColors.brand),
                            SizedBox(width: 6),
                            Text('Add Customer', style: TextStyle(color: AppColors.brand, fontWeight: FontWeight.w600, fontSize: 13)),
                          ]),
                        ),
                      ),
                      searchHint: 'Search customers by name or phone',
                      emptyMessage: 'No customers match your search',
                      items: state.customers.map((c) => c.toJson()).toList(),
                      selectedId: _selectedCustomerId,
                      itemId: (c) => c['_id']?.toString() ?? '',
                      itemTitle: (c) => c['name']?.toString() ?? '',
                      itemSubtitle: (c) {
                        final phone = c['phone']?.toString() ?? '';
                        final email = c['email']?.toString() ?? '';
                        if (phone.isNotEmpty && email.isNotEmpty) {
                          return '$phone • $email';
                        }
                        return phone.isNotEmpty ? phone : email;
                      },
                      onSelected: (id) => setState(() => _selectedCustomerId = id),
                    ),
                    const SizedBox(height: 22),
                    SearchableSelectionField(
                      sectionLabel: 'ASSIGN TO',
                      searchHint: 'Search staff by name, phone or email',
                      emptyMessage: 'No staff match your search',
                      items: state.staffList,
                      selectedId: _selectedStaffId,
                      itemId: (s) => s['_id']?.toString() ?? '',
                      itemTitle: (s) => s['name']?.toString() ?? '',
                      itemSubtitle: (s) {
                        final phone = s['phone']?.toString() ?? '';
                        final email = s['email']?.toString() ?? '';
                        if (phone.isNotEmpty && email.isNotEmpty) {
                          return '$phone • $email';
                        }
                        return phone.isNotEmpty ? phone : email;
                      },
                      itemEnabled: (s) =>
                          s['invitePending'] != true &&
                          s['inviteStatus'] != 'pending',
                      onSelected: (id) => setState(() => _selectedStaffId = id),
                    ),
                    const SizedBox(height: 22),
                    LocationPickerField(
                      onPlaceSelected: (place) =>
                          setState(() => _selectedPlace = place),
                    ),
                    const SizedBox(height: 22),
                    const Row(children: [
                      Text('DESCRIPTION', style: TextStyle(color: AppColors.silver, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                      SizedBox(width: 4),
                      Text('(optional)', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                    ]),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _descCtrl,
                      enabled: !_assigning,
                      minLines: 3,
                      maxLines: 5,
                      maxLength: 300,
                      style: const TextStyle(color: AppColors.text),
                      decoration: const InputDecoration(
                        fillColor: AppColors.white,
                        hintText: 'Provide specific notes, gate codes, or requirements for the assignee...',
                      ),
                    ),
                    const SizedBox(height: 14),
                    _section('PRIORITY', trailing: const Text('Response time indicator', style: TextStyle(color: AppColors.muted, fontSize: 12))),
                    Transform.translate(
                      offset: const Offset(-4, 0),
                      child: SizedBox(
                        width: MediaQuery.sizeOf(context).width - 32,
                        child: Row(children: [for (final p in ['low', 'normal', 'high', 'urgent']) _priorityOption(p)]),
                      ),
                    ),
                    if (_assignError != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.redSoft,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.red.withValues(alpha: 0.35)),
                        ),
                        child: Text(
                          _assignError!,
                          style: const TextStyle(color: AppColors.red, fontSize: 13),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: const BoxDecoration(
                color: AppColors.white,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: PrimaryButton(
                label: 'Assign Job',
                icon: Icons.assignment_turned_in_outlined,
                loading: _assigning,
                onPressed: _assigning ? null : _assignJob,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
