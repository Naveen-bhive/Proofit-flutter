import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import 'deep_link_utils.dart';

/// Resolves invite deep links on cold start and forwards warm-start links to GoRouter.
class DeepLinkService {
  DeepLinkService._();

  static final _appLinks = AppLinks();
  static StreamSubscription<Uri>? _subscription;

  static void listen(GoRouter router) {
    _subscription?.cancel();
    _subscription = _appLinks.uriLinkStream.listen(
      (uri) => _openInvite(router, uri),
      onError: (Object e) => debugPrint('Deep link stream error: $e'),
    );
  }

  static void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }

  /// Best-effort read for cold start. Retries briefly because Android can
  /// deliver the intent slightly after the first frame.
  static Future<String?> resolveInviteToken({
    Duration timeout = const Duration(milliseconds: 1200),
  }) async {
    final deadline = DateTime.now().add(timeout);
    String? token;

    while (DateTime.now().isBefore(deadline)) {
      token = await _readInviteTokenOnce();
      if (token != null) return token;
      await Future.delayed(const Duration(milliseconds: 120));
    }

    return token;
  }

  static Future<String?> _readInviteTokenOnce() async {
    try {
      final initial = await _appLinks.getInitialLink()
          .timeout(const Duration(milliseconds: 400), onTimeout: () => null);
      final fromInitial = DeepLinkUtils.inviteTokenFromUri(initial);
      if (fromInitial != null) return fromInitial;
    } catch (_) {}

    try {
      final latest = await _appLinks.getLatestLink()
          .timeout(const Duration(milliseconds: 400), onTimeout: () => null);
      return DeepLinkUtils.inviteTokenFromUri(latest);
    } catch (_) {
      return null;
    }
  }

  static void _openInvite(GoRouter router, Uri uri) {
    final token = DeepLinkUtils.inviteTokenFromUri(uri);
    if (token == null) return;
    router.go('/invite/$token');
  }
}
