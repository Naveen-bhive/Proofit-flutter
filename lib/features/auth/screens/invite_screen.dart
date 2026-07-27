import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/app_button.dart';
import '../widgets/google_sign_in_button.dart';
import '../controllers/auth_controller.dart';
import '../utils/auth_helpers.dart';
import '../../staff/controllers/staff_controller.dart';

class InviteScreen extends ConsumerStatefulWidget {
  final String token;
  const InviteScreen({super.key, required this.token});
  @override
  ConsumerState<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends ConsumerState<InviteScreen> {
  Map<String, dynamic>? _invite;
  bool _loading = true;
  bool _googleLoading = false;
  String? _error;
  final _passCtrl = TextEditingController();
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    if (widget.token.isEmpty) {
      _loading = false;
      _error = 'Invalid or expired invite link.';
    } else {
      _loadInvite();
    }
  }

  @override
  void dispose() { _passCtrl.dispose(); super.dispose(); }

  Future<void> _loadInvite() async {
    final data = await ref.read(authControllerProvider.notifier).getInviteDetails(widget.token);
    setState(() {
      _invite = data;
      _loading = false;
      if (data == null) _error = 'Invalid or expired invite link.';
    });
  }

  Future<void> _accept() async {
    final email = (_invite?['email'] as String?)?.trim() ?? '';
    final password = _passCtrl.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter your password to continue');
      return;
    }

    setState(() { _loading = true; _error = null; });
    final result = await ref.read(authControllerProvider.notifier)
        .signInWithPassword(email, password, inviteToken: widget.token);
    if (!mounted) return;
    if (result == null) {
      setState(() { _loading = false; _error = 'Sign in failed. Check your password.'; });
      return;
    }
    ref.invalidate(staffControllerProvider);
    context.go('/staff');
  }

  Future<void> _acceptWithGoogle() async {
    setState(() { _googleLoading = true; _error = null; });
    final result = await ref.read(authControllerProvider.notifier)
        .signInWithGoogle(inviteToken: widget.token);
    if (!mounted) return;
    setState(() => _googleLoading = false);
    if (result == null) {
      setState(() => _error = authErrorMessage(ref.read(authControllerProvider), google: true));
      return;
    }
    ref.invalidate(staffControllerProvider);
    context.go('/staff');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.dark,
    body: SafeArea(child: Padding(padding: const EdgeInsets.all(28),
      child: _loading
        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Image.asset('assets/images/splash_logo.png', width: 88, height: 88),
            const SizedBox(height: 24),
            const CircularProgressIndicator(color: AppColors.brand),
            const SizedBox(height: 16),
            const Text('Loading invitation…',
              style: TextStyle(color: AppColors.silver, fontSize: 14)),
          ]))
        : _error != null && _invite == null
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.error_outline, color: AppColors.red, size: 48),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.red)),
              const SizedBox(height: 20),
              AppButton(label: 'Go to sign in', isOutlined: true, onPressed: () => context.go('/signin')),
            ]))
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 60),
              Container(width: 64, height: 64,
                decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(18)),
                child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 32)),
              const SizedBox(height: 28),
              const Text("You're invited!", style: TextStyle(color: AppColors.silver, fontSize: 16)),
              const SizedBox(height: 6),
              Text(_invite?['orgName'] ?? '',
                style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: AppColors.white)),
              const SizedBox(height: 8),
              Text('Sign in as ${_invite?['email'] ?? ''}',
                style: const TextStyle(color: AppColors.silver, fontSize: 14)),
              const SizedBox(height: 32),
              TextField(
                controller: _passCtrl,
                obscureText: _obscure,
                style: const TextStyle(color: AppColors.white),
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline, color: AppColors.muted),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, color: AppColors.muted),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              if (_error != null && _invite != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppColors.red, fontSize: 13)),
              ],
              const Spacer(),
              AppButton(
                label: 'Accept & Sign In',
                isLoading: _loading && !_googleLoading,
                onPressed: (_loading || _googleLoading) ? null : _accept,
              ),
              const SizedBox(height: 12),
              GoogleSignInButton(
                isLoading: _googleLoading,
                onPressed: (_loading || _googleLoading) ? null : _acceptWithGoogle,
              ),
            ]))),
  );
}
