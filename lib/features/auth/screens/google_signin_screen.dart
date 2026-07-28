import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../controllers/auth_controller.dart';
import '../../owner/controllers/owner_controller.dart';
import '../../staff/controllers/staff_controller.dart';

class GoogleSignInScreen extends ConsumerStatefulWidget {
  final bool isStaffInvite;
  const GoogleSignInScreen({super.key, this.isStaffInvite = false});
  @override ConsumerState<GoogleSignInScreen> createState() => _GoogleSignInScreenState();
}

class _GoogleSignInScreenState extends ConsumerState<GoogleSignInScreen> {
  bool _loading = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() { _loading = true; _error = null; });
    final result = await ref.read(authControllerProvider.notifier).signInWithGoogle();
    if (!mounted) return;
    setState(() => _loading = false);

    if (result == null) {
      setState(() => _error = 'Sign-in cancelled or failed. Please try again.');
      return;
    }
    if (result == 'new_owner') { context.go('/owner-setup'); return; }
    if (result == 'owner') {
      ref.invalidate(ownerControllerProvider);
      context.go('/owner');
      return;
    }
    if (result == 'staff') {
      ref.invalidate(staffControllerProvider);
      context.go('/staff');
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark,
      body: SafeArea(child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(children: [
          const Spacer(flex: 2),

          // Logo
          Image.asset(
            'assets/images/logo.png',
            width: MediaQuery.of(context).size.width * 0.72,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 16),
          const Text('Work Done. Proved Instantly.', style: TextStyle(color: AppColors.silver, fontSize: 16)),

          const Spacer(flex: 2),

          // Google Sign-In Button
          _loading
            ? const CircularProgressIndicator(color: AppColors.brand)
            : GestureDetector(
                onTap: _signIn,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 4))],
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Image.asset('assets/images/google_logo.png', width: 22, height: 22, fit: BoxFit.contain),
                    const SizedBox(width: 12),
                    const Text('Continue with Google', style: TextStyle(color: Color(0xFF1F1F1F), fontSize: 16, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),

          if (_error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.red.withValues(alpha: 0.3))),
              child: Row(children: [
                const Icon(Icons.error_outline, color: AppColors.red, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(_error!, style: const TextStyle(color: AppColors.red, fontSize: 13))),
              ])),
          ],

          const Spacer(),
          const Text('By continuing you agree to ProofIt\'s Terms of Service', style: TextStyle(color: AppColors.muted, fontSize: 11), textAlign: TextAlign.center),
          const SizedBox(height: 8),
        ]),
      )),
    );
  }
}