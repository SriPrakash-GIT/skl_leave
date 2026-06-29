  import 'dart:async';
  import 'dart:convert';
  import 'dart:io';
  import 'package:flutter/material.dart';
  import 'package:flutter/services.dart';
  import 'package:shared_preferences/shared_preferences.dart';
  import 'package:http/http.dart' as http;
  import 'package:flutter_udid/flutter_udid.dart';
  import 'package:firebase_core/firebase_core.dart';
  import 'firebase_options.dart';
  import 'package:git_leave/utils/global_variables.dart';
  import 'package:git_leave/screens/auth/login_screen.dart';
  import 'package:git_leave/screens/home/home_screen.dart';
  import 'package:git_leave/screens/leave/leave_apply_screen.dart';
  import 'package:git_leave/screens/leave/leave_status_screen.dart';
  import 'package:git_leave/screens/admin/admin_leave_screen.dart';
  import 'package:git_leave/screens/admin/admin_preferences_screen.dart';
  import 'package:git_leave/screens/onduty/onduty_report_screen.dart';
  import 'package:git_leave/screens/admin/admin_login_screen.dart';
  import 'package:git_leave/screens/admin/admin_dashboard_screen.dart';
import 'package:git_leave/services/notification_service.dart';

  
  bool chk = false;
  bool isAdmin = false;

  Future<void> main() async {
    WidgetsFlutterBinding.ensureInitialized();
    
    try {
      // Initialize Firebase
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      await NotificationService.init();

      await NotificationService.initFcmToken();

      debugPrint("Firebase Connected Successfully.....");
    debugPrint("FCM Token after init: $fcmToken");

      // Get Device ID
      await getDeviceID();

      // Lock orientation
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);

      // Load saved server settings
      final prefs = await SharedPreferences.getInstance();
      final savedIp = prefs.getString('server_ip') ?? '';
      final savedPort = prefs.getString('server_port') ?? '';
      final savedVersion = prefs.getString('server_version') ?? '';

      if (savedIp.isNotEmpty && savedPort.isNotEmpty && savedVersion.isNotEmpty) {
        ip = savedIp;
        port = savedPort;
        version = savedVersion;
        ipAddress = 'http://$ip:$port';
      }

      debugPrint("=== Server Configuration ===");
      debugPrint("IP: $ip");
      debugPrint("Port: $port");
      debugPrint("URL: $ipAddress");

      // Send FCM token to backend
      if (ipAddress.isNotEmpty && ipAddress != 'http://:') {
        await getNotificationToken(fcmToken, deviceId);
      }

      // Auto login check
      final savedEmployeeId = prefs.getString('employeeId');
      final savedPassword = prefs.getString('password');

      if (savedEmployeeId != null && savedPassword != null) {
        globalIDcardNo = savedEmployeeId;
        chk = true;
      }
    } catch (e, stackTrace) {
      debugPrint("Startup Error: $e");
      debugPrintStack(stackTrace: stackTrace);
    }

    runApp(const MyApp());
  }

  Future<void> getNotificationToken(String? fcmToken, String? deviceId) async {
    try {
      if (ipAddress.isEmpty || ipAddress == 'http://:') return;

      final response = await http.post(
        Uri.parse("$ipAddress/api/userdevice"),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode({
          "deviceToken": fcmToken,
          "deviceID": deviceId,
        }),
      );

      if (response.statusCode == 200) {
        debugPrint("FCM Token sent: ${response.body}");
      }
    } catch (e) {
      debugPrint("Notification Token Error: $e");
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
      debugPrint("Device ID: $deviceId | Type: $deviceType");
    } catch (e) {
      debugPrint("Failed to get UDID: $e");
      deviceId = "unknown_device";
    }
  }

  class MyApp extends StatelessWidget {
    const MyApp({super.key});

    @override
    Widget build(BuildContext context) {
      return MaterialApp(
        title: 'GIT Leave App',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
          useMaterial3: true,
        ),
        // Auto login if credentials saved, else show login page
        home: chk ? const HomeScreen() : const LoginPage(),
        routes: {
          '/home':            (context) => const HomeScreen(),
          '/onDuty': (context) => const OnDutyReportPage(),
          '/employeeLogin':   (context) => const LoginPage(),
          '/adminLogin':      (context) => const AdminLoginPage(),   
          '/applyLeave':      (context) => LeaveApplyPage(),
          '/leaveStatus':     (context) => LeaveStatusPage(),
          '/adminLeave':      (context) => const AdminLeavePage(),
          '/adminDashboard':  (context) => const AdminDashboardPage(), 
          '/adminPreferences':(context) {
            // adminId must be loaded from prefs — use FutureBuilder wrapper
            return const _AdminPreferencesRoute();
          },
        },
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(context),
            child: child ?? const SizedBox.shrink(),
          );
        },
      );
    }
  }

  /// Helper widget to load adminId from SharedPreferences before
  /// opening AdminPreferencesPage (which requires adminId parameter)
  class _AdminPreferencesRoute extends StatefulWidget {
    const _AdminPreferencesRoute();

    @override
    State<_AdminPreferencesRoute> createState() => _AdminPreferencesRouteState();
  }

  class _AdminPreferencesRouteState extends State<_AdminPreferencesRoute> {
    String _adminId = '';
    bool _loaded = false;

    @override
    void initState() {
      super.initState();
      _load();
    }

    Future<void> _load() async {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _adminId = prefs.getString('adminId') ?? '';
        _loaded = true;
      });
    }

    @override
    Widget build(BuildContext context) {
      if (!_loaded) {
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      }
      return AdminPreferencesPage(adminId: _adminId);
    }
  }