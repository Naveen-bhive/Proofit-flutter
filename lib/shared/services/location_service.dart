import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/constants/app_colors.dart';

class LocationService {
  static StreamSubscription<Position>? _positionStream;
  static Function(Position)? onLocationUpdate;

  static Future<bool> hasAlwaysPermission() async {
    if (Platform.isAndroid) {
      return Permission.locationAlways.isGranted;
    }
    final perm = await Geolocator.checkPermission();
    return perm == LocationPermission.always;
  }

  static Future<bool> hasForegroundPermission() async {
    if (Platform.isAndroid) {
      final whenInUse = await Permission.locationWhenInUse.status;
      final always = await Permission.locationAlways.status;
      return whenInUse.isGranted || always.isGranted;
    }
    final perm = await Geolocator.checkPermission();
    return perm == LocationPermission.whileInUse || perm == LocationPermission.always;
  }

  /// True when GPS / location services are enabled on the device.
  static Future<bool> isLocationServiceOn() => Geolocator.isLocationServiceEnabled();

  /// Precise (fine) location - required for usable live map pins.
  /// On unsupported platforms, falls back to having foreground permission.
  static Future<bool> hasPreciseLocation() async {
    try {
      final status = await Geolocator.getLocationAccuracy();
      if (status == LocationAccuracyStatus.precise) return true;
      if (status == LocationAccuracyStatus.reduced) return false;
    } catch (_) {}
    // Older OS / unknown - if we have permission, treat as OK.
    return hasForegroundPermission();
  }

  /// Guide staff to enable Precise location (Android 12+ / iOS reduced accuracy).
  static Future<bool> ensurePreciseLocation(BuildContext context) async {
    if (await hasPreciseLocation()) return true;
    if (!context.mounted) return false;

    final proceed = await _showDialog(
      context,
      title: 'Turn on Precise location',
      message:
          'ProofIt needs Precise location so your owner can see your exact position on the live map.\n\n'
          'On the next screen, choose Precise (not Approximate).',
      primaryLabel: 'Open Settings',
      secondaryLabel: 'Cancel',
      onPrimary: openAppSettings,
    );
    if (proceed != true) return false;

    // Re-check after returning from settings (lifecycle resume also re-checks).
    await Future<void>.delayed(const Duration(milliseconds: 500));
    return hasPreciseLocation();
  }

  /// Foreground-only request (for one-shot GPS / camera stamp).
  static Future<bool> requestPermission() async {
    final serviceOn = await Geolocator.isLocationServiceEnabled();
    if (!serviceOn) return false;

    if (Platform.isAndroid) {
      var whenInUse = await Permission.locationWhenInUse.status;
      if (whenInUse.isDenied) {
        whenInUse = await Permission.locationWhenInUse.request();
      }
      if (whenInUse.isPermanentlyDenied) return false;
      final always = await Permission.locationAlways.status;
      return whenInUse.isGranted || always.isGranted;
    }

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    return perm == LocationPermission.whileInUse || perm == LocationPermission.always;
  }

  /// Full background-location flow with a guide dialog.
  ///
  /// Android 11+ never shows "Allow all the time" on the first prompt.
  /// Flow:
  /// 1) Request "While using the app"
  /// 2) Show an in-app guide telling the staff to pick "Allow all the time"
  /// 3) Request [Permission.locationAlways] (system dialog / settings)
  /// 4) If still denied, open App Settings with clear steps
  static Future<bool> ensureAlwaysLocationPermission(BuildContext context) async {
    final serviceOn = await Geolocator.isLocationServiceEnabled();
    if (!serviceOn) {
      if (context.mounted) {
        await _showDialog(
          context,
          title: 'Turn on location',
          message:
              'Location services are off on this phone. Turn on GPS / Location, then try again.',
          primaryLabel: 'Open settings',
          onPrimary: () async {
            await Geolocator.openLocationSettings();
          },
        );
      }
      return false;
    }

    // Step 1 - foreground ("While using the app")
    var whenInUse = await Permission.locationWhenInUse.status;
    if (!whenInUse.isGranted && !await Permission.locationAlways.isGranted) {
      if (context.mounted) {
        final proceed = await _showDialog(
          context,
          title: 'Location access needed',
          message:
              'ProofIt needs your location while you are checked in so your manager can see you on the live map.\n\n'
              'On the next screen, choose "While using the app" (or "Allow").',
          primaryLabel: 'Continue',
          secondaryLabel: 'Not now',
        );
        if (proceed != true || !context.mounted) return false;
      }
      whenInUse = await Permission.locationWhenInUse.request();
    }

    if (await Permission.locationAlways.isGranted) return true;

    if (!whenInUse.isGranted && !await Permission.locationWhenInUse.isGranted) {
      if (context.mounted) {
        await _showDialog(
          context,
          title: 'Location permission required',
          message:
              'Without location permission you cannot check in.\n\n'
              'Open Settings -> Permissions -> Location, then allow location for ProofIt.',
          primaryLabel: 'Open Settings',
          onPrimary: openAppSettings,
          secondaryLabel: 'Cancel',
        );
      }
      return false;
    }

    // Step 2 - guide for "Allow all the time"
    if (!context.mounted) return false;
    final continueAlways = await _showAlwaysGuideDialog(context);
    if (continueAlways != true || !context.mounted) return false;

    // Step 3 - background request (this is when "Allow all the time" appears)
    var always = await Permission.locationAlways.request();
    if (always.isGranted) return true;

    // Some OEMs send the user to Settings instead of returning granted immediately.
    // Re-check after a short pause when returning from settings-style UI.
    always = await Permission.locationAlways.status;
    if (always.isGranted) return true;

    if (!context.mounted) return false;
    final openSettings = await _showDialog(
      context,
      title: 'Select "Allow all the time"',
      message:
          'Background tracking is required while you are checked in.\n\n'
          'Please do this now:\n'
          '1. Tap Open Settings\n'
          '2. Tap Permissions (or Location)\n'
          '3. Tap Location\n'
          '4. Choose "Allow all the time"\n\n'
          'Then return to ProofIt and try again.',
      primaryLabel: 'Open Settings',
      secondaryLabel: 'Cancel',
    );
    if (openSettings == true) {
      await openAppSettings();
      // Give the user time; re-check when they come back.
      always = await Permission.locationAlways.status;
      if (always.isGranted) return true;
      // Status may still be stale until app resumes - caller can re-check.
      await Future.delayed(const Duration(milliseconds: 400));
      always = await Permission.locationAlways.status;
    }
    return always.isGranted;
  }

