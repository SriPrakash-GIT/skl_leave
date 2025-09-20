import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

void startBackgroundLocation() {
  FlutterForegroundTask.startService(
    notificationTitle: "OnDuty Tracking Active",
    notificationText: "Tracking your location",
    callback: backgroundTaskEntryPoint,
  );
}

void backgroundTaskEntryPoint() {
  FlutterForegroundTask.setTaskHandler(BackgroundTaskHandler());
}

class BackgroundTaskHandler extends TaskHandler {
  StreamSubscription<Position>? _positionStream;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    LocationSettings settings = AndroidSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 1,
      intervalDuration: const Duration(seconds: 2),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: "SKL HR App",
        notificationText: "Tracking in progress",
        enableWakeLock: true,
      ),
    );

    _positionStream = Geolocator.getPositionStream(locationSettings: settings)
        .listen((pos) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('bg_lat', pos.latitude);
      await prefs.setDouble('bg_lng', pos.longitude);
    });
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTerminated) async {
    await _positionStream?.cancel();
  }
}
