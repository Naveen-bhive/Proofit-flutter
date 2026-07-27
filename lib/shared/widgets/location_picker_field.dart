import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../core/constants/app_colors.dart';
import '../services/location_service.dart';
import '../services/places_service.dart';

/// Map-based job location picker with search, pan/zoom, and manual coordinates.
class LocationPickerField extends StatefulWidget {
  final String? initialAddress;
  final double? initialLat;
  final double? initialLng;
  final ValueChanged<SelectedPlace?> onPlaceSelected;

  const LocationPickerField({
    super.key,
    this.initialAddress,
    this.initialLat,
    this.initialLng,
    required this.onPlaceSelected,
  });

  @override
  State<LocationPickerField> createState() => _LocationPickerFieldState();
}

class _LocationPickerFieldState extends State<LocationPickerField> {
  static const _defaultCenter = LatLng(20.5937, 78.9629);
  static const _defaultZoom = 16.0;

  final _searchCtrl = TextEditingController();
  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();

  GoogleMapController? _mapCtrl;
  LatLng _pinPosition = _defaultCenter;
  double _zoom = _defaultZoom;
  String? _address;
  String? _coordError;
  bool _loading = true;
  bool _resolving = false;
  bool _showCoords = false;
  bool _searchLoading = false;
  List<PlaceSuggestion> _suggestions = [];
  Timer? _geocodeDebounce;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
    _bootstrap();
  }

  @override
  void dispose() {
    _geocodeDebounce?.cancel();
    _searchDebounce?.cancel();
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _mapCtrl?.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (widget.initialLat != null && widget.initialLng != null) {
      _pinPosition = LatLng(widget.initialLat!, widget.initialLng!);
      _address = widget.initialAddress;
      _syncCoordFields();
      _emitSelection();
      if (mounted) setState(() => _loading = false);
      return;
    }

    final pos = await LocationService.getCurrentPosition();
    if (pos != null) {
      _pinPosition = LatLng(pos.latitude, pos.longitude);
    }
    _syncCoordFields();
    await _resolveAddress();
    if (mounted) {
      setState(() => _loading = false);
      if (_mapCtrl != null) {
        await _moveCamera(_pinPosition, zoom: _zoom);
      }
    }
  }

  void _syncCoordFields() {
    _latCtrl.text = _pinPosition.latitude.toStringAsFixed(6);
    _lngCtrl.text = _pinPosition.longitude.toStringAsFixed(6);
  }

  void _emitSelection() {
    widget.onPlaceSelected(SelectedPlace(
      address: _address ?? '${_pinPosition.latitude}, ${_pinPosition.longitude}',
      latitude: _pinPosition.latitude,
      longitude: _pinPosition.longitude,
    ));
  }

  Future<void> _resolveAddress() async {
    setState(() => _resolving = true);
    final addr = await LocationService.getAddressFromCoords(
      _pinPosition.latitude,
      _pinPosition.longitude,
    );
    if (!mounted) return;
    setState(() {
      _address = addr;
      _resolving = false;
    });
    _emitSelection();
  }

  void _onPinMoved(LatLng position, {bool geocode = true}) {
    setState(() {
      _pinPosition = position;
      _coordError = null;
    });
    _syncCoordFields();
    if (!geocode) return;
    _geocodeDebounce?.cancel();
    _geocodeDebounce = Timer(const Duration(milliseconds: 450), _resolveAddress);
  }

  Future<void> _moveCamera(LatLng target, {double? zoom}) async {
    final z = zoom ?? _zoom;
    setState(() => _zoom = z);
    await _mapCtrl?.animateCamera(CameraUpdate.newLatLngZoom(target, z));
  }

  Future<void> _onMapCreated(GoogleMapController controller) async {
    _mapCtrl = controller;
    if (!_loading) {
      await _moveCamera(_pinPosition, zoom: _zoom);
    }
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () async {
      final q = _searchCtrl.text;
      if (q.trim().length < 3) {
        if (mounted) setState(() { _suggestions = []; _searchLoading = false; });
        return;
      }
      setState(() => _searchLoading = true);
      final results = await PlacesService.autocomplete(q);
      if (mounted) setState(() { _suggestions = results; _searchLoading = false; });
    });
  }

  Future<void> _pickSuggestion(PlaceSuggestion suggestion) async {
    setState(() {
      _suggestions = [];
      _searchLoading = true;
      _searchCtrl.text = suggestion.description;
    });
    final place = await PlacesService.placeDetails(suggestion.placeId);
    if (!mounted) return;
    setState(() => _searchLoading = false);
    if (place == null) return;

    final target = LatLng(place.latitude, place.longitude);
    setState(() {
      _pinPosition = target;
      _address = place.address;
      _zoom = 14;
      _coordError = null;
    });
    _syncCoordFields();
    await _moveCamera(target, zoom: 14);
    _emitSelection();
  }

  void _clearSearch() {
    _searchCtrl.clear();
    setState(() => _suggestions = []);
  }

  void _applyManualCoords() {
    final lat = double.tryParse(_latCtrl.text.trim());
    final lng = double.tryParse(_lngCtrl.text.trim());
    if (lat == null || lng == null || lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      setState(() => _coordError = 'Enter valid latitude (-90 to 90) and longitude (-180 to 180)');
      return;
    }
    final target = LatLng(lat, lng);
    setState(() {
      _coordError = null;
      _zoom = 16;
    });
    _onPinMoved(target);
    _moveCamera(target, zoom: 16);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'JOB LOCATION',
          style: TextStyle(
            color: AppColors.muted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _searchCtrl,
          style: const TextStyle(color: AppColors.white),
          decoration: InputDecoration(
            hintText: 'Search city, district, or address',
            hintStyle: const TextStyle(color: AppColors.muted, fontSize: 14),
            prefixIcon: const Icon(Icons.search, color: AppColors.muted),
            suffixIcon: _searchLoading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brand),
                    ),
                  )
                : (_searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: AppColors.muted),
                        onPressed: _clearSearch,
                      )
                    : null),
          ),
        ),
        if (_suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(maxHeight: 140),
            decoration: BoxDecoration(
              color: AppColors.dark3,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _suggestions.length.clamp(0, 5),
              separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
              itemBuilder: (_, i) {
                final s = _suggestions[i];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.place_outlined, color: AppColors.brand, size: 20),
                  title: Text(
                    s.description,
                    style: const TextStyle(color: AppColors.white, fontSize: 13),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => _pickSuggestion(s),
                );
              },
            ),
          ),
        const SizedBox(height: 8),
        const Text(
          'Pan, zoom, or tap the map to fine-tune the pin',
          style: TextStyle(color: AppColors.silver, fontSize: 12),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 260,
            child: _loading
                ? const ColoredBox(
                    color: AppColors.dark3,
                    child: Center(child: CircularProgressIndicator(color: AppColors.brand)),
                  )
                : Stack(
                    alignment: Alignment.center,
                    children: [
                      GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: _pinPosition,
                          zoom: _zoom,
                        ),
                        onMapCreated: _onMapCreated,
                        onCameraMove: (pos) {
                          _pinPosition = pos.target;
                          _zoom = pos.zoom;
                        },
                        onCameraIdle: () {
                          _syncCoordFields();
                          _geocodeDebounce?.cancel();
                          _geocodeDebounce = Timer(
                            const Duration(milliseconds: 450),
                            _resolveAddress,
                          );
                        },
                        onTap: (latLng) => _moveCamera(latLng, zoom: _zoom),
                        myLocationEnabled: true,
                        myLocationButtonEnabled: false,
                        zoomControlsEnabled: true,
                        zoomGesturesEnabled: true,
                        scrollGesturesEnabled: true,
                        rotateGesturesEnabled: true,
                        tiltGesturesEnabled: true,
                        mapToolbarEnabled: false,
                        gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                          Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
                        },
                      ),
                      const IgnorePointer(
                        child: Icon(Icons.location_pin, color: AppColors.brand, size: 42),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              _resolving ? Icons.hourglass_empty : Icons.location_on_outlined,
              color: AppColors.brand,
              size: 16,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _resolving
                    ? 'Getting address...'
                    : (_address ?? 'Move the map to set the job location'),
                style: const TextStyle(color: AppColors.silver, fontSize: 12, height: 1.4),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () => setState(() => _showCoords = !_showCoords),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(
                  _showCoords ? Icons.expand_less : Icons.expand_more,
                  color: AppColors.muted,
                  size: 20,
                ),
                const SizedBox(width: 4),
                const Text(
                  'Enter latitude & longitude manually',
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        if (_showCoords) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _latCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  style: const TextStyle(color: AppColors.white, fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'Latitude',
                    hintText: 'e.g. 12.971600',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _lngCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  style: const TextStyle(color: AppColors.white, fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'Longitude',
                    hintText: 'e.g. 77.594600',
                  ),
                ),
              ),
            ],
          ),
          if (_coordError != null) ...[
            const SizedBox(height: 6),
            Text(_coordError!, style: const TextStyle(color: AppColors.red, fontSize: 12)),
          ],
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _applyManualCoords,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.brand,
                side: const BorderSide(color: AppColors.brand),
              ),
              child: const Text('Apply coordinates'),
            ),
          ),
        ],
      ],
    );
  }
}
