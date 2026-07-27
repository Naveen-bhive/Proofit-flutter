import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';

import 'auth_storage.dart';

typedef FcmTokenHandler = Future<void> Function(String token);

const _badgeChannel = MethodChannel('com.bhive.proofit/badge');

Future<bool> _shouldShowPush(RemoteMessage message) async {
  final targetUserId = message.data['userId'];
  if (targetUserId == null || targetUserId.isEmpty) return true;
  final user = await AuthStorage.getUser();
  if (user == null || user.id.isEmpty) return false;
  return user.id == targetUserId;
}

DarwinNotificationDetails _iosDetails(RemoteMessage message) {
  final badge = int.tryParse(message.data['badge'] ?? '');
  return DarwinNotificationDetails(badgeNumber: badge);
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  if (!await _shouldShowPush(message)) return;

  final n = message.notification;
  final plugin = FlutterLocalNotificationsPlugin();
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosSettings = DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
  );
  await plugin.initialize(const InitializationSettings(android: androidSettings, iOS: iosSettings));
  const androidDetails = AndroidNotificationDetails(
    'proofit_channel', 'ProofIt Notifications',
    importance: Importance.high, priority: Priority.high,
  );
  await plugin.show(
    DateTime.now().millisecondsSinceEpoch ~/ 1000,
    n?.title ?? message.data['title'] ?? 'ProofIt',
    n?.body ?? message.data['body'] ?? '',
    NotificationDetails(android: androidDetails, iOS: _iosDetails(message)),
    payload: message.data['type'],
  );
}

class NotificationService {
  static FirebaseMessaging? get _fcm =>
      Firebase.apps.isEmpty ? null : FirebaseMessaging.instance;
  static final _local = FlutterLocalNotificationsPlugin();
  static FcmTokenHandler? _onTokenRefresh;
  static GoRouter? _router;
  static Map<String, dynamic>? _pendingTapData;

  static Future<void> init({FcmTokenHandler? onTokenRefresh}) async {
    _onTokenRefresh = onTokenRefresh;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    // Don't let the plugin fire its own OS permission prompt at init time — the
    // app requests permission deliberately later via requestPermission(), and a
    // second/earlier prompt here would either double-ask or jump the gun on timing.
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _local.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
      onDidReceiveNotificationResponse: (response) {
        final type = response.payload;
        if (type != null && type.isNotEmpty) _handleTap({'type': type});
      },
    );

    const channel = AndroidNotificationChannel(
      'proofit_channel', 'ProofIt Notifications',
      importance: Importance.high,
    );
    await _local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    if (_fcm == null) return;

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    FirebaseMessaging.onMessage.listen((message) async {
      if (!await _shouldShowPush(message)) return;
      final n = message.notification;
      showLocalNotification(
        title: n?.title ?? message.data['title'] ?? 'ProofIt',
        body:  n?.body  ?? message.data['body']  ?? '',
        payload: message.data['type'],
        badge: int.tryParse(message.data['badge'] ?? ''),
      );
    });

    // Tapped while backgrounded.
    FirebaseMessaging.onMessageOpenedApp.listen((message) => _handleTap(message.data));

    // Tapped from a terminated state (cold start).
    final initialMessage = await _fcm!.getInitialMessage();
    if (initialMessage != null) {
      _pendingTapData = initialMessage.data;
    }

    _fcm!.onTokenRefresh.listen((token) async {
      if (_onTokenRefresh != null) await _onTokenRefresh!(token);
    });
  }

  /// Call once the router exists (after first frame) so a cold-start tap can
  /// still navigate, then keep using [router] for any tap that follows.
  static void attachRouter(GoRouter router) {
    _router = router;
    final pending = _pendingTapData;
    if (pending != null) {
      _pendingTapData = null;
      _handleTap(pending);
    }
  }

  static void _handleTap(Map<String, dynamic> data) {
    final router = _router;
    if (router == null) {
      _pendingTapData = data;
      return;
    }
    unawaited(_routeForTap(data).then(router.go));
  }

  static Future<String> _routeForTap(Map<String, dynamic> data) async {
    final user = await AuthStorage.getUser();
    final isStaff = user?.role == 'staff';
    final reportId = data['reportId'] as String?;
    final type = data['type'] as String?;

    if (reportId != null && reportId.isNotEmpty) {
      if (type == 'draft_reminder' && isStaff) return '/staff/draft/$reportId';
      return isStaff ? '/staff/report/$reportId' : '/owner/report/$reportId';
    }
    return isStaff ? '/staff/notifications' : '/owner/notifications';
  }

  static Future<void> requestPermission() async {
    final fcm = _fcm;
    if (fcm == null) return;
    await fcm.requestPermission(alert: true, badge: true, sound: true);
    // iOS: firebase_messaging's request above already covers UNUserNotificationCenter
    // permission, but the local-notifications plugin was told not to ask for its own
    // (see init()) — nothing further to do here for that plugin.
  }

  static Future<String?> getToken() async {
    final fcm = _fcm;
    if (fcm == null) return null;
    return fcm.getToken();
  }

  static Future<void> showLocalNotification({
    required String title,
    required String body,
    String? payload,
    int? badge,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'proofit_channel', 'ProofIt Notifications',
      importance: Importance.high, priority: Priority.high,
    );
    final iosDetails = DarwinNotificationDetails(badgeNumber: badge);
    await _local.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title, body,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: payload,
    );
  }

  /// Zeroes the native app-icon badge. No-op on Android (launcher badges there
  /// are derived from active notifications, not a manually-set counter).
  static Future<void> clearBadge() async {
    if (!Platform.isIOS) return;
    try {
      await _badgeChannel.invokeMethod('clearBadge');
    } catch (_) {}
  }
}
