import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_service.dart';
import '../../../shared/widgets/plan_gate.dart';
import '../../../shared/services/socket_service.dart';
import '../../leave/leave_common.dart' show LeaveAvatar, SheetHandle;
import '../controllers/owner_controller.dart';

/// Owner live map. Shows every staff member with a known location ("All
/// Staff"), or a single staff member when [initialStaffId] is given (e.g. from
/// a "staff logged in" push) or picked from the staff filter.
class LiveMapScreen extends ConsumerStatefulWidget {
  final String? initialStaffId;
  const LiveMapScreen({super.key, this.initialStaffId});
  @override
  ConsumerState<LiveMapScreen> createState() => _LiveMapScreenState();
}

class _StaffOption {
  final String id;
  final String name;
  final String? photoUrl;
  const _StaffOption(this.id, this.name, this.photoUrl);
}

class _LiveMapScreenState extends ConsumerState<LiveMapScreen> {
  GoogleMapController? _mapCtrl;
  bool _showMap = true;
  final Map<String, Map<String, dynamic>> _liveLocations = {};
  Timer? _fallbackTimer;
  final List<SocketListenerId> _socketIds = [];

  /// null = All Staff.
  String? _selectedId;
  List<_StaffOption> _staff = [];

  /// Staff ids already framed in "All Staff" mode; refit only when it changes.
  Set<String> _fittedIds = {};

  /// Selected staff still needs the camera moved to them (location may arrive later).
  bool _pendingFocus = false;

  final Map<String, BitmapDescriptor> _iconCache = {};
  final Set<String> _iconsInFlight = {};

  static const _defaultCenter = LatLng(20.5937, 78.9629); // India
  static const _staleThreshold = Duration(minutes: 7);
  static const _focusZoom = 16.0;

