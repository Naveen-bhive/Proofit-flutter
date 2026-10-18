import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/profile_validators.dart';
import '../../../shared/services/places_service.dart';
import '../../../shared/widgets/address_location_field.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../../../core/constants/app_text_styles.dart';
import '../controllers/owner_controller.dart';

/// Owner profile: view mode by default, with an explicit edit mode for
/// company name, mobile number and address (all required).
class OwnerProfileDetailsScreen extends ConsumerStatefulWidget {
  const OwnerProfileDetailsScreen({super.key});
  @override
  ConsumerState<OwnerProfileDetailsScreen> createState() => _OwnerProfileDetailsScreenState();
}

class _OwnerProfileDetailsScreenState extends ConsumerState<OwnerProfileDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _companyCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  SelectedPlace? _place;
  bool _editing = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fillFromState();
    // Pick up changes made on another device.
    ref.read(ownerControllerProvider.notifier).syncOrgFromServer().then((_) {
      if (mounted && !_editing) setState(_fillFromState);
    });
  }

  @override
  void dispose() {
    _companyCtrl.dispose();
    _mobileCtrl.dispose();
    super.dispose();
  }

  void _fillFromState() {
    final s = ref.read(ownerControllerProvider);
    _companyCtrl.text = s.orgName;
    _mobileCtrl.text = ProfileValidators.normalizeMobile(s.ownerPhone);
    _place = s.address.trim().isNotEmpty && s.addressLatitude != null && s.addressLongitude != null
        ? SelectedPlace(address: s.address, latitude: s.addressLatitude!, longitude: s.addressLongitude!)
        : null;
  }

  bool get _dirty {
    final s = ref.read(ownerControllerProvider);
    return _companyCtrl.text.trim() != s.orgName ||
        ProfileValidators.normalizeMobile(_mobileCtrl.text) != ProfileValidators.normalizeMobile(s.ownerPhone) ||
        _place?.address != (s.address.trim().isEmpty ? null : s.address) ||
        _place?.latitude != s.addressLatitude ||
        _place?.longitude != s.addressLongitude;
  }

  void _startEdit() => setState(() {
        _fillFromState();
        _error = null;
        _editing = true;
      });

  void _cancelEdit() => setState(() {
        _fillFromState();
        _error = null;
        _editing = false;
      });

  Future<bool> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.dark2,
        title: const Text('Discard changes?', style: TextStyle(color: AppColors.text)),
        content: const Text('Your edits have not been saved.', style: TextStyle(color: AppColors.silver)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep editing', style: TextStyle(color: AppColors.silver))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Discard', style: TextStyle(color: AppColors.red))),
        ],
      ),
    );
    return discard == true;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final err = await ref.read(ownerControllerProvider.notifier).updateProfile(
          companyName: _companyCtrl.text.trim(),
          mobile: ProfileValidators.normalizeMobile(_mobileCtrl.text),
          address: _place!.address,
          latitude: _place!.latitude,
          longitude: _place!.longitude,
        );
    if (!mounted) return;
    if (err == null) {
      setState(() {
        _saving = false;
        _editing = false;
        _fillFromState();
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated')));
    } else {
      setState(() {
        _saving = false;
        _error = err;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ownerControllerProvider);

    return PopScope(
      canPop: !_editing,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // Back while editing: leave straight away if nothing changed, otherwise confirm first.
        final leave = !_dirty || await _confirmDiscard();
        if (!context.mounted) return;
        if (leave) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: AppColors.dark,
        body: SafeArea(
          child: Column(children: [
            PageHeader(
              title: _editing ? 'Edit Profile' : 'Profile',
              onBack: () => Navigator.of(context).maybePop(),
              actions: [
                if (!_editing)
                  HeaderIconButton(icon: Icons.edit_outlined, tinted: true, round: false, onTap: _startEdit),
              ],
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: _editing ? _editForm() : _viewMode(state),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ── View mode ──────────────────────────────────────────────

  Widget _viewMode(OwnerState s) {
    final pinned = s.addressLatitude != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 16),
      Row(children: [
        SoftBadge(label: s.isProfileComplete ? 'Verified Organization' : 'Profile incomplete',
            color: s.isProfileComplete ? AppColors.brand : AppColors.yellow, fontSize: 12),
        const Spacer(),
        Text('Plan: ${s.plan.isEmpty ? '-' : s.plan[0].toUpperCase() + s.plan.substring(1)}',
            style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
      ]),
      const SizedBox(height: 18),
      SurfaceCard(
        radius: 22,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Column(children: [
          _row(Icons.apartment_rounded, AppColors.brand, 'Company Name', s.orgName),
          const Divider(height: 1, color: AppColors.borderSoft),
          _row(Icons.phone_outlined, AppColors.light, 'Mobile Number', s.ownerPhone.isEmpty ? '' : '+91 ${ProfileValidators.normalizeMobile(s.ownerPhone)}'),
          const Divider(height: 1, color: AppColors.borderSoft),
          _row(Icons.location_on_outlined, AppColors.light, 'Address', s.address),
          const Divider(height: 1, color: AppColors.borderSoft),
          _mapRow(pinned),
        ]),
      ),
    ]);
  }

  Widget _row(IconData icon, Color color, String label, String value) {
    final missing = value.trim().isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(children: [
        IconTile(icon: icon, color: color, background: AppColors.dark3, size: 40, iconSize: 20),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label.toUpperCase(), style: AppTextStyles.label.copyWith(fontSize: 11)),
            const SizedBox(height: 4),
            missing
                ? const SoftBadge(label: 'Not provided', color: AppColors.red, dot: true, fontSize: 12)
                : Text(value, style: const TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w600)),
          ]),
        ),
      ]),
    );
  }

  Widget _mapRow(bool pinned) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(children: [
        IconTile(icon: Icons.map_outlined, color: pinned ? AppColors.greenDark : AppColors.red, size: 40, iconSize: 20),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('MAP LOCATION', style: AppTextStyles.label.copyWith(fontSize: 11)),
            const SizedBox(height: 4),
            Row(children: [
              pinned
                  ? const SoftBadge(label: 'Pinned on map', color: AppColors.greenDark, dot: true, fontSize: 12)
                  : const SoftBadge(label: 'Not provided', color: AppColors.red, dot: true, fontSize: 12),
              if (!pinned) ...[
                const SizedBox(width: 8),
                const Flexible(
                  child: Text('(Tap edit to pin map)',
                      style: TextStyle(color: AppColors.muted, fontSize: 12, fontStyle: FontStyle.italic)),
                ),
              ],
            ]),
          ]),
        ),
      ]),
    );
  }

  // ── Edit mode ──────────────────────────────────────────────

  Widget _editForm() {
    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextFormField(
          controller: _companyCtrl,
          enabled: !_saving,
          style: const TextStyle(color: AppColors.text),
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          validator: ProfileValidators.companyName,
          decoration: const InputDecoration(labelText: 'Company Name', prefixIcon: Icon(Icons.business_outlined)),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _mobileCtrl,
          enabled: !_saving,
          style: const TextStyle(color: AppColors.text),
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
          inputFormatters: [MobileInputFormatter()],
          validator: ProfileValidators.mobile,
          decoration: const InputDecoration(labelText: 'Mobile Number', prefixIcon: Icon(Icons.phone_outlined), prefixText: '+91  ', hintText: '10-digit number'),
        ),
        const SizedBox(height: 16),
        AddressLocationField(
          // Keyed so a Cancel / re-entry rebuilds the field from the saved profile.
          key: ValueKey('${_place?.latitude}-${_place?.longitude}-$_editing'),
          initialValue: _place,
          existingAddress: ref.read(ownerControllerProvider).address,
          enabled: !_saving,
          onChanged: (p) => _place = p,
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: AppColors.red)),
        ],
        const SizedBox(height: 20),
        PrimaryButton(label: 'Save Changes', icon: Icons.check_rounded, loading: _saving, onPressed: _save),
        const SizedBox(height: 12),
        SecondaryButton(label: 'Cancel', onPressed: _saving ? null : _cancelEdit),
      ]),
    );
  }
}
