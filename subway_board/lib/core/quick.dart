// Quick add: reads a date, time, repeat, duration, amount, #line/#category and
// a star out of one line of text, and leaves the rest as the title.
//   "Pay rent ₹15000 1st monthly"   → bill, due the 1st, repeats monthly
//   "Gym tomorrow 6pm for 1h"        → event
//   "Lunch 180"                      → spend under Food
//   "Laptop service 3pm 3700"        → task (+ calendar slot, + ₹3,700 when done)
import 'logic.dart';
import 'model.dart';
import 'money.dart';
import 'util.dart';

enum QMode { task, event, spend }

enum QKind { date, time, repeat, dur, amount, line, mcat, star }

/// One thing the parser recognised; shown as a chip under the field.
class QToken {
  final QKind kind;
  final String text; // the words it came from
  const QToken(this.kind, this.text);
}

class Quick {
  String title = '';
  String? due; // YYYY-MM-DD
  int? time; // minutes after midnight
  int? dur; // minutes
  String? repeat;
  int? amount; // minor units
  String? line; // line id
  String? mcat; // money category id
  bool star = false;
  bool income = false;
  final tokens = <QToken>[];
  bool has(QKind k) => tokens.any((t) => t.kind == k);
}

const _months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
const _wdays = {'mon': 1, 'tue': 2, 'wed': 3, 'thu': 4, 'fri': 5, 'sat': 6, 'sun': 7};

const _billWords = r'pay|paid|bill|rent|emi|recharge|fee|fees|subscription|due|renew';

/// A plain number at the very end of the text.
final _tailAmount = RegExp(r'\s(\d[\d,]*(?:\.\d{1,2})?\s*[kK]?)\s*$');

/// Words that make the number after them a count or a label, not money.
final _countWords = RegExp(
    r'^(chapter|chapters|ch|chap|page|pages|pg|pp|lesson|unit|week|day|days|room|no|num|part|step|steps|level|exercise|ex|q|question|questions|set|sets|rep|reps|x|lecture|lec|section|sec|problem|problems|hw|assignment|lab|floor|gate|platform|bus|route|flight|train|version|v|class|grade|top|km|m|kg|g|ml|l|min|mins|words|lines|slides|times|pushups|squats|steps|item|items|ticket|seat|batch|roll|id|pin|code|ext)\.?$',
    caseSensitive: false);

