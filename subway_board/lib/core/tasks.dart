// Tasks: to-dos with an optional due date/time, line, repeat, subtasks and an
// optional amount (a bill: ticking it off logs the payment in Money).
import 'util.dart';

class SubTask {
  String id, title;
  bool done;
  SubTask({required this.id, required this.title, this.done = false});
  SubTask copy() => SubTask(id: id, title: title, done: done);
  Map<String, dynamic> toJson() => {'id': id, 't': title, if (done) 'd': true};
}

class Task {
  String id, title, notes, cat;

  /// Due day as YYYY-MM-DD, '' = no date (someday).
  String due;

  /// Minutes after midnight on the due day; null = any time that day.
  int? time;
  bool star, done;
  int doneAt, created;

  /// '' | daily | weekdays | weekly | biweekly | monthly | quarterly | yearly,
  /// or a custom rule 'c:N:U' / 'c:N:w:1,4' (every N days/weeks/months/years,
  /// weeks optionally on ISO weekdays). Completing a repeating task logs it as
  /// done and moves the task to its next due day.
  String repeat;

  /// The next due day counts from the day it's ticked off, not the due day.
  bool repFromDone;

  /// Last day the repeat runs (YYYY-MM-DD), '' = no end.
  String repUntil;

  /// Repeats left after this one; null = no limit.
  int? repLeft;

  /// 0 = none, 1 = highest … 3 = lowest.
  int prio;

  /// Reminders, in minutes before the due moment (the due time, or 9:00 on
  /// the due day for a task with no time). null = the old default: one at the
  /// due time when there is one.
  List<int>? remind;

  /// Bill amount in minor units (paise/cents); 0 = not a bill.
  int amount;

  /// Money category the payment is logged under ('' = auto).
  String mcat;

  /// Account the payment comes out of ('' = the default account).
  String acct;
  List<SubTask> subs;

  /// Ticking off this occurrence logged this transaction (removed on un-tick).
  String? txn;

  Task({
    required this.id,
    required this.title,
    this.notes = '',
    required this.cat,
    this.due = '',
    this.time,
    this.star = false,
    this.done = false,
    this.doneAt = 0,
    int? created,
    this.repeat = '',
    this.repFromDone = false,
    this.repUntil = '',
    this.repLeft,
    this.prio = 0,
    this.remind,
    this.amount = 0,
    this.mcat = '',
    this.acct = '',
    List<SubTask>? subs,
    this.txn,
  })  : created = created ?? nowMs(),
        subs = subs ?? [];

  Task copy() => Task(
        id: id, title: title, notes: notes, cat: cat, due: due, time: time, star: star, done: done,
        doneAt: doneAt, created: created, repeat: repeat, repFromDone: repFromDone, repUntil: repUntil, repLeft: repLeft,
        prio: prio, remind: remind == null ? null : List.of(remind!), amount: amount, mcat: mcat, acct: acct,
        subs: subs.map((s) => s.copy()).toList(), txn: txn,
      );

  bool get isBill => amount > 0;

  /// The reminders that actually fire (see [remind]).
  List<int> get reminders => remind ?? (time != null ? const [0] : const []);

  /// Moment a reminder [before] minutes ahead fires, or null without a date.
  int? remindAt(int before) {
    if (due.isEmpty) return null;
    final base = time == null ? dms(due) + kTaskDayBase * kMin : dueMs!;
    return base - before * kMin;
  }

  /// Due moment in ms (end of day when there's no time), or null without a date.
  int? get dueMs {
    if (due.isEmpty) return null;
    final d0 = dms(due);
    return time == null ? addDays(d0, 1) - 1 : d0 + time! * kMin;
  }

