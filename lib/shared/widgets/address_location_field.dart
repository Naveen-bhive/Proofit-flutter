import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/profile_validators.dart';
import '../services/places_service.dart';
import '../widgets/app_button.dart';
import 'location_picker_field.dart';

/// Form field that shows the chosen address and opens a full-screen map picker
/// to change it. Its value is a [SelectedPlace] (address text + map pin), and it
/// is invalid until a location has been chosen.
class AddressLocationField extends FormField<SelectedPlace> {
  AddressLocationField({
    super.key,
    super.initialValue,
    String? existingAddress,
    super.enabled,
    ValueChanged<SelectedPlace?>? onChanged,
  }) : super(
          validator: (v) => v == null ? 'Choose your address location on the map' : null,
          builder: (state) {
            final place = state.value;
            final hasError = state.hasError;

            Future<void> open() async {
              final result = await Navigator.of(state.context, rootNavigator: true).push<SelectedPlace>(
                MaterialPageRoute(
                  fullscreenDialog: true,
                  builder: (_) => AddressPickerScreen(initial: place, existingAddress: existingAddress),
                ),
              );
              if (result != null) {
                state.didChange(result);
                onChanged?.call(result);
              }
            }

            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('ADDRESS',
                  style: TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.2)),
              const SizedBox(height: 8),
              InkWell(
                onTap: state.widget.enabled ? open : null,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.dark3,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: hasError ? AppColors.red : AppColors.border),
                  ),
                  child: Row(children: [
                    Icon(place == null ? Icons.add_location_alt_outlined : Icons.location_on,
                        color: place == null ? AppColors.silver : AppColors.brand, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: place == null
                          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const Text('Choose address on map', style: TextStyle(color: AppColors.white, fontSize: 14)),
                              if (existingAddress != null && existingAddress.trim().isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text('Current: $existingAddress',
                                    maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.silver, fontSize: 12)),
                              ],
                            ])
                          : Text(place.address, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.white, fontSize: 14)),
                    ),
                    const SizedBox(width: 8),
                    Text(place == null ? 'Choose' : 'Change',
                        style: const TextStyle(color: AppColors.brand, fontSize: 13, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
              if (hasError)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 4),
                  child: Text(state.errorText ?? '', style: const TextStyle(color: AppColors.red, fontSize: 12)),
                ),
            ]);
          },
        );
}

/// Full-screen map picker: search or move the pin, then refine the address text.
class AddressPickerScreen extends StatefulWidget {
  final SelectedPlace? initial;
  final String? existingAddress;
  const AddressPickerScreen({super.key, this.initial, this.existingAddress});

  @override
  State<AddressPickerScreen> createState() => _AddressPickerScreenState();
}

class _AddressPickerScreenState extends State<AddressPickerScreen> {
  final _addressCtrl = TextEditingController();
  SelectedPlace? _place;
  String? _error;

  @override
  void initState() {
    super.initState();
    _place = widget.initial;
    final start = widget.initial?.address ?? widget.existingAddress ?? '';
    _addressCtrl.text = start;
  }

  @override
  void dispose() {
    _addressCtrl.dispose();
    super.dispose();
  }

  void _onPlace(SelectedPlace? p) {
    // The map picker reports during its own init; apply after the frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || p == null) return;
      final first = _place == null;
      final moved = first || _place!.latitude != p.latitude || _place!.longitude != p.longitude;
      setState(() {
        _place = p;
        // Moving the pin refreshes the address text, except the very first report
        // when the owner already has an address typed in (kept until they move the pin).
        final keepTyped = first && _addressCtrl.text.trim().isNotEmpty;
        if ((moved && !keepTyped) || _addressCtrl.text.trim().isEmpty) {
          _addressCtrl.text = p.address;
        }
      });
    });
  }

  void _confirm() {
    final place = _place;
    if (place == null) {
      setState(() => _error = 'Move the pin or search to choose a location');
      return;
    }
    final err = ProfileValidators.address(_addressCtrl.text);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    Navigator.of(context).pop(SelectedPlace(
      address: _addressCtrl.text.trim(),
      latitude: place.latitude,
      longitude: place.longitude,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(title: const Text('Choose address')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            LocationPickerField(
              initialAddress: widget.initial?.address,
              initialLat: widget.initial?.latitude,
              initialLng: widget.initial?.longitude,
              onPlaceSelected: _onPlace,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _addressCtrl,
              style: const TextStyle(color: AppColors.white),
              keyboardType: TextInputType.streetAddress,
              textCapitalization: TextCapitalization.sentences,
              minLines: 2,
              maxLines: 4,
              maxLength: 300,
              decoration: const InputDecoration(
                labelText: 'Full address',
                helperText: 'Set the pin first, then add flat / door number if needed',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(_error!, style: const TextStyle(color: AppColors.red, fontSize: 13)),
            ],
            const SizedBox(height: 16),
            AppButton(label: 'Confirm address', onPressed: _confirm),
          ]),
        ),
      ),
    );
  }
}
