import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/app_button.dart';
import '../controllers/auth_controller.dart';
import '../widgets/auth_shell.dart';

class ResetPasswordScreen extends ConsumerStatefulWidget {
  final String? initialEmail;
  const ResetPasswordScreen({super.key, this.initialEmail});

  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  late final TextEditingController _emailCtrl;
  final _codeCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  bool _obscureConfirm = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _emailCtrl = TextEditingController(text: widget.initialEmail ?? '');
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    final code = _codeCtrl.text.trim();
    final password = _passCtrl.text;
    final confirm = _confirmCtrl.text;

    if (email.isEmpty || code.isEmpty || password.isEmpty) {
      setState(() => _error = 'Fill in email, code and new password');
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
    final result = await ref.read(authControllerProvider.notifier).resetPassword(
      email: email,
      code: code,
      password: password,
    );
    if (!mounted) return;
    setState(() => _loading = false);

    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message), backgroundColor: AppColors.green),
      );
      context.go('/signin');
      return;
    }
    setState(() => _error = result.message);
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      title: 'Reset password',
      subtitle: 'Enter the 6-digit code from your email and choose a new password.',
      onBack: () => context.go('/forgot-password'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          style: const TextStyle(color: AppColors.white),
          decoration: const InputDecoration(
            labelText: 'Email',
            prefixIcon: Icon(Icons.email_outlined, color: AppColors.muted),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _codeCtrl,
          keyboardType: TextInputType.number,
          maxLength: 6,
          style: const TextStyle(color: AppColors.white, letterSpacing: 4, fontWeight: FontWeight.w700),
          decoration: const InputDecoration(
            labelText: 'Reset code',
            prefixIcon: Icon(Icons.pin_outlined, color: AppColors.muted),
            counterText: '',
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _passCtrl,
          obscureText: _obscure,
          style: const TextStyle(color: AppColors.white),
          decoration: InputDecoration(
            labelText: 'New password',
            prefixIcon: const Icon(Icons.lock_outline, color: AppColors.muted),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: AppColors.muted),
              onPressed: () => setState(() => _obscure = !_obscure),
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
            labelText: 'Confirm password',
            prefixIcon: const Icon(Icons.lock_outline, color: AppColors.muted),
            suffixIcon: IconButton(
              icon: Icon(_obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: AppColors.muted),
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
          label: 'Update password',
          isLoading: _loading,
          onPressed: _loading ? null : _submit,
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _loading ? null : () => context.go('/forgot-password'),
          child: const Text('Resend code', style: TextStyle(color: AppColors.brand, fontSize: 13)),
        ),
      ]),
    );
  }
}
