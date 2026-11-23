// Home-screen widget bridge (Android). Pushes a snapshot of the weeks around
// today (events, tasks and money logged) to the native widget, hands widget
// taps back to the app, and applies what was done on the widget itself.
//
// Ticks and quick adds made on the widget wait in a queue on the phone until a
// copy of the app applies them: this one when it's open, otherwise a short-lived
// background one. Every action is safe to apply twice, so a retry after the app
// was closed mid-way never doubles anything.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/logic.dart';
import '../core/model.dart';
import '../core/money.dart';
import '../core/tasks.dart';
import '../core/util.dart';

/// A tap on the widget: type is 'event' (with id), 'day', 'add', 'task' or 'money'; day is YYYY-MM-DD.
typedef WidgetLaunch = Map<String, String?>;

abstract final class WidgetBridge {
  static const _ch = MethodChannel('subwayboard/widget');
  static Timer? _debounce;
  static String? _last;
  static bool get _on => !kIsWeb && Platform.isAndroid;

  /// Listens for widget taps and "new actions" kicks while the app runs;
  /// returns the tap that launched it, if any.
  static Future<WidgetLaunch?> init(void Function(WidgetLaunch) onLaunch, {Future<void> Function()? onKick}) async {
    if (!_on) return null;
    listen(onLaunch: onLaunch, onKick: onKick);
    try {
      final m = await _ch.invokeMethod<Map>('takeLaunch');
      return m == null ? null : Map<String, String?>.from(m);
    } catch (e) {
      debugPrint('widget launch: $e');
      return null;
    }
  }

