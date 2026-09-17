import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/api_service.dart';
import 'app_update_service.dart';

/// Native "Rate ProofIt" popup (Google Play In-App Review / iOS
/// SKStoreReviewController) — the same system dialog shown in the Play
/// Store screenshots, not a custom UI.
///
/// Auto-prompts once, at a moment that looks like success (report submitted,
/// checked in), and never again after that — the OS itself also throttles
/// how often it will actually show the dialog, but we don't rely on that.
class ReviewService {
  static const _storage = FlutterSecureStorage();
  static const _promptedKey     = 'review_prompted_v1';
  static const _successCountKey = 'review_success_count';
  static const _firstSeenKey    = 'review_first_seen_at';

  // Ask after this many "successful action" moments...
  static const _successThreshold = 2;
  // ...but not before the app has been in use for a little while.
  static const _minUsageDelay = Duration(minutes: 3);

  /// Call once, early in app startup. Only ever records the first time.
  static Future<void> recordFirstSeen() async {
    try {
      final existing = await _storage.read(key: _firstSeenKey);
      if (existing == null) {
        await _storage.write(
            key: _firstSeenKey, value: DateTime.now().toIso8601String());
      }
    } catch (_) {}
  }

  /// Call after something that feels like a "win" for the user — a
  /// submitted report, a check-in. Fire-and-forget; never throws.
  static Future<void> maybePromptAfterSuccess() async {
    try {
      if (await _storage.read(key: _promptedKey) == '1') return;

      final countRaw = await _storage.read(key: _successCountKey);
      final count = (int.tryParse(countRaw ?? '0') ?? 0) + 1;
      await _storage.write(key: _successCountKey, value: '$count');
      if (count < _successThreshold) return;

      final firstSeenRaw = await _storage.read(key: _firstSeenKey);
      final firstSeen =
          firstSeenRaw != null ? DateTime.tryParse(firstSeenRaw) : null;
      if (firstSeen != null &&
          DateTime.now().difference(firstSeen) < _minUsageDelay) {
        return;
      }

      final review = InAppReview.instance;
      if (!await review.isAvailable()) return;

      // Mark prompted before requesting — the OS dialog can't tell us
      // whether the user actually rated, so "shown once" is our contract.
      await _storage.write(key: _promptedKey, value: '1');
      await review.requestReview();
    } catch (e) {
      debugPrint('ReviewService.maybePromptAfterSuccess failed: $e');
    }
  }

  /// User-initiated "Rate ProofIt" from Settings. Always tries to take the
  /// user somewhere useful, even if the auto-prompt already fired once.
  static Future<void> requestManualReview(ApiService api) async {
    try {
      final review = InAppReview.instance;
      if (await review.isAvailable()) {
        await review.requestReview();
      } else {
        final config = await AppUpdateService.fetchConfig(api);
        final url = config?.storeUrl;
        if (url != null && url.isNotEmpty) {
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        } else {
          await review.openStoreListing();
        }
      }
      await _storage.write(key: _promptedKey, value: '1');
    } catch (e) {
      debugPrint('ReviewService.requestManualReview failed: $e');
    }
  }
}
