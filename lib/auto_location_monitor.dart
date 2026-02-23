import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'globalVariable.dart';
import 'dart:ui';

class FixedLocation {
  double latitude;
  double longitude;
  String address;
  DateTime updatedAt;

  FixedLocation({
    required this.latitude,
    required this.longitude,
    required this.address,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'address': address,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory FixedLocation.fromJson(Map<String, dynamic> json) => FixedLocation(
    latitude: json['latitude'].toDouble(),
    longitude: json['longitude'].toDouble(),
    address: json['address'] ?? '',
    updatedAt: DateTime.parse(json['updatedAt']),
  );
}

class AutoLocationMonitor {
  static const double EXIT_RADIUS = 100.0; // meters
  static const String TAG = "AutoLocationMonitor";

  static final FlutterBackgroundService _backgroundService =
  FlutterBackgroundService();

  static late FlutterLocalNotificationsPlugin _notifications;

  // Separate subscriptions for foreground and background to avoid conflicts
  static StreamSubscription<Position>? _foregroundPositionSubscription;
  static StreamSubscription<Position>? _backgroundPositionSubscription;

  static bool _wasInsideGeofence = true;
  static FixedLocation? _currentFixedLocation;
  static String? _currentUserId;
  static String? _currentServerUrl;

  static bool _exitAlertSent = false;
  static bool _entryAlertSent = false;
  static DateTime _lastExitTime = DateTime.now().subtract(const Duration(days: 1));
  static DateTime _lastEntryTime = DateTime.now().subtract(const Duration(days: 1));

  static const int ALERT_COOLDOWN_SECONDS = 300; // 5 minutes

  // static bool _isFirstLocationUpdate = true;

  // Guard to prevent concurrent startMonitoring calls
  static bool _isStarting = false;

  // ============= INITIALIZATION =============

  static Future<void> initialize() async {
    await initNotifications();
    await initializeBackgroundService();
    print("$TAG: AutoLocationMonitor initialized");
  }

  static Future<void> initNotifications() async {
    try {
      _notifications = FlutterLocalNotificationsPlugin();

      // Request notification permission for Android 13+
      if (Platform.isAndroid) {
        final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        await androidPlugin?.requestNotificationsPermission();
      }

      const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');

      final DarwinInitializationSettings iosSettings =
      DarwinInitializationSettings();

      final InitializationSettings settings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _notifications.initialize(settings);

      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'geofence_channel',
        'Geofence Monitor',
        description: 'Channel for geofence notifications',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      );

      final androidImpl = _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl != null) {
        await androidImpl.createNotificationChannel(channel);
      }

      print("$TAG: Notifications initialized and permission requested");
    } catch (e) {
      print("$TAG: Error initializing notifications: $e");
    }
  }

  // ============= BACKGROUND SERVICE SETUP =============

