package com.leaveApp.SklHrApp.skl_leave;

import android.app.PictureInPictureParams;
import android.os.Build;
import android.util.Rational;

import androidx.annotation.NonNull;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {
    private static final String CHANNEL = "com.sklhr/pip";

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);

        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    if (call.method.equals("enterPiP")) {
                        boolean success = enterPipModeSafe();
                        result.success(success);
                    } else {
                        result.notImplemented();
                    }
                });
    }

    /**
     * Safe PiP entry
     */
    private boolean enterPipModeSafe() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !isFinishing() && !isDestroyed() && hasWindowFocus()) {
            try {

                Rational aspectRatio = new Rational(9, 16);
                PictureInPictureParams params = new PictureInPictureParams.Builder()
                        .setAspectRatio(aspectRatio)
                        .build();
                return enterPictureInPictureMode(params);
            } catch (IllegalStateException e) {
                e.printStackTrace();
                return false;
            }
        }
        return false;
    }

    @Override
    public void onUserLeaveHint() {
        super.onUserLeaveHint();
        enterPipModeSafe();
    }

    @Override
    public void onPictureInPictureModeChanged(boolean isInPictureInPictureMode) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode);
        // You can send event to Flutter here if needed
    }
}
