import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skl_leave/login.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'globalVariable.dart';

// FixedLocation class
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
  static const double EXIT_RADIUS = 100.0; // 100 meters threshold
  static const String TAG = "AutoLocationMonitor";

  // Only one instance of notifications
  static late FlutterLocalNotificationsPlugin _notifications;

  // Assign notifications instance (especially for background isolate)
  static void setNotificationsInstance(
      FlutterLocalNotificationsPlugin instance) {
    _notifications = instance;
  }

  /// Initialize notifications (Android + iOS)
  static Future<void> initNotifications() async {
    try {
      print("$TAG: Initializing notifications...");

      // If instance not assigned yet, create one
      _notifications = _notifications ??
          FlutterLocalNotificationsPlugin();

      // Android initialization
      const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');

      final DarwinInitializationSettings iosSettings =
      DarwinInitializationSettings();

      final InitializationSettings settings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _notifications.initialize(settings);

      // Create Android notification channel
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'auto_monitor_channel',
        'Auto Location Monitor',
        description: 'Channel for location monitoring notifications',
        importance: Importance.high,
        enableVibration: true,
        playSound: true,
      );

      final androidImpl = _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl != null) {
        await androidImpl.createNotificationChannel(channel);
        print("$TAG: Android notification channel created");
      }

      print("$TAG: Notifications initialized successfully");
    } catch (e) {
      print("$TAG: Error initializing notifications: $e");
    }
  }

  /// Show notification with optional distance info
  static Future<void> showNotification(String title, String body,
      {double? distance}) async {
    try {
      String displayBody = body;

      if (distance != null) {
        String formattedDistance;
        String distanceUnit;

        if (distance >= 1000) {
          formattedDistance = (distance / 1000).toStringAsFixed(2);
          distanceUnit = 'km';
        } else {
          formattedDistance = distance.toStringAsFixed(1);
          distanceUnit = 'm';
        }

        displayBody = '📍 Distance: $formattedDistance $distanceUnit\n';
        displayBody += distance > EXIT_RADIUS
            ? '⚠️ ${(distance - EXIT_RADIUS).toStringAsFixed(1)}m beyond radius'
            : '✅ ${(EXIT_RADIUS - distance).toStringAsFixed(1)}m remaining';
        displayBody += '\n$body';
      }

      const androidDetails = AndroidNotificationDetails(
        'auto_monitor_channel',
        'Auto Location Monitor',
        channelDescription: 'Channel for location monitoring notifications',
        importance: Importance.high,
        priority: Priority.high,
        ticker: 'ticker',
        showWhen: true,
        visibility: NotificationVisibility.public,
        enableVibration: true,
        playSound: true,
        colorized: true,
        icon: '@mipmap/ic_launcher',
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const platformDetails =
      NotificationDetails(android: androidDetails, iOS: iosDetails);

      await _notifications.show(
        DateTime.now().millisecond, // Unique ID
        title,
        displayBody,
        platformDetails,
      );

      print("$TAG: Notification shown successfully");
    } catch (e) {
      print("$TAG: Error showing notification: $e");
    }
  }

  /// Fetch fixed location from server API
  static Future<FixedLocation?> fetchFixedLocation() async {
    try {
      final url = "$ipAddress/api/getFixedLocation";
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode({"IDCARDNO": globalIDcardNo}),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data["status"] == true) {
          return FixedLocation(
            latitude: double.parse(data["latitude"].toString()),
            longitude: double.parse(data["longitude"].toString()),
            address: data["address"] ?? '',
            updatedAt: DateTime.now(),
          );
        }
      }
    } catch (e) {
      print("$TAG: Error fetching fixed location: $e");
    }
    return null;
  }

  /// Save fixed location locally
  static Future<void> saveFixedLocation(FixedLocation location) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fixed_location', jsonEncode(location.toJson()));
    await prefs.setBool('monitoring_active', true);
    print("$TAG: Fixed location saved");
  }

  /// Get saved fixed location
  static Future<FixedLocation?> getFixedLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('fixed_location');
    return data != null ? FixedLocation.fromJson(jsonDecode(data)) : null;
  }

  /// Check if monitoring is active
  static Future<bool> isMonitoringActive() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('monitoring_active') ?? false;
  }

  /// Check current location, calculate distance and send notification/alert
  static Future<void> checkLocationAndNotify() async {
    print("$TAG: ===== CHECK LOCATION STARTED =====");
    print("$TAG: Time: ${DateTime.now()}");

    try {
      final prefs = await SharedPreferences.getInstance();
      final isActive = prefs.getBool('monitoring_active') ?? false;
      if (!isActive) {
        print("$TAG: Monitoring not active, exiting");
        return;
      }

      final fixedLoc = await getFixedLocation();
      if (fixedLoc == null) {
        print("$TAG: No fixed location found");
        return;
      }
      print("$TAG: Fixed location: ${fixedLoc.latitude}, ${fixedLoc.longitude}");

      // Check if location services are enabled
      final locationEnabled = await Geolocator.isLocationServiceEnabled();
      print("$TAG: Location services enabled: $locationEnabled");

      if (!locationEnabled) {
        print("$TAG: Location services are disabled");
        await showNotification(
          '📍 Location Disabled',
          'Please enable location services',
        );
        return;
      }

      // Check permissions
      final permission = await Geolocator.checkPermission();
      print("$TAG: Location permission: $permission");

      if (permission == LocationPermission.denied) {
        print("$TAG: Location permission denied");
        return;
      }

      if (permission == LocationPermission.deniedForever) {
        print("$TAG: Location permission permanently denied");
        return;
      }

      // Try to get current position with better error handling
      Position? currentPos;

      // First try: get current position with timeout
      try {
        print("$TAG: Attempting to get current position...");
        currentPos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 15),
        ).timeout(const Duration(seconds: 20));
        print("$TAG: Got current position: ${currentPos.latitude}, ${currentPos.longitude}");
      } catch (e) {
        print("$TAG: Failed to get current position: $e");

        // Second try: get last known position
        try {
          print("$TAG: Attempting to get last known position...");
          currentPos = await Geolocator.getLastKnownPosition();
          if (currentPos != null) {
            print("$TAG: Got last known position: ${currentPos.latitude}, ${currentPos.longitude}");
          } else {
            print("$TAG: No last known position available");
          }
        } catch (e2) {
          print("$TAG: Failed to get last known position: $e2");
        }
      }

      if (currentPos == null) {
        print("$TAG: Could not get any position data");
        await showNotification(
          '📍 Location Unavailable',
          'Could not get current location',
        );
        return;
      }

      // Calculate distance
      final distance = Geolocator.distanceBetween(
        fixedLoc.latitude,
        fixedLoc.longitude,
        currentPos.latitude,
        currentPos.longitude,
      );

      print("$TAG: Distance from fixed location: ${distance.toStringAsFixed(2)} meters");
      print("$TAG: Exit radius: $EXIT_RADIUS meters");
      print("$TAG: Outside radius: ${distance > EXIT_RADIUS}");

      // Check if we need to send alert
      final lastAlertTime = prefs.getInt('last_alert_time') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      final timeSinceLastAlert = now - lastAlertTime;
      final alertCooldown = 300000; // 5 minutes

      if (distance > EXIT_RADIUS) {
        print("$TAG: Outside radius detected");

        if (timeSinceLastAlert > alertCooldown) {
          print("$TAG: Alert cooldown passed, sending alert");

          // Get address for current location
          String? currentAddress;
          try {
            final placemarks = await placemarkFromCoordinates(
                currentPos.latitude,
                currentPos.longitude
            );
            if (placemarks.isNotEmpty) {
              final p = placemarks.first;
              currentAddress = [
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

          // Send alert to server
          final success = await sendExitAlert(
            currentPos: currentPos,
            fixedLoc: fixedLoc,
            distance: distance,
            currentAddress: currentAddress,
          );

          if (success) {
            await prefs.setInt('last_alert_time', now);
            await prefs.setDouble('last_alert_distance', distance);

            await showNotification(
              '⚠️ Exit Alert',
              'You are ${distance.toStringAsFixed(1)}m from work location',
              distance: distance,
            );
            print("$TAG: Alert sent successfully");
          } else {
            print("$TAG: Failed to send alert to server");
          }
        } else {
          print("$TAG: Alert cooldown active, ${(alertCooldown - timeSinceLastAlert) / 1000}s remaining");
        }
      } else {
        print("$TAG: Within radius, no alert needed");

        // Optional: Show occasional "still inside" notification for debugging
        if (timeSinceLastAlert > 3600000) { // Every hour
          await showNotification(
            '📍 Within Location',
            'You are ${distance.toStringAsFixed(1)}m from work',
            distance: distance,
          );
        }
      }

      // Refresh fixed location every 6 hours
      final lastFetch = prefs.getInt('last_fetch_time') ?? 0;
      if ((now - lastFetch) > 21600000) {
        print("$TAG: Refreshing fixed location from server");
        final newFixedLoc = await fetchFixedLocation();
        if (newFixedLoc != null) {
          await saveFixedLocation(newFixedLoc);
          await prefs.setInt('last_fetch_time', now);
          print("$TAG: Fixed location updated");
        }
      }

    } catch (e, st) {
      print("$TAG: ❌ Fatal error: $e");
      print("$TAG: Stack trace: $st");
    }

    print("$TAG: ===== CHECK LOCATION COMPLETED =====\n");
  }
  /// Send exit alert to server API
  static Future<bool> sendExitAlert({
    required Position currentPos,
    required FixedLocation fixedLoc,
    required double distance,
    String? currentAddress,
  }) async {
    try {
      final url = "$ipAddress/api/locationExitAlert";
      final body = jsonEncode({
        "IDCARDNO": globalIDcardNo,
        "TYPE": "EXIT_ALERT",
        "CURRENT_LAT": currentPos.latitude,
        "CURRENT_LNG": currentPos.longitude,
        "FIXED_LAT": fixedLoc.latitude,
        "FIXED_LNG": fixedLoc.longitude,
        "DISTANCE_METERS": distance.toStringAsFixed(2),
        "CURRENT_ADDRESS": currentAddress ?? "",
        "FIXED_ADDRESS": fixedLoc.address,
        "TIMESTAMP": DateTime.now().toIso8601String(),
        "ACCURACY": currentPos.accuracy,
        "SPEED": currentPos.speed,
      });

      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: body,
      ).timeout(const Duration(seconds: 10));

      return response.statusCode == 200;
    } catch (e) {
      print("$TAG: Error sending alert: $e");
      return false;
    }
  }

  /// Start monitoring service (foreground + WorkManager)
  static Future<void> startMonitoring() async {
    try {
      await initNotifications();
      final fixedLoc = await fetchFixedLocation();
      if (fixedLoc == null) {
        await showNotification('❌ Monitoring Failed', 'Could not fetch fixed location');
        return;
      }

      await saveFixedLocation(fixedLoc);

      await Workmanager().cancelByUniqueName('auto-location-check');
      await Workmanager().registerPeriodicTask(
        'auto-location-check',          // Unique task name
        'checkLocationAndNotify',       // Task callback name
        frequency: const Duration(minutes: 15),
        initialDelay: const Duration(seconds: 30),
        constraints: Constraints(
          networkType: NetworkType.not_required, // optional: remove network restriction if not needed
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: false,
        ),
        existingWorkPolicy: ExistingWorkPolicy.keep, // Keep existing task to avoid multiple triggers
        backoffPolicy: BackoffPolicy.linear,         // simpler backoff
        backoffPolicyDelay: const Duration(seconds: 10),
      );


      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('monitoring_active', true);

      await showNotification('✅ Monitoring Started', 'Location: ${fixedLoc.address}', distance: 0.0);
      print("$TAG: Monitoring started successfully");
    } catch (e, st) {
      print("$TAG: Error starting monitoring: $e\n$st");
      await showNotification('❌ Monitoring Error', 'Failed to start: $e');
    }
  }

  /// Stop monitoring
  static Future<void> stopMonitoring() async {
    try {
      await Workmanager().cancelByUniqueName('auto-location-check');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('monitoring_active', false);

      await showNotification('🛑 Monitoring Stopped', 'Location monitoring has been stopped');
      print("$TAG: Monitoring stopped");
    } catch (e) {
      print("$TAG: Error stopping monitoring: $e");
    }
  }
}