  bool overdue(int now) {
    if (done || due.isEmpty) return false;
    if (time == null) return due.compareTo(dstr(now)) < 0;
    return dueMs! < now;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        if (notes.isNotEmpty) 'notes': notes,
        'cat': cat,
        'due': due,
        'time': ?time,
        if (star) 'star': true,
        if (done) 'done': true,
        if (doneAt > 0) 'doneAt': doneAt,
        'created': created,
        if (repeat.isNotEmpty) 'repeat': repeat,
        if (repFromDone) 'repFromDone': true,
        if (repUntil.isNotEmpty) 'repUntil': repUntil,
        'repLeft': ?repLeft,
        if (prio > 0) 'prio': prio,
        'remind': ?remind,
        if (amount > 0) 'amount': amount,
        if (mcat.isNotEmpty) 'mcat': mcat,
        if (acct.isNotEmpty) 'acct': acct,
        if (subs.isNotEmpty) 'subs': subs.map((s) => s.toJson()).toList(),
        'txn': ?txn,
      };
}

const kTaskRepeats = ['daily', 'weekdays', 'weekly', 'biweekly', 'monthly', 'quarterly', 'yearly'];

/// Minutes after midnight that "on the day" means for a task with no time.
const kTaskDayBase = 9 * 60;

final _custom = RegExp(r'^c:([1-9]\d{0,2}):([dwmy])(?::([1-7](?:,[1-7]){0,6}))?$');

/// A custom repeat rule, or null for presets and ''.
({int n, String unit, List<int> days})? customRepeat(String r) {
  final m = _custom.firstMatch(r);
  if (m == null) return null;
  final days = m[3] == null ? <int>[] : (m[3]!.split(',').map(int.parse).toSet().toList()..sort());
  return (n: int.parse(m[1]!), unit: m[2]!, days: m[2] == 'w' ? days : <int>[]);
}

/// The rule as (every, unit, weekdays), presets included; null for ''.
({int n, String unit, List<int> days})? repeatParts(String r) => switch (r) {
      'daily' => (n: 1, unit: 'd', days: <int>[]),
      'weekdays' => (n: 1, unit: 'w', days: [1, 2, 3, 4, 5]),
      'weekly' => (n: 1, unit: 'w', days: <int>[]),
      'biweekly' => (n: 2, unit: 'w', days: <int>[]),
      'monthly' => (n: 1, unit: 'm', days: <int>[]),
      'quarterly' => (n: 3, unit: 'm', days: <int>[]),
      'yearly' => (n: 1, unit: 'y', days: <int>[]),
      _ => customRepeat(r),
    };

/// Builds a rule; simple ones come back as the matching preset.
String makeRepeat(int n, String unit, [List<int> days = const []]) {
  final d = (days.toSet().toList()..sort());
  if (unit != 'w') d.clear();
  if (n == 1 && unit == 'd') return 'daily';
  if (n == 1 && unit == 'w' && d.isEmpty) return 'weekly';
  if (n == 1 && unit == 'w' && d.length == 5 && d.first == 1 && d.last == 5) return 'weekdays';
  if (n == 2 && unit == 'w' && d.isEmpty) return 'biweekly';
  if (n == 1 && unit == 'm') return 'monthly';
  if (n == 3 && unit == 'm') return 'quarterly';
  if (n == 1 && unit == 'y') return 'yearly';
  return 'c:$n:$unit${d.isNotEmpty ? ':${d.join(',')}' : ''}';
}

bool isTaskRepeat(String r) => kTaskRepeats.contains(r) || _custom.hasMatch(r);

const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// "Daily", "Every 3 days", "Every 2 weeks on Tue, Fri"…
String repeatLabel(String r) {
  const presets = {
    '': 'Never',
    'daily': 'Daily',
    'weekdays': 'Weekdays',
    'weekly': 'Weekly',
    'biweekly': 'Every 2 weeks',
    'monthly': 'Monthly',
    'quarterly': 'Every 3 months',
    'yearly': 'Yearly',
  };
  if (presets.containsKey(r)) return presets[r]!;
  final c = customRepeat(r);
  if (c == null) return 'Repeats';
  const units = {'d': ('day', 'days'), 'w': ('week', 'weeks'), 'm': ('month', 'months'), 'y': ('year', 'years')};
  final u = units[c.unit]!;
  final base = c.n == 1 ? 'Every ${u.$1}' : 'Every ${c.n} ${u.$2}';
  return c.days.isEmpty ? base : '$base on ${c.days.map((d) => _dayNames[d - 1]).join(', ')}';
}

