import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'location_service.dart';

/// [accuracy] is the fix's horizontal accuracy in metres and [recordedAt] when
/// it was taken, so the server can ignore stale or out-of-order readings.
typedef LocationCallback = Future<void> Function(
    double latitude, double longitude,
    {double? accuracy, DateTime? recordedAt});

/// Keeps sending GPS updates while staff is checked in.
/// Android: continues in the background (foreground service + "Allow all the time").
/// iOS: foreground-only — updates pause once the app is backgrounded, since the app
/// no longer declares the "location" background mode (App Store Guideline 2.5.4).
class LiveLocationTracker {
  static StreamSubscription<Position>? _subscription;
  static Timer? _heartbeatTimer;
  static LocationCallback? _onLocation;
  static DateTime? _lastSent;
  static double? _lastLat;
  static double? _lastLng;
  static double? _lastAccuracy;
  static DateTime? _lastFixAt;
  static const _minSendInterval = Duration(seconds: 20);
  static const _heartbeatInterval = Duration(seconds: 20);

  /// Older fixes are refreshed before a heartbeat instead of being resent.
  static const _maxFixAge = Duration(minutes: 2);

  static bool get isRunning => _subscription != null;

  /// Starts tracking. Prefer calling [LocationService.ensureAlwaysLocationPermission]
  /// from a screen with a [BuildContext] before check-in so "Allow all the time"
  /// is granted with a guiding dialog.
  /// Returns `true` when the position stream is running.
  static Future<bool> start({required LocationCallback onLocation}) async {
    _onLocation = onLocation;
    if (_subscription != null) return true;

    final serviceOn = await Geolocator.isLocationServiceEnabled();
    if (!serviceOn) {
      debugPrint('LiveLocationTracker: location services off');
      return false;
    }

    final hasForeground = await LocationService.requestPermission();
    if (!hasForeground) {
      debugPrint('LiveLocationTracker: foreground location denied');
      return false;
    }

    // Android 10+ — second-step background permission when UI already granted it.
    final always = await LocationService.hasAlwaysPermission();
    if (!always) {
      final granted = await LocationService.requestBackgroundPermission();
      if (!granted) {
        debugPrint(
            'LiveLocationTracker: background location not granted — stream may pause in background');
      }
    }

    _subscription =
        Geolocator.getPositionStream(locationSettings: _settings).listen(
      _handlePosition,
      onError: (err) => debugPrint('LiveLocationTracker error: $err'),
    );

    _heartbeatTimer?.cancel();
    _heartbeatTimer =
        Timer.periodic(_heartbeatInterval, (_) => unawaited(_heartbeatTick()));
    unawaited(_heartbeatTick());

    debugPrint(
        'LiveLocationTracker: started (always=${await LocationService.hasAlwaysPermission()})');
    return true;
  }

  static void stop() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _subscription?.cancel();
    _subscription = null;
    _onLocation = null;
    _lastSent = null;
    _lastLat = null;
    _lastLng = null;
    _lastAccuracy = null;
    _lastFixAt = null;
    debugPrint('LiveLocationTracker: stopped');
  }

  static LocationSettings get _settings {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        // 0 = emit on [intervalDuration] even when staff is stationary (live ping, not movement).
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 20),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'ProofIt is sharing your live location',
          notificationText:
              'Your owner can see you on the live map while you are checked in',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }
    if (Platform.isIOS) {
      // No "location" UIBackgroundMode on iOS (App Store Guideline 2.5.4) — updates
      // are foreground-only and iOS pauses/stops them once the app is backgrounded.
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        pauseLocationUpdatesAutomatically: true,
        showBackgroundLocationIndicator: false,
        activityType: ActivityType.other,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0,
    );
  }

  /// Sends last known coords on a timer so "live" means active tracking, not movement.
  static Future<void> _heartbeatTick() async {
    if (_onLocation == null) return;
    try {
      final fresh = _lastFixAt != null &&
          DateTime.now().difference(_lastFixAt!) < _maxFixAge;
      if (_lastLat != null && _lastLng != null && fresh) {
        // Same fix and timestamp — keeps the live map fresh without
        // pretending it is a new reading.
        await _sendPosition(_lastLat!, _lastLng!, _lastAccuracy, _lastFixAt);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      await _handlePosition(pos);
    } catch (e) {
      debugPrint('LiveLocationTracker heartbeat: $e');
    }
  }

  static Future<void> _handlePosition(Position position) async {
    _lastLat = position.latitude;
    _lastLng = position.longitude;
    _lastAccuracy = position.accuracy;
    _lastFixAt = position.timestamp.toUtc();
    await _sendPosition(
        position.latitude, position.longitude, _lastAccuracy, _lastFixAt);
  }

  static Future<void> _sendPosition(double latitude, double longitude,
      double? accuracy, DateTime? recordedAt) async {
    final now = DateTime.now();
    if (_lastSent != null && now.difference(_lastSent!) < _minSendInterval)
      return;
    _lastSent = now;

    final callback = _onLocation;
    if (callback == null) return;
    try {
      await callback(latitude, longitude,
          accuracy: accuracy, recordedAt: recordedAt);
    } catch (e) {
      debugPrint('LiveLocationTracker send failed: $e');
    }
  }
}
