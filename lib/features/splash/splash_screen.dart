import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import '../../core/constants/app_colors.dart';
import '../../core/network/api_service.dart';
import '../../shared/services/app_update_service.dart';
import '../../shared/services/auth_storage.dart';
import '../../shared/services/deep_link_service.dart';
import '../../shared/services/notification_service.dart';
import '../../shared/services/review_service.dart';
import '../auth/controllers/auth_controller.dart';
import '../staff/controllers/staff_controller.dart';
import 'force_update_screen.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});
  @override ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  static const _minDisplay = Duration(milliseconds: 450);
  static const _maxWait   = Duration(seconds: 2);

  AppUpdateConfig? _forceUpdate;

  @override
  void initState() {
    super.initState();
    unawaited(ReviewService.recordFirstSeen());
    _navigate();
  }

  Future<void> _finishAndGo(String route) async {
    if (!mounted) {
      FlutterNativeSplash.remove();
      return;
    }
    try {
      context.go(route);
    } catch (_) {
      // Fall through — still remove the native splash.
    } finally {
      FlutterNativeSplash.remove();
    }
    unawaited(NotificationService.requestPermission());
  }

  Future<void> _navigate() async {
    final started = DateTime.now();
    try {
      final config = await AppUpdateService.fetchConfig(ref.read(apiServiceProvider))
          .timeout(const Duration(seconds: 3), onTimeout: () => null);
      if (config != null && await AppUpdateService.isForceUpdateRequired(config)) {
        final elapsed = DateTime.now().difference(started);
        if (elapsed < _minDisplay) await Future.delayed(_minDisplay - elapsed);
        if (!mounted) {
          FlutterNativeSplash.remove();
          return;
        }
        setState(() => _forceUpdate = config);
        FlutterNativeSplash.remove();
        return;
      }

      final inviteToken = await DeepLinkService.resolveInviteToken()
          .timeout(const Duration(seconds: 2), onTimeout: () => null);

      String? role;
      if (inviteToken == null || inviteToken.isEmpty) {
        role = await ref.read(authControllerProvider.notifier).restoreSession()
            .timeout(_maxWait, onTimeout: () => null);
      }

      final elapsed = DateTime.now().difference(started);
      if (elapsed < _minDisplay) {
        await Future.delayed(_minDisplay - elapsed);
      }

      if (!mounted) {
        FlutterNativeSplash.remove();
        return;
      }

      if (inviteToken != null && inviteToken.isNotEmpty) {
        await _finishAndGo('/invite/$inviteToken');
        return;
      }

      if (role == 'owner') {
        final user = await AuthStorage.getUser();
        if (user != null && user.orgId.isEmpty) {
          await _finishAndGo('/owner-setup');
          return;
        }
        await _finishAndGo('/owner');
        return;
      }
      if (role == 'staff') {
        ref.invalidate(staffControllerProvider);
        await _finishAndGo('/staff');
        return;
      }
      await _finishAndGo('/signin');
    } catch (e, st) {
      debugPrint('Splash navigation failed: $e\n$st');
      FlutterNativeSplash.remove();
      if (mounted) {
        try {
          context.go('/signin');
        } catch (_) {}
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_forceUpdate != null) {
      return ForceUpdateScreen(config: _forceUpdate!);
    }
    return Scaffold(
      backgroundColor: AppColors.dark,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/splash_logo.png', width: 120, height: 120),
            const SizedBox(height: 28),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                color: AppColors.brand,
                strokeWidth: 2.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
