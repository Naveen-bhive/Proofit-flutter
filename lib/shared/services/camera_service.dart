import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'photo_stamp_service.dart';
import 'location_service.dart';

class CapturedPhoto {
  final File file;
  final DateTime capturedAt;
  final double? latitude;
  final double? longitude;
  final String? address;

  const CapturedPhoto({
    required this.file,
    required this.capturedAt,
    this.latitude,
    this.longitude,
    this.address,
  });
}

class CameraService {
  static final _picker = ImagePicker();

  static Future<bool> requestCameraPermission(BuildContext context) async {
    final status = await Permission.camera.request();
    if (status.isGranted) return true;
    if (status.isPermanentlyDenied && context.mounted) {
      await _showSettingsDialog(context, 'Camera Access Required',
          'ProofIt needs camera access.\n\nGo to Settings → ProofIt → Camera.');
    }
    return false;
  }

  static const _maxPhotoMB = 10.0;

  /// Opens the camera (one shot) or the gallery (multi-select up to [limit])
  /// and returns the raw files straight away — no GPS or stamping yet — so
  /// the caller can show a spinner immediately. Pair with [stamp].
  static Future<List<File>> pickRaw(BuildContext context,
      {required bool fromCamera, int limit = 1}) async {
    try {
      final List<XFile> picked;
      if (fromCamera) {
        if (!await requestCameraPermission(context)) return [];
        final shot = await _picker.pickImage(
            source: ImageSource.camera,
            imageQuality: 85,
            maxWidth: 1920,
            maxHeight: 1920,
            preferredCameraDevice: CameraDevice.rear);
        picked = [if (shot != null) shot];
      } else if (limit <= 1) {
        final one = await _picker.pickImage(
            source: ImageSource.gallery,
            imageQuality: 85,
            maxWidth: 1920,
            maxHeight: 1920);
        picked = [if (one != null) one];
      } else {
        picked = await _picker.pickMultiImage(
            imageQuality: 85, maxWidth: 1920, maxHeight: 1920, limit: limit);
      }

      final files = <File>[];
      for (final x in picked.take(limit)) {
        final file = File(x.path);
        final sizeMB = await getFileSizeMB(file);
        if (sizeMB > _maxPhotoMB) {
          if (context.mounted) {
            _showError(context,
                'Photo too large (${sizeMB.toStringAsFixed(1)}MB). Max 10MB.');
          }
          continue;
        }
        files.add(file);
      }
      return files;
    } catch (e) {
      debugPrint('Photo pick error: $e');
      if (context.mounted) {
        _showError(context,
            fromCamera ? 'Camera error. Please try again.' : 'Could not open gallery.');
      }
      return [];
    }
  }

