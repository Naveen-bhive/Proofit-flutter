import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/services/review_service.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../controllers/owner_controller.dart';
import '../../../shared/permissions/app_permissions.dart';
import '../../../shared/permissions/permission_editor.dart';
import '../../../shared/permissions/permission_session.dart';

class StaffManagementScreen extends ConsumerStatefulWidget {
  const StaffManagementScreen({super.key});
  @override
  ConsumerState<StaffManagementScreen> createState() => _StaffManagementScreenState();
}

class _StaffManagementScreenState extends ConsumerState<StaffManagementScreen> {
  bool _loading = true;
  String _filter = 'all';
  String _query = '';
  /// Permission ids the signed-in user may grant (owner: all).
  Set<String> _grantable = const {};

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final notifier = ref.read(ownerControllerProvider.notifier);
      await notifier.loadStaff();
      final grantable = ref.read(permissionSessionProvider).can(AppPermissions.staffPermissions)
          ? await notifier.loadGrantablePermissions()
          : <String>{};
      if (mounted) setState(() { _loading = false; _grantable = grantable; });
    });
  }

  Future<void> _editPermissions(Map<String, dynamic> staff) async {
    final id = staff['_id']?.toString() ?? '';
    if (id.isEmpty) return;
    final current = {for (final p in (staff['permissions'] as List? ?? const [])) p.toString()};
    await PermissionEditorSheet.show(
      context,
      title: 'Permissions for ${staff['name'] ?? 'staff'}',
      initial: current,
      grantable: _grantable,
      featureEnabled: ref.read(ownerControllerProvider).isEnabled,
      onSave: (perms) => ref.read(ownerControllerProvider.notifier).setStaffPermissions(id, perms),
    );
  }

  void _showAddStaffSheet() {
    final parentContext = context;
    AppSheet.show(
      context,
      builder: (sheetCtx) => _AddStaffSheet(
        parentContext: parentContext,
        grantable: _grantable,
        featureEnabled: ref.read(ownerControllerProvider).isEnabled,
        onSubmit: ({required String name, required String phone, required String email, required int target, required Set<String> permissions}) async {
          final notifier = ref.read(ownerControllerProvider.notifier);
          final result = await notifier.addStaff(name: name, phone: phone, email: email, permissions: permissions.toList());
          if (result.ok && target > 0) {
            final added = ref.read(ownerControllerProvider).staffList.where(
                (s) => (s['email'] ?? '').toString().toLowerCase() == email.toLowerCase());
            if (added.isNotEmpty) await notifier.setStaffTarget(added.first['_id'].toString(), target);
          }
          return result;
        },
      ),
    );
  }

  Future<void> _confirmRemove(Map<String, dynamic> staff, bool pending) async {
    final name = (staff['name'] ?? 'this staff member').toString();
    final confirmed = await showConfirmDialog(
      context,
      icon: pending ? Icons.mail_lock_outlined : Icons.person_remove_outlined,
      title: pending ? 'Cancel invitation?' : 'Remove staff member?',
      message: 'Are you sure you want to ${pending ? 'cancel this invitation' : 'remove $name'}?',
      confirmLabel: pending ? 'Cancel invite' : 'Remove',
      cancelLabel: 'Keep',
    );
    if (confirmed) await ref.read(ownerControllerProvider.notifier).removeStaff(staff['_id'].toString());
  }

  Future<void> _showSetTarget(Map<String, dynamic> staff) async {
    final controller = TextEditingController(text: '${staff['dailyTarget'] ?? 0}');
    String? error;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          title: const Text('Set Daily Target', style: TextStyle(color: AppColors.text)),
          content: TextField(controller: controller, autofocus: true, keyboardType: TextInputType.number, style: const TextStyle(color: AppColors.text), decoration: InputDecoration(labelText: 'Jobs per day', errorText: error)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            TextButton(onPressed: () async {
              final value = int.tryParse(controller.text.trim());
              if (value == null || value < 0) {
                setDialogState(() => error = 'Enter zero or a positive whole number');
                return;
              }
              final result = await ref.read(ownerControllerProvider.notifier).setStaffTarget(staff['_id'].toString(), value);
              if (!dialogContext.mounted) return;
              if (result.ok) {
                Navigator.pop(dialogContext);
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message), backgroundColor: AppColors.green));
              } else {
                setDialogState(() => error = result.message);
              }
            }, child: const Text('Save', style: TextStyle(color: AppColors.brand))),
          ],
        ),
      ),
    );
    controller.dispose();
  }

  bool _isPending(Map<String, dynamic> s) => s['invitePending'] == true || s['inviteStatus'] == 'pending';

  Future<void> _call(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (!await launchUrl(uri) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not start a call')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ownerControllerProvider);
    final session = ref.watch(permissionSessionProvider);
    final canInvite = session.can(AppPermissions.staffCreate);
    final all = state.staffList;
    final pendingCount = all.where(_isPending).length;
    final q = _query.trim().toLowerCase();
    final visible = all.where((s) {
      final pending = _isPending(s);
      if (_filter == 'active' && pending) return false;
      if (_filter == 'pending' && !pending) return false;
      if (q.isEmpty) return true;
      return ['name', 'phone', 'email'].any((k) => (s[k] ?? '').toString().toLowerCase().contains(q));
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.dark,
      body: SafeArea(
        child: Column(children: [
          PageHeader(
            title: 'Staff Management',
            actions: [
              if (canInvite)
                HeaderIconButton(icon: Icons.person_add_alt_outlined, tinted: true, round: false, onTap: _showAddStaffSheet),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: SearchBox(hint: 'Search staff by name, phone...', onChanged: (v) => setState(() => _query = v)),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(children: [
              Expanded(
                child: PillChipBar(chips: [
                  PillChip(label: 'All', count: all.isEmpty ? null : all.length, selected: _filter == 'all',
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6), onTap: () => setState(() => _filter = 'all')),
                  PillChip(label: 'Active', selected: _filter == 'active',
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6), onTap: () => setState(() => _filter = 'active')),
                  PillChip(label: 'Pending', count: pendingCount == 0 ? null : pendingCount, selected: _filter == 'pending',
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6), onTap: () => setState(() => _filter = 'pending')),
                ]),
              ),
              Text('Total: ${all.length} staff', style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
            ]),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
                : all.isEmpty
                    ? ListView(padding: const EdgeInsets.fromLTRB(16, 70, 16, 24), children: [
                        if (canInvite)
                          _inviteCard()
                        else
                          const Center(child: Text('No staff yet', style: TextStyle(color: AppColors.silver))),
                      ])
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        children: [
                          if (visible.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 40),
                              child: Center(child: Text('No staff match this filter', style: TextStyle(color: AppColors.silver))),
                            ),
                          ...visible.map((s) => _staffCard(s, session)),
                          const SizedBox(height: 4),
                          if (canInvite) _infoBanner(),
                        ],
                      ),
          ),
        ]),
      ),
    );
  }

  Widget _inviteCard() {
    return GestureDetector(
      onTap: _showAddStaffSheet,
      child: CustomPaint(
        painter: const DashedBorderPainter(color: AppColors.border, radius: 18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), boxShadow: AppColors.softShadow, color: AppColors.white),
          child: const Column(children: [
            Text('Invite New Staff Member', style: TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.w600)),
            SizedBox(height: 6),
            Text('Assign inspection jobs, set targets and monitor field proofs in real time.',
              textAlign: TextAlign.center, style: TextStyle(color: AppColors.silver, fontSize: 12.5, height: 1.4)),
          ]),
        ),
      ),
    );
  }

  Widget _infoBanner() {
    return GestureDetector(
      onTap: _showAddStaffSheet,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.brandSoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.brandBorder),
          boxShadow: AppColors.softShadow,
        ),
        child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline_rounded, color: AppColors.brand, size: 20),
          SizedBox(width: 12),
          Expanded(
            child: Text('Need more team members? Tap here to send an email invitation to a new staff member.',
              style: TextStyle(color: AppColors.brandDark, fontSize: 13, height: 1.45)),
          ),
        ]),
      ),
    );
  }

  Widget _staffCard(Map<String, dynamic> s, PermissionSession session) {
    final pending = _isPending(s);
    // The server marks members whose access exceeds the viewer's as not manageable.
    final manageable = s['canManage'] != false;
    final isUser = s['kind'] != 'invite';
    final canTarget = manageable && session.can(AppPermissions.staffEdit);
    final canRemove = manageable && session.can(AppPermissions.staffDelete);
    final canPermit = manageable && isUser && session.can(AppPermissions.staffPermissions);
    final grantedCount = (s['permissions'] as List? ?? const []).length;
    final menu = [
      if (!pending && canTarget)
        const PopupMenuItem(value: 'target', child: Text('Set Target', style: TextStyle(color: AppColors.text))),
      if (canPermit)
        const PopupMenuItem(value: 'permissions', child: Text('Permissions', style: TextStyle(color: AppColors.text))),
      if (canRemove)
        PopupMenuItem(
          value: 'remove',
          child: Text(pending ? 'Cancel invite' : 'Remove', style: const TextStyle(color: AppColors.red)),
        ),
    ];
    final name = (s['name'] ?? 'Staff').toString();
    final phone = (s['phone'] ?? '').toString();
    final email = (s['email'] ?? '').toString();
    final id = s['_id']?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: SurfaceCard(
        radius: 18,
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 14),
        onTap: pending || id.isEmpty ? null : () => context.push('/owner/staff/$id'),
        child: Column(children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            InitialAvatar(name: name, size: 48, color: pending ? AppColors.yellow : AppColors.brand, online: pending ? null : true),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.h3.copyWith(fontSize: 16.5, fontWeight: FontWeight.w600))),
                if (!pending) ...[
                  const SizedBox(width: 8),
                  const SoftBadge(label: 'Active', color: AppColors.greenDark, fontSize: 11),
                ],
                if (grantedCount > 0) ...[
                  const SizedBox(width: 6),
                  const SoftBadge(label: 'Team access', color: AppColors.brand, icon: Icons.verified_user_outlined, fontSize: 11),
                ],
              ]),
              const SizedBox(height: 4),
              if (phone.isNotEmpty) _line(Icons.phone_outlined, phone),
              if (email.isNotEmpty) _line(Icons.mail_outline_rounded, email),
            ])),
            if (menu.isNotEmpty)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, color: AppColors.muted, size: 20),
                itemBuilder: (_) => menu,
                onSelected: (val) {
                  if (val == 'target') _showSetTarget(s);
                  if (val == 'permissions') _editPermissions(s);
                  if (val == 'remove') _confirmRemove(s, pending);
                },
              ),
          ]),
          const Padding(
            padding: EdgeInsets.fromLTRB(0, 12, 8, 12),
            child: Divider(height: 1, color: AppColors.borderSoft),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: pending
                ? const Row(children: [
                    SoftBadge(label: 'Invitation yet to be accepted', color: AppColors.amberDark, icon: Icons.schedule_rounded,
                      background: AppColors.amberSoft, fontSize: 12),
                  ])
                : Row(children: [
                    GestureDetector(
                      onTap: canTarget ? () => _showSetTarget(s) : null,
                      child: SoftBadge(label: 'Target: ${s['dailyTarget'] ?? 0} jobs/day', color: AppColors.amberDark,
                        icon: Icons.track_changes_rounded, background: AppColors.amberSoft, fontSize: 12),
                    ),
                    const Spacer(),
                    if (session.can(AppPermissions.jobsCreate))
                      GestureDetector(
                        onTap: () => context.push('/owner/jobs'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(color: AppColors.dark4, borderRadius: BorderRadius.circular(8)),
                          child: const Text('Assign Job', style: TextStyle(color: AppColors.light, fontSize: 12.5, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    if (phone.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => _call(phone),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(color: AppColors.brandSoft, borderRadius: BorderRadius.circular(8)),
                          child: const Icon(Icons.call_outlined, color: AppColors.brand, size: 16),
                        ),
                      ),
                    ],
                  ]),
          ),
        ]),
      ),
    );
  }

  Widget _line(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(top: 3),
    child: Row(children: [
      Icon(icon, size: 14, color: AppColors.muted),
      const SizedBox(width: 6),
      Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppColors.silver, fontSize: 13))),
    ]),
  );
}

