import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/utils/ui_feedback.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_service.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/location_picker_field.dart';
import '../../../shared/widgets/searchable_selection_field.dart';
import '../../../shared/services/places_service.dart';
import '../controllers/owner_controller.dart';

class JobsScreen extends ConsumerStatefulWidget {
  const JobsScreen({super.key});
  @override ConsumerState<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends ConsumerState<JobsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  List<Map<String, dynamic>> _jobs = [];
  bool _loading = true;
  String _statusFilter = 'pending';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tabs.addListener(() {
      setState(() => _statusFilter = ['pending','in_progress','completed'][_tabs.index]);
      _load();
    });
    _load();
    ref.read(ownerControllerProvider.notifier).loadStaff();
    ref.read(ownerControllerProvider.notifier).loadCustomers();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final api = ref.read(apiServiceProvider);
      final res = await api.get('/jobs', params: {'status': _statusFilter});
      if (res.data['success'] == true) {
        setState(() => _jobs = List<Map<String,dynamic>>.from(res.data['data']['jobs'] ?? []));
      }
    } catch (_) {}
    setState(() => _loading = false);
  }

  void _showAssignJob() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.dark2,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => _AssignJobSheet(
        parentContext: context,
        onAssigned: _load,
      ),
    );
  }

  Color _priorityColor(String p) => _jobPriorityColor(p);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        title: const Text('Jobs'),
        bottom: TabBar(
          controller: _tabs, labelColor: AppColors.brand, unselectedLabelColor: AppColors.muted, indicatorColor: AppColors.brand,
          tabs: const [Tab(text: 'Pending'), Tab(text: 'In Progress'), Tab(text: 'Completed')]),
        actions: [IconButton(icon: const Icon(Icons.add_rounded, color: AppColors.brand), onPressed: _showAssignJob)],
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
        : _jobs.isEmpty
          ? EmptyState(type: EmptyType.reports, title: 'No ${_statusFilter.replaceAll('_',' ')} jobs',
              subtitle: 'Assign jobs to staff from the + button',
              actionLabel: 'Assign Job', onAction: _showAssignJob)
          : RefreshIndicator(color: AppColors.brand, onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _jobs.length,
                itemBuilder: (_, i) {
                  final j        = _jobs[i];
                  final priority = j['priority'] ?? 'normal';
                  final customer = j['customerId'];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: AppColors.dark2, borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: priority == 'urgent' ? AppColors.red.withOpacity(0.4) : AppColors.border)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(j['title'] ?? '', style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 15), overflow: TextOverflow.ellipsis)),
                        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: _priorityColor(priority).withOpacity(0.15), borderRadius: BorderRadius.circular(100)),
                          child: Text(priority[0].toUpperCase() + priority.substring(1),
                            style: TextStyle(color: _priorityColor(priority), fontSize: 11, fontWeight: FontWeight.w700))),
                      ]),
                      const SizedBox(height: 6),
                      if (customer != null) Row(children: [
                        const Icon(Icons.person_outline, color: AppColors.brand, size: 14),
                        const SizedBox(width: 4),
                        Text(customer['name'] ?? '', style: const TextStyle(color: AppColors.brand, fontSize: 13, fontWeight: FontWeight.w600)),
                        if (customer['phone'] != null) ...[
                          const Text(' • ', style: TextStyle(color: AppColors.muted)),
                          Text(customer['phone'], style: const TextStyle(color: AppColors.silver, fontSize: 12)),
                        ],
                      ]),
                      Row(children: [
                        const Icon(Icons.person_outline, color: AppColors.muted, size: 14),
                        const SizedBox(width: 4),
                        Text(j['assignedTo']?['name'] ?? '', style: const TextStyle(color: AppColors.silver, fontSize: 13)),
                      ]),
                      if (j['location']?['address'] != null) Row(children: [
                        const Icon(Icons.location_on_outlined, color: AppColors.muted, size: 14),
                        const SizedBox(width: 4),
                        Expanded(child: Text(j['location']['address'], style: const TextStyle(color: AppColors.muted, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      ]),
                      const SizedBox(height: 4),
                      Text(j['createdAt'] != null ? DateFormat('d MMM, h:mm a').format(DateTime.parse(j['createdAt'])) : '',
                        style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                    ]),
                  );
                })),
    );
  }
}

