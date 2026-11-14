import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz_data;

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();

  // Meal reminders channel
  static const _channelId = 'nutriscan_reminders';
  static const _channelName = 'Meal Reminders';

  // Water reminders channel
  static const _waterChannelId = 'nutriscan_water';
  static const _waterChannelName = 'Water Reminders';

  // Health alert channel
  static const _alertChannelId = 'nutriscan_alerts';
  static const _alertChannelName = 'Health Alerts';

  // Water notification IDs: 10–20 (11 slots)
  static const _waterIdBase = 10;
  static const _waterSlots = [
    [7, 0], [8, 30], [10, 0], [11, 30], [13, 0],
    [14, 30], [16, 0], [17, 30], [19, 0], [20, 30], [22, 0],
  ];

  static Future<void> init() async {
    tz_data.initializeTimeZones();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(android: androidInit),
      onDidReceiveNotificationResponse: (response) {
        debugPrint('Notification tapped: ${response.payload}');
      },
    );

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: 'Daily reminders to log your meals',
        importance: Importance.high,
      ),
    );

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _waterChannelId,
        _waterChannelName,
        description: 'Reminders to drink water throughout the day',
        importance: Importance.high,
      ),
    );

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _alertChannelId,
        _alertChannelName,
        description: 'Immediate alerts when health goals are exceeded or unmet',
        importance: Importance.high,
      ),
    );
  }

  // ── Immediate health alerts ────────────────────────────────────────────────

  /// Fire a one-shot notification immediately (used for threshold breaches).
  static Future<void> sendImmediateAlert({
    required int id,
    required String title,
    required String body,
  }) async {
    try {
      await _plugin.show(
        id,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _alertChannelId,
            _alertChannelName,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Health alert notification failed: $e');
    }
  }

  // ── End-of-day summary ─────────────────────────────────────────────────────

  /// Schedule a daily 9 PM summary (ID 30).
  /// Pass current calorie totals to personalise the body text.
  static Future<void> scheduleEndOfDaySummary({
    double todayCalories = 0,
    double goalCalories = 2000,
  }) async {
    await _plugin.cancel(30);
    try {
      final remaining =
          (goalCalories - todayCalories).clamp(0.0, double.infinity);
      final body = todayCalories > 0
          ? 'You consumed ${todayCalories.toStringAsFixed(0)} kcal today. '
              '${remaining.toStringAsFixed(0)} kcal remaining for your goal. Keep it up!'
          : 'Check how you did today — calories, macros, and water goals are waiting!';

      final now = DateTime.now();
      var targetLocal = DateTime(now.year, now.month, now.day, 21, 0);
      if (targetLocal.isBefore(now)) {
        targetLocal = targetLocal.add(const Duration(days: 1));
      }
      final target = tz.TZDateTime.from(targetLocal.toUtc(), tz.UTC);
      await _plugin.zonedSchedule(
        30,
        '📊 Today\'s Summary',
        body,
        target,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _alertChannelId,
            _alertChannelName,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: 'progress',
      );
    } catch (e) {
      debugPrint('End-of-day summary scheduling failed: $e');
    }
  }

  static Future<void> cancelEndOfDaySummary() async {
    await _plugin.cancel(30);
  }

  // ── Contextual meal reminders ──────────────────────────────────────────────

  /// One-shot lunch check at 14:00 today (ID 31).
  /// Only schedules if 14:00 hasn't passed yet. Cancel when a meal is logged.
  static Future<void> scheduleLunchReminder() async {
    await _plugin.cancel(31);
    try {
      final now = DateTime.now();
      final targetLocal = DateTime(now.year, now.month, now.day, 14, 0);
      if (targetLocal.isBefore(now)) return;
      final target = tz.TZDateTime.from(targetLocal.toUtc(), tz.UTC);
      await _plugin.zonedSchedule(
        31,
        '🍽️ Haven\'t logged lunch yet?',
        'Keep your streak going! Quick scan your meal now.',
        target,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: 'camera',
      );
    } catch (e) {
      debugPrint('Lunch reminder scheduling failed: $e');
    }
  }

  static Future<void> cancelLunchReminder() async {
    await _plugin.cancel(31);
  }

  /// One-shot dinner check at 19:30 today (ID 32).
  /// Only schedules if 19:30 hasn't passed yet. Cancel when a meal is logged.
  static Future<void> scheduleDinnerReminder() async {
    await _plugin.cancel(32);
    try {
      final now = DateTime.now();
      final targetLocal = DateTime(now.year, now.month, now.day, 19, 30);
      if (targetLocal.isBefore(now)) return;
      final target = tz.TZDateTime.from(targetLocal.toUtc(), tz.UTC);
      await _plugin.zonedSchedule(
        32,
        '🌙 Dinner time!',
        'Don\'t forget to log your dinner and hit your daily goal.',
        target,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: 'camera',
      );
    } catch (e) {
      debugPrint('Dinner reminder scheduling failed: $e');
    }
  }

  static Future<void> cancelDinnerReminder() async {
    await _plugin.cancel(32);
  }

  static Future<void> requestPermissions() async {
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  // ── Meal reminders ─────────────────────────────────────────────────────────

  static Future<void> scheduleMealReminders() async {
    await _scheduleDaily(1, '🍳 Breakfast time!',
        "Don't forget to log your breakfast!", 8);
    await _scheduleDaily(2, '🥗 Lunch time!',
        'Time to log your lunch and stay on track!', 13);
    await _scheduleDaily(3, '🍽️ Dinner time!',
        'Log your dinner to hit your daily goals!', 19);
  }

  // ── Water reminders ────────────────────────────────────────────────────────

  /// Schedule 11 daily water reminders from 7:00 AM to 10:00 PM every 90 min.
  static Future<void> scheduleWaterReminders() async {
    await cancelWaterReminders();
    for (int i = 0; i < _waterSlots.length; i++) {
      await _scheduleWaterReminder(
        id: _waterIdBase + i,
        hour: _waterSlots[i][0],
        minute: _waterSlots[i][1],
      );
    }
  }

  static Future<void> cancelWaterReminders() async {
    for (int i = 0; i < _waterSlots.length; i++) {
      await _plugin.cancel(_waterIdBase + i);
    }
  }

  static Future<void> _scheduleWaterReminder({
    required int id,
    required int hour,
    required int minute,
  }) async {
    try {
      final now = DateTime.now();
      var targetLocal = DateTime(now.year, now.month, now.day, hour, minute);
      if (targetLocal.isBefore(now)) {
        targetLocal = targetLocal.add(const Duration(days: 1));
      }
      final target = tz.TZDateTime.from(targetLocal.toUtc(), tz.UTC);

      await _plugin.zonedSchedule(
        id,
        '💧 Time to Hydrate!',
        "Don't forget to drink a glass of water. Stay healthy!",
        target,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _waterChannelId,
            _waterChannelName,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: 'water',
      );
    } catch (e) {
      debugPrint('Failed to schedule water notification $id: $e');
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static Future<void> _scheduleDaily(
      int id, String title, String body, int hour) async {
    try {
      final now = DateTime.now();
      var targetLocal = DateTime(now.year, now.month, now.day, hour, 0);
      if (targetLocal.isBefore(now)) {
        targetLocal = targetLocal.add(const Duration(days: 1));
      }
      final target = tz.TZDateTime.from(targetLocal.toUtc(), tz.UTC);

      await _plugin.zonedSchedule(
        id,
        title,
        body,
        target,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e) {
      debugPrint('Failed to schedule notification $id: $e');
    }
  }

  static Future<void> showWelcomeNotification() async {
    try {
      await _plugin.show(
        0,
        '👋 Welcome to NutriScan!',
        'Start scanning food to track your nutrition goals.',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Welcome notification failed: $e');
    }
  }

  static Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }
}
