// location_service.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:workmanager/workmanager.dart';
import 'auto_location_monitor.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  static Timer? _foregroundTimer;
  static bool _isMonitoring = false;

  // Start monitoring (handles both foreground and background)
  static Future<void> startMonitoring() async {
    if (_isMonitoring) return;

    _isMonitoring = true;

    // Start foreground monitoring (when app is open)
    _startForegroundMonitoring();

    // Start background monitoring (when app is closed)
    await AutoLocationMonitor.startMonitoring();

    print("📍 LocationService: Monitoring started");
  }

  // Stop monitoring
  static Future<void> stopMonitoring() async {
    _isMonitoring = false;
    _foregroundTimer?.cancel();
    _foregroundTimer = null;

    await AutoLocationMonitor.stopMonitoring();
    print("📍 LocationService: Monitoring stopped");
  }

  // Foreground monitoring using Timer (runs when app is open)
  static void _startForegroundMonitoring() {
    _foregroundTimer?.cancel();

    // Check location every 60 seconds when app is open
    _foregroundTimer = Timer.periodic(const Duration(seconds: 60), (timer) async {
      if (!_isMonitoring) {
        timer.cancel();
        return;
      }

      print("📍 LocationService: Foreground check at ${DateTime.now()}");
      await AutoLocationMonitor.checkLocationAndNotify();
    });

    // Also check immediately on start
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AutoLocationMonitor.checkLocationAndNotify();
    });
  }

  // Force a manual check (useful for testing)
  static Future<void> manualCheck() async {
    print("📍 LocationService: Manual check triggered");
    await AutoLocationMonitor.checkLocationAndNotify();
  }
}