Color _jobPriorityColor(String p) => switch (p) {
  'urgent' => AppColors.red,
  'high'   => AppColors.yellow,
  'low'    => AppColors.muted,
  _        => AppColors.brand,
};

class _AssignJobSheet extends ConsumerStatefulWidget {
  final BuildContext parentContext;
  final Future<void> Function() onAssigned;

  const _AssignJobSheet({required this.parentContext, required this.onAssigned});

  @override
  ConsumerState<_AssignJobSheet> createState() => _AssignJobSheetState();
}

class _AssignJobSheetState extends ConsumerState<_AssignJobSheet> {
  final _titleCtrl = TextEditingController();
  final _descCtrl  = TextEditingController();

  String? _selectedStaffId;
  String? _selectedCustomerId;
  SelectedPlace? _selectedPlace;
  String _priority = 'normal';
  bool _assigning = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _showQuickAddCustomer() {
    final nameCtrl  = TextEditingController();
    final phoneCtrl = TextEditingController();
    bool sending = false;
    String? formError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.dark3,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (addCtx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 24,
          ),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Add Customer',
              style: TextStyle(color: AppColors.white, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            TextFormField(
              controller: nameCtrl,
              enabled: !sending,
              style: const TextStyle(color: AppColors.white),
              decoration: const InputDecoration(
                labelText: 'Customer Name *',
                prefixIcon: Icon(Icons.person_outline, color: AppColors.muted),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: phoneCtrl,
              enabled: !sending,
              keyboardType: TextInputType.phone,
              style: const TextStyle(color: AppColors.white),
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
              decoration: const InputDecoration(
                labelText: 'Phone Number *',
                hintText: '10-digit mobile number',
                prefixText: '+91 ',
                prefixStyle: TextStyle(color: AppColors.silver),
              ),
            ),
            if (formError != null) ...[
              const SizedBox(height: 12),
              Text(formError!, style: const TextStyle(color: AppColors.red, fontSize: 13)),
            ],
            const SizedBox(height: 20),
            AppButton(
              label: 'Add Customer',
              isLoading: sending,
              onPressed: sending ? null : () async {
                final name = nameCtrl.text.trim();
                final digits = phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
                final phone = digits.length == 12 && digits.startsWith('91') ? digits.substring(2) : digits;
                if (name.isEmpty) {
                  setSheet(() => formError = 'Customer name is required');
                  return;
                }
                if (!RegExp(r'^[6-9]\d{9}$').hasMatch(phone)) {
                  setSheet(() => formError = 'Enter a valid 10-digit Indian mobile number');
                  return;
                }
                setSheet(() { sending = true; formError = null; });
                final id = await ref.read(ownerControllerProvider.notifier).addCustomer(name, phone, '', '');
                if (!ctx.mounted) return;
                if (id == null) {
                  setSheet(() {
                    sending = false;
                    formError = 'Could not add customer. Check your plan limit.';
                  });
                  return;
                }
                Navigator.pop(addCtx);
                setState(() => _selectedCustomerId = id);
                if (widget.parentContext.mounted) {
                  ScaffoldMessenger.of(widget.parentContext).showSnackBar(const SnackBar(
                    content: Text('Customer added and selected'),
                    backgroundColor: AppColors.green,
                  ));
                }
              },
            ),
            const SizedBox(height: 20),
          ]),
        ),
      ),
    );
  }

  Future<void> _assignJob() async {
    if (_titleCtrl.text.isEmpty || _selectedStaffId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Job title and staff are required'),
        backgroundColor: AppColors.red,
      ));
      return;
    }

    setState(() => _assigning = true);
    try {
      final api = ref.read(apiServiceProvider);
      await api.post('/jobs', data: {
        'title':       _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'assignedTo':  _selectedStaffId,
        if (_selectedCustomerId != null) 'customerId': _selectedCustomerId,
        'priority':    _priority,
        if (_selectedPlace != null)
          'location': {
            'address':   _selectedPlace!.address,
            'latitude':  _selectedPlace!.latitude,
            'longitude': _selectedPlace!.longitude,
          },
      });
      if (!mounted) return;
      Navigator.pop(context);
      await widget.onAssigned();
      if (!widget.parentContext.mounted) return;
      ScaffoldMessenger.of(widget.parentContext).showSnackBar(const SnackBar(
        content: Text('Job assigned!'),
        backgroundColor: AppColors.green,
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _assigning = false);
      showErrorSnackBar(context, e, fallback: 'Could not assign the job. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ownerControllerProvider);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20,
        right: 20,
        top: 24,
      ),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Assign New Job',
            style: TextStyle(color: AppColors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          TextFormField(
            controller: _titleCtrl,
            enabled: !_assigning,
            style: const TextStyle(color: AppColors.white),
            decoration: const InputDecoration(
              labelText: 'Job Title *',
              prefixIcon: Icon(Icons.work_outline, color: AppColors.muted),
            ),
          ),
          const SizedBox(height: 12),
          SearchableSelectionField(
            sectionLabel: 'CUSTOMER',
            searchHint: 'Search customers by name or phone',
            emptyMessage: 'No customers match your search',
            items: state.customers.map((c) => c.toJson()).toList(),
            selectedId: _selectedCustomerId,
            itemId: (c) => c['_id']?.toString() ?? '',
            itemTitle: (c) => c['name']?.toString() ?? '',
            itemSubtitle: (c) {
              final phone = c['phone']?.toString() ?? '';
              final email = c['email']?.toString() ?? '';
              if (phone.isNotEmpty && email.isNotEmpty) return '$phone • $email';
              return phone.isNotEmpty ? phone : email;
            },
            onSelected: (id) => setState(() => _selectedCustomerId = id),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _assigning ? null : _showQuickAddCustomer,
            icon: const Icon(Icons.person_add_alt_1_outlined, size: 18, color: AppColors.brand),
            label: const Text('Add Customer', style: TextStyle(color: AppColors.brand, fontWeight: FontWeight.w600)),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(height: 16),
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
              if (phone.isNotEmpty && email.isNotEmpty) return '$phone • $email';
              return phone.isNotEmpty ? phone : email;
            },
            itemEnabled: (s) =>
                s['invitePending'] != true && s['inviteStatus'] != 'pending',
            onSelected: (id) => setState(() => _selectedStaffId = id),
          ),
          const SizedBox(height: 12),
          LocationPickerField(
            onPlaceSelected: (place) => setState(() => _selectedPlace = place),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _descCtrl,
            enabled: !_assigning,
            maxLines: 2,
            style: const TextStyle(color: AppColors.white),
            decoration: const InputDecoration(labelText: 'Description (optional)'),
          ),
          const SizedBox(height: 12),
          const Text('PRIORITY',
            style: TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.2)),
          const SizedBox(height: 8),
          Row(children: [
            for (final p in ['low', 'normal', 'high', 'urgent'])
              GestureDetector(
                onTap: _assigning ? null : () => setState(() => _priority = p),
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _priority == p
                        ? _jobPriorityColor(p).withOpacity(0.2)
                        : AppColors.dark3,
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                      color: _priority == p ? _jobPriorityColor(p) : AppColors.border,
                    ),
                  ),
                  child: Text(
                    p[0].toUpperCase() + p.substring(1),
                    style: TextStyle(
                      color: _priority == p ? _jobPriorityColor(p) : AppColors.silver,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 20),
          AppButton(
            label: 'Assign Job',
            icon: Icons.assignment_ind_outlined,
            isLoading: _assigning,
            onPressed: _assigning ? null : _assignJob,
          ),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }
}