typedef _AddStaffSubmit = Future<({bool ok, String message})> Function({
  required String name,
  required String phone,
  required String email,
  required int target,
  required Set<String> permissions,
});

class _AddStaffSheet extends StatefulWidget {
  final BuildContext parentContext;
  final _AddStaffSubmit onSubmit;
  /// Permissions the inviter may grant; empty hides the permissions picker.
  final Set<String> grantable;
  final bool Function(String feature) featureEnabled;
  const _AddStaffSheet({
    required this.parentContext,
    required this.onSubmit,
    required this.grantable,
    required this.featureEnabled,
  });

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
  int _target = 0;
  Set<String> _permissions = {};

  Future<void> _pickPermissions() async {
    final picked = await PermissionEditorSheet.show(
      context,
      title: 'Team access',
      subtitle: 'Optional. Choose owner features this member can use; you can change it later.',
      initial: _permissions,
      grantable: widget.grantable,
      featureEnabled: widget.featureEnabled,
      saveLabel: 'Use these permissions',
      onSave: (_) async => null,
    );
    if (picked != null && mounted) setState(() => _permissions = picked);
  }

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
      target: _target,
      permissions: _permissions,
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
    ReviewService.maybePromptAfterSuccess();
  }

  void _inviteAnother() {
    setState(() {
      _succeeded = false;
      _successMessage = null;
      _formError = null;
      _target = 0;
      _permissions = {};
      _nameCtrl.clear();
      _phoneCtrl.clear();
      _emailCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_sending,
      child: _succeeded ? _buildSuccess() : _buildForm(),
    );
  }

  Widget _buildSuccess() {
    final name = _nameCtrl.text.trim();
    final phone = _normalizePhone(_phoneCtrl.text);
    return AppSheet(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Align(alignment: Alignment.centerRight, child: SheetCloseButton()),
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.green.withValues(alpha: 0.10),
            border: Border.all(color: AppColors.green.withValues(alpha: 0.18), width: 6),
          ),
          child: Center(
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(colors: [AppColors.green, AppColors.greenDark],
                  begin: Alignment.topLeft, end: Alignment.bottomRight),
                boxShadow: AppColors.glow(AppColors.green),
              ),
              child: const Icon(Icons.check_rounded, color: AppColors.white, size: 34),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Flexible(child: Text('Invitation Sent!', style: AppTextStyles.h2.copyWith(fontSize: 22))),
          const SizedBox(width: 10),
          const SoftBadge(label: 'Delivered', color: AppColors.greenDark, uppercase: true, fontSize: 10),
        ]),
        const SizedBox(height: 10),
        Text(
          _successMessage ?? "We've emailed an onboarding link to your staff member to join ProofIt and start reporting.",
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.silver, fontSize: 14, height: 1.5),
        ),
        const SizedBox(height: 20),
        SurfaceCard(
          color: AppColors.dark3,
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Row(children: [
              InitialAvatar(name: name, size: 42, color: AppColors.brand),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 15)),
                Row(children: [
                  const Icon(Icons.mail_outline_rounded, size: 13, color: AppColors.muted),
                  const SizedBox(width: 5),
                  Expanded(child: Text(_emailCtrl.text.trim(), maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.silver, fontSize: 12.5))),
                ]),
              ])),
              const SoftBadge(label: 'Pending', color: AppColors.yellow, dot: true, fontSize: 11.5),
            ]),
            const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1, color: AppColors.border)),
            Row(children: [
              Expanded(child: _summaryBox('Phone', phone.isEmpty ? '-' : '+91 $phone')),
              const SizedBox(width: 10),
              Expanded(child: _summaryBox('Daily Target', '$_target jobs / day', dot: true)),
            ]),
          ]),
        ),
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          child: PrimaryButton(label: 'Done', trailingIcon: Icons.check_rounded, onPressed: () => Navigator.pop(context)),
        ),
        const SizedBox(height: 6),
        TextButton.icon(
          onPressed: _inviteAnother,
          icon: const Icon(Icons.add_rounded, size: 18, color: AppColors.light),
          label: const Text('Invite Another Member', style: TextStyle(color: AppColors.light, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

  Widget _summaryBox(String label, String value, {bool dot = false}) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
      const SizedBox(height: 4),
      Row(children: [
        if (dot) ...[
          Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle)),
          const SizedBox(width: 6),
        ],
        Flexible(child: Text(value, style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 13.5))),
      ]),
    ]),
  );

  Widget _buildForm() {
    return AppSheet(
      title: 'Add Staff Member',
      titleTrailing: const SoftBadge(label: 'Invite', color: AppColors.brand, uppercase: true, fontSize: 10),
      subtitle: 'Invite team members to assign jobs, set daily targets, and track live activity.',
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const FieldLabel('Full Name', required: true),
        TextFormField(
          controller: _nameCtrl,
          enabled: !_sending,
          textCapitalization: TextCapitalization.words,
          style: const TextStyle(color: AppColors.text),
          decoration: const InputDecoration(hintText: 'e.g. John Doe', prefixIcon: Icon(Icons.person_outline_rounded, size: 20)),
        ),
        const SizedBox(height: 16),
        const FieldLabel('Phone Number'),
        TextFormField(
          controller: _phoneCtrl,
          enabled: !_sending,
          keyboardType: TextInputType.phone,
          style: const TextStyle(color: AppColors.text),
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
          decoration: InputDecoration(
            hintText: '97561 34513',
            prefixIcon: Container(
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: const BoxDecoration(border: Border(right: BorderSide(color: AppColors.border))),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Text('\u{1F1EE}\u{1F1F3}', style: TextStyle(fontSize: 14)),
                SizedBox(width: 6),
                Text('+91', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 14)),
                Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: AppColors.muted),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const FieldLabel('Email Address', required: true, hint: 'Used for invitation link'),
        TextFormField(
          controller: _emailCtrl,
          enabled: !_sending,
          keyboardType: TextInputType.emailAddress,
          style: const TextStyle(color: AppColors.text),
          decoration: const InputDecoration(hintText: 'name@company.com', prefixIcon: Icon(Icons.mail_outline_rounded, size: 20)),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.dark3,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
            boxShadow: AppColors.softShadow,
          ),
          child: Row(children: [
            const IconTile(icon: Icons.track_changes_rounded, color: AppColors.brand, size: 36, iconSize: 18, radius: 10),
            const SizedBox(width: 12),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Daily Job Target', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 13.5)),
              Text('Target completed jobs/day', style: TextStyle(color: AppColors.silver, fontSize: 11.5)),
            ])),
            Container(
              decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _stepBtn(Icons.remove_rounded, _target > 0 && !_sending ? () => setState(() => _target--) : null),
                SizedBox(width: 26, child: Text('$_target', textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700))),
                _stepBtn(Icons.add_rounded, _target < 999 && !_sending ? () => setState(() => _target++) : null),
              ]),
            ),
          ]),
        ),
        if (widget.grantable.isNotEmpty) ...[
          const SizedBox(height: 12),
          InkWell(
            onTap: _sending ? null : _pickPermissions,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.dark3,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(children: [
                const IconTile(icon: Icons.verified_user_outlined, color: AppColors.brand, size: 36, iconSize: 18, radius: 10),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Team access', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 13.5)),
                  Text(
                    _permissions.isEmpty ? 'Staff app only (default)' : '${_permissions.length} permission${_permissions.length == 1 ? '' : 's'} selected',
                    style: const TextStyle(color: AppColors.silver, fontSize: 11.5),
                  ),
                ])),
                const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
              ]),
            ),
          ),
        ],
        if (_formError != null) ...[
          const SizedBox(height: 12),
          Text(_formError!, style: const TextStyle(color: AppColors.red, fontSize: 13)),
        ],
        const SizedBox(height: 22),
        PrimaryButton(
          label: 'Send Invite',
          icon: Icons.send_outlined,
          loading: _sending,
          onPressed: _sending ? null : _sendInvite,
        ),
      ]),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback? onTap) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Icon(icon, size: 16, color: onTap == null ? AppColors.border : AppColors.silver),
    ),
  );
}
