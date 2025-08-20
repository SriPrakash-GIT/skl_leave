import 'dart:convert';
import 'dart:io';
import 'package:flutter_udid/flutter_udid.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'globalVariable.dart';
import 'home.dart';
import 'login.dart';
import 'notificationtoken.dart';
import 'newLocation.dart';

late String? deviceId = "";
String? deviceType;

late var chk = false;
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await PushNotification.init();

  await getDeviceID();

  getNotificationToken(fcmToken, deviceId);

  final prefs = await SharedPreferences.getInstance();
  // await prefs.setString("deviceToken", fcmToken);
  String? savedEmployeeId = prefs.getString('employeeId');
  String? savedPassword = prefs.getString('password');
  // String? deviceNewId = prefs.getString('DeviceIdToken');

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
  String cutTableApi = "$ipAddress/api/userdevice";
  SharedPreferences prefs = await SharedPreferences.getInstance();
  try {
    final response = await http.post(Uri.parse(cutTableApi),
        headers: <String, String>{
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: jsonEncode({"deviceToken": fcmToken, "deviceID": deviceId}));

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = json.decode(response.body);
      // await prefs.setString('DeviceIdToken', fcmToken);
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

Future<void> getDeviceID() async {
  try {
    deviceId = await FlutterUdid.udid;
    deviceType = Platform.isAndroid
        ? 'ANDROID'
        : Platform.isIOS
            ? 'IOS'
            : 'Unknown';
    print("Device UDID: $deviceId");
    print("Device deviceType: $deviceType");
  } catch (e) {
    print("Failed to get UDID: $e");
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Skl - HR App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: chk ? HomeScreen() : const LoginPage(),
      // home: ReachedWorkPage(),
      debugShowCheckedModeBanner: false,
      routes: {
        '/home': (context) => HomeScreen(),
        '/newLocation': (context) => ReachedWorkPage(),
      },
    );
  }
}
