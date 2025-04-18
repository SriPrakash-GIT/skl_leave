import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skl_leave/register.dart';

import 'firebase_options.dart';
import 'globalVariable.dart';
import 'home.dart';
import 'login.dart';
import 'notificationtoken.dart';

late String? deviceId;
late var chk = false;
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await PushNotification.init();

  // Get device ID during initialization
  deviceId = await getDeviceId();
  print('Device ID: $deviceId');
  getNotificationToken(fcmToken, deviceId);

  final prefs = await SharedPreferences.getInstance();
  String? savedEmployeeId = prefs.getString('employeeId');
  String? savedPassword = prefs.getString('password');

  SharedPreferences prefs1 = await SharedPreferences.getInstance();
  await prefs1.setString('server_ip', ip);
  await prefs1.setString('server_port', port);
  await prefs1.setString('server_version', version);
  ipAddress = 'http://$ip:$port/$version';
  if (savedEmployeeId != null && savedPassword != null) {
    globalIDcardNo = savedEmployeeId;
    chk = true;
  }
  runApp(const MyApp());
}

Future<void> getNotificationToken(fcmToken, deviceId) async {
  print(fcmToken +
      "---------------------fcmToken-----------------------------------------------------");
  String cutTableApi = "$ipAddress/api/userdevice";
  try {
    final response = await http.post(Uri.parse(cutTableApi),
        headers: <String, String>{
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: jsonEncode({"deviceToken": fcmToken, "deviceID": deviceId}));

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = json.decode(response.body);
      if (data["status"] == true) {
        print("suceesstoken---------------------------------");
      }
    }
  } catch (e) {
    _showErrorDialog("Connection Error", "Please ReOpen this Page");
    print(e);
  }
}

void _showErrorDialog(String title, String content) {
  var context;
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: <Widget>[
          TextButton(
            child: const Text('OK'),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
        ],
      );
    },
  );
}

Future<String?> getDeviceId() async {
  final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();

  try {
    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.id; // Use androidId instead of id
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      return iosInfo.identifierForVendor;
    }
  } catch (e) {
    print('Error getting device ID: $e');
  }

  return null;
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Skl-LeaveApp',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: chk ? HomeScreen() : const LoginPage(),
      debugShowCheckedModeBanner: false,
      routes: {
        '/home': (context) => HomeScreen(),
        '/RegisterPage': (context) => RegisterPage(),
      },
    );
  }
}
