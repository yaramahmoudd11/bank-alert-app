import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final SupabaseClient _supabase = Supabase.instance.client;

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel =
      AndroidNotificationChannel(
    'bank_alerts_channel',
    'Bank Alerts',
    description: 'Foreground and local alerts for bank security events',
    importance: Importance.max,
    playSound: true,
  );

  static Future<void> initialize() async {
    if (kIsWeb) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      settings: initSettings,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    debugPrint('Notification permission: ${settings.authorizationStatus}');

    await _messaging.subscribeToTopic('test_alerts');
    debugPrint('Subscribed to topic: test_alerts');

    final token = await _messaging.getToken();
    debugPrint('FCM TOKEN: $token');

    if (token != null) {
      await saveToken(token);
    }

    _messaging.onTokenRefresh.listen((String newToken) async {
      debugPrint('FCM TOKEN REFRESHED: $newToken');
      await saveToken(newToken);
      await _messaging.subscribeToTopic('test_alerts');
    });

    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      debugPrint('================ FCM RECEIVED ================');
      debugPrint('Foreground message title: ${message.notification?.title}');
      debugPrint('Foreground message body: ${message.notification?.body}');
      debugPrint('Foreground message data: ${message.data}');
      debugPrint('=============================================');

      await showInstantAlert(
        title: message.notification?.title ??
            message.data['title']?.toString() ??
            'Security Alert',
        body: message.notification?.body ??
            message.data['body']?.toString() ??
            message.data['message']?.toString() ??
            'New alert received',
      );
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('Notification opened app');
      debugPrint('Opened message title: ${message.notification?.title}');
      debugPrint('Opened message body: ${message.notification?.body}');
      debugPrint('Opened message data: ${message.data}');
    });

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('App opened from terminated state by notification');
      debugPrint('Initial message title: ${initialMessage.notification?.title}');
      debugPrint('Initial message body: ${initialMessage.notification?.body}');
      debugPrint('Initial message data: ${initialMessage.data}');
    }
  }

  static Future<void> showInstantAlert({
    required String title,
    required String body,
  }) async {
    await _localNotifications.show(
  id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
  title: title,
  body: body,
  notificationDetails: const NotificationDetails(
    android: AndroidNotificationDetails(
      'bank_alerts_channel',
      'Bank Alerts',
      channelDescription:
          'Foreground and local alerts for bank security events',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      icon: '@mipmap/ic_launcher',
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    ),
  ),
);
  
  }

  static Future<void> saveToken(String token) async {
    try {
      await _supabase.from('device_tokens').upsert(
        {
          'token': token,
          'platform': defaultTargetPlatform.name,
          'updated_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'token',
      );

      debugPrint('Token saved to Supabase successfully');
    } catch (e) {
      debugPrint('Error saving token to Supabase: $e');
    }
  }
}