  /// Kept for call sites that don't have a [BuildContext].
  /// Prefer [ensureAlwaysLocationPermission] from UI screens.
  static Future<bool> requestBackgroundPermission() async {
    final whenInUse = await Permission.locationWhenInUse.status;
    if (!whenInUse.isGranted && !await Permission.locationAlways.isGranted) {
      final result = await Permission.locationWhenInUse.request();
      if (!result.isGranted) return false;
    }
    if (await Permission.locationAlways.isGranted) return true;
    final always = await Permission.locationAlways.request();
    return always.isGranted;
  }

  static Future<Position?> getCurrentPosition() async {
    final hasPermission = await requestPermission();
    if (!hasPermission) return null;
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
    } catch (_) {
      return await Geolocator.getLastKnownPosition();
    }
  }

  static void startLocationStream({
    required Function(Position) onUpdate,
    int intervalSeconds = 30,
  }) {
    _positionStream?.cancel();
    onLocationUpdate = onUpdate;

    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    _positionStream = Geolocator.getPositionStream(locationSettings: settings).listen(
      (position) => onLocationUpdate?.call(position),
      onError: (err) => debugPrint('Location stream error: $err'),
    );
  }

  static void stopLocationStream() {
    _positionStream?.cancel();
    _positionStream = null;
    onLocationUpdate = null;
  }

  static Future<String> getAddressFromCoords(double lat, double lng) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isEmpty) return '$lat, $lng';
      final p = placemarks.first;
      return [p.street, p.locality, p.administrativeArea]
          .where((s) => s != null && s.isNotEmpty)
          .join(', ');
    } catch (_) {
      return '$lat, $lng';
    }
  }

  static Future<bool> isMockLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition();
      return pos.isMocked;
    } catch (_) {
      return false;
    }
  }

  static Future<bool?> _showAlwaysGuideDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.dark2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Allow location all the time',
          style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 18),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Your manager needs your live location even when ProofIt is in the background or the screen is locked.',
                style: TextStyle(color: AppColors.silver, height: 1.45, fontSize: 14),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.brand.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.brand.withValues(alpha: 0.35)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'On the next screen, choose:',
                      style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    SizedBox(height: 10),
                    Text(
                      'Allow all the time',
                      style: TextStyle(color: AppColors.brand, fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                    SizedBox(height: 10),
                    Text(
                      'Do not choose "Only this time" or "While using the app" for this step - live tracking will not work in the background.',
                      style: TextStyle(color: AppColors.silver, height: 1.4, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not now', style: TextStyle(color: AppColors.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'I understand - Continue',
              style: TextStyle(color: AppColors.brand, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  static Future<bool?> _showDialog(
    BuildContext context, {
    required String title,
    required String message,
    required String primaryLabel,
    String? secondaryLabel,
    Future<void> Function()? onPrimary,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.dark2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
        content: Text(message, style: const TextStyle(color: AppColors.silver, height: 1.5)),
        actions: [
          if (secondaryLabel != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(secondaryLabel, style: const TextStyle(color: AppColors.muted)),
            ),
          TextButton(
            onPressed: () async {
              if (onPrimary != null) await onPrimary();
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
            child: Text(
              primaryLabel,
              style: const TextStyle(color: AppColors.brand, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
