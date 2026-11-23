// Reminder notifications (scheduled ahead, so they fire with the app closed)
// and the in-app chime.
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'platform.dart';

/// One alert to schedule.
class Alert {
  final int at;
  final String title, body;
  final bool boarding; // true = "Now boarding" (before), false = "Now departing"

  /// 'board' (event and task reminders) or 'money' (bills due, the evening log nudge).
  final String kind;
  const Alert(this.at, this.title, this.body, this.boarding, {this.kind = 'board'});
}

class Alerts {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  Future<void>? _starting;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  /// Starts the plugin; everything below waits for it, so it can run alongside the app's own loading.
  Future<void> init() => _starting ??= _init();

  Future<void> _init() async {
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_notification'),
          iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
        ),
      );
      _ready = true;
    } catch (e) {
      debugPrint('notifications unavailable: $e');
    }
  }

  /// Asks for permission. Returns whether notifications may be shown.
  Future<bool> requestPermission() async {
    await _starting;
    if (!_ready) return false;
    final a = _android;
    if (a != null) return await a.requestNotificationsPermission() ?? false;
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    return await ios?.requestPermissions(alert: true, sound: true) ?? false;
  }

  Future<bool> enabled() async {
    await _starting;
    if (!_ready) return false;
    final a = _android;
    if (a != null) return await a.areNotificationsEnabled() ?? false;
    return true;
  }

  static const _channels = {
    'boarding': ('Boarding alerts', 'Before a departure', 'chime_boarding'),
    'departing': ('Departure alerts', 'When an event starts', 'chime_departing'),
    'silent': ('Silent alerts', 'Reminders without the chime', null),
    'money': ('Money', 'Bills due, the evening log reminder and budget alerts', null),
  };

  NotificationDetails _details(Alert a, bool sound) {
    final ch = a.kind == 'money' ? 'money' : (!sound ? 'silent' : (a.boarding ? 'boarding' : 'departing'));
    final (name, desc, raw) = _channels[ch]!;
    return NotificationDetails(
      android: AndroidNotificationDetails(
        ch,
        name,
        channelDescription: desc,
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        playSound: raw != null || ch == 'money',
        sound: raw == null ? null : RawResourceAndroidNotificationSound(raw),
      ),
      iOS: DarwinNotificationDetails(presentSound: sound, sound: sound ? (a.boarding ? 'chime_boarding.wav' : 'chime_departing.wav') : null),
    );
  }

  /// What was last handed to the system, so an unchanged list isn't cancelled
  /// and re-registered (each one is an alarm plus a write the plugin keeps).
  String? _scheduled;

  /// Replaces every pending reminder with [alerts].
  Future<void> schedule(List<Alert> alerts, {required bool sound}) async {
    await _starting;
    if (!_ready) return;
    try {
      final exact = await _android?.canScheduleExactNotifications() ?? true;
      final sig = [sound, exact, for (final a in alerts) '${a.at}|${a.kind}|${a.boarding}|${a.title}|${a.body}'].join('\n');
      if (sig == _scheduled) return;
      _scheduled = null;
      await _plugin.cancelAllPendingNotifications();
      if (alerts.isEmpty) {
        _scheduled = sig;
        return;
      }
      var id = 1;
      for (final a in alerts) {
        await _plugin.zonedSchedule(
          id: id++,
          scheduledDate: tz.TZDateTime.fromMillisecondsSinceEpoch(tz.UTC, a.at),
          notificationDetails: _details(a, sound),
          androidScheduleMode: exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle,
          title: a.title,
          body: a.body,
        );
      }
      _scheduled = sig;
    } catch (e) {
      debugPrint('scheduling failed: $e');
    }
  }

  /// Shows a notification right away (budget alerts).
  Future<void> showNow(int id, String title, String body) async {
    await _starting;
    if (!_ready) return;
    try {
      await _plugin.show(id: id, title: title, body: body, notificationDetails: _details(Alert(0, title, body, false, kind: 'money'), true));
    } catch (e) {
      debugPrint('notify failed: $e');
    }
  }

  Future<void> cancelAll() async {
    await _starting;
    _scheduled = null;
    if (_ready) await _plugin.cancelAllPendingNotifications();
  }

  /// Plays the chime now (res/raw, the same sound as the notifications).
  Future<void> chime({required bool boarding}) => AppPlatform.chime(boarding: boarding);
}
