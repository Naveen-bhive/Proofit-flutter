import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/app_button.dart';
import '../controllers/auth_controller.dart';
import '../widgets/auth_shell.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Enter your email address');
      return;
    }

    setState(() { _loading = true; _error = null; _success = null; });
    final result = await ref.read(authControllerProvider.notifier).requestPasswordReset(email);
    if (!mounted) return;
    setState(() => _loading = false);

    if (result.success) {
      setState(() => _success = result.message);
      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        context.push('/reset-password?email=${Uri.encodeComponent(email)}');
      });
      return;
    }
    setState(() => _error = result.message);
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      title: 'Forgot password?',
      subtitle: 'Enter your email and we\'ll send you a 6-digit code to reset your password.',
      onBack: () => context.go('/signin'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          textInputAction: TextInputAction.done,
          style: const TextStyle(color: AppColors.white),
          decoration: const InputDecoration(
            labelText: 'Email',
            prefixIcon: Icon(Icons.email_outlined, color: AppColors.muted),
          ),
          onSubmitted: (_) => _submit(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          AuthErrorBanner(message: _error!),
        ],
        if (_success != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.green.withValues(alpha: 0.3)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.check_circle_outline, color: AppColors.green, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(_success!, style: const TextStyle(color: AppColors.green, fontSize: 13))),
            ]),
          ),
        ],
        const SizedBox(height: 22),
        AppButton(
          label: 'Send reset code',
          isLoading: _loading,
          onPressed: _loading ? null : _submit,
        ),
      ]),
    );
  }
}