/// The whole rule in words: "Every 2 weeks on Tue, Fri · after it's done · until 31 Mar 2027".
String repeatSentence(Task t) {
  if (t.repeat.isEmpty) return 'Never';
  final parts = [repeatLabel(t.repeat)];
  if (t.repFromDone) parts.add('after it’s done');
  if (t.repUntil.isNotEmpty) parts.add('until ${monthDay(dms(t.repUntil))}');
  if (t.repLeft != null) parts.add(t.repLeft == 0 ? 'last one' : '${t.repLeft} more');
  return parts.join(' · ');
}

/// "1 day before", "At due time"… for a reminder [before] minutes ahead.
String remindLabel(int before, {required bool timed}) {
  if (!timed) {
    if (before == 0) return 'On the day';
    if (before == 10080) return '1 week before';
  }
  if (before == 0) return 'At due time';
  if (before % 1440 == 0) return before == 1440 ? '1 day before' : '${before ~/ 1440} days before';
  if (before % 60 == 0) return before == 60 ? '1 hr before' : '${before ~/ 60} hr before';
  return '$before min before';
}

/// Reminder choices offered: before a time, or (no time) days ahead at 9:00.
const kRemindTimed = [0, 10, 30, 60, 180, 1440];
const kRemindDay = [0, 1440, 2880, 10080];

num? _n(dynamic v) => v is num ? v : (v is String ? num.tryParse(v) : null);
final _day = RegExp(r'^\d{4}-\d{2}-\d{2}$');

Task? taskFromJson(dynamic raw, Set<String> lineIds, String fallbackCat) {
  if (raw is! Map) return null;
  final title = raw['title'];
  if (title is! String) return null;
  final t = _n(raw['time'])?.round();
  return Task(
    id: raw['id']?.toString() ?? uid(),
    title: title,
    notes: raw['notes'] is String ? raw['notes'] : '',
    cat: lineIds.contains(raw['cat']) ? raw['cat'] as String : fallbackCat,
    due: raw['due'] is String && _day.hasMatch(raw['due']) ? raw['due'] : '',
    time: t != null && t >= 0 && t < 1440 ? t : null,
    star: raw['star'] == true,
    done: raw['done'] == true,
    doneAt: _n(raw['doneAt'])?.round() ?? 0,
    created: _n(raw['created'])?.round(),
    repeat: raw['repeat'] is String && isTaskRepeat(raw['repeat']) ? raw['repeat'] : '',
    repFromDone: raw['repFromDone'] == true,
    repUntil: raw['repUntil'] is String && _day.hasMatch(raw['repUntil']) ? raw['repUntil'] : '',
    repLeft: _n(raw['repLeft'])?.round().clamp(0, 9999),
    prio: (_n(raw['prio'])?.round() ?? 0).clamp(0, 3),
    remind: raw['remind'] is List ? [for (final r in raw['remind']) if (r is num && r >= 0 && r <= 60 * 1440) r.round()] : null,
    amount: (_n(raw['amount'])?.round() ?? 0).clamp(0, 1 << 50),
    mcat: raw['mcat'] is String ? raw['mcat'] : '',
    acct: raw['acct'] is String ? raw['acct'] : '',
    subs: [
      if (raw['subs'] is List)
        for (final s in raw['subs'])
          if (s is Map && s['t'] is String) SubTask(id: s['id']?.toString() ?? uid(), title: s['t'], done: s['d'] == true),
    ],
    txn: raw['txn'] is String ? raw['txn'] : null,
  );
}

