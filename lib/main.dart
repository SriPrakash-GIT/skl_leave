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
import 'package:workmanager/workmanager.dart';
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


@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    print("🔔 WorkManager task executed: $task at ${DateTime.now()}");

    try {
      // Ensure Flutter bindings are initialized
      WidgetsFlutterBinding.ensureInitialized();

      // Initialize Firebase
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      // CRITICAL: Initialize location services in background isolate
      // FIXED: Added await here
      if (!await Geolocator.isLocationServiceEnabled()) {
        print("⚠️ Location services are disabled");
      }

      // Check if we can access location in background
      LocationPermission permission = await Geolocator.checkPermission();
      print("📱 Background location permission: $permission");

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        print("❌ Cannot access location in background - insufficient permissions");
        return Future.value(true);
      }

      // Initialize notifications
      final FlutterLocalNotificationsPlugin notifications =
      FlutterLocalNotificationsPlugin();

      const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');

      final DarwinInitializationSettings iosSettings =
      DarwinInitializationSettings();

      final InitializationSettings initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await notifications.initialize(initSettings);

      // Create notification channel
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'auto_monitor_channel',
        'Auto Location Monitor',
        description: 'Channel for location monitoring notifications',
        importance: Importance.high,
        enableVibration: true,
        playSound: true,
      );

      final androidImpl = notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      if (androidImpl != null) {
        await androidImpl.createNotificationChannel(channel);
        print("✅ Notification channel created");
      }

      // Assign notifications instance
      AutoLocationMonitor.setNotificationsInstance(notifications);

      // Load SharedPreferences
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
        print("Background loaded server: $ipAddress");
      }

      // Load employee ID
      final idCard = prefs.getString('employeeId');
      if (idCard == null) {
        print("❌ No employee ID found");
        return Future.value(true);
      }
      globalIDcardNo = idCard;

      // Check if monitoring is active
      final isActive = prefs.getBool('monitoring_active') ?? false;
      if (!isActive) {
        print("📴 Monitoring not active");
        return Future.value(true);
      }

      print("✅ Background isolate ready");

      // Execute the task
      if (task == 'checkLocationAndNotify') {
        print("📍 Executing checkLocationAndNotify");
        await AutoLocationMonitor.checkLocationAndNotify();
        print("✅ Completed checkLocationAndNotify");
      }
    } catch (e, stackTrace) {
      print("❌ Error in WorkManager task: $e");
      print("Stack trace: $stackTrace");
    }

    return Future.value(true);
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );


  await Workmanager().initialize(
    callbackDispatcher,
    isInDebugMode: false, // Set to false in production
  );

  print("🚀 WorkManager initialized");

  // Initialize notifications
  await AutoLocationMonitor.initNotifications();

  // Initialize other services
  await PushNotification.init();
  await getDeviceID();

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

  await getNotificationToken(fcmToken, deviceId);

  // Load saved login credentials
  String? savedEmployeeId = prefs.getString('employeeId');
  String? savedPassword = prefs.getString('password');

  if (savedEmployeeId != null && savedPassword != null) {
    globalIDcardNo = savedEmployeeId;
    chk = true;

    // Restore monitoring if it was active
    bool wasMonitoringActive = prefs.getBool('monitoring_active') ?? false;
    if (wasMonitoringActive) {
      print("🔄 Restoring monitoring service");
      // Re-register the periodic task
      await registerPeriodicTask();
    }
  }

  runApp(const MyApp());
}


// Separate function to register periodic task
Future<void> registerPeriodicTask() async {
  try {
    // Cancel any existing tasks
    await Workmanager().cancelByUniqueName('auto-location-check');

    // Register with correct constraints for Android
    await Workmanager().registerPeriodicTask(
      "auto-location-check",
      "checkLocationAndNotify",
      frequency: const Duration(minutes: 15),
      initialDelay: const Duration(seconds: 30),
      constraints: Constraints(
        networkType: NetworkType.connected, // Need network for API calls
        requiresBatteryNotLow: false,
        requiresCharging: false,
        requiresDeviceIdle: false, // Allow running when device not idle
        requiresStorageNotLow: false,
      ),
      existingWorkPolicy: ExistingWorkPolicy.replace,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(seconds: 10),
    );

    print("✅ WorkManager periodic task registered");

    // For Android, also register a one-time task to verify
    await Workmanager().registerOneOffTask(
      "initial-check",
      "checkLocationAndNotify",
      initialDelay: const Duration(seconds: 5),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );

  } catch (e) {
    print("❌ Failed to register periodic task: $e");
  }
}
// Also add this to handle boot complete
Future<void> initializeAfterBoot() async {
  final prefs = await SharedPreferences.getInstance();
  final wasActive = prefs.getBool('monitoring_active') ?? false;

  if (wasActive) {
    print("🔄 Device rebooted, re-registering WorkManager task");
    await registerPeriodicTask();
  }
}

// ... rest of your functions (getNotificationToken, getDeviceID, MyApp) remain the same

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
