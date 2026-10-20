// Reminder notifications (scheduled ahead, so they fire with the app closed)
// and the in-app chime.
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

/// One alert to schedule.
class Alert {
  final int at;
  final String title, body;
  final bool boarding; // true = "Now boarding" (before), false = "Now departing"
  const Alert(this.at, this.title, this.body, this.boarding);
}

class Alerts {
  final _plugin = FlutterLocalNotificationsPlugin();
  final _player = AudioPlayer();
  bool _ready = false;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  Future<void> init() async {
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
    await _player.setReleaseMode(ReleaseMode.stop);
  }

  /// Asks for permission. Returns whether notifications may be shown.
  Future<bool> requestPermission() async {
    if (!_ready) return false;
    final a = _android;
    if (a != null) return await a.requestNotificationsPermission() ?? false;
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    return await ios?.requestPermissions(alert: true, sound: true) ?? false;
  }

  Future<bool> enabled() async {
    if (!_ready) return false;
    final a = _android;
    if (a != null) return await a.areNotificationsEnabled() ?? false;
    return true;
  }

  static const _channels = {
    'boarding': ('Boarding alerts', 'Before a departure', 'chime_boarding'),
    'departing': ('Departure alerts', 'When an event starts', 'chime_departing'),
    'silent': ('Silent alerts', 'Reminders without the chime', null),
  };

  NotificationDetails _details(Alert a, bool sound) {
    final ch = !sound ? 'silent' : (a.boarding ? 'boarding' : 'departing');
    final (name, desc, raw) = _channels[ch]!;
    return NotificationDetails(
      android: AndroidNotificationDetails(
        ch,
        name,
        channelDescription: desc,
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        playSound: raw != null,
        sound: raw == null ? null : RawResourceAndroidNotificationSound(raw),
      ),
      iOS: DarwinNotificationDetails(presentSound: sound, sound: sound ? (a.boarding ? 'chime_boarding.wav' : 'chime_departing.wav') : null),
    );
  }

  /// Replaces every pending reminder with [alerts].
  Future<void> schedule(List<Alert> alerts, {required bool sound}) async {
    if (!_ready) return;
    try {
      await _plugin.cancelAllPendingNotifications();
      if (alerts.isEmpty) return;
      final exact = await _android?.canScheduleExactNotifications() ?? true;
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
    } catch (e) {
      debugPrint('scheduling failed: $e');
    }
  }

  Future<void> cancelAll() async {
    if (_ready) await _plugin.cancelAllPendingNotifications();
  }

  Future<void> chime({required bool boarding}) async {
    try {
      await _player.stop();
      await _player.play(AssetSource(boarding ? 'sounds/chime_boarding.wav' : 'sounds/chime_departing.wav'));
    } catch (e) {
      debugPrint('chime failed: $e');
    }
  }
}
