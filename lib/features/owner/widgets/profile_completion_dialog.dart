import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/profile_validators.dart';
import '../../../shared/services/places_service.dart';
import '../../../shared/widgets/address_location_field.dart';
import '../../../shared/widgets/app_button.dart';
import '../controllers/owner_controller.dart';

/// Blocking popup for owners whose profile predates the mobile number / address
/// fields. It cannot be dismissed (no back, no tap-outside, no cancel) and only
/// closes once the missing details are saved.
class ProfileCompletionDialog extends ConsumerStatefulWidget {
  const ProfileCompletionDialog({super.key});

  /// Shows the dialog and completes once the profile has been saved.
  static Future<void> show(BuildContext context) => showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const ProfileCompletionDialog(),
      );

  @override
  ConsumerState<ProfileCompletionDialog> createState() => _ProfileCompletionDialogState();
}

class _ProfileCompletionDialogState extends ConsumerState<ProfileCompletionDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _mobileCtrl;
  SelectedPlace? _place;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final s = ref.read(ownerControllerProvider);
    _mobileCtrl = TextEditingController(text: ProfileValidators.normalizeMobile(s.ownerPhone));
    if (s.address.trim().isNotEmpty && s.addressLatitude != null && s.addressLongitude != null) {
      _place = SelectedPlace(address: s.address, latitude: s.addressLatitude!, longitude: s.addressLongitude!);
    }
  }

  @override
  void dispose() {
    _mobileCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final s = ref.read(ownerControllerProvider);
    final err = await ref.read(ownerControllerProvider.notifier).updateProfile(
          companyName: s.orgName,
          mobile: ProfileValidators.normalizeMobile(_mobileCtrl.text),
          address: _place!.address,
          latitude: _place!.latitude,
          longitude: _place!.longitude,
        );
    if (!mounted) return;
    if (err == null) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _saving = false;
        _error = err;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: AppColors.dark2,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        title: const Text('Complete your profile', style: TextStyle(color: AppColors.white)),
        content: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text(
                'Please add your mobile number and choose your address on the map to continue using ProofIt.',
                style: TextStyle(color: AppColors.silver, fontSize: 13),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _mobileCtrl,
                style: const TextStyle(color: AppColors.white),
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                inputFormatters: [MobileInputFormatter()],
                validator: ProfileValidators.mobile,
                decoration: const InputDecoration(labelText: 'Mobile Number', prefixText: '+91  ', hintText: '10-digit number'),
              ),
              const SizedBox(height: 14),
              AddressLocationField(
                initialValue: _place,
                existingAddress: ref.read(ownerControllerProvider).address,
                enabled: !_saving,
                onChanged: (p) => _place = p,
              ),
              if (_error != null) ...[
                const SizedBox(height: 4),
                Text(_error!, style: const TextStyle(color: AppColors.red, fontSize: 13)),
              ],
            ]),
          ),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: AppButton(label: 'Save & Continue', isLoading: _saving, onPressed: _save),
          ),
        ],
      ),
    );
  }
}
