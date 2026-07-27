import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
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
  static final _picker     = ImagePicker();
  static final _deviceInfo = DeviceInfoPlugin();

  static Future<bool> requestCameraPermission(BuildContext context) async {
    final status = await Permission.camera.request();
    if (status.isGranted) return true;
    if (status.isPermanentlyDenied && context.mounted) {
      await _showSettingsDialog(context, 'Camera Access Required',
        'ProofIt needs camera access.\n\nGo to Settings → ProofIt → Camera.');
    }
    return false;
  }

  static Future<bool> requestStoragePermission(BuildContext context) async {
    PermissionStatus status;
    if (Platform.isAndroid) {
      final info = await _deviceInfo.androidInfo;
      status = info.version.sdkInt >= 33
        ? await Permission.photos.request()
        : await Permission.storage.request();
    } else {
      status = await Permission.photos.request();
    }
    if (status.isGranted || status.isLimited) return true;
    if (status.isPermanentlyDenied && context.mounted) {
      await _showSettingsDialog(context, 'Photo Library Access Required',
        'ProofIt needs photo library access.\n\nGo to Settings → ProofIt → Photos.');
    }
    return false;
  }

  // ── Take photo → stamp → return file + capture metadata ─────────────
  // Upload to Drive is handled by submit flow
  static Future<CapturedPhoto?> takePhoto(BuildContext context, {String? staffName, String? jobTitle}) async {
    final hasCam = await requestCameraPermission(context);
    if (!hasCam) return null;
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.camera, imageQuality: 85,
        maxWidth: 1920, maxHeight: 1920,
        preferredCameraDevice: CameraDevice.rear);
      if (picked == null) return null;

      final file   = File(picked.path);
      final sizeMB = await getFileSizeMB(file);
      if (sizeMB > 10) {
        if (context.mounted) _showError(context, 'Photo too large (${sizeMB.toStringAsFixed(1)}MB). Max 10MB.');
        return null;
      }

      // Get GPS at capture moment
      final capturedAt = DateTime.now();
      double? lat, lng;
      String? address;
      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5));
        lat     = pos.latitude;
        lng     = pos.longitude;
        address = await LocationService.getAddressFromCoords(lat, lng);
      } catch (_) {}

      // Stamp timestamp + GPS into photo
      final stamped = await PhotoStampService.stampPhoto(
        originalFile: file,
        capturedAt:   capturedAt,
        latitude:     lat,
        longitude:    lng,
        address:      address,
        staffName:    staffName,
        jobTitle:     jobTitle,
      );

      return CapturedPhoto(
        file: stamped,
        capturedAt: capturedAt,
        latitude: lat,
        longitude: lng,
        address: address,
      );
    } catch (e) {
      debugPrint('Camera error: $e');
      if (context.mounted) _showError(context, 'Camera error. Please try again.');
      return null;
    }
  }

  static Future<CapturedPhoto?> pickFromGallery(BuildContext context, {String? staffName, String? jobTitle}) async {
    if (!await requestStoragePermission(context)) return null;
    try {
      final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1920, maxHeight: 1920);
      if (picked == null) return null;

      final file = File(picked.path);
      final capturedAt = DateTime.now();
      double? lat, lng;
      String? address;
      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5));
        lat = pos.latitude;
        lng = pos.longitude;
        address = await LocationService.getAddressFromCoords(lat, lng);
      } catch (_) {}

      final stamped = await PhotoStampService.stampPhoto(
        originalFile: file,
        capturedAt: capturedAt,
        latitude: lat,
        longitude: lng,
        address: address,
        staffName: staffName,
        jobTitle: jobTitle,
      );

      return CapturedPhoto(
        file: stamped,
        capturedAt: capturedAt,
        latitude: lat,
        longitude: lng,
        address: address,
      );
    } catch (_) { return null; }
  }

  static Future<double> getFileSizeMB(File file) async {
    return (await file.length()) / (1024 * 1024);
  }

  static void _showError(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: const Color(0xFFEF4444)));
  }

  static Future<void> _showSettingsDialog(BuildContext context, String title, String message) async {
    await showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      content: Text(message, style: const TextStyle(color: Color(0xFFCCCCCC), height: 1.5)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Color(0xFF999999)))),
        TextButton(onPressed: () async { Navigator.pop(context); await openAppSettings(); },
          child: const Text('Open Settings', style: TextStyle(color: Color(0xFFFF4D00), fontWeight: FontWeight.w700))),
      ]));
  }
}