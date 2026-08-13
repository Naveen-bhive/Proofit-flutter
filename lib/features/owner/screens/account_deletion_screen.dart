import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/services/auth_storage.dart';
import '../controllers/owner_controller.dart';

class AccountDeletionScreen extends ConsumerStatefulWidget {
  const AccountDeletionScreen({super.key});

  @override
  ConsumerState<AccountDeletionScreen> createState() => _AccountDeletionScreenState();
}

class _AccountDeletionScreenState extends ConsumerState<AccountDeletionScreen> {
  final _reasonCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  bool _loading = true;
  bool _submitting = false;
  bool _emailReadOnly = false;
  bool _phoneReadOnly = false;
  Map<String, dynamic>? _pendingRequest;
  String? _rejectionReason;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final user = await AuthStorage.getUser();
    final req = await ref.read(ownerControllerProvider.notifier).fetchAccountDeletionStatus();
    if (!mounted) return;

    final email = user?.email ?? '';
    final phone = user?.phone ?? '';
    setState(() {
      _emailCtrl.text = email;
      _phoneCtrl.text = phone;
      _emailReadOnly = email.isNotEmpty;
      _phoneReadOnly = phone.isNotEmpty;
      if (req != null && req['status'] == 'pending') {
        _pendingRequest = req;
        _rejectionReason = null;
      } else {
        _pendingRequest = null;
        _rejectionReason = req != null && req['status'] == 'rejected' ? req['rejectionReason']?.toString() : null;
      }
      _loading = false;
    });
  }

  Future<void> _submit() async {
    if (_reasonCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Please tell us why you want to delete your account');
      return;
    }
    if (_emailCtrl.text.trim().isEmpty || _phoneCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Email and phone are required');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.dark2,
        title: const Text('Delete account?', style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
        content: const Text(
          'This will submit a request to permanently delete your organisation. If approved, you and all your staff will lose access immediately. This cannot be undone.',
          style: TextStyle(color: AppColors.silver),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel', style: TextStyle(color: AppColors.silver))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Submit request', style: TextStyle(color: AppColors.red))),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() { _submitting = true; _error = null; });
    final result = await ref.read(ownerControllerProvider.notifier).requestAccountDeletion(
      reason: _reasonCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _submitting = false);

    if (result.ok) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
      return;
    }
    setState(() => _error = result.message);
  }

  Future<void> _cancelRequest() async {
    final requestId = _pendingRequest?['_id']?.toString();
    if (requestId == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.dark2,
        title: const Text('Cancel deletion request?', style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
        content: const Text('Your account and organisation will remain active.', style: TextStyle(color: AppColors.silver)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep request', style: TextStyle(color: AppColors.silver))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cancel request', style: TextStyle(color: AppColors.red))),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _submitting = true);
    final result = await ref.read(ownerControllerProvider.notifier).cancelAccountDeletionRequest(requestId);
    if (!mounted) return;
    setState(() => _submitting = false);

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
    if (result.ok) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(title: const Text('Delete Account')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: _pendingRequest != null ? _buildPendingView() : _buildFormView(),
            ),
    );
  }

  Widget _buildPendingView() {
    final reason = _pendingRequest?['reason']?.toString() ?? '';
    final createdAt = _pendingRequest?['createdAt']?.toString();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: AppColors.dark2, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.hourglass_top_rounded, color: AppColors.brand, size: 20),
            SizedBox(width: 10),
            Text('Pending review', style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 16)),
          ]),
          const SizedBox(height: 12),
          const Text('Your deletion request has been submitted and is awaiting super admin review.',
              style: TextStyle(color: AppColors.silver, fontSize: 13.5)),
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('REASON', style: TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.2)),
            const SizedBox(height: 4),
            Text(reason, style: const TextStyle(color: AppColors.light, fontSize: 14)),
          ],
          if (createdAt != null) ...[
            const SizedBox(height: 12),
            Text('Submitted ${_formatDate(createdAt)}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          ],
        ]),
      ),
      const SizedBox(height: 24),
      AppButton(
        label: 'Cancel request',
        isOutlined: true,
        color: AppColors.red,
        isLoading: _submitting,
        onPressed: _submitting ? null : _cancelRequest,
      ),
    ]);
  }

  Widget _buildFormView() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_rejectionReason != null && _rejectionReason!.isNotEmpty) ...[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.red.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Your previous request was rejected', style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w700, fontSize: 13.5)),
            const SizedBox(height: 6),
            Text(_rejectionReason!, style: const TextStyle(color: AppColors.silver, fontSize: 13)),
          ]),
        ),
        const SizedBox(height: 20),
      ],
      const Text(
        'Submitting this request will notify our team. If approved, your account and organisation — including all staff access — will be permanently deleted.',
        style: TextStyle(color: AppColors.silver, fontSize: 13.5),
      ),
      const SizedBox(height: 20),
      TextField(
        controller: _reasonCtrl,
        maxLines: 4,
        style: const TextStyle(color: AppColors.white),
        decoration: const InputDecoration(
          labelText: 'Reason *',
          hintText: 'Tell us why you want to delete your account',
          alignLabelWithHint: true,
        ),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _emailCtrl,
        readOnly: _emailReadOnly,
        enabled: !_emailReadOnly,
        keyboardType: TextInputType.emailAddress,
        style: TextStyle(color: _emailReadOnly ? AppColors.muted : AppColors.white),
        decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined, color: AppColors.muted)),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _phoneCtrl,
        readOnly: _phoneReadOnly,
        enabled: !_phoneReadOnly,
        keyboardType: TextInputType.phone,
        style: TextStyle(color: _phoneReadOnly ? AppColors.muted : AppColors.white),
        decoration: const InputDecoration(labelText: 'Phone', prefixIcon: Icon(Icons.phone_outlined, color: AppColors.muted)),
      ),
      if (_error != null) ...[
        const SizedBox(height: 14),
        Text(_error!, style: const TextStyle(color: AppColors.red, fontSize: 13)),
      ],
      const SizedBox(height: 24),
      AppButton(
        label: 'Submit deletion request',
        color: AppColors.red,
        isLoading: _submitting,
        onPressed: _submitting ? null : _submit,
      ),
      const SizedBox(height: 20),
    ]);
  }

  String _formatDate(String iso) {
    try {
      final d = DateTime.parse(iso).toLocal();
      return '${d.day}/${d.month}/${d.year}';
    } catch (_) {
      return '';
    }
  }
}
