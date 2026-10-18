import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../staff/controllers/staff_controller.dart';
import '../controllers/auth_controller.dart';
import '../utils/auth_helpers.dart';
import '../widgets/apple_sign_in_button.dart';
import '../widgets/auth_shell.dart';
import '../../../shared/widgets/ui_kit.dart' show PrimaryButton;
import '../widgets/google_sign_in_button.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  bool _loading = false;
  bool _googleLoading = false;
  bool _appleLoading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _signInWithPassword() async {
    final email = _emailCtrl.text.trim();
    final password = _passCtrl.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter email and password');
      return;
    }

    setState(() { _loading = true; _error = null; });
    final result = await ref.read(authControllerProvider.notifier)
        .signInWithPassword(email, password);
    if (!mounted) return;
    setState(() => _loading = false);
    _handleAuthResult(result);
  }

  Future<void> _signInWithGoogle() async {
    setState(() { _googleLoading = true; _error = null; });
    final result = await ref.read(authControllerProvider.notifier).signInWithGoogle();
    if (!mounted) return;
    setState(() => _googleLoading = false);
    if (result == null) {
      setState(() => _error = authErrorMessage(ref.read(authControllerProvider), google: true));
      return;
    }
    _handleAuthResult(result);
  }

  Future<void> _signInWithApple() async {
    setState(() { _appleLoading = true; _error = null; });
    final result = await ref.read(authControllerProvider.notifier).signInWithApple();
    if (!mounted) return;
    setState(() => _appleLoading = false);
    if (result == null) {
      setState(() => _error = authErrorMessage(ref.read(authControllerProvider), provider: 'apple'));
      return;
    }
    _handleAuthResult(result);
  }

  void _handleAuthResult(String? result) {
    if (result == null) {
      setState(() => _error = authErrorMessage(ref.read(authControllerProvider)));
      return;
    }
    if (result == 'new_owner') { context.go('/owner-setup'); return; }
    if (result == 'owner')     { context.go('/owner');       return; }
    if (result == 'staff') {
      ref.invalidate(staffControllerProvider);
      context.go('/staff');
      return;
    }
  }

  void _showInviteDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.dark2,
        title: const Text('Open invite link', style: TextStyle(color: AppColors.text)),
        content: TextField(
          controller: ctrl,
          style: const TextStyle(color: AppColors.text),
          decoration: const InputDecoration(
            hintText: 'Paste invite URL or token',
            hintStyle: TextStyle(color: AppColors.muted),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final token = extractInviteToken(ctrl.text);
              Navigator.pop(ctx);
              if (token == null || token.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Could not read invite link')),
                );
                return;
              }
              context.go('/invite/$token');
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      title: 'Welcome back',
      subtitle: 'Sign in to manage your team and reports.',
      footer: Column(children: [
        GestureDetector(
          onTap: () => context.go('/signup'),
          child: const Text.rich(
            TextSpan(
              text: 'New business?  ',
              style: TextStyle(color: AppColors.silver, fontSize: 13.5),
              children: [
                TextSpan(
                  text: 'Create account',
                  style: TextStyle(color: AppColors.brand, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: _showInviteDialog,
          child: const Text.rich(
            TextSpan(
              text: 'Staff member?  ',
              style: TextStyle(color: AppColors.silver, fontSize: 13.5),
              children: [
                TextSpan(
                  text: 'Open your invite link',
                  style: TextStyle(
                    color: AppColors.light,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.underline,
                    decorationColor: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (kDebugMode)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'API: ${AppConstants.baseUrl}',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 10),
            ),
          ),
      ]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const AuthFieldLabel('Work Email'),
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          textInputAction: TextInputAction.next,
          style: const TextStyle(color: AppColors.text),
          decoration: const InputDecoration(
            hintText: 'name@company.com',
            prefixIcon: Icon(Icons.mail_outline_rounded, color: AppColors.muted),
          ),
        ),
        const SizedBox(height: 18),
        AuthFieldLabel(
          'Password',
          trailing: GestureDetector(
            onTap: _loading || _googleLoading ? null : () => context.push('/forgot-password'),
            child: const Text('Forgot password?',
                style: TextStyle(color: AppColors.brand, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ),
        TextField(
          controller: _passCtrl,
          obscureText: _obscure,
          textInputAction: TextInputAction.done,
          style: const TextStyle(color: AppColors.text),
          decoration: InputDecoration(
            hintText: 'Enter your password',
            prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppColors.muted),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: AppColors.muted),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          onSubmitted: (_) => _signInWithPassword(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          AuthErrorBanner(message: _error!),
        ],
        const SizedBox(height: 22),
        PrimaryButton(
          label: 'Sign in',
          trailingIcon: Icons.arrow_forward_rounded,
          gradient: AppColors.brandGradient,
          loading: _loading,
          onPressed: (_loading || _googleLoading || _appleLoading) ? null : _signInWithPassword,
        ),
        const AuthDivider(),
        GoogleSignInButton(
          isLoading: _googleLoading,
          onPressed: (_loading || _googleLoading || _appleLoading) ? null : _signInWithGoogle,
        ),
        if (Platform.isIOS) ...[
          const SizedBox(height: 12),
          AppleSignInButton(
            isLoading: _appleLoading,
            onPressed: (_loading || _googleLoading || _appleLoading) ? null : _signInWithApple,
          ),
        ],
      ]),
    );
  }
}