/// The next due day of a repeating task, after [from] (YYYY-MM-DD).
String nextDue(String from, String repeat) {
  final d = DateTime.fromMillisecondsSinceEpoch(dms(from));
  DateTime n;
  switch (repeat) {
    case 'daily':
      n = DateTime(d.year, d.month, d.day + 1);
    case 'weekdays':
      n = DateTime(d.year, d.month, d.day + 1);
      while (n.weekday > 5) {
        n = DateTime(n.year, n.month, n.day + 1);
      }
    case 'weekly':
      n = DateTime(d.year, d.month, d.day + 7);
    case 'biweekly':
      n = DateTime(d.year, d.month, d.day + 14);
    case 'monthly':
      n = _addMonths(d, 1);
    case 'quarterly':
      n = _addMonths(d, 3);
    case 'yearly':
      n = _addMonths(d, 12);
    default:
      final c = customRepeat(repeat);
      if (c == null) return from;
      switch (c.unit) {
        case 'd':
          n = DateTime(d.year, d.month, d.day + c.n);
        case 'm':
          n = _addMonths(d, c.n);
        case 'y':
          n = _addMonths(d, 12 * c.n);
        default:
          if (c.days.isEmpty) {
            n = DateTime(d.year, d.month, d.day + 7 * c.n);
          } else {
            // The next listed weekday, in every N-th week counted from this one.
            final week0 = DateTime(d.year, d.month, d.day - (d.weekday - 1));
            n = DateTime(d.year, d.month, d.day + 1);
            for (var i = 0; i < 7 * c.n + 7; i++) {
              final weeks = (DateTime.utc(n.year, n.month, n.day).difference(DateTime.utc(week0.year, week0.month, week0.day)).inDays) ~/ 7;
              if (c.days.contains(n.weekday) && weeks % c.n == 0) break;
              n = DateTime(n.year, n.month, n.day + 1);
            }
          }
      }
  }
  return dstr(n.millisecondsSinceEpoch);
}

/// Same day of month [m] months later, clamped to the month's last day (Jan 31 → Feb 28).
DateTime _addMonths(DateTime d, int m) {
  final last = DateTime(d.year, d.month + m + 1, 0).day;
  return DateTime(d.year, d.month + m, d.day > last ? last : d.day);
}

int _prioRank(Task t) => t.prio == 0 ? 9 : t.prio;

/// Sort: dated first by due moment, then priority, then starred, then newest.
int compareTasks(Task a, Task b) {
  final da = a.dueMs, db = b.dueMs;
  if (da != null && db != null && da != db) return da.compareTo(db);
  if ((da == null) != (db == null)) return da == null ? 1 : -1;
  final p = _prioRank(a).compareTo(_prioRank(b));
  if (p != 0) return p;
  if (a.star != b.star) return a.star ? -1 : 1;
  return b.created.compareTo(a.created);
}

/// Priority first (P1, P2, P3, none), then as [compareTasks].
int compareTasksByPrio(Task a, Task b) {
  final p = _prioRank(a).compareTo(_prioRank(b));
  return p != 0 ? p : compareTasks(a, b);
}

/// "Today", "Tomorrow", "Yesterday", "Fri", "Fri, Nov 28" or "Nov 28, 2027".
String dueLabel(String due, int now) {
  if (due.isEmpty) return '';
  final today = dstr(now);
  if (due == today) return 'Today';
  final d = dms(due);
  final diff = ((d - sod(now)) / kDay).round();
  if (diff == 1) return 'Tomorrow';
  if (diff == -1) return 'Yesterday';
  if (diff > 1 && diff < 7) return weekdayShort(d);
  final y = DateTime.fromMillisecondsSinceEpoch(d).year;
  return y == DateTime.fromMillisecondsSinceEpoch(now).year ? '${weekdayShort(d)}, ${monthDay(d)}' : '${monthDay(d)}, $y';
}

/// Minutes after midnight as a clock time.
String minLabel(int m, {bool use24h = false}) => fmtT(DateTime(2000, 1, 1, m ~/ 60, m % 60).millisecondsSinceEpoch, use24h: use24h);
