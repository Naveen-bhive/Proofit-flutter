import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:in_app_update/in_app_update.dart';

import '../../core/network/api_service.dart';

/// Admin-configured, per-platform update requirements — set from the admin
/// panel's App Update page, no rebuild needed to raise the bar.
class AppUpdateConfig {
  final String minVersion;
  final String latestVersion;
  final String storeUrl;
  final String updateMessage;
  final bool forceUpdateEnabled;
  final bool autoUpdateEnabled;

  const AppUpdateConfig({
    required this.minVersion,
    required this.latestVersion,
    required this.storeUrl,
    required this.updateMessage,
    required this.forceUpdateEnabled,
    this.autoUpdateEnabled = true,
  });

  factory AppUpdateConfig.fromJson(Map<String, dynamic> json) =>
      AppUpdateConfig(
        minVersion: (json['minVersion'] as String?) ?? '1.0.0',
        latestVersion: (json['latestVersion'] as String?) ?? '1.0.0',
        storeUrl: (json['storeUrl'] as String?) ?? '',
        updateMessage: (json['updateMessage'] as String?) ??
            'A new version of ProofIt is available. Please update to continue.',
        forceUpdateEnabled: (json['forceUpdateEnabled'] as bool?) ?? true,
        autoUpdateEnabled: (json['autoUpdateEnabled'] as bool?) ?? true,
      );
}

/// Checks the installed app version against the admin-configured minimum.
/// Fails open on any error (network down, backend unreachable, bad data) —
/// a broken config check must never lock users out of the app.
class AppUpdateService {
  /// Uses Play Core for Android installations distributed through Google Play.
  /// Play requires user consent; flexible updates download in the background.
  static Future<bool> startAndroidUpdate({required bool immediate}) async {
    if (!Platform.isAndroid) return false;
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.installStatus == InstallStatus.downloaded) {
        await InAppUpdate.completeFlexibleUpdate();
        return true;
      }
      if (info.updateAvailability != UpdateAvailability.updateAvailable) {
        return false;
      }
      if (immediate && info.immediateUpdateAllowed) {
        final result = await InAppUpdate.performImmediateUpdate();
        return result == AppUpdateResult.success;
      }
      if (!immediate && info.flexibleUpdateAllowed) {
        final result = await InAppUpdate.startFlexibleUpdate();
        return result == AppUpdateResult.success;
      }
    } catch (e) {
      // Sideloaded and development builds are not eligible for Play Core.
      debugPrint('AppUpdateService.startAndroidUpdate failed: $e');
    }
    return false;
  }

  static Future<AppUpdateConfig?> fetchConfig(ApiService api) async {
    try {
      final platform = Platform.isIOS ? 'ios' : 'android';
      final res = await api.get('/app/config',
          params: {'platform': platform}).timeout(const Duration(seconds: 6));
      final body = res.data;
      if (body is Map && body['success'] == true && body['data'] is Map) {
        return AppUpdateConfig.fromJson(
            Map<String, dynamic>.from(body['data'] as Map));
      }
    } catch (e) {
      debugPrint('AppUpdateService.fetchConfig failed: $e');
    }
    return null;
  }

  /// Returns the installed version string, e.g. "1.0.2".
  static Future<String> currentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  static Future<bool> isForceUpdateRequired(AppUpdateConfig config) async {
    if (!config.forceUpdateEnabled) return false;
    try {
      final current = await currentVersion();
      return _isVersionBelow(current, config.minVersion);
    } catch (e) {
      debugPrint('AppUpdateService.isForceUpdateRequired failed: $e');
      return false;
    }
  }

  /// Numeric, dot-separated version compare (e.g. "1.2.10" > "1.2.9").
  /// Any parse trouble fails open (returns false — not below minimum).
  static bool _isVersionBelow(String current, String min) {
    try {
      final c = current.split('.').map((s) => int.parse(s.trim())).toList();
      final m = min.split('.').map((s) => int.parse(s.trim())).toList();
      final len = c.length > m.length ? c.length : m.length;
      for (var i = 0; i < len; i++) {
        final cv = i < c.length ? c[i] : 0;
        final mv = i < m.length ? m[i] : 0;
        if (cv != mv) return cv < mv;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
