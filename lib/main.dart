import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_udid/flutter_udid.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart' as permissionHandler;
import 'firebase_options.dart';
import 'globalVariable.dart';
import 'home.dart';
import 'login.dart';
import 'notificationtoken.dart';
import 'newLocation.dart';
import 'auto_location_monitor.dart';

late String? deviceId = "";
String? deviceType;
late var chk = false;

Future<void> main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();

    print("await 1");
    // Initialize Firebase
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    print("await 2");
    // Initialize notifications (needed for showing permission reminders)
    await AutoLocationMonitor.initNotifications();

    print("await 3");

    try {
      await PushNotification.init();
    }catch(e){
      print("Notification Error: $e");
    }
    print("await 4");
    await getDeviceID();

    print("await 5");
    final prefs = await SharedPreferences.getInstance();

    // Load server settings
    String savedIp = prefs.getString('server_ip') ?? '';
    String savedPort = prefs.getString('server_port') ?? '';
    String savedVersion = prefs.getString('server_version') ?? '';

    if (savedIp.isNotEmpty && savedPort.isNotEmpty && savedVersion.isNotEmpty) {
      ip = savedIp;
      port = savedPort;
      version = savedVersion;
      ipAddress = 'http://$ip:$port/$version';
      print("Loaded server IP: $ipAddress");
    }

    print("await 6");
    await getNotificationToken(fcmToken, deviceId);

    // Load saved login credentials
    String? savedEmployeeId = prefs.getString('employeeId');
    String? savedPassword = prefs.getString('password');

    if (savedEmployeeId != null && savedPassword != null) {
      globalIDcardNo = savedEmployeeId;
      chk = true;

      // 🔐 Handle location permission for 24/7 monitoring
      if (Platform.isAndroid) {
        print("await 7");
        await _handleAndroidLocationPermission();
      } else {
        print("await 8");
        // iOS handling
        await _handleIOSLocationPermission();
      }
    }

    print("check location 1");
    // Initialize notifications and location monitor
    await AutoLocationMonitor.initialize();
    print("check location 2");

    // Restore monitoring state if it was active
    await AutoLocationMonitor.restoreMonitoringState();
    print("check location 4");

    runApp(const MyApp());
  } catch (e) {
    print("$e  main error");
  }
}

/// Handle Android location permission with "Allow all the time" option
Future<void> _handleAndroidLocationPermission() async {
  try {
    // First check if we already have "always" permission
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.always) {
      // Already have permission, start monitoring
      print("✅ Already have 'always' permission");
      // await _startMonitoringIfNeeded();
      return;
    }

    // Request permission - this shows dialog for "While using the app"
    print("📱 Requesting location permission...");
    permission = await Geolocator.requestPermission();

    if (permission == LocationPermission.denied) {
      // User denied permission
      print("❌ User denied location permission");
      await AutoLocationMonitor.showNotification(
        '📍 Location Permission Required',
        'Please grant location permission in settings for 24/7 monitoring.',
      );
      return;
    }

    if (permission == LocationPermission.deniedForever) {
      // User permanently denied
      print("❌ User permanently denied location permission");
      await AutoLocationMonitor.showNotification(
        '📍 Location Permission Required',
        'Please enable location permission in app settings for 24/7 monitoring.',
      );

      // Optionally open app settings
      if (await _shouldOpenSettings()) {
        await Geolocator.openAppSettings();
      }
      return;
    }

    // Now we have at least "while in use" permission
    // Ask user to enable "Allow all the time" for background monitoring
    print("📱 Requesting 'Allow all the time' permission...");

    // Show a dialog explaining why we need "always" permission
    bool shouldOpenSettings = await _showBackgroundPermissionDialog();

    if (shouldOpenSettings) {
      // Open system settings where user can select "Allow all the time"
      await Geolocator.openAppSettings();

      // After returning from settings, check again
      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.always) {
        print("✅ User granted 'always' permission");
        // await _startMonitoringIfNeeded();
      } else {
        print("⚠️ User still doesn't have 'always' permission");
        await AutoLocationMonitor.showNotification(
          '⚠️ Limited Monitoring',
          'For 24/7 monitoring, please enable "Allow all the time" in location settings.',
        );
      }
    }
  } catch (e) {
    print("Error handling permission: $e");
  }
}