  static void _ensureTextureMapMode() {
    if (!Platform.isAndroid) return;
    final maps = GoogleMapsFlutterPlatform.instance;
    if (maps is GoogleMapsFlutterAndroid) {
      // Must stay false in release - hybrid composition bleeds a grey native layer over other routes.
      maps.useAndroidViewSurface = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _ensureTextureMapMode();
    final initial = widget.initialStaffId;
    if (initial != null && initial.isNotEmpty) {
      _selectedId = initial;
      _pendingFocus = true;
    }
    _loadStaff();
    _loadInitial();
    _setupSocket();
    // REST fallback - merge by timestamp so socket updates aren't overwritten.
    _fallbackTimer =
        Timer.periodic(const Duration(seconds: 10), (_) => _loadInitial());
  }

  Future<void> _loadStaff() async {
    try {
      final res = await ref.read(apiServiceProvider).get('/staff');
      if (res.data['success'] != true || !mounted) return;
      final rows = List<Map<String, dynamic>>.from(res.data['data'] ?? []);
      setState(() {
        _staff = rows
            .where((r) => r['kind'] != 'invite')
            .map((r) => _StaffOption(r['_id'].toString(),
                (r['name'] ?? 'Staff').toString(), r['photoUrl']?.toString()))
            .toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      });
    } catch (_) {}
  }

  DateTime? _parseLastSeen(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    try {
      return DateTime.parse(iso).toLocal();
    } catch (_) {
      return null;
    }
  }

  /// Keep fresher pin data when REST poll runs (don't wipe recent socket moves).
  void _mergeLocation(String id, Map<String, dynamic> incoming) {
    final normalized = _normalizeLocation(id, incoming);
    final existing = _liveLocations[id];
    if (existing == null) {
      _liveLocations[id] = normalized;
      return;
    }
    final existingSeen = _parseLastSeen(existing['lastSeen']?.toString());
    final incomingSeen = _parseLastSeen(normalized['lastSeen']?.toString());
    final Map<String, dynamic> merged;
    if (existingSeen != null &&
        incomingSeen != null &&
        existingSeen.isAfter(incomingSeen)) {
      merged = {...normalized, ...existing};
    } else {
      merged = {...existing, ...normalized};
    }
    _liveLocations[id] = _finalizeLocation(merged);
  }

  Future<void> _loadInitial() async {
    await ref.read(ownerControllerProvider.notifier).loadLiveLocations();
    final locs = ref.read(ownerControllerProvider).staffLocations;
    if (!mounted) return;
    setState(() {
      final serverIds = <String>{};
      for (final l in locs) {
        final id = l['staffId']?.toString() ?? '';
        if (id.isEmpty) continue;
        serverIds.add(id);
        _mergeLocation(id, l);
      }
      // Drop staff who checked out (no longer in server snapshot).
      _liveLocations.removeWhere((id, _) => !serverIds.contains(id));
    });
    _updateCamera();
  }

  Map<String, dynamic> _normalizeLocation(
      String id, Map<String, dynamic> data) {
    final lastSeen = data['lastSeen']?.toString() ??
        data['timestamp']?.toString() ??
        DateTime.now().toIso8601String();
    final base = {
      ...data,
      'staffId': id,
      'name': data['name'] ?? 'Staff',
      'lat': (data['lat'] ?? data['latitude'] ?? 0).toDouble(),
      'lng': (data['lng'] ?? data['longitude'] ?? 0).toDouble(),
      'lastSeen': lastSeen,
    };
    return _finalizeLocation(base);
  }

  /// Live = recent ping from staff app. Stale = no ping in threshold. Not movement-based.
  /// Offline = not checked in; the pin is the location shared at sign-in.
  Map<String, dynamic> _finalizeLocation(Map<String, dynamic> data) {
    final lastSeen = data['lastSeen']?.toString();
    final status = _resolveTrackingStatus(
      lastSeen,
      data['trackingStatus']?.toString(),
    );
    return {
      ...data,
      'trackingStatus': status,
      'isStale': status != 'live',
    };
  }

  String _resolveTrackingStatus(String? lastSeenIso, String? serverStatus) {
    if (serverStatus == 'impaired') return 'impaired';
    if (serverStatus == 'offline') return 'offline';
    if (_isStaleFromLastSeen(lastSeenIso)) return 'stale';
    return 'live';
  }

  bool _isStaleFromLastSeen(String? iso) {
    if (iso == null || iso.isEmpty) return true;
    try {
      final dt = DateTime.parse(iso).toLocal();
      return DateTime.now().difference(dt) >= _staleThreshold;
    } catch (_) {
      return true;
    }
  }

  void _setupSocket() {
    SocketService.connect();
    _socketIds.add(SocketService.onStaffLocation((data) {
      if (!mounted) return;
      final id = data['staffId']?.toString() ?? '';
      if (id.isEmpty) return;
      setState(() {
        _mergeLocation(id, {
          ...data,
          'lastSeen': data['lastSeen'] ??
              data['timestamp'] ??
              DateTime.now().toIso8601String(),
          'trackingStatus': data['trackingStatus'] ?? 'live',
          'isStale': false,
        });
      });
      if (id == _selectedId) _followSelected();
    }));
    _socketIds.add(SocketService.onStaffCheckIn((data) {
      if (!mounted) return;
      final id = data['staffId']?.toString() ?? '';
      if (id.isEmpty) return;
      final loc = data['location'] is Map
          ? Map<String, dynamic>.from(data['location'] as Map)
          : null;
      final lat = (loc?['latitude'] ?? data['latitude']) as num?;
      final lng = (loc?['longitude'] ?? data['longitude']) as num?;
      if (lat == null || lng == null) return;
      setState(() {
        _mergeLocation(id, {
          'staffId': id,
          'name': data['name'] ?? 'Staff',
          'lat': lat.toDouble(),
          'lng': lng.toDouble(),
          'lastSeen': DateTime.now().toIso8601String(),
          'trackingStatus': 'live',
          'isStale': false,
        });
      });
      _updateCamera();
    }));
    _socketIds.add(SocketService.onStaffCheckOut((data) {
      if (!mounted) return;
      final id = data['staffId']?.toString() ?? '';
      if (id.isEmpty) return;
      setState(() => _liveLocations.remove(id));
    }));
    _socketIds.add(SocketService.onStaffTrackingStatus((data) {
      if (!mounted) return;
      final id = data['staffId']?.toString() ?? '';
      if (id.isEmpty) return;
      final socketStatus = data['trackingStatus']?.toString();
      final socketLastSeen = data['lastSeen']?.toString();
      // Ignore stale cron hints when the ping is still within the live window.
      if (socketStatus == 'stale' &&
          socketLastSeen != null &&
          !_isStaleFromLastSeen(socketLastSeen)) {
        return;
      }
      setState(() {
        _mergeLocation(id, {
          ...?(_liveLocations[id]),
          ...data,
          'staffId': id,
          if (data['reason'] != null) 'impairedReason': data['reason'],
        });
      });
    }));
  }

  // ─── Camera ─────────────────────────────────────────────────────────────

  LatLng _posOf(Map<String, dynamic> l) =>
      LatLng((l['lat'] as num).toDouble(), (l['lng'] as num).toDouble());

  Map<String, dynamic>? get _selectedLocation =>
      _selectedId == null ? null : _liveLocations[_selectedId];

  /// Called after data changes: focus a pending selection, or reframe the
  /// "All Staff" view when the set of visible staff changes.
  void _updateCamera() {
    if (_selectedId != null) {
      if (_pendingFocus) _focusSelected();
      return;
    }
    final ids = _liveLocations.keys.toSet();
    if (ids.length != _fittedIds.length || !ids.containsAll(_fittedIds)) {
      _fitToMarkers();
    }
  }

  void _focusSelected() {
    final loc = _selectedLocation;
    if (_mapCtrl == null || loc == null) return;
    _pendingFocus = false;
    _mapCtrl!.animateCamera(CameraUpdate.newLatLngZoom(_posOf(loc), _focusZoom));
    _mapCtrl!.showMarkerInfoWindow(MarkerId(_selectedId!));
  }

  /// Keep the selected staff member in view as new pings arrive.
  void _followSelected() {
    if (_pendingFocus) {
      _focusSelected();
      return;
    }
    final loc = _selectedLocation;
    if (_mapCtrl == null || loc == null) return;
    _mapCtrl!.animateCamera(CameraUpdate.newLatLng(_posOf(loc)));
  }

  void _fitToMarkers() {
    if (_mapCtrl == null || _liveLocations.isEmpty) return;
    _fittedIds = _liveLocations.keys.toSet();

    final points = _liveLocations.values.map(_posOf).toList();
    if (points.length == 1) {
      _mapCtrl!.animateCamera(CameraUpdate.newLatLngZoom(points.first, 14));
      return;
    }

    double minLat = points.first.latitude, maxLat = points.first.latitude;
    double minLng = points.first.longitude, maxLng = points.first.longitude;
    for (final p in points) {
      minLat = minLat < p.latitude ? minLat : p.latitude;
      maxLat = maxLat > p.latitude ? maxLat : p.latitude;
      minLng = minLng < p.longitude ? minLng : p.longitude;
      maxLng = maxLng > p.longitude ? maxLng : p.longitude;
    }
    _mapCtrl!.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(
          southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng)),
      80,
    ));
  }

  void _select(String? staffId) {
    setState(() {
      _selectedId = staffId;
      _pendingFocus = staffId != null;
    });
    if (staffId == null) {
      _fitToMarkers();
    } else {
      _focusSelected();
    }
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    for (final id in _socketIds) {
      SocketService.off(id);
    }
    _mapCtrl?.dispose();
    _mapCtrl = null;
    _ensureTextureMapMode();
    super.dispose();
  }

  @override
  void deactivate() {
    _showMap = false;
    _ensureTextureMapMode();
    super.deactivate();
  }

  // ─── Markers ────────────────────────────────────────────────────────────

  int get _liveCount =>
      _liveLocations.values.where((l) => l['trackingStatus'] == 'live').length;

  Color _statusColor(String status) => switch (status) {
        'impaired' => AppColors.red,
        'stale' => AppColors.yellow,
        'offline' => AppColors.silver,
        _ => AppColors.green,
      };

  double _fallbackHue(String status) => switch (status) {
        'impaired' => BitmapDescriptor.hueRed,
        'stale' => BitmapDescriptor.hueYellow,
        'offline' => BitmapDescriptor.hueAzure,
        _ => BitmapDescriptor.hueGreen,
      };

  Set<Marker> get _markers {
    final visible = _selectedId == null
        ? _liveLocations.values
        : _liveLocations.values.where((l) => l['staffId'] == _selectedId);
    return visible.map((l) {
      final id = l['staffId']?.toString() ?? '';
      final name = _displayName(l);
      final status = l['trackingStatus']?.toString() ?? 'live';
      final key = '$name|$status';
      final icon = _iconCache[key];
      if (icon == null) _buildLabelIcon(key, name, status);
      return Marker(
        markerId: MarkerId(id),
        position: _posOf(l),
        icon: icon ?? BitmapDescriptor.defaultMarkerWithHue(_fallbackHue(status)),
        anchor: const Offset(0.5, 1.0),
        zIndexInt: status == 'live' ? 2 : 1,
        infoWindow: InfoWindow(title: name, snippet: _snippetFor(l)),
        onTap: () {
          if (_selectedId != id) _select(id);
        },
      );
    }).toSet();
  }

  String _displayName(Map<String, dynamic> l) {
    final id = l['staffId']?.toString();
    final fromList = _staff.where((s) => s.id == id).firstOrNull?.name;
    return (fromList ?? l['name']?.toString() ?? 'Staff').trim();
  }

  /// Draws a name pill with a status-coloured pin under it, so every staff
  /// member is identifiable on the map without tapping.
  Future<void> _buildLabelIcon(String key, String name, String status) async {
    if (_iconsInFlight.contains(key)) return;
    _iconsInFlight.add(key);
    try {
      final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 2.0;
      final color = _statusColor(status);
      final label = name.length > 18 ? '${name.substring(0, 17)}…' : name;

      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
              color: Colors.white, fontSize: 12.5 * dpr, fontWeight: FontWeight.w700),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final padH = 10 * dpr, padV = 6 * dpr, dotR = 7 * dpr, stem = 6 * dpr, border = 2 * dpr;
      final pillW = tp.width + padH * 2 + dotR * 1.6;
      final pillH = tp.height + padV * 2;
      final width = pillW + border * 2;
      final height = pillH + stem + dotR * 2 + border * 3;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final pill = RRect.fromRectAndRadius(
          Rect.fromLTWH(border, border, pillW, pillH), Radius.circular(pillH / 2));
      canvas.drawRRect(pill.inflate(border), Paint()..color = color);
      canvas.drawRRect(pill, Paint()..color = AppColors.dark2);
      // Status dot inside the pill.
      canvas.drawCircle(Offset(border + padH * 0.8 + dotR * 0.4, border + pillH / 2), dotR * 0.45,
          Paint()..color = color);
      tp.paint(canvas, Offset(border + padH * 0.8 + dotR * 1.4, border + padV));
      // Stem and pin.
      final cx = width / 2;
      final stemTop = border * 2 + pillH;
      canvas.drawRect(Rect.fromLTWH(cx - border / 2, stemTop, border, stem), Paint()..color = color);
      final pinCenter = Offset(cx, stemTop + stem + dotR);
      canvas.drawCircle(pinCenter, dotR + border, Paint()..color = Colors.white);
      canvas.drawCircle(pinCenter, dotR, Paint()..color = color);

      final image = await recorder.endRecording().toImage(width.ceil(), height.ceil());
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null || !mounted) return;
      setState(() {
        _iconCache[key] =
            BitmapDescriptor.bytes(bytes.buffer.asUint8List(), imagePixelRatio: dpr);
      });
    } catch (_) {
      // Default hue marker stays in place.
    } finally {
      _iconsInFlight.remove(key);
    }
  }

  String _snippetFor(Map<String, dynamic> l) {
    final status = l['trackingStatus']?.toString() ?? 'live';
    final lastSeen = l['lastSeen']?.toString();
    final age = _relativeAge(lastSeen);
    if (status == 'impaired') {
      return age == null
          ? 'Live tracking interrupted'
          : 'Live tracking interrupted · last ping $age';
    }
    if (status == 'stale') {
      return age == null
          ? 'No location signal'
          : 'No location signal · last ping $age';
    }
    if (status == 'offline') {
      return age == null
          ? 'Not checked in · location at sign-in'
          : 'Not checked in · signed in $age';
    }
    return age == null ? 'Live' : 'Live · updated $age';
  }

  String? _relativeAge(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    try {
      final dt = DateTime.parse(iso).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
      if (diff.inHours < 24) return '${diff.inHours} hr ago';
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return null;
    }
  }

  CameraPosition get _initialCamera {
    final selected = _selectedLocation;
    if (selected != null) {
      return CameraPosition(target: _posOf(selected), zoom: _focusZoom);
    }
    if (_liveLocations.isNotEmpty) {
      return CameraPosition(target: _posOf(_liveLocations.values.first), zoom: 13);
    }
    return const CameraPosition(target: _defaultCenter, zoom: 5);
  }

  // ─── Staff filter ───────────────────────────────────────────────────────

  String _selectedName() {
    final id = _selectedId;
    if (id == null) return 'All Staff';
    return _staff.where((s) => s.id == id).firstOrNull?.name ??
        _liveLocations[id]?['name']?.toString() ??
        'Staff';
  }

  Future<void> _openStaffFilter() async {
    // Staff with a location first, then the rest alphabetically.
    final options = [..._staff];
    for (final l in _liveLocations.values) {
      final id = l['staffId']?.toString() ?? '';
      if (id.isNotEmpty && !options.any((s) => s.id == id)) {
        options.add(_StaffOption(id, l['name']?.toString() ?? 'Staff', l['photoUrl']?.toString()));
      }
    }
    options.sort((a, b) {
      final la = _liveLocations.containsKey(a.id) ? 0 : 1;
      final lb = _liveLocations.containsKey(b.id) ? 0 : 1;
      return la != lb ? la - lb : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.dark2,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SheetHandle(),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Show on map',
                  style: TextStyle(color: AppColors.white, fontSize: 17, fontWeight: FontWeight.w700)),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              children: [
                _filterRow(
                  ctx,
                  value: '',
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.brand.withValues(alpha: 0.18),
                    child: const Icon(Icons.groups_rounded, color: AppColors.brand, size: 20),
                  ),
                  title: 'All Staff',
                  subtitle: '${_liveLocations.length} on map · $_liveCount live',
                  statusColor: null,
                  selected: _selectedId == null,
                ),
                for (final s in options) _staffFilterRow(ctx, s),
              ],
            ),
          ),
        ]),
      ),
    );
    if (picked != null) _select(picked.isEmpty ? null : picked);
  }

  Widget _staffFilterRow(BuildContext ctx, _StaffOption s) {
    final loc = _liveLocations[s.id];
    final status = loc?['trackingStatus']?.toString();
    return _filterRow(
      ctx,
      value: s.id,
      leading: LeaveAvatar(name: s.name, photoUrl: s.photoUrl, size: 36),
      title: s.name,
      subtitle: loc == null ? 'Location unavailable' : _snippetFor(loc),
      statusColor: status == null ? null : _statusColor(status),
      selected: _selectedId == s.id,
      dimmed: loc == null,
    );
  }

  Widget _filterRow(
    BuildContext ctx, {
    required String value,
    required Widget leading,
    required String title,
    required String subtitle,
    required Color? statusColor,
    required bool selected,
    bool dimmed = false,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.pop(ctx, value),
      child: Opacity(
        opacity: dimmed ? 0.55 : 1,
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.brand.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? AppColors.brand.withValues(alpha: 0.5) : Colors.transparent),
          ),
          child: Row(children: [
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                const SizedBox(height: 2),
                Row(children: [
                  if (statusColor != null) ...[
                    Container(width: 7, height: 7, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                  ] else if (dimmed) ...[
                    const Icon(Icons.location_off_outlined, size: 13, color: AppColors.muted),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.silver, fontSize: 12)),
                  ),
                ]),
              ]),
            ),
            if (selected) const Icon(Icons.check_circle_rounded, color: AppColors.brand, size: 20),
          ]),
        ),
      ),
    );
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final hasAccess =
        ref.read(ownerControllerProvider.notifier).hasFeature('liveMap');
    final total = _liveLocations.length;
    final badgeLabel = total == 0
        ? 'No one on map'
        : (_liveCount == total ? '$total live' : '$_liveCount live · ${total - _liveCount} other');
    final badgeColor = _liveCount > 0
        ? AppColors.green
        : (total > 0 ? AppColors.yellow : AppColors.muted);
    final selected = _selectedLocation;

    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
          title: Row(children: [
            const Text('Live Map'),
            const SizedBox(width: 8),
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  badgeLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: badgeColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ]),
          actions: [
            IconButton(
                icon: const Icon(Icons.refresh_rounded),
                onPressed: _loadInitial),
            if (_selectedId == null && _liveLocations.isNotEmpty)
              IconButton(
                  icon: const Icon(Icons.fit_screen_outlined),
                  onPressed: _fitToMarkers),
          ]),
      body: PlanGate(
        hasAccess: hasAccess,
        requiredPlan: 'Pro',
        child: Stack(children: [
          if (_showMap)
            GoogleMap(
              key: const ValueKey('owner-live-map'),
              onMapCreated: (c) {
                _mapCtrl = c;
                if (_selectedId != null) {
                  _focusSelected();
                } else {
                  _fitToMarkers();
                }
              },
              initialCameraPosition: _initialCamera,
              markers: _markers,
              padding: EdgeInsets.only(top: 64, bottom: _selectedId != null ? 120 : 56),
              myLocationEnabled: false,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: true,
              mapToolbarEnabled: false,
            )
          else
            const ColoredBox(color: AppColors.dark, child: SizedBox.expand()),
          Positioned(top: 12, left: 12, right: 12, child: _filterBar()),
          if (_selectedId != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: selected != null ? _selectedCard(selected) : _unavailableCard(),
            )
          else if (_liveLocations.isEmpty)
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: _messageCard(
                Icons.location_off_outlined,
                'No staff locations yet. Staff appear here when they check in, or briefly after they sign in with location enabled.',
              ),
            ),
        ]),
      ),
    );
  }

  Widget _filterBar() {
    final isAll = _selectedId == null;
    return Row(children: [
      Flexible(
        child: Material(
          color: AppColors.dark2.withValues(alpha: 0.96),
          elevation: 4,
          shadowColor: Colors.black54,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: _openStaffFilter,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: isAll ? AppColors.border : AppColors.brand),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(isAll ? Icons.groups_rounded : Icons.person_pin_circle_outlined,
                    color: AppColors.brand, size: 20),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(_selectedName(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.silver),
              ]),
            ),
          ),
        ),
      ),
      if (!isAll) ...[
        const SizedBox(width: 8),
        Material(
          color: AppColors.dark2.withValues(alpha: 0.96),
          elevation: 4,
          shadowColor: Colors.black54,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: () => _select(null),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.close_rounded, color: AppColors.silver, size: 18),
                SizedBox(width: 4),
                Text('All Staff', style: TextStyle(color: AppColors.light, fontWeight: FontWeight.w600, fontSize: 13)),
              ]),
            ),
          ),
        ),
      ],
    ]);
  }

  Widget _selectedCard(Map<String, dynamic> l) {
    final status = l['trackingStatus']?.toString() ?? 'live';
    final color = _statusColor(status);
    final id = l['staffId']?.toString();
    final option = _staff.where((s) => s.id == id).firstOrNull;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.dark2.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(children: [
        LeaveAvatar(name: _displayName(l), photoUrl: option?.photoUrl ?? l['photoUrl']?.toString(), size: 42),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_displayName(l),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 3),
            Row(children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(_snippetFor(l),
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.silver, fontSize: 12)),
              ),
            ]),
          ]),
        ),
        IconButton(
          tooltip: 'Center on map',
          onPressed: () {
            _pendingFocus = true;
            _focusSelected();
          },
          icon: const Icon(Icons.my_location_rounded, color: AppColors.brand),
        ),
      ]),
    );
  }

  Widget _unavailableCard() => _messageCard(
        Icons.location_off_outlined,
        "${_selectedName()}'s location is unavailable right now. The map will zoom to them as soon as "
        'their app shares a location (when they check in, or sign in with location enabled).',
        trailing: TextButton(
          onPressed: () => _select(null),
          child: const Text('All Staff', style: TextStyle(color: AppColors.brand, fontWeight: FontWeight.w700)),
        ),
      );

  Widget _messageCard(IconData icon, String text, {Widget? trailing}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.dark2.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          Icon(icon, color: AppColors.muted, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: const TextStyle(color: AppColors.silver, fontSize: 13, height: 1.4)),
          ),
          if (trailing != null) trailing,
        ]),
      );
}
