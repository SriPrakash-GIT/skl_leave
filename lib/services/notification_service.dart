import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:git_leave/utils/global_variables.dart';

// Top-level handler for background messages — must be top-level, not inside a class
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('Background message: ${message.messageId}');
}

class NotificationService {
  static final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  static const _channelId = 'leave_channel';
  static const _channelName = 'Leave Notifications';
  static const _channelDesc = 'Leave request and approval notifications';

  static Future<void> init() async {
    // Register background handler FIRST — before anything else
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Request permission (iOS + Android 13+)
    await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Local notifications channel (Android)
    const androidChannel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.high,
    );

    // FIX 1: Missing '<' before AndroidFlutterLocalNotificationsPlugin
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);

    // Init local notifications plugin
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    // v18+ uses named parameter `settings:`
    await _local.initialize(settings: initSettings);

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    debugPrint('Notification tapped: ${message.data}');
  });

   final initialMessage = await _fcm.getInitialMessage();
  if (initialMessage != null) {
    debugPrint('App opened from terminated via notification: ${initialMessage.data}');
  }

    // Foreground message handler
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notification = message.notification;
      if (notification != null) {
        // v18+ uses named parameters: id:, title:, body:, notificationDetails:
        _local.show(
          id: notification.hashCode,
          title: notification.title,
          body: notification.body,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              _channelId,
              _channelName,
              channelDescription: _channelDesc,
              importance: Importance.high,
              priority: Priority.high,
              icon: '@mipmap/ic_launcher',
            ),
            iOS: DarwinNotificationDetails(),
          ),
        );
      }
    });
  }

  /// Fetch FCM token and cache it into the global variable
  static Future<void> initFcmToken() async {
    fcmToken = await _fcm.getToken(); // String? = String? — no ?? needed
    debugPrint('FCM Token: $fcmToken');

    // Keep global token fresh if FCM rotates it
    _fcm.onTokenRefresh.listen((newToken) {
      fcmToken = newToken;
    });
  }

  /// Call after employee OR admin login — saves token to their Firestore doc
  static Future<void> saveTokenForUser(String idcardno) async {
    // FIX 2: was `final fcmToken = await _fcm.getToken()` then checking
    // undefined `token`. Now uses the global fcmToken directly.
    if (fcmToken == null || fcmToken!.isEmpty) return;

    await FirebaseFirestore.instance
        .collection('employees')
        .doc(idcardno)
        .update({
      'fcmToken': fcmToken,
      'tokenUpdatedAt': FieldValue.serverTimestamp(),
    });

    debugPrint('FCM token saved for: $idcardno');

    // FIX 3: Moved onTokenRefresh out of saveTokenForUser — it belongs in
    // initFcmToken so it isn't re-registered on every login call.
  }

  /// Convenience alias — admin is in the same employees collection
  static Future<void> saveAdminToken(String adminIdcardno) async {
    await saveTokenForUser(adminIdcardno);
  }
}