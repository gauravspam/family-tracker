import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../utils/frosted_toast.dart';

/// Handles Firebase Cloud Messaging for the admin app.
///
/// Shows local notifications for geofence alerts in both foreground and
/// background (via a dedicated Android notification channel).
class FcmService {
  FcmService._();

  static final _messaging = FirebaseMessaging.instance;
  static final _localNotifications = FlutterLocalNotificationsPlugin();
  static String? _currentToken;
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static const _channelId = 'geofence_alerts';
  static const _channelName = 'Geofence Alerts';
  static const _channelDesc = 'When a family member enters or exits a geofence';

  /// Must be called once before any other Firebase usage.
  static Future<void> init() async {
    await Firebase.initializeApp();

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _localNotifications.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Create the Android notification channel
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDesc,
            importance: Importance.high,
            playSound: true,
            enableVibration: true,
          ),
        );

    // Request permission (iOS; no-op on Android)
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    _currentToken = await _messaging.getToken();

    _messaging.onTokenRefresh.listen((token) {
      _currentToken = token;
    });

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle background tapped notifications (app opens from terminated state)
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);
  }

  /// Current FCM token, or null if not yet ready.
  static String? get token => _currentToken;

  static void _handleForegroundMessage(RemoteMessage message) {
    final data = message.data;
    final title = data['title'] ?? 'Geofence Alert';
    final body = data['body'] ?? '';
    final isEnter = data['eventType'] == 'geofenceEnter';

    _showLocalNotification(title: title, body: body, isEnter: isEnter);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final nav = navigatorKey.currentState;
      if (nav == null) return;
      showGeofenceToast(
        navigator: nav,
        isEnter: data['eventType'] == 'geofenceEnter',
        geoLabel: data['geofenceName'] ?? 'Geofence',
        deviceName: data['deviceName'] ?? body,
      );
    });
  }

  static void _showLocalNotification({
    required String title,
    required String body,
    bool isEnter = false,
  }) {
    _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
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

  static void _onNotificationTap(NotificationResponse response) {
    // Bring the app to foreground / navigate to home
    // The navigatorKey is already set on MaterialApp, so the app resumes.
  }

  static void _handleNotificationTap(RemoteMessage message) {
    // App was opened by tapping a notification — nav is handled by the key.
  }
}
