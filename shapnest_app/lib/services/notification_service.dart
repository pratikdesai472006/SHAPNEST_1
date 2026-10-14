import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  final Map<int, DateTime> _lastNotificationTime = {};

  static const String channelId = 'shapnest_hazard_alerts';
  static const String channelName = 'SHAPNEST Safety Alerts';
  static const String channelDesc =
      'Real-time proximity warnings when child is near dangerous appliances';

  Future<void> initialize() async {
    if (_isInitialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    try {
      await _notificationsPlugin.initialize(settings: initSettings);

      // Create high-importance notification channel for Android 8.0+
      final androidNotificationPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidNotificationPlugin != null) {
        await androidNotificationPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            channelId,
            channelName,
            description: channelDesc,
            importance: Importance.max,
            playSound: true,
            enableVibration: true,
          ),
        );
      }

      _isInitialized = true;
    } catch (e) {
      debugPrint('[NotificationService] Init error: $e');
    }
  }

  /// Request runtime notification permissions on Android 13+ and iOS
  Future<bool> requestPermissions() async {
    try {
      // 1. Check & request through permission_handler
      final status = await Permission.notification.request();
      if (status.isGranted) return true;

      // 2. Fallback to platform-specific notification plugin request
      final androidImplementation = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidImplementation != null) {
        final granted =
            await androidImplementation.requestNotificationsPermission();
        return granted ?? false;
      }

      final iosImplementation = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();
      if (iosImplementation != null) {
        final granted = await iosImplementation.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        return granted ?? false;
      }

      return status.isGranted;
    } catch (e) {
      debugPrint('[NotificationService] Permission request error: $e');
      return false;
    }
  }

  /// Post a heads-up system/device notification
  Future<void> showHazardNotification({
    required int id,
    required String title,
    required String body,
    bool isCritical = true,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    final now = DateTime.now();
    final lastTime = _lastNotificationTime[id];
    // Rate limit per node: minimum 10 seconds between notifications to avoid spamming the OS
    if (lastTime != null && now.difference(lastTime).inSeconds < 10) {
      return;
    }
    _lastNotificationTime[id] = now;

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDesc,
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'SHAPNEST Safety Alert',
      icon: '@mipmap/ic_launcher',
      color: isCritical ? const Color(0xFFFF1744) : const Color(0xFFFFD600),
      enableLights: true,
      enableVibration: true,
      playSound: true,
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: title,
        summaryText: 'SHAPNEST Hazard Monitor',
      ),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
      await _notificationsPlugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: notificationDetails,
      );
    } catch (e) {
      debugPrint('[NotificationService] Show notification error: $e');
    }
  }
}