  static Future<void> initializeBackgroundService() async {
    final service = FlutterBackgroundService();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: 'geofence_channel',
        initialNotificationTitle: 'Location Monitor',
        initialNotificationContent: 'Monitoring work location 24/7',
        foregroundServiceNotificationId: 888,
        autoStartOnBoot: true,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
  }

  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) {
    try {
      DartPluginRegistrant.ensureInitialized();
      print("$TAG: Background service started - 24/7 monitoring active");

      if (service is AndroidServiceInstance) {
        service.on('setAsForeground').listen((event) {
          service.setAsForegroundService();
        });

        service.on('setAsBackground').listen((event) {
          service.setAsBackgroundService();
        });
      }

      service.on('stopService').listen((event) {
        service.stopSelf();
      });

      _startBackgroundLocationMonitoring(service);
    } catch (e) {
      print("$TAG: Error in onStart: $e");
    }
  }

  @pragma('vm:entry-point')
  static Future<bool> onIosBackground(ServiceInstance service) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    print("$TAG: iOS background started");
    return true;
  }

  // ============= BACKGROUND LOCATION MONITORING =============

  static void _startBackgroundLocationMonitoring(ServiceInstance service) {
    print("$TAG: Starting 24/7 background location monitoring");
    _checkPermissionsAndStart(service);
  }

  static void _checkPermissionsAndStart(ServiceInstance service) async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print("$TAG: Location services disabled, will retry in 30 seconds");
        Timer(const Duration(seconds: 30), () {
          _checkPermissionsAndStart(service);
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        print("$TAG: Location permissions denied, can't monitor");
        return;
      }

      if (permission == LocationPermission.deniedForever) {
        print("$TAG: Location permissions permanently denied");
        return;
      }

      if (Platform.isAndroid && permission != LocationPermission.always) {
        print("$TAG: User doesn't have 'always' permission, will use foreground only");
        // Don't return - we'll still monitor in foreground mode
      }

      await _loadUserData();

      if (_currentFixedLocation == null) {
        print("$TAG: No fixed location found, will retry in 1 minute");
        Timer(const Duration(minutes: 1), () {
          _checkPermissionsAndStart(service);
        });
        return;
      }

      print("$TAG: Loaded fixed location: ${_currentFixedLocation!.latitude}, ${_currentFixedLocation!.longitude}");
      print("$TAG: User ID: $_currentUserId");

      _listenToPositionChanges(service);
    } catch (e) {
      print("$TAG: Error checking permissions: $e");
    }
  }

  static Future<void> _loadUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final fixedLocData = prefs.getString('fixed_location');
      if (fixedLocData != null) {
        _currentFixedLocation = FixedLocation.fromJson(jsonDecode(fixedLocData));
      }

      _currentUserId = prefs.getString('employeeId');


      _currentServerUrl = ipAddress;

      _exitAlertSent = prefs.getBool('exit_alert_sent') ?? false;
      _entryAlertSent = prefs.getBool('entry_alert_sent') ?? false;

      String? lastExitTimeStr = prefs.getString('last_exit_time');
      if (lastExitTimeStr != null) {
        _lastExitTime = DateTime.parse(lastExitTimeStr);
      }

      String? lastEntryTimeStr = prefs.getString('last_entry_time');
      if (lastEntryTimeStr != null) {
        _lastEntryTime = DateTime.parse(lastEntryTimeStr);
      }
    } catch (e) {
      print("$TAG: Error loading user data: $e");
    }
  }

  static void _listenToPositionChanges(ServiceInstance service) {
    // Cancel any existing background subscription to avoid duplicates
    _backgroundPositionSubscription?.cancel();

    print("$TAG: Listening to position changes for 24/7 monitoring");

    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    _backgroundPositionSubscription = Geolocator.getPositionStream(locationSettings: locationSettings)
        .listen((Position position) async {
      try {
        if (_currentFixedLocation == null) return;

        double distance = Geolocator.distanceBetween(
          _currentFixedLocation!.latitude,
          _currentFixedLocation!.longitude,
          position.latitude,
          position.longitude,
        );

        bool isInside = distance <= EXIT_RADIUS;
        print("$TAG: Position update - Distance: ${distance.toStringAsFixed(1)}m, Inside: $isInside");

        if (isInside) {
          if (!_entryAlertSent) {
            print("$TAG: 🟢 INSIDE RADIUS - SENDING ENTRY");
            await _handleEntryEvent(position, distance);
          }
        } else {
          if (!_exitAlertSent) {
            print("$TAG: 🔴 OUTSIDE RADIUS - SENDING EXIT");
            await _handleExitEvent(position, distance);
          }
        }
      } catch (e) {
        print("$TAG: Error processing position: $e");
      }
    }, onError: (error) {
      print("$TAG: Position stream error: $error");
      Future.delayed(const Duration(seconds: 10), () {
        _listenToPositionChanges(service);
      });
    });
  }

  // ============= EVENT HANDLERS =============
  static Future<void> _handleExitEvent(
      Position position, double distance) async {
    try {
      DateTime now = DateTime.now();
      if (now.difference(_lastExitTime).inSeconds < ALERT_COOLDOWN_SECONDS) {
        print("$TAG: Exit alert in cooldown, skipping");
        return;
      }

      if (_exitAlertSent) {
        print("$TAG: Exit alert already sent for current session");
        return;
      }

      print("$TAG: 🚨 PROCESSING EXIT ALERT");

      String? currentAddress = await _getAddressFromCoordinates(
          position.latitude, position.longitude);

      bool alertSent = await _sendBoundaryAlert(
        eventType: 'EXIT',
        currentPos: position,
        distance: distance,
        currentAddress: currentAddress,
      );

      if (alertSent) {
        _exitAlertSent = true;
        _entryAlertSent = false;
        _lastExitTime = now;

        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('exit_alert_sent', true);
        await prefs.setBool('entry_alert_sent', false);
        await prefs.setString('last_exit_time', now.toIso8601String());

        await showNotification(
          '⚠️ LEFT WORK AREA',
          'You are ${distance.toStringAsFixed(1)}m away from work',
          distance: distance,
        );

        print("$TAG: ✅ Exit alert sent successfully");
      } else {
        print("$TAG: ❌ Failed to send exit alert");
      }
    } catch (e) {
      print("$TAG: Error handling exit event: $e");
    }
  }

  static Future<void> _handleEntryEvent(
      Position position, double distance) async {
    try {
      DateTime now = DateTime.now();
      if (now.difference(_lastEntryTime).inSeconds < ALERT_COOLDOWN_SECONDS) {
        print("$TAG: Entry alert in cooldown, skipping");
        return;
      }

      if (_entryAlertSent) {
        print("$TAG: Entry alert already sent for current session");
        return;
      }

      print("$TAG: 🟢 PROCESSING ENTRY ALERT");

      String? currentAddress = await _getAddressFromCoordinates(
          position.latitude, position.longitude);

      bool alertSent = await _sendBoundaryAlert(
        eventType: 'ENTRY',
        currentPos: position,
        distance: distance,
        currentAddress: currentAddress,
      );

      if (alertSent) {
        _entryAlertSent = true;
        _exitAlertSent = false;
        _lastEntryTime = now;

        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('entry_alert_sent', true);
        await prefs.setBool('exit_alert_sent', false);
        await prefs.setString('last_entry_time', now.toIso8601String());

        await showNotification(
          '📍 RETURNED TO WORK',
          'You are within ${(EXIT_RADIUS - distance).toStringAsFixed(1)}m of work',
          distance: distance,
        );

        print("$TAG: ✅ Entry alert sent successfully");
      } else {
        print("$TAG: ❌ Failed to send entry alert");
      }
    } catch (e) {
      print("$TAG: Error handling entry event: $e");
    }
  }

  // ============= HELPER METHODS =============
  static Future<String?> _getAddressFromCoordinates(double lat, double lng) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        return [
          p.street,
          p.subLocality,
          p.locality,
          p.administrativeArea,
          p.country
        ].where((e) => e != null && e.isNotEmpty).join(', ');
      }
    } catch (e) {
      print("$TAG: Error getting address: $e");
    }
    return null;
  }

  // ============= SERVER COMMUNICATION =============
  static Future<bool> _sendBoundaryAlert({
    required String eventType,
    required Position currentPos,
    required double distance,
    String? currentAddress,
  }) async {
    try {
      if (_currentServerUrl == null || _currentUserId == null || _currentFixedLocation == null) {
        print("$TAG: Missing server URL, user ID, or fixed location");
        return false;
      }

      final url = "$ipAddress/api/locationExitAlert";
      final body = jsonEncode({
        "IDCARDNO": _currentUserId,
        "EVENT_TYPE": eventType,
        "CURRENT_LAT": currentPos.latitude,
        "CURRENT_LNG": currentPos.longitude,
        "FIXED_LAT": _currentFixedLocation!.latitude,
        "FIXED_LNG": _currentFixedLocation!.longitude,
        "DISTANCE_METERS": distance.toStringAsFixed(2),
        "CURRENT_ADDRESS": currentAddress ?? "",
        "FIXED_ADDRESS": _currentFixedLocation!.address,
        "TIMESTAMP": DateTime.now().toIso8601String(),
        "ACCURACY": currentPos.accuracy,
        "SPEED": currentPos.speed,
        "IS_WITHIN_RADIUS": distance <= EXIT_RADIUS,
      });

      print("$TAG: Sending $eventType alert to server: $url");
      print("$TAG: Request body: $body");

      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: body,
      ).timeout(const Duration(seconds: 10));

      print("$TAG: Response status: ${response.statusCode}");
      print("$TAG: Response body: ${response.body}");

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        // Handle both boolean and numeric status
        if (responseData["status"] == true || responseData["status"] == 1 || responseData["success"] == true) {
          return true;
        }
      }
      return false;
    } catch (e) {
      print("$TAG: Error sending alert: $e");
      return false;
    }
  }

  // ============= NOTIFICATIONS =============
  static Future<void> showNotification(String title, String body,
      {double? distance}) async {
    try {
      String displayBody = body;
      if (distance != null) {
        if (distance >= 1000) {
          displayBody = '📍 ${(distance / 1000).toStringAsFixed(2)} km from work\n$body';
        } else {
          displayBody = '📍 ${distance.toStringAsFixed(1)} m from work\n$body';
        }
      }

      const androidDetails = AndroidNotificationDetails(
        'geofence_channel',
        'Geofence Monitor',
        channelDescription: 'Channel for geofence notifications',
        importance: Importance.high,
        priority: Priority.high,
        ticker: 'ticker',
        visibility: NotificationVisibility.public,
        enableVibration: true,
        playSound: true,
        icon: '@mipmap/ic_launcher',
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const platformDetails = NotificationDetails(
          android: androidDetails, iOS: iosDetails);

      await _notifications.show(
        DateTime.now().millisecond,
        title,
        displayBody,
        platformDetails,
      );
      print("$TAG: Notification shown: $title");
    } catch (e) {
      print("$TAG: Error showing notification: $e");
    }
  }

  // ============= API METHODS =============
  static Future<FixedLocation?> fetchFixedLocation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String idCardNo = prefs.getString('employeeId') ?? '';

      if (idCardNo.isEmpty) {
        print("$TAG: employee ID missing");
        return null;
      }

      final url = "$ipAddress/api/getFixedLocation";
      print("$TAG: Fetching fixed location from: $url");
      print("$TAG: Request body: ${jsonEncode({"IDCARDNO": idCardNo})}");

      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode({"IDCARDNO": idCardNo}),
      ).timeout(const Duration(seconds: 10));

      print("$TAG: Response status: ${response.statusCode}");
      print("$TAG: Response body: ${response.body}");

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        // Handle both boolean and numeric status from backend
        bool status = false;
        if (data["status"] is bool) {
          status = data["status"];
        } else if (data["status"] is num) {
          status = data["status"] == 1;
        }

        if (status && data["latitude"] != null && data["longitude"] != null) {
          print("$TAG: Fixed location received successfully");
          return FixedLocation(
            latitude: double.parse(data["latitude"].toString()),
            longitude: double.parse(data["longitude"].toString()),
            address: data["address"] ?? '',
            updatedAt: DateTime.now(),
          );
        } else {
          print("$TAG: No fixed location found for user");
        }
      }
    } catch (e) {
      print("$TAG: Error fetching fixed location: $e");
    }
    return null;
  }

  static Future<void> saveFixedLocation(FixedLocation location) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fixed_location', jsonEncode(location.toJson()));
    await prefs.setBool('monitoring_active', true);
    _currentFixedLocation = location;
    print("$TAG: Fixed location saved: ${location.latitude}, ${location.longitude}");
  }

  static Future<FixedLocation?> getFixedLocation() async {
    if (_currentFixedLocation != null) return _currentFixedLocation;

    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('fixed_location');
    if (data != null) {
      _currentFixedLocation = FixedLocation.fromJson(jsonDecode(data));
    }
    return _currentFixedLocation;
  }

  static Future<bool> isMonitoringActive() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('monitoring_active') ?? false;
  }

  // ============= CONTROL METHODS =============
  static Future<void> startMonitoring() async {
    // Prevent concurrent starts
    if (_isStarting) {
      print("$TAG: startMonitoring already in progress, skipping...");
      return;
    }
    _isStarting = true;
    try {
      print("$TAG: ===== STARTING 24/7 MONITORING =====");

      // Check location services
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await showNotification(
          '📍 Location Services Disabled',
          'Please enable location services for 24/7 monitoring',
        );
        return;
      }

      // Check permissions but don't block on Android
      if (Platform.isAndroid) {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
          await showNotification(
            '📍 Location Permission Required',
            'Please grant location permission in settings for 24/7 monitoring',
          );
          return;
        }
      }

      await initialize();

      final fixedLoc = await fetchFixedLocation();
      if (fixedLoc == null) {
        await showNotification(
          '📍 Work Location Not Set',
          'Please set your work location first',
        );
        return;
      }

      await saveFixedLocation(fixedLoc);

      // Reset alert states
      final prefs = await SharedPreferences.getInstance();
      _exitAlertSent = false;
      _entryAlertSent = false;
      // _isFirstLocationUpdate = true;
      await prefs.setBool('exit_alert_sent', false);
      await prefs.setBool('entry_alert_sent', false);

      await _loadUserData(); // reload after saving

      await _backgroundService.startService();

      _startForegroundMonitoring();

      await prefs.setBool('monitoring_active', true);

      await showNotification(
        '✅ 24/7 MONITORING ACTIVE',
        'You will be notified when leaving/entering work area',
      );

      print("$TAG: ✅ 24/7 monitoring started successfully");
    } catch (e, st) {
      print("$TAG: Error starting monitoring: $e\n$st");
      await showNotification('❌ Monitoring Error', 'Failed to start: $e');
    } finally {
      _isStarting = false;
    }
  }

  static void _startForegroundMonitoring() {
    _foregroundPositionSubscription?.cancel();

    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    _foregroundPositionSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings)
            .listen((Position position) async {
          if (_currentFixedLocation == null) return;

          double distance = Geolocator.distanceBetween(
            _currentFixedLocation!.latitude,
            _currentFixedLocation!.longitude,
            position.latitude,
            position.longitude,
          );

          bool isInside = distance <= EXIT_RADIUS;

          if (isInside && !_entryAlertSent) {
            await _handleEntryEvent(position, distance);
          } else if (!isInside && !_exitAlertSent) {
            await _handleExitEvent(position, distance);
          }
        });
  }

  static Future<void> stopMonitoring() async {
    try {
      print("$TAG: Stopping 24/7 monitoring...");

      _backgroundService.invoke("stopService");
      await _foregroundPositionSubscription?.cancel();
      await _backgroundPositionSubscription?.cancel();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('monitoring_active', false);

      await showNotification('🛑 Monitoring Stopped', '24/7 location monitoring stopped');
      print("$TAG: Monitoring stopped");
    } catch (e) {
      print("$TAG: Error stopping monitoring: $e");
    }
  }

  static Future<void> restoreMonitoringState() async {
    final prefs = await SharedPreferences.getInstance();
    final wasActive = true;
    print("check location 3 $wasActive");
    if (wasActive) {
      print("$TAG: 🔄 Restoring 24/7 monitoring state");
      await startMonitoring();
    }
  }

  static Future<void> resetAlertStates() async {
    final prefs = await SharedPreferences.getInstance();
    _exitAlertSent = false;
    _entryAlertSent = false;
    // _isFirstLocationUpdate = true;
    await prefs.setBool('exit_alert_sent', false);
    await prefs.setBool('entry_alert_sent', false);
    print("$TAG: Alert states reset");
  }
}