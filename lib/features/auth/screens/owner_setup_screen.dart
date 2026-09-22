import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/profile_validators.dart';
import '../../../shared/services/places_service.dart';
import '../../../shared/widgets/address_location_field.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../core/utils/api_error_utils.dart';
import '../controllers/auth_controller.dart';

class OwnerSetupScreen extends ConsumerStatefulWidget {
  const OwnerSetupScreen({super.key});
  @override
  ConsumerState<OwnerSetupScreen> createState() => _OwnerSetupScreenState();
}

class _OwnerSetupScreenState extends ConsumerState<OwnerSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _companyCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  SelectedPlace? _place;
  bool _loading = false;
  String? _error;

  Future<void> _setup() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final success = await ref.read(authControllerProvider.notifier).setupOwner(
          _companyCtrl.text.trim(),
          mobile: ProfileValidators.normalizeMobile(_mobileCtrl.text),
          address: _place!.address,
          latitude: _place!.latitude,
          longitude: _place!.longitude,
        );
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
  void dispose() {
    _companyCtrl.dispose();
    _mobileCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 40),
              const Text('Set up your account',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.white, letterSpacing: -0.5)),
              const SizedBox(height: 8),
              const Text('This takes 30 seconds', style: TextStyle(color: AppColors.silver)),
              const SizedBox(height: 36),
              TextFormField(
                controller: _companyCtrl,
                style: const TextStyle(color: AppColors.white),
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                validator: ProfileValidators.companyName,
                decoration: const InputDecoration(labelText: 'Company / Business Name'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _mobileCtrl,
                style: const TextStyle(color: AppColors.white),
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                inputFormatters: [MobileInputFormatter()],
                validator: ProfileValidators.mobile,
                decoration: const InputDecoration(labelText: 'Mobile Number', prefixText: '+91  ', hintText: '10-digit number'),
              ),
              const SizedBox(height: 16),
              AddressLocationField(
                initialValue: _place,
                enabled: !_loading,
                onChanged: (p) => _place = p,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppColors.red)),
              ],
              const SizedBox(height: 20),
              AppButton(label: 'Get Started', isLoading: _loading, onPressed: _setup),
            ]),
          ),
        ),
      ),
    );
  }
}
