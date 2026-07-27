import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'auth_storage.dart';

typedef FcmTokenHandler = Future<void> Function(String token);

Future<bool> _shouldShowPush(RemoteMessage message) async {
  final targetUserId = message.data['userId'];
  if (targetUserId == null || targetUserId.isEmpty) return true;
  final user = await AuthStorage.getUser();
  if (user == null || user.id.isEmpty) return false;
  return user.id == targetUserId;
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  if (!await _shouldShowPush(message)) return;

  final n = message.notification;
  final plugin = FlutterLocalNotificationsPlugin();
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  await plugin.initialize(const InitializationSettings(android: androidSettings));
  const androidDetails = AndroidNotificationDetails(
    'proofit_channel', 'ProofIt Notifications',
    importance: Importance.high, priority: Priority.high,
  );
  await plugin.show(
    DateTime.now().millisecondsSinceEpoch ~/ 1000,
    n?.title ?? message.data['title'] ?? 'ProofIt',
    n?.body ?? message.data['body'] ?? '',
    const NotificationDetails(android: androidDetails),
    payload: message.data['type'],
  );
}

class NotificationService {
  static FirebaseMessaging? get _fcm =>
      Firebase.apps.isEmpty ? null : FirebaseMessaging.instance;
  static final _local = FlutterLocalNotificationsPlugin();
  static FcmTokenHandler? _onTokenRefresh;

  static Future<void> init({FcmTokenHandler? onTokenRefresh}) async {
    _onTokenRefresh = onTokenRefresh;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    await _local.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
      onDidReceiveNotificationResponse: (_) {},
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
      );
    });

    _fcm!.onTokenRefresh.listen((token) async {
      if (_onTokenRefresh != null) await _onTokenRefresh!(token);
    });
  }

  static Future<void> requestPermission() async {
    final fcm = _fcm;
    if (fcm == null) return;
    await fcm.requestPermission(alert: true, badge: true, sound: true);
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
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'proofit_channel', 'ProofIt Notifications',
      importance: Importance.high, priority: Priority.high,
    );
    await _local.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title, body,
      const NotificationDetails(android: androidDetails),
      payload: payload,
    );
  }
}
