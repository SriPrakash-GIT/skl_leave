import 'package:flutter/material.dart';
import 'package:flutter_overlay_window_plus/flutter_overlay_window_plus.dart';
import 'package:flutter/services.dart';

class MiniMapOverlay {
  static const overlayChannel = MethodChannel('overlay_channel');

  static Future<bool> show() async {
    try {
      final hasPermission =
          await FlutterOverlayWindowPlus.isPermissionGranted();
      if (!hasPermission) {
        await FlutterOverlayWindowPlus.requestPermission();
      }

      return await FlutterOverlayWindowPlus.showOverlay(
        enableDrag: true,
        overlayTitle: "SKL HR - OnDuty",
        overlayContent: "Location tracking active",
        flag: OverlayFlag.defaultFlag,
        visibility: NotificationVisibility.visibilityPublic,
        alignment: OverlayAlignment.center, // Fixed
      );
    } catch (e) {
      print("Overlay error: $e");
      return false;
    }
  }

  static Future<bool> close() async {
    return await FlutterOverlayWindowPlus.closeOverlay();
  }
}
