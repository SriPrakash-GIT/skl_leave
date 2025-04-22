import 'package:firebase_messaging/firebase_messaging.dart';

late String? fcmToken = "";

class PushNotification {
  static final firebaseMessaging = FirebaseMessaging.instance;
  static Future init() async {
    await firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    fcmToken = await firebaseMessaging.getToken();
    print("FCM Token: $fcmToken");
  }
}
