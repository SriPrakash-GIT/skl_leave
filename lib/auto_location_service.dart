import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auto_location_monitor.dart';

class AutoLocationService {
  static final AutoLocationService _instance = AutoLocationService._internal();
  factory AutoLocationService() => _instance;
  AutoLocationService._internal();

  static bool _isInitialized = false;


  static Future<void> initialize() async {
    if (_isInitialized) return;

    WidgetsFlutterBinding.ensureInitialized();

    final prefs = await SharedPreferences.getInstance();
    final wasActive = prefs.getBool('monitoring_active') ?? false;

    if (wasActive) {
      await AutoLocationMonitor.startMonitoring();
    }

    _isInitialized = true;
  }

  static Future<void> refreshFixedLocation() async {
    final fixedLoc = await AutoLocationMonitor.fetchFixedLocation();
    if (fixedLoc != null) {
      await AutoLocationMonitor.saveFixedLocation(fixedLoc);
    }
  }
}