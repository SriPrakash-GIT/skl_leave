import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:io';

late final String? fcmToken;

class PushNotification {
  static final FirebaseMessaging firebaseMessaging = FirebaseMessaging.instance;

  static Future<void> init() async {
    // Request permission first
    NotificationSettings settings = await firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('🔔 Push notification permission granted');

      // iOS-specific: Wait for APNs token
      if (Platform.isIOS) {
        fcmToken = await firebaseMessaging.getAPNSToken();
        if (fcmToken == null) {
          print("⚠️ APNs token not yet available.");
        } else {
          print("✅ APNs token: $fcmToken");
        }
      }

      // Get the FCM token
      fcmToken = await firebaseMessaging.getToken();
      print("✅ FCM Token: $fcmToken");

      // Listen to token refresh
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        print("🔁 FCM Token refreshed: $newToken");
        // You can update your backend with the new token here
      });
    } else {
      print('❌ Push notification permission denied');
    }
  }
}
