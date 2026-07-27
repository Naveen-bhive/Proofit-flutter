import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../controllers/auth_controller.dart';
import '../utils/auth_helpers.dart';
import '../widgets/apple_sign_in_button.dart';
import '../widgets/auth_shell.dart';
import '../widgets/google_sign_in_button.dart';

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  bool _googleLoading = false;
  bool _appleLoading = false;
  String? _error;

  Future<void> _signUpWithGoogle() async {
    setState(() { _googleLoading = true; _error = null; });
    final result = await ref.read(authControllerProvider.notifier).signUpWithGoogle();
    if (!mounted) return;
    setState(() => _googleLoading = false);
    if (result == null) {
      setState(() => _error = authErrorMessage(ref.read(authControllerProvider), google: true));
      return;
    }
    if (result == 'new_owner') {
      context.go('/owner-setup');
      return;
    }
    if (result == 'owner') {
      context.go('/owner');
      return;
    }
    setState(() => _error = 'This Google account is already registered. Try signing in.');
  }

  Future<void> _signUpWithApple() async {
    setState(() { _appleLoading = true; _error = null; });
    final result = await ref.read(authControllerProvider.notifier).signInWithApple();
    if (!mounted) return;
    setState(() => _appleLoading = false);
    if (result == null) {
      setState(() => _error = authErrorMessage(ref.read(authControllerProvider), provider: 'apple'));
      return;
    }
    if (result == 'new_owner') {
      context.go('/owner-setup');
      return;
    }
    if (result == 'owner') {
      context.go('/owner');
      return;
    }
    setState(() => _error = 'This Apple account is already registered. Try signing in.');
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      title: 'Create your business',
      subtitle: 'Register as an owner with Google. You\'ll add your company name next.',
      onBack: () => context.go('/signin'),
      footer: Column(children: [
        TextButton(
          onPressed: () => context.go('/signin'),
          child: const Text.rich(
            TextSpan(
              text: 'Already have an account? ',
              style: TextStyle(color: AppColors.silver, fontSize: 14),
              children: [
                TextSpan(
                  text: 'Sign in',
                  style: TextStyle(color: AppColors.brand, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
        TextButton(
          onPressed: () => context.go('/signin'),
          child: const Text(
            'Staff member? Use your invite link to sign in',
            style: TextStyle(color: AppColors.muted, fontSize: 13),
          ),
        ),
      ]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_error != null) ...[
          AuthErrorBanner(message: _error!),
          const SizedBox(height: 16),
        ],
        GoogleSignInButton(
          label: 'Sign up with Google',
          isLoading: _googleLoading,
          onPressed: (_googleLoading || _appleLoading) ? null : _signUpWithGoogle,
        ),
        if (Platform.isIOS) ...[
          const SizedBox(height: 12),
          AppleSignInButton(
            isLoading: _appleLoading,
            onPressed: (_googleLoading || _appleLoading) ? null : _signUpWithApple,
          ),
        ],
      ]),
    );
  }
}
