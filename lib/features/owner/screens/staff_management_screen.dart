import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/app_button.dart';
import '../controllers/owner_controller.dart';

class StaffManagementScreen extends ConsumerStatefulWidget {
  const StaffManagementScreen({super.key});
  @override
  ConsumerState<StaffManagementScreen> createState() => _StaffManagementScreenState();
}

class _StaffManagementScreenState extends ConsumerState<StaffManagementScreen> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await ref.read(ownerControllerProvider.notifier).loadStaff();
      if (mounted) setState(() => _loading = false);
    });
  }

  void _showAddStaffSheet() {
    final parentContext = context;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.dark2,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => _AddStaffSheet(
        parentContext: parentContext,
        onSubmit: ({required String name, required String phone, required String email}) async {
          return ref.read(ownerControllerProvider.notifier).addStaff(
            name: name,
            phone: phone,
            email: email,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ownerControllerProvider);
    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        title: const Text('Staff Management'),
        actions: [
          IconButton(icon: const Icon(Icons.person_add_outlined, color: AppColors.brand), onPressed: _showAddStaffSheet),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
          : state.staffList.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.people_outline, color: AppColors.muted, size: 60),
                  const SizedBox(height: 16),
                  const Text('No staff added yet', style: TextStyle(color: AppColors.silver, fontSize: 16)),
                  const SizedBox(height: 20),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: AppButton(label: 'Add First Staff Member', onPressed: _showAddStaffSheet)),
                ]))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: state.staffList.length,
                  itemBuilder: (_, i) {
                    final s = state.staffList[i];
                    final pending = s['invitePending'] == true || s['inviteStatus'] == 'pending';
                    final name = (s['name'] ?? 'Staff').toString();
                    final phone = (s['phone'] ?? '').toString();
                    final email = (s['email'] ?? '').toString();
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: AppColors.dark2, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
                      child: Row(children: [
                        CircleAvatar(
                          backgroundColor: (pending ? AppColors.yellow : AppColors.brand).withValues(alpha: 0.2),
                          radius: 20,
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: TextStyle(
                              color: pending ? AppColors.yellow : AppColors.brand,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(name, style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w600)),
                          Text(phone, style: const TextStyle(color: AppColors.silver, fontSize: 12)),
                          if (email.isNotEmpty)
                            Text(email, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                          const SizedBox(height: 4),
                          if (pending)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.yellow.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(100),
                                border: Border.all(color: AppColors.yellow.withValues(alpha: 0.35)),
                              ),
                              child: const Text(
                                'Invitation yet to be accepted',
                                style: TextStyle(color: AppColors.yellow, fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            )
                          else
                            Text('Target: ${s['dailyTarget'] ?? 0} jobs/day', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                        ])),
                        PopupMenuButton(
                          color: AppColors.dark3,
                          itemBuilder: (_) => [
                            if (!pending)
                              const PopupMenuItem(value: 'target', child: Text('Set Target', style: TextStyle(color: AppColors.white))),
                            PopupMenuItem(
                              value: 'remove',
                              child: Text(pending ? 'Cancel invite' : 'Remove', style: const TextStyle(color: AppColors.red)),
                            ),
                          ],
                          onSelected: (val) {
                            if (val == 'remove') ref.read(ownerControllerProvider.notifier).removeStaff(s['_id']);
                          },
                        ),
                      ]),
                    );
                  }),
    );
  }
}

typedef _AddStaffSubmit = Future<({bool ok, String message})> Function({
  required String name,
  required String phone,
  required String email,
});

class _AddStaffSheet extends StatefulWidget {
  final BuildContext parentContext;
  final _AddStaffSubmit onSubmit;
  const _AddStaffSheet({required this.parentContext, required this.onSubmit});

  @override
  State<_AddStaffSheet> createState() => _AddStaffSheetState();
}

class _AddStaffSheetState extends State<_AddStaffSheet> {
  final _nameCtrl  = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  bool _sending = false;
  bool _succeeded = false;
  String? _formError;
  String? _successMessage;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  String? _validatePhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    final phone = digits.length == 12 && digits.startsWith('91') ? digits.substring(2) : digits;
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(phone)) {
      return 'Enter a valid 10-digit Indian mobile number';
    }
    return null;
  }

  String _normalizePhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    return digits.length == 12 && digits.startsWith('91') ? digits.substring(2) : digits;
  }

  Future<void> _sendInvite() async {
    final name = _nameCtrl.text.trim();
    final phoneErr = _validatePhone(_phoneCtrl.text);
    if (name.isEmpty) {
      setState(() => _formError = 'Name is required');
      return;
    }
    if (phoneErr != null) {
      setState(() => _formError = phoneErr);
      return;
    }
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _formError = 'Email is required to send the invitation');
      return;
    }
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _formError = 'Enter a valid email address');
      return;
    }

    setState(() {
      _sending = true;
      _formError = null;
    });

    final result = await widget.onSubmit(
      name: name,
      phone: _normalizePhone(_phoneCtrl.text),
      email: email,
    );

    if (!mounted) return;

    if (!result.ok) {
      setState(() {
        _sending = false;
        _formError = result.message;
      });
      return;
    }

    setState(() {
      _sending = false;
      _succeeded = true;
      _successMessage = result.message;
    });

    await Future.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;
    Navigator.pop(context);
    if (!widget.parentContext.mounted) return;
    ScaffoldMessenger.of(widget.parentContext)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(result.message),
        backgroundColor: AppColors.green,
        duration: const Duration(seconds: 3),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_sending,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 20,
          right: 20,
          top: 24,
        ),
        child: _succeeded ? _buildSuccess() : _buildForm(),
      ),
    );
  }

  Widget _buildSuccess() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AppColors.green.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_rounded, color: AppColors.green, size: 40),
        ),
        const SizedBox(height: 20),
        const Text('Invitation sent',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.white)),
        const SizedBox(height: 8),
        Text(
          _successMessage ?? 'Your staff member will receive the invite shortly.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.silver, fontSize: 14, height: 1.45),
        ),
      ]),
    );
  }

  Widget _buildForm() {
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Add Staff Member',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.white)),
      const SizedBox(height: 20),
      TextFormField(
        controller: _nameCtrl,
        enabled: !_sending,
        style: const TextStyle(color: AppColors.white),
        decoration: const InputDecoration(labelText: 'Full Name'),
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _phoneCtrl,
        enabled: !_sending,
        keyboardType: TextInputType.phone,
        style: const TextStyle(color: AppColors.white),
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(10),
        ],
        decoration: const InputDecoration(
          labelText: 'Phone Number',
          hintText: '10-digit mobile number',
          prefixText: '+91 ',
          prefixStyle: TextStyle(color: AppColors.silver),
        ),
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _emailCtrl,
        enabled: !_sending,
        keyboardType: TextInputType.emailAddress,
        style: const TextStyle(color: AppColors.white),
        decoration: const InputDecoration(
          labelText: 'Email *',
          hintText: 'Invitation will be sent to this email',
        ),
      ),
      if (_formError != null) ...[
        const SizedBox(height: 12),
        Text(_formError!, style: const TextStyle(color: AppColors.red, fontSize: 13)),
      ],
      if (_sending) ...[
        const SizedBox(height: 16),
        const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brand),
          ),
          SizedBox(width: 10),
          Text('Sending invitationâ€¦', style: TextStyle(color: AppColors.silver, fontSize: 14)),
        ]),
      ],
      const SizedBox(height: 20),
      AppButton(
        label: 'Send Invite',
        isLoading: _sending,
        onPressed: _sending ? null : _sendInvite,
      ),
      const SizedBox(height: 20),
    ]);
  }
}
