import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'core/router/app_router.dart';
import 'core/network/api_service.dart';
import 'core/theme/app_theme.dart';
import 'shared/services/notification_service.dart';
import 'shared/services/auth_storage.dart';
import 'shared/services/deep_link_service.dart';
import 'shared/services/revenue_cat_service.dart';
import 'shared/services/socket_service.dart';
import 'shared/widgets/error_boundary.dart';
import 'features/auth/controllers/auth_controller.dart';
import 'features/owner/controllers/owner_controller.dart';
import 'features/staff/controllers/staff_controller.dart';

void main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  AppErrorHandler.init();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  try {
    await Firebase.initializeApp();
  } catch (e, st) {
    debugPrint('Firebase.initializeApp failed: $e\n$st');
  }
  await RevenueCatService.configure();
  if (Platform.isAndroid) {
    final maps = GoogleMapsFlutterPlatform.instance;
    if (maps is GoogleMapsFlutterAndroid) {
      // Texture mode avoids the native map surface bleeding over other tabs in release builds.
      maps.useAndroidViewSurface = false;
    }
  }
  runApp(const ProviderScope(child: ErrorBoundary(child: ProofItApp())));
}

class ProofItApp extends ConsumerStatefulWidget {
  const ProofItApp({super.key});
  @override
  ConsumerState<ProofItApp> createState() => _ProofItAppState();
}

class _ProofItAppState extends ConsumerState<ProofItApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initNotifications();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final router = ref.read(appRouterProvider);
      DeepLinkService.listen(router);
      NotificationService.attachRouter(router);
    });
  }

  Future<void> _initNotifications() async {
    await NotificationService.init(onTokenRefresh: (token) async {
      try {
        if (!await AuthStorage.isLoggedIn()) return;
        await ref.read(apiServiceProvider).post('/notifications/fcm-token', data: {
          'token': token,
          'platform': Platform.isIOS ? 'ios' : 'android',
        });
      } catch (_) {}
    });
    await NotificationService.clearBadge();
    ref.read(authControllerProvider.notifier).syncFcmToken();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    DeepLinkService.dispose();
    SocketService.disconnect();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      try {
        final isLoggedIn = await AuthStorage.isLoggedIn();
        if (!isLoggedIn) return;
        await NotificationService.clearBadge();
        await ref.read(authControllerProvider.notifier).syncFcmToken();
        final org = await ref.read(authControllerProvider.notifier).syncOrgFromServer();
        final user = await AuthStorage.getUser();
        if (org != null && user != null) {
          if (user.role == 'owner') {
            ref.read(ownerControllerProvider.notifier).applyOrgName(org.name);
          } else if (user.role == 'staff') {
            ref.read(staffControllerProvider.notifier).applyOrgName(org.name);
          }
        }
      } catch (_) {}
    } else if (state == AppLifecycleState.detached) {
      SocketService.disconnect();
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'ProofIt',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: router,
    );
  }
}