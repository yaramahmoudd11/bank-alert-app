import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  NotificationService.handleNotificationResponse(response);
}

class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final SupabaseClient _supabase = Supabase.instance.client;

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const String alertActionUrl = 'http://172.20.10.2:5000/alert_action';

  static const String _ignoreActionId = 'IGNORE_SECURITY_ALERT';
  static const String _safetyPayloadPrefix = 'safety_alert:';

  static final Set<String> _completedSafetyAlerts = <String>{};
  static final Set<String> _startedSafetyTimers = <String>{};

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

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

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
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        NotificationService.handleNotificationResponse(response);
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
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
    debugPrint('Firebase projectId: ${Firebase.app().options.projectId}');
    debugPrint('Firebase senderId: ${Firebase.app().options.messagingSenderId}');
    debugPrint('Firebase appId: ${Firebase.app().options.appId}');

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

      final category = message.data['category']?.toString() ?? '';
      final isDoorAlert = category == 'access' || category == 'intrusion';
      final alertId = message.data['alert_id']?.toString() ??
          message.data['id']?.toString() ??
          DateTime.now().millisecondsSinceEpoch.toString();

      await showInstantAlert(
        title: message.notification?.title ??
            message.data['title']?.toString() ??
            'Security Alert',
        body: message.notification?.body ??
            message.data['body']?.toString() ??
            message.data['message']?.toString() ??
            'New alert received',
        enableSafetyActions: isDoorAlert,
        alertId: alertId,
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

  static int _notificationIdFromAlertId(String alertId) {
    return alertId.hashCode & 0x7fffffff;
  }

  static String _payloadForAlertId(String alertId) {
    return '$_safetyPayloadPrefix$alertId';
  }

  static String? _alertIdFromPayload(String? payload) {
    if (payload == null || !payload.startsWith(_safetyPayloadPrefix)) {
      return null;
    }

    return payload.substring(_safetyPayloadPrefix.length);
  }

  static Future<void> handleNotificationResponse(
    NotificationResponse response,
  ) async {
    final alertId = _alertIdFromPayload(response.payload);

    if (alertId == null) return;

    // Any user response means the manager saw/responded to the alert.
    // Ignore sends NO HTTP request. It only cancels the 10-second safety action.
    cancelSafetyAction(alertId);

    if (response.actionId == _ignoreActionId) {
      debugPrint('Notification Ignore clicked for alert $alertId. No request sent.');
      return;
    }

    debugPrint('Notification opened for alert $alertId. Auto alert_action cancelled.');
  }

  static void cancelSafetyAction(String alertId) {
    _completedSafetyAlerts.add(alertId);
  }

  static void startSafetyTimer({
    required String alertId,
    required String reason,
  }) {
    if (_startedSafetyTimers.contains(alertId)) return;

    _startedSafetyTimers.add(alertId);

    Future.delayed(const Duration(seconds: 10), () async {
      if (_completedSafetyAlerts.contains(alertId)) {
        debugPrint('Safety action cancelled for alert $alertId.');
        return;
      }

      _completedSafetyAlerts.add(alertId);

      try {
        await sendPiGetRequest(
          url: alertActionUrl,
          reason: reason,
        );

        debugPrint('No response for 10 seconds. alert_action sent for alert $alertId.');
      } catch (e) {
        debugPrint('Auto alert_action failed for alert $alertId: $e');
      }
    });
  }

  static Future<void> sendPiGetRequest({
    required String url,
    required String reason,
  }) async {
    debugPrint('Sending request to Pi: $url | Reason: $reason');

    final response = await http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 5));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Raspberry Pi error ${response.statusCode}: ${response.body}',
      );
    }
  }

  static Future<void> showInstantAlert({
    required String title,
    required String body,
    bool enableSafetyActions = false,
    String? alertId,
  }) async {
    final safetyAlertId =
        alertId ?? DateTime.now().millisecondsSinceEpoch.toString();

    final notificationId = enableSafetyActions
        ? _notificationIdFromAlertId(safetyAlertId)
        : DateTime.now().millisecondsSinceEpoch ~/ 1000;

    await _localNotifications.show(
      id: notificationId,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'bank_alerts_channel',
          'Bank Alerts',
          channelDescription:
              'Foreground and local alerts for bank security events',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          icon: '@mipmap/ic_launcher',
          actions: enableSafetyActions
              ? const <AndroidNotificationAction>[
                  AndroidNotificationAction(
                    _ignoreActionId,
                    'Ignore',
                    showsUserInterface: false,
                    cancelNotification: true,
                  ),
                ]
              : null,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: enableSafetyActions ? _payloadForAlertId(safetyAlertId) : null,
    );

    if (enableSafetyActions) {
      startSafetyTimer(
        alertId: safetyAlertId,
        reason: 'notification_no_manager_response_alert_$safetyAlertId',
      );
    }
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
