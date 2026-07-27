import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/app_button.dart';
import '../controllers/auth_controller.dart';
import '../widgets/auth_shell.dart';

class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _currentCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  bool _loadingInfo = true;
  bool _hasPassword = true;
  String _email = '';
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAccount();
  }

  Future<void> _loadAccount() async {
    final info = await ref.read(authControllerProvider.notifier).fetchAccountInfo();
    if (!mounted) return;
    setState(() {
      _loadingInfo = false;
      if (info != null) {
        _hasPassword = info.hasPassword;
        _email = info.email;
      }
    });
  }

  @override
  void dispose() {
    _currentCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final current = _currentCtrl.text;
    final password = _passCtrl.text;
    final confirm = _confirmCtrl.text;

    if (_hasPassword && current.isEmpty) {
      setState(() => _error = 'Enter your current password');
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = 'Enter a new password');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters');
      return;
    }
    if (password != confirm) {
      setState(() => _error = 'Passwords do not match');
      return;
    }

    setState(() { _loading = true; _error = null; });
    final result = await ref.read(authControllerProvider.notifier).changePassword(
      currentPassword: _hasPassword ? current : null,
      newPassword: password,
    );
    if (!mounted) return;
    setState(() => _loading = false);

    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message), backgroundColor: AppColors.green),
      );
      context.pop();
      return;
    }
    setState(() => _error = result.message);
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingInfo) {
      return const Scaffold(
        backgroundColor: AppColors.dark,
        body: Center(child: CircularProgressIndicator(color: AppColors.brand)),
      );
    }

    return AuthShell(
      title: _hasPassword ? 'Change password' : 'Set password',
      subtitle: _hasPassword
          ? 'Update the password for ${_email.isNotEmpty ? _email : 'your account'}.'
          : 'Add a password so you can sign in with email as well as Google.',
      onBack: () => context.pop(),
      showWordmark: false,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_hasPassword) ...[
          TextField(
            controller: _currentCtrl,
            obscureText: _obscureCurrent,
            textInputAction: TextInputAction.next,
            style: const TextStyle(color: AppColors.white),
            decoration: InputDecoration(
              labelText: 'Current password',
              prefixIcon: const Icon(Icons.lock_outline, color: AppColors.muted),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureCurrent ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: AppColors.muted,
                ),
                onPressed: () => setState(() => _obscureCurrent = !_obscureCurrent),
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
        TextField(
          controller: _passCtrl,
          obscureText: _obscureNew,
          textInputAction: TextInputAction.next,
          style: const TextStyle(color: AppColors.white),
          decoration: InputDecoration(
            labelText: 'New password',
            prefixIcon: const Icon(Icons.lock_outline, color: AppColors.muted),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureNew ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: AppColors.muted,
              ),
              onPressed: () => setState(() => _obscureNew = !_obscureNew),
            ),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _confirmCtrl,
          obscureText: _obscureConfirm,
          textInputAction: TextInputAction.done,
          style: const TextStyle(color: AppColors.white),
          decoration: InputDecoration(
            labelText: 'Confirm new password',
            prefixIcon: const Icon(Icons.lock_outline, color: AppColors.muted),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: AppColors.muted,
              ),
              onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
            ),
          ),
          onSubmitted: (_) => _submit(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          AuthErrorBanner(message: _error!),
        ],
        const SizedBox(height: 22),
        AppButton(
          label: _hasPassword ? 'Update password' : 'Set password',
          isLoading: _loading,
          onPressed: _loading ? null : _submit,
        ),
      ]),
    );
  }
}