  /// Records (camera) or picks (gallery) one video. Videos aren't stamped —
  /// capture time and GPS travel as metadata. [maxBytes] is only a hint to
  /// spare a pointless upload; the server enforces the real limits.
  static Future<CapturedPhoto?> pickVideo(BuildContext context,
      {required bool fromCamera,
      Duration maxDuration = const Duration(minutes: 3),
      int? maxBytes}) async {
    try {
      if (fromCamera) {
        final granted = await requestCameraPermission(context);
        if (!granted || !context.mounted) return null;
      }
      final picked = await _picker.pickVideo(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        maxDuration: maxDuration,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (picked == null) return null;
      final file = File(picked.path);
      final sizeMB = await getFileSizeMB(file);
      if (maxBytes != null && sizeMB * 1024 * 1024 > maxBytes) {
        if (context.mounted) {
          _showError(context,
              'Video too large (${sizeMB.toStringAsFixed(0)}MB). Max ${(maxBytes / (1024 * 1024)).round()}MB — record a shorter clip.');
        }
        return null;
      }
      final fix = await _currentFix();
      return CapturedPhoto(
        file: file,
        capturedAt: DateTime.now(),
        latitude: fix?.lat,
        longitude: fix?.lng,
        address: fix?.address,
      );
    } catch (e) {
      debugPrint('Video pick error: $e');
      if (context.mounted) {
        _showError(context,
            fromCamera ? 'Could not record video. Please try again.' : 'Could not open videos.');
      }
      return null;
    }
  }

  /// Stamps date/time/GPS onto [raw] (off the UI isolate) and returns the
  /// stamped file with its capture metadata.
  static Future<CapturedPhoto> stamp(File raw,
      {String? staffName, String? jobTitle}) async {
    final capturedAt = DateTime.now();
    final fix = await _currentFix();
    final stamped = await PhotoStampService.stampPhoto(
      originalFile: raw,
      capturedAt: capturedAt,
      latitude: fix?.lat,
      longitude: fix?.lng,
      address: fix?.address,
      staffName: staffName,
      jobTitle: jobTitle,
    );
    return CapturedPhoto(
      file: stamped,
      capturedAt: capturedAt,
      latitude: fix?.lat,
      longitude: fix?.lng,
      address: fix?.address,
    );
  }

  // ── GPS fix cache ───────────────────────────────────────────────────
  // A fresh high-accuracy fix + reverse geocode costs several seconds; reuse
  // one for photos taken close together, and share a single in-flight lookup
  // when several gallery photos are stamped at once.
  static ({double lat, double lng, String? address, DateTime at})? _fix;
  static Future<({double lat, double lng, String? address, DateTime at})?>?
      _fixInFlight;
  static const _fixMaxAge = Duration(seconds: 60);

  static Future<({double lat, double lng, String? address, DateTime at})?>
      _currentFix() {
    final cached = _fix;
    if (cached != null && DateTime.now().difference(cached.at) < _fixMaxAge) {
      return Future.value(cached);
    }
    return _fixInFlight ??= _lookupFix().whenComplete(() => _fixInFlight = null);
  }

  static Future<({double lat, double lng, String? address, DateTime at})?>
      _lookupFix() async {
    try {
      Position? pos = await Geolocator.getLastKnownPosition();
      final stale = pos == null ||
          DateTime.now().difference(pos.timestamp) > const Duration(minutes: 2);
      if (stale) {
        pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 5));
      }
      final p = pos;
      final prev = _fix;
      // Skip the reverse-geocode round trip when we haven't moved.
      final sameSpot = prev != null &&
          prev.address != null &&
          Geolocator.distanceBetween(prev.lat, prev.lng, p.latitude, p.longitude) < 50;
      final address = sameSpot
          ? prev.address
          : await LocationService.getAddressFromCoords(p.latitude, p.longitude);
      return _fix = (
        lat: p.latitude,
        lng: p.longitude,
        address: address,
        at: DateTime.now(),
      );
    } catch (_) {
      return _fix;
    }
  }

  // ── Take photo → stamp → return file + capture metadata ─────────────
  // Upload to Drive is handled by submit flow
  static Future<CapturedPhoto?> takePhoto(BuildContext context,
      {String? staffName, String? jobTitle}) async {
    final raw = await pickRaw(context, fromCamera: true);
    if (raw.isEmpty) return null;
    return stamp(raw.first, staffName: staffName, jobTitle: jobTitle);
  }

  static Future<CapturedPhoto?> pickFromGallery(BuildContext context,
      {String? staffName, String? jobTitle}) async {
    final raw = await pickRaw(context, fromCamera: false);
    if (raw.isEmpty) return null;
    return stamp(raw.first, staffName: staffName, jobTitle: jobTitle);
  }

  static Future<double> getFileSizeMB(File file) async {
    return (await file.length()) / (1024 * 1024);
  }

  static void _showError(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: const Color(0xFFEF4444)));
  }

  static Future<void> _showSettingsDialog(
      BuildContext context, String title, String message) async {
    await showDialog(
        context: context,
        builder: (_) => AlertDialog(
                backgroundColor: const Color(0xFF1A1A1A),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                title: Text(title,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700)),
                content: Text(message,
                    style:
                        const TextStyle(color: Color(0xFFCCCCCC), height: 1.5)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel',
                          style: TextStyle(color: Color(0xFF999999)))),
                  TextButton(
                      onPressed: () async {
                        Navigator.pop(context);
                        await openAppSettings();
                      },
                      child: const Text('Open Settings',
                          style: TextStyle(
                              color: Color(0xFF2F80ED),
                              fontWeight: FontWeight.w700))),
                ]));
  }
}
