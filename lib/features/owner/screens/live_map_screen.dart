import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/plan_gate.dart';
import '../../../shared/services/socket_service.dart';
import '../controllers/owner_controller.dart';

class LiveMapScreen extends ConsumerStatefulWidget {
  const LiveMapScreen({super.key});
  @override ConsumerState<LiveMapScreen> createState() => _LiveMapScreenState();
}

class _LiveMapScreenState extends ConsumerState<LiveMapScreen> {
  GoogleMapController? _mapCtrl;
  bool _showMap = true;
  final Map<String, Map<String, dynamic>> _liveLocations = {};
  Timer? _fallbackTimer;
  final List<SocketListenerId> _socketIds = [];

  static const _defaultCenter = LatLng(20.5937, 78.9629); // India
  static const _staleThreshold = Duration(minutes: 7);

  static void _ensureTextureMapMode() {
    if (!Platform.isAndroid) return;
    final maps = GoogleMapsFlutterPlatform.instance;
    if (maps is GoogleMapsFlutterAndroid) {
      // Must stay false in release â€” hybrid composition bleeds a grey native layer over other routes.
      maps.useAndroidViewSurface = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _ensureTextureMapMode();
    _loadInitial();
    _setupSocket();
    // REST fallback â€” merge by timestamp so socket updates aren't overwritten.
    _fallbackTimer = Timer.periodic(const Duration(seconds: 10), (_) => _loadInitial());
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
    _fitToMarkers();
  }

  Map<String, dynamic> _normalizeLocation(String id, Map<String, dynamic> data) {
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
          'lastSeen': data['lastSeen'] ?? data['timestamp'] ?? DateTime.now().toIso8601String(),
          'trackingStatus': data['trackingStatus'] ?? 'live',
          'isStale': false,
        });
      });
    }));
    _socketIds.add(SocketService.onStaffCheckIn((data) {
      if (!mounted) return;
      final id = data['staffId']?.toString() ?? '';
      if (id.isEmpty) return;
      final loc = data['location'] is Map ? Map<String, dynamic>.from(data['location'] as Map) : null;
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
      _fitToMarkers();
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

  void _fitToMarkers() {
    if (_mapCtrl == null || _liveLocations.isEmpty) return;

    final points = _liveLocations.values
        .map((l) => LatLng((l['lat'] as num).toDouble(), (l['lng'] as num).toDouble()))
        .toList();
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
      LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng)),
      64,
    ));
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

  int get _liveCount =>
      _liveLocations.values.where((l) => l['trackingStatus'] == 'live').length;
  int get _offlineCount => _liveLocations.length - _liveCount;

  Set<Marker> get _markers => _liveLocations.values.map((l) {
    final id = l['staffId']?.toString() ?? '';
    final status = l['trackingStatus']?.toString() ?? 'live';
    final hue = switch (status) {
      'impaired' => BitmapDescriptor.hueRed,
      'stale'    => BitmapDescriptor.hueYellow,
      _          => BitmapDescriptor.hueOrange,
    };
    return Marker(
      markerId: MarkerId(id),
      position: LatLng((l['lat'] as num).toDouble(), (l['lng'] as num).toDouble()),
      icon: BitmapDescriptor.defaultMarkerWithHue(hue),
      infoWindow: InfoWindow(
        title: l['name']?.toString() ?? 'Staff',
        snippet: _snippetFor(l),
      ),
    );
  }).toSet();

  String _snippetFor(Map<String, dynamic> l) {
    final status = l['trackingStatus']?.toString() ?? 'live';
    final lastSeen = l['lastSeen']?.toString();
    final age = _relativeAge(lastSeen);
    if (status == 'impaired') {
      return age == null
          ? 'Live tracking interrupted'
          : 'Live tracking interrupted Â· last ping $age';
    }
    if (status == 'stale') {
      return age == null ? 'No location signal' : 'No location signal Â· last ping $age';
    }
    return age == null ? 'Live' : 'Live Â· updated $age';
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
    if (_liveLocations.isNotEmpty) {
      final first = _liveLocations.values.first;
      return CameraPosition(
        target: LatLng((first['lat'] as num).toDouble(), (first['lng'] as num).toDouble()),
        zoom: 13,
      );
    }
    return const CameraPosition(target: _defaultCenter, zoom: 5);
  }

  @override
  Widget build(BuildContext context) {
    final hasAccess = ref.read(ownerControllerProvider.notifier).hasFeature('liveMap');
    final badgeLabel = _offlineCount > 0
        ? '$_liveCount live Â· $_offlineCount no signal'
        : '${_liveLocations.length} live';
    final badgeColor = _liveCount > 0
        ? AppColors.green
        : (_liveLocations.isNotEmpty ? AppColors.yellow : AppColors.muted);

    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(title: Row(children: [
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
      ]), actions: [
        IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _loadInitial),
        if (_liveLocations.isNotEmpty)
          IconButton(icon: const Icon(Icons.fit_screen_outlined), onPressed: _fitToMarkers),
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
              _fitToMarkers();
            },
            initialCameraPosition: _initialCamera,
            markers: _markers,
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: true,
            mapToolbarEnabled: false,
          )
          else
            const ColoredBox(color: AppColors.dark, child: SizedBox.expand()),
          if (_liveLocations.isEmpty)
            Positioned(
              left: 16, right: 16, bottom: 24,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.dark2.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Row(children: [
                  Icon(Icons.location_off_outlined, color: AppColors.muted, size: 22),
                  SizedBox(width: 12),
                  Expanded(child: Text(
                    'No staff checked in yet. Staff appear here when they check in and share location.',
                    style: TextStyle(color: AppColors.silver, fontSize: 13, height: 1.4),
                  )),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}