/// Parses [input]. Kinds in [ignore] are left in the title (the user tapped
/// that chip away). [now] is the clock; spends read dates as past, plans as future.
Quick parseQuick(String input, QMode mode, AppData s, Money money, {Set<QKind> ignore = const {}, int? now}) {
  final q = Quick();
  final t0 = sod(now ?? nowMs());
  final past = mode == QMode.spend;
  var text = ' ${input.replaceAll(RegExp(r'\s+'), ' ')} ';

  /// Finds [re] once; on a match, records it and blanks it out of the text.
  bool take(QKind kind, RegExp re, bool Function(RegExpMatch m) use) {
    if (ignore.contains(kind) || q.has(kind)) return false;
    for (final m in re.allMatches(text)) {
      if (use(m)) {
        q.tokens.add(QToken(kind, m[0]!.trim()));
        text = text.replaceRange(m.start, m.end, ' ');
        return true;
      }
    }
    return false;
  }

  String day(DateTime d) => dstr(d.millisecondsSinceEpoch);
  final today = DateTime.fromMillisecondsSinceEpoch(t0);

  // A calendar date that's already gone means next year for plans, this year for spends.
  String fixYear(int month, int dayN) {
    var d = DateTime(today.year, month, dayN);
    if (d.month != month) return '';
    if (!past && d.isBefore(today)) d = DateTime(today.year + 1, month, dayN);
    if (past && d.isAfter(today)) d = DateTime(today.year - 1, month, dayN);
    return day(d);
  }

  // ---------- repeat ----------
  if (mode != QMode.spend) {
    take(QKind.repeat, RegExp(r'\s(every\s*day|daily|every\s*week\s*days?|weekdays|every\s*week|weekly|every\s*month|monthly|every\s*year|yearly|annually)(?=\s)', caseSensitive: false), (m) {
      final w = m[1]!.toLowerCase().replaceAll(RegExp(r'\s'), '');
      q.repeat = w.contains('weekday')
          ? 'weekdays'
          : (w.contains('day') || w == 'daily')
              ? 'daily'
              : (w.contains('week'))
                  ? 'weekly'
                  : (w.contains('month'))
                      ? 'monthly'
                      : 'yearly';
      return true;
    });
  }

  // ---------- date ----------
  final dateRes = <(RegExp, String? Function(RegExpMatch))>[
    (RegExp(r'\s(?:on\s+|by\s+)?(today|tonight|tod)(?=\s)', caseSensitive: false), (m) => day(today)),
    (RegExp(r'\s(?:on\s+|by\s+)?(tomorrow|tmrw|tmr)(?=\s)', caseSensitive: false), (m) => day(DateTime(today.year, today.month, today.day + 1))),
    (RegExp(r'\s(yesterday|yday)(?=\s)', caseSensitive: false), (m) => day(DateTime(today.year, today.month, today.day - 1))),
    (RegExp(r'\s(?:on\s+|by\s+)?next\s+week(?=\s)', caseSensitive: false), (m) => day(DateTime(today.year, today.month, today.day + 7))),
    (RegExp(r'\sin\s+(\d{1,3})\s*(days?|d|weeks?|w)(?=\s)', caseSensitive: false), (m) {
      final n = int.parse(m[1]!) * (m[2]!.toLowerCase().startsWith('w') ? 7 : 1);
      return day(DateTime(today.year, today.month, today.day + n));
    }),
    (RegExp(r'\s(?:on\s+|by\s+)?(\d{1,2})(?:st|nd|rd|th)?\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*(?=\s)', caseSensitive: false),
        (m) => _orNull(fixYear(_months.indexOf(m[2]!.toLowerCase().substring(0, 3)) + 1, int.parse(m[1]!)))),
    (RegExp(r'\s(?:on\s+|by\s+)?(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\s+(\d{1,2})(?:st|nd|rd|th)?(?=\s)', caseSensitive: false),
        (m) => _orNull(fixYear(_months.indexOf(m[1]!.toLowerCase().substring(0, 3)) + 1, int.parse(m[2]!)))),
    (RegExp(r'\s(?:on\s+|by\s+)?(\d{1,2})/(\d{1,2})(?=\s)'), (m) {
      final dd = int.parse(m[1]!), mm = int.parse(m[2]!);
      return mm >= 1 && mm <= 12 ? _orNull(fixYear(mm, dd)) : null;
    }),
    // "1st", "15th": that day of this month (or next, for plans).
    (RegExp(r'\s(?:on\s+(?:the\s+)?|by\s+(?:the\s+)?)?(\d{1,2})(st|nd|rd|th)(?=\s)', caseSensitive: false), (m) {
      final n = int.parse(m[1]!);
      if (n < 1 || n > 31) return null;
      var d = DateTime(today.year, today.month, n);
      if (!past && d.isBefore(today)) d = DateTime(today.year, today.month + 1, n);
      if (past && d.isAfter(today)) d = DateTime(today.year, today.month - 1, n);
      return day(d);
    }),
    (RegExp(r'\s(?:on\s+|by\s+)?(next\s+|this\s+|last\s+)?(mon|tue|tues|wed|thu|thur|thurs|fri|sat|sun)(?:day|sday|nesday|rsday|urday)?(?=\s)', caseSensitive: false), (m) {
      final wd = _wdays[m[2]!.toLowerCase().substring(0, 3)]!;
      final mod = (m[1] ?? '').trim().toLowerCase();
      var diff = (wd - today.weekday) % 7;
      if (past || mod == 'last') {
        diff = -((today.weekday - wd) % 7);
        if (mod == 'last' && diff == 0) diff = -7;
      } else if (mod == 'next' && diff == 0) {
        diff = 7;
      }
      return day(DateTime(today.year, today.month, today.day + diff));
    }),
  ];
  for (final (re, fn) in dateRes) {
    if (take(QKind.date, re, (m) {
      final d = fn(m);
      if (d == null) return false;
      q.due = d;
      return true;
    })) {
      break;
    }
  }

  // ---------- time ----------
  if (mode != QMode.spend) {
    final timeRes = <(RegExp, int? Function(RegExpMatch))>[
      (RegExp(r'\s(?:at\s+|@\s*)?(\d{1,2})(?:[:.](\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)(?=\s)', caseSensitive: false), (m) {
        var h = int.parse(m[1]!);
        final mi = int.parse(m[2] ?? '0');
        if (h < 1 || h > 12 || mi > 59) return null;
        final pm = m[3]!.toLowerCase().startsWith('p');
        if (h == 12) h = 0;
        return (h + (pm ? 12 : 0)) * 60 + mi;
      }),
      (RegExp(r'\s(?:at\s+|@\s*)?([01]?\d|2[0-3])[:.]([0-5]\d)(?=\s)'), (m) => int.parse(m[1]!) * 60 + int.parse(m[2]!)),
      (RegExp(r'\s(?:at\s+)?(noon|midday)(?=\s)', caseSensitive: false), (m) => 12 * 60),
      (RegExp(r'\s(?:at\s+)?midnight(?=\s)', caseSensitive: false), (m) => 0),
      // "at 5": before 8 means the evening.
      (RegExp(r'\s(?:at|@)\s*(\d{1,2})(?=\s)', caseSensitive: false), (m) {
        final h = int.parse(m[1]!);
        if (h > 23) return null;
        return (h >= 1 && h < 8 ? h + 12 : h) * 60;
      }),
    ];
    for (final (re, fn) in timeRes) {
      if (take(QKind.time, re, (m) {
        final v = fn(m);
        if (v == null) return false;
        q.time = v;
        return true;
      })) {
        break;
      }
    }
  }

  // ---------- duration (events) ----------
  if (mode != QMode.spend) {
    // A task needs the "for" ("Study for 2h"), so "Run 5 km in 1h" stays a title.
    final f = mode == QMode.event ? r'(?:for\s+)?' : r'for\s+';
    take(QKind.dur, RegExp('\\s$f(\\d+(?:\\.\\d+)?)\\s*(h|hr|hrs|hour|hours)(?:\\s*(\\d{1,2})\\s*(?:m|min|mins))?(?=\\s)', caseSensitive: false), (m) {
      q.dur = (double.parse(m[1]!) * 60).round() + int.parse(m[3] ?? '0');
      return q.dur! > 0 && q.dur! <= 24 * 60;
    });
    take(QKind.dur, RegExp('\\s$f(\\d{1,3})\\s*(m|min|mins|minutes)(?=\\s)', caseSensitive: false), (m) {
      q.dur = int.parse(m[1]!);
      return q.dur! > 0;
    });
  }

  // ---------- #tags: a line, or a money category ----------
  for (final m in RegExp(r'\s#([\p{L}\p{N}_-]+)(?=\s)', unicode: true).allMatches(text).toList().reversed) {
    final tag = m[1]!.toLowerCase();
    bool starts(String name) => name.toLowerCase().replaceAll(' ', '').startsWith(tag);
    if (!ignore.contains(QKind.mcat) && q.mcat == null && (mode == QMode.spend || mode == QMode.task)) {
      final c = money.cats.where((c) => starts(c.name) || c.id == tag).firstOrNull;
      if (c != null && (mode == QMode.spend || !s.lines.any((l) => starts(l.name)))) {
        q.mcat = c.id;
        q.tokens.add(QToken(QKind.mcat, m[0]!.trim()));
        text = text.replaceRange(m.start, m.end, ' ');
        continue;
      }
    }
    if (!ignore.contains(QKind.line) && q.line == null && mode != QMode.spend) {
      final l = s.lines.where((l) => starts(l.name) || l.label.toLowerCase() == tag).firstOrNull;
      if (l != null) {
        q.line = l.id;
        q.tokens.add(QToken(QKind.line, m[0]!.trim()));
        text = text.replaceRange(m.start, m.end, ' ');
      }
    }
  }

  // ---------- star ----------
  if (mode == QMode.task) {
    take(QKind.star, RegExp(r'\s(!+|\*)(?=\s)'), (m) => q.star = true);
  }

  // ---------- amount ----------
  {
    // With a currency mark it's always money. A bare number: for spends and
    // bills anywhere; otherwise only closing the line ("Laptop service 3pm 3700").
    final marked = RegExp(r'\s(?:(₹|rs\.?|inr|\$|€|£)\s*(\d[\d,]*(?:\.\d{1,2})?\s*[kK]?)|(\d[\d,]*(?:\.\d{1,2})?)\s*(?:₹|rs\.?|inr|/-|bucks))(?=\s)', caseSensitive: false);
    final bare = RegExp(r'\s(\+)?(\d[\d,]*(?:\.\d{1,2})?\s*[kK]?)(?=\s)');
    final billy = RegExp('(^|\\s)($_billWords)(?=\\s)', caseSensitive: false).hasMatch(text);
    if (!take(QKind.amount, marked, (m) {
      final v = parseAmount(m[2] ?? m[3]!);
      if (v == null || v == 0) return false;
      q.amount = v;
      return true;
    })) {
      if (mode == QMode.spend || billy) {
        take(QKind.amount, bare, (m) {
          final v = parseAmount(m[2]!);
          if (v == null || v == 0) return false;
          if (mode != QMode.spend && v < 1000) return false; // "Read chapter 3" isn't a bill
          q.amount = v;
          if (m[1] != null) q.income = true;
          return true;
        });
      } else {
        take(QKind.amount, _tailAmount, (m) {
          final raw = m[1]!.trim();
          final v = parseAmount(raw);
          if (v == null || v < 10000) return false; // under 100: a count, not a price
          if (RegExp(r'^(19|20)\d\d$').hasMatch(raw)) return false; // a year
          final before = RegExp(r'(\S+)\s*$').firstMatch(text.substring(0, m.start))?[1];
          if (before != null && _countWords.hasMatch(before)) return false; // "Read page 120"
          q.amount = v;
          return true;
        });
      }
    }
  }
  if (mode == QMode.spend && RegExp(r'\s(salary|income|received|refund|got paid|cashback)(?=\s)', caseSensitive: false).hasMatch(text)) q.income = true;

  // ---------- what's left is the title ----------
  var title = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  title = title.replaceAll(RegExp(r'^(on|at|by|for|and|-|–|,|\.)\s+|\s+(on|at|by|for|and|the|-|–|,)$', caseSensitive: false), '').trim();
  title = title.replaceAll(RegExp(r'\s+(on|at|by|for)$', caseSensitive: false), '').trim();
  q.title = title;

  if (q.line == null && mode != QMode.spend && !ignore.contains(QKind.line)) q.line = matchLine(s, title, '');
  if (q.mcat == null && (mode == QMode.spend || q.amount != null) && !ignore.contains(QKind.mcat)) {
    q.mcat = matchMCat(money, title) ?? (mode == QMode.task && q.amount != null ? (money.cats.any((c) => c.id == 'bills') ? 'bills' : null) : null);
  }
  return q;
}

String? _orNull(String s) => s.isEmpty ? null : s;