  static void listen({void Function(WidgetLaunch)? onLaunch, Future<void> Function()? onKick}) {
    if (!_on) return;
    _ch.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'launch':
          if (call.arguments is Map && onLaunch != null) onLaunch(Map<String, String?>.from(call.arguments as Map));
        case 'kick':
          await onKick?.call();
      }
    });
  }

  /// Sends fresh data to the widget, coalescing bursts of saves.
  static void push(AppData Function() data) {
    if (!_on) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () => pushNow(data()));
  }

  /// Sends fresh data now (after applying widget actions, so the widget never
  /// flips back to what it showed before).
  static Future<void> pushNow(AppData s) async {
    if (!_on) return;
    _debounce?.cancel();
    final snap = snapshot(s);
    // Unchanged since the last push (a resume, an edit off the widget's weeks): nothing to send.
    if (snap == _last) return;
    try {
      await _ch.invokeMethod('update', snap);
      _last = snap;
    } catch (e) {
      debugPrint('widget update: $e');
    }
  }

  // ---------- widget actions ----------

  /// What was done on the widget and not yet applied.
  static Future<List<Map<String, dynamic>>> peekActions() async {
    if (!_on) return const [];
    try {
      final raw = await _ch.invokeMethod<List>('peekActions') ?? const [];
      return [
        for (final r in raw)
          if (r is String) jsonDecode(r) as Map<String, dynamic>,
      ];
    } catch (e) {
      debugPrint('widget actions: $e');
      return const [];
    }
  }

  /// Applied and saved: the widget can forget these.
  static Future<void> ackActions(List<String> ids) async {
    if (!_on || ids.isEmpty) return;
    try {
      await _ch.invokeMethod('ackActions', ids);
    } catch (e) {
      debugPrint('widget ack: $e');
    }
  }

  /// From the widget's quick-add window: queue an add for the app to apply.
  static Future<void> enqueue(Map<String, dynamic> action) async {
    if (!_on) return;
    try {
      await _ch.invokeMethod('enqueue', jsonEncode(action));
    } catch (e) {
      debugPrint('widget enqueue: $e');
    }
  }

  /// The quick-add window's starting mode ('task' | 'event' | 'spend').
  static Future<String?> quickMode() async {
    if (!_on) return null;
    try {
      return await _ch.invokeMethod<String>('quickMode');
    } catch (_) {
      return null;
    }
  }

  /// Background worker: done for now, the widget can let it go.
  static Future<void> idle() async {
    if (!_on) return;
    try {
      await _ch.invokeMethod('idle');
    } catch (_) {}
  }

  // ---------- snapshot ----------

  /// The widget steps a week back to five weeks ahead, so it gets events (and
  /// repeat occurrences) for that window, open tasks due in it (and overdue
  /// ones), tasks ticked off in it, and what was spent or earned up to today.
  static String snapshot(AppData s) {
    final now = nowMs();
    final today = sod(now), from = addDays(today, -8), to = addDays(today, 38);
    final m = s.money;
    String cash(int minor, {bool sign = false}) => fmtMoney(minor, m.currency, sign: sign);
    final tasks = {for (final t in s.tasks) t.id: t};

    // Same rule as AppState.linkDone: a repeating task is done for days before its due day.
    bool linkDone(Task t, String day) => t.repeat.isEmpty ? t.done : (t.due.isNotEmpty && day.compareTo(t.due) < 0);

    final fromDay = dstr(from), toDay = dstr(to);
    // A done copy of a repeating task can't be un-ticked from the widget (that would duplicate it).
    final repeating = {for (final t in s.tasks) if (!t.done && t.repeat.isNotEmpty) '${t.cat}|${t.title}'};

    final days = <String, Map<String, dynamic>>{};
    final spentBy = <String, int>{}, inBy = <String, int>{};
    final txns = <Map<String, dynamic>>[];
    for (final t in m.txns) {
      if (t.at < from || t.at >= addDays(today, 1) || t.isMove) continue;
      final day = dstr(t.at);
      final c = m.catOf(t.cat);
      final spend = spendOf(t, m);
      spentBy[day] = (spentBy[day] ?? 0) + spend;
      if (t.income) inBy[day] = (inBy[day] ?? 0) + t.amount;
      final plus = t.income || t.type == 'refund';
      txns.add({
        'id': t.id,
        'title': t.title.trim().isEmpty ? c.name : t.title.trim(),
        'emoji': c.emoji,
        'cat': c.name,
        'at': t.at,
        'amt': '${plus ? '+' : ''}${cash(t.amount)}',
        'plus': plus,
      });
    }
    for (final day in {...spentBy.keys, ...inBy.keys}) {
      final sp = spentBy[day] ?? 0, inc = inBy[day] ?? 0;
      days[day] = {
        if (sp != 0) 'spent': cash(sp),
        if (inc != 0) 'in': '+${cash(inc)}',
      };
    }

    return jsonEncode({
      'v': 2,
      'theme': s.settings.theme,
      'from': from,
      'to': to,
      'lines': [
        for (final l in s.lines) {'id': l.id, 'label': l.label, 'color': l.color, 'name': l.name},
      ],
      'events': [
        for (final e in occurrences(s, from, to))
          {
            'id': e.id,
            'title': e.title,
            'loc': e.loc,
            'start': e.start,
            'end': e.end,
            'allDay': e.allDay,
            'cat': e.cat,
            'rep': e.seriesId != null,
            ..._link(e, tasks, linkDone, cash),
          },
      ],
      'tasks': [
        for (final t in s.tasks)
          if ((!t.done && t.due.isNotEmpty && t.due.compareTo(toDay) < 0) || (t.done && t.doneAt >= from && dstr(t.doneAt).compareTo(fromDay) >= 0))
            {
              'id': t.id,
              'title': t.title,
              'cat': t.cat,
              'due': t.due,
              'time': ?t.time,
              if (t.star) 'star': true,
              if (t.done) 'doneDay': dstr(t.doneAt),
              if (t.repeat.isNotEmpty) 'rep': true,
              if (t.done && repeating.contains('${t.cat}|${t.title}')) 'noUndo': true,
              if (t.isBill) 'amt': cash(t.amount),
              'created': t.created,
            },
      ],
      'txns': txns,
      'days': days,
    });
  }

  /// A linked event's task: its tick (for this occurrence's day) and bill amount.
  static Map<String, dynamic> _link(Event e, Map<String, Task> tasks, bool Function(Task, String) done, String Function(int) cash) {
    final t = e.task == null ? null : tasks[e.task];
    if (t == null) return const {};
    return {
      'task': t.id,
      'done': done(t, dstr(e.start)),
      if (t.repeat.isNotEmpty) 'trep': true,
      if (t.isBill) 'amt': cash(t.amount),
    };
  }

  /// Asks the launcher to place the widget. False when it can't (then add it from the widget picker).
  static Future<bool> pin() async {
    if (!_on) return false;
    try {
      return await _ch.invokeMethod<bool>('pin') ?? false;
    } catch (_) {
      return false;
    }
  }
}
