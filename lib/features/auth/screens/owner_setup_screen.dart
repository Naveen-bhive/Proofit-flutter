import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../core/utils/api_error_utils.dart';
import '../controllers/auth_controller.dart';

class OwnerSetupScreen extends ConsumerStatefulWidget {
  const OwnerSetupScreen({super.key});
  @override
  ConsumerState<OwnerSetupScreen> createState() => _OwnerSetupScreenState();
}

class _OwnerSetupScreenState extends ConsumerState<OwnerSetupScreen> {
  final _nameCtrl    = TextEditingController();
  final _companyCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _setup() async {
    if (_nameCtrl.text.trim().isEmpty || _companyCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Please fill in all fields');
      return;
    }
    setState(() { _loading = true; _error = null; });
    final success = await ref.read(authControllerProvider.notifier)
        .setupOwner(_companyCtrl.text.trim(), ownerName: _nameCtrl.text.trim());
    if (!mounted) return;
    setState(() => _loading = false);
    if (success) {
      context.go('/owner');
    } else {
      final authState = ref.read(authControllerProvider);
      setState(() => _error = friendlyErrorMessage(
            authState.error,
            fallback: 'Could not create your account. Please try again.',
          ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark,
      body: SafeArea(child: Padding(padding: const EdgeInsets.all(24), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 40),
        const Text('Set up your account', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.white, letterSpacing: -0.5)),
        const SizedBox(height: 8),
        const Text('This takes 30 seconds', style: TextStyle(color: AppColors.silver)),
        const SizedBox(height: 36),
        TextFormField(
          controller: _nameCtrl,
          style: const TextStyle(color: AppColors.white),
          decoration: const InputDecoration(labelText: 'Your Name'),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _companyCtrl,
          style: const TextStyle(color: AppColors.white),
          decoration: const InputDecoration(labelText: 'Company / Business Name'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: AppColors.red)),
        ],
        const SizedBox(height: 28),
        AppButton(label: 'Get Started', isLoading: _loading, onPressed: _setup),
      ]))),
    );
  }
}