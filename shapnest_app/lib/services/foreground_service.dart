import 'dart:io';
import 'package:flutter/services.dart';

/// Manages the native Android Foreground Service
/// to keep BLE scanning, telemetry parsing, and hazard alerts alive in the background
class ForegroundService {
  static const MethodChannel _channel =
      MethodChannel('com.shapnest.shapnest_app/foreground_service');

  static bool _isRunning = false;
  static bool get isRunning => _isRunning;

  /// Start the persistent Android Foreground Service
  static Future<void> start({
    String title = 'SHAPNEST Active Protection',
    String text = 'Continuously monitoring hazard zones & child wristband in background.',
  }) async {
    if (!Platform.isAndroid || _isRunning) return;

    try {
      await _channel.invokeMethod('startService', {
        'title': title,
        'text': text,
      });
      _isRunning = true;
    } catch (_) {
      // Graceful fallback
    }
  }

  /// Stop the Android Foreground Service
  static Future<void> stop() async {
    if (!Platform.isAndroid || !_isRunning) return;

    try {
      await _channel.invokeMethod('stopService');
      _isRunning = false;
    } catch (_) {}
  }
}
