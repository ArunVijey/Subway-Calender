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

  /// '' | daily | weekdays | weekly | monthly | yearly. Completing a repeating
  /// task logs it as done and moves the task to its next due day.
  String repeat;

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
    this.amount = 0,
    this.mcat = '',
    this.acct = '',
    List<SubTask>? subs,
    this.txn,
  })  : created = created ?? nowMs(),
        subs = subs ?? [];

  Task copy() => Task(
        id: id, title: title, notes: notes, cat: cat, due: due, time: time, star: star, done: done,
        doneAt: doneAt, created: created, repeat: repeat, amount: amount, mcat: mcat, acct: acct,
        subs: subs.map((s) => s.copy()).toList(), txn: txn,
      );

  bool get isBill => amount > 0;

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
        if (amount > 0) 'amount': amount,
        if (mcat.isNotEmpty) 'mcat': mcat,
        if (acct.isNotEmpty) 'acct': acct,
        if (subs.isNotEmpty) 'subs': subs.map((s) => s.toJson()).toList(),
        'txn': ?txn,
      };
}

const kTaskRepeats = ['daily', 'weekdays', 'weekly', 'biweekly', 'monthly', 'quarterly', 'yearly'];

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
    repeat: kTaskRepeats.contains(raw['repeat']) ? raw['repeat'] : '',
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
      return from;
  }
  return dstr(n.millisecondsSinceEpoch);
}

/// Same day of month [m] months later, clamped to the month's last day (Jan 31 → Feb 28).
DateTime _addMonths(DateTime d, int m) {
  final last = DateTime(d.year, d.month + m + 1, 0).day;
  return DateTime(d.year, d.month + m, d.day > last ? last : d.day);
}

/// Sort: dated first by due moment, then starred, then newest.
int compareTasks(Task a, Task b) {
  final da = a.dueMs, db = b.dueMs;
  if (da != null && db != null && da != db) return da.compareTo(db);
  if ((da == null) != (db == null)) return da == null ? 1 : -1;
  if (a.star != b.star) return a.star ? -1 : 1;
  return b.created.compareTo(a.created);
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