/// Handle iOS location permission
Future<void> _handleIOSLocationPermission() async {
  LocationPermission permission = await Geolocator.checkPermission();

  if (permission == LocationPermission.always) {
    // Already have permission
    // await _startMonitoringIfNeeded();
    return;
  }

  // Request permission - on iOS this will show dialog with options
  permission = await Geolocator.requestPermission();

  if (permission == LocationPermission.always) {
    // await _startMonitoringIfNeeded();
  } else if (permission == LocationPermission.whileInUse) {
    // User only granted while in use
    print("⚠️ User granted only 'while in use' permission");
    await AutoLocationMonitor.showNotification(
      '⚠️ Limited Monitoring',
      'For background monitoring, please select "Always" in location settings.',
    );

    // Open settings
    if (await _shouldOpenSettings()) {
      await Geolocator.openAppSettings();
    }
  } else {
    // Denied
    await AutoLocationMonitor.showNotification(
      '📍 Location Permission Required',
      'Please enable location permission in settings for 24/7 monitoring.',
    );
  }
}

/// Show dialog explaining why we need "always" permission
Future<bool> _showBackgroundPermissionDialog() async {
  // Since we're in main, we need to use a navigator key or store context
  // For simplicity, we'll return true and rely on the notification
  // In a real app, you'd want to show a proper dialog in the first screen

  await AutoLocationMonitor.showNotification(
    '🔔 Allow All the Time Required',
    'For 24/7 monitoring, please select "Allow all the time" in location settings.',
  );

  return true; // Assume user will open settings
}

/// Check if we should open settings based on user preference
Future<bool> _shouldOpenSettings() async {
  final prefs = await SharedPreferences.getInstance();
  final lastPrompt = prefs.getInt('last_permission_prompt') ?? 0;
  final now = DateTime.now().millisecondsSinceEpoch;

  // Don't prompt more than once every 24 hours
  if (now - lastPrompt < 24 * 60 * 60 * 1000) {
    return false;
  }

  await prefs.setInt('last_permission_prompt', now);
  return true;
}

/// Start monitoring if conditions are met
Future<void> _startMonitoringIfNeeded() async {
  final prefs = await SharedPreferences.getInstance();
  final hasFixedLocation = prefs.getString('fixed_location') != null;

  if (hasFixedLocation) {
    Future.microtask(() async {
      print("main: Starting 24/7 monitoring automatically...");
      await AutoLocationMonitor.startMonitoring();
    });
  } else {
    print("main: No fixed location yet, monitoring will start after location is set");
    // Show notification that they need to set work location
    await AutoLocationMonitor.showNotification(
      '📍 Set Work Location',
      'Please set your work location to start 24/7 monitoring.',
    );
  }
}

// Keep existing functions...
Future<void> getNotificationToken(fcmToken, deviceId) async {
  String cutTableApi = "$ipAddress/api/userdevice";

  try {
    final response = await http.post(
      Uri.parse(cutTableApi),
      headers: {
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonEncode({
        "deviceToken": fcmToken,
        "deviceID": deviceId
      }),
    );

    if (response.statusCode == 200) {
      print("✅ Device token sent successfully");
    }
  } catch (e) {
    print("❌ Token API Error: $e");
  }
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
    print("Device Type: $deviceType");
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
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
        ),
        useMaterial3: true,
      ),
      home: chk ? HomeScreen() : const LoginPage(),
      debugShowCheckedModeBanner: false,
      routes: {
        '/home': (context) => HomeScreen(),
        '/newLocation': (context) => ReachedWorkPage(),
      },
    );
  }
}