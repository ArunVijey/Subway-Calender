// iCalendar parsing, RRULE expansion and export — a direct port of the web
// app's parseIcs / expand / toReal so imports produce identical events.
import 'package:timezone/timezone.dart' as tz;

import 'model.dart';
import 'util.dart';

/// Wall-clock components (month is 1-based).
class Wall {
  final int y, mo, d, h, mi, s;
  const Wall(this.y, this.mo, this.d, [this.h = 0, this.mi = 0, this.s = 0]);
}

/// The wall time read as if it were UTC ("naive" ms).
int naive(Wall w) => DateTime.utc(w.y, w.mo, w.d, w.h, w.mi, w.s).millisecondsSinceEpoch;

Wall wallN(int t) {
  final d = DateTime.fromMillisecondsSinceEpoch(t, isUtc: true);
  return Wall(d.year, d.month, d.day, d.hour, d.minute, d.second);
}

Wall wallL(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return Wall(d.year, d.month, d.day, d.hour, d.minute, d.second);
}

int _localMs(Wall w) => DateTime(w.y, w.mo, w.d, w.h, w.mi, w.s).millisecondsSinceEpoch;

/// Converts a wall time in [zone] (IANA name, 'UTC', or null = device local) to epoch ms.
int toReal(Wall w, String? zone, bool allDay) {
  if (allDay) return DateTime(w.y, w.mo, w.d).millisecondsSinceEpoch;
  if (zone == null) return _localMs(w);
  if (zone == 'UTC') return naive(w);
  try {
    final loc = tz.getLocation(zone);
    return tz.TZDateTime(loc, w.y, w.mo, w.d, w.h, w.mi, w.s).millisecondsSinceEpoch;
  } catch (_) {
    // Unknown zone (e.g. Windows names from Outlook): fall back to device time, like the web app.
    return _localMs(w);
  }
}

class Prop {
  final String name, value;
  final Map<String, String> params;
  const Prop(this.name, this.params, this.value);
}

class IcsDate {
  final bool allDay;
  final Wall w;
  final String? tz;
  const IcsDate(this.allDay, this.w, this.tz);
}

final _dateRe = RegExp(r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})?(Z)?)?$', caseSensitive: false);

IcsDate? pDate(Prop? prop, [String? dtz]) {
  if (prop == null) return null;
  final m = _dateRe.firstMatch(prop.value.trim());
  if (m == null) return null;
  final allDay = m[4] == null || prop.params['VALUE'] == 'DATE';
  int g(int i) => int.parse(m[i] ?? '0');
  return IcsDate(
    allDay,
    Wall(g(1), g(2), g(3), g(4), g(5), g(6)),
    allDay ? null : (m[7] != null ? 'UTC' : (prop.params['TZID'] ?? dtz)),
  );
}

final _durRe = RegExp(r'^([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$', caseSensitive: false);

int? pDur(String? v) {
  final m = _durRe.firstMatch((v ?? '').trim());
  if (m == null) return null;
  int g(int i) => int.parse(m[i] ?? '0');
  final ms = g(2) * 7 * kDay + g(3) * kDay + g(4) * kHour + g(5) * kMin + g(6) * 1000;
  return m[1] == '-' ? -ms : ms;
}

class Window {
  final int start, end;
  const Window(this.start, this.end);
}

/// Synced/imported events are kept from 30 days ago to a year ahead.
Window syncWin() {
  final now = nowMs();
  return Window(sod(now) - 30 * kDay, now + 365 * kDay);
}

const _wdn = {'SU': 0, 'MO': 1, 'TU': 2, 'WE': 3, 'TH': 4, 'FR': 5, 'SA': 6};

/// JS getUTCDay(): 0 = Sunday.
int _utcDay(int t) => DateTime.fromMillisecondsSinceEpoch(t, isUtc: true).weekday % 7;

/// Date.UTC(y, m, d) with 0-based month; overflow rolls over like JS.
int _utc(int y, int m, int d) => DateTime.utc(y, m + 1, d).millisecondsSinceEpoch;

/// Days in month (0-based month).
int _dim(int y, int m) => DateTime.utc(y, m + 2, 0).day;

class _ByDay {
  final int n, wd;
  const _ByDay(this.n, this.wd);
}

final _byDayRe = RegExp(r'^([+-]?\d+)?(MO|TU|WE|TH|FR|SA|SU)$', caseSensitive: false);

/// Expands an RRULE into occurrence start times (epoch ms) overlapping [win].
List<int> expand(String rs, IcsDate ds, int durMs, Window win) {
  final r = <String, String>{};
  for (final x in rs.split(';')) {
    final kv = x.split('=');
    if (kv.length >= 2 && kv[0].trim().isNotEmpty && kv[1].trim().isNotEmpty) r[kv[0].trim().toUpperCase()] = kv[1].trim();
  }
  if (!const ['DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY'].contains(r['FREQ'])) return [toReal(ds.w, ds.tz, ds.allDay)];
  final iv = (int.tryParse(r['INTERVAL'] ?? '') ?? 1).clamp(1, 1 << 30);
  final count = int.tryParse(r['COUNT'] ?? '') ?? 0;
  var until = double.infinity;
  if (r['UNTIL'] != null) {
    final u = pDate(Prop('UNTIL', const {}, r['UNTIL']!), ds.tz);
    if (u != null) until = (u.allDay ? addDays(toReal(u.w, null, true), 1) - 1 : toReal(u.w, u.tz, false)).toDouble();
  }
  final byDay = (r['BYDAY'] ?? '')
      .split(',')
      .map((s) => _byDayRe.firstMatch(s.trim()))
      .whereType<RegExpMatch>()
      .map((m) => _ByDay(int.parse(m[1] ?? '0'), _wdn[m[2]!.toUpperCase()]!))
      .toList();
  final byMD = (r['BYMONTHDAY'] ?? '').split(',').map((s) => int.tryParse(s.trim()) ?? 0).where((n) => n != 0 && n.abs() <= 31).toList();
  final byM = (r['BYMONTH'] ?? '').split(',').map((s) => int.tryParse(s.trim()) ?? 0).where((n) => n >= 1 && n <= 12).toList();

  final s0 = naive(ds.w);
  final sd = DateTime.fromMillisecondsSinceEpoch(s0, isUtc: true);
  final day0 = DateTime.utc(sd.year, sd.month, sd.day).millisecondsSinceEpoch;
  final tod = s0 - day0;
  final lo = win.start - 2 * kDay, hi = win.end + 2 * kDay;
  final out = <int>[];
  var n = 0;

  bool emit(int t) {
    if (t < s0) return true;
    n++;
    if ((count > 0 && n > count) || t > hi || t > until + 2 * kDay) return false;
    if (t + durMs < lo) return true;
    final real = toReal(wallN(t), ds.tz, ds.allDay);
    if (real > until) return false;
    out.add(real);
    return true;
  }

  List<int> mDays(int y, int m) {
    final len = _dim(y, m);
    final set = <int>{};
    if (byMD.isNotEmpty) {
      for (final d in byMD) {
        final x = d > 0 ? d : len + d + 1;
        if (x >= 1 && x <= len) set.add(x);
      }
    } else if (byDay.isNotEmpty) {
      final f = _utcDay(_utc(y, m, 1)), l = _utcDay(_utc(y, m, len));
      for (final b in byDay) {
        final h = 1 + ((b.wd - f + 7) % 7);
        if (b.n == 0) {
          for (var d = h; d <= len; d += 7) {
            set.add(d);
          }
        } else if (b.n > 0) {
          final d = h + (b.n - 1) * 7;
          if (d <= len) set.add(d);
        } else {
          final d = len - ((l - b.wd + 7) % 7) + (b.n + 1) * 7;
          if (d >= 1) set.add(d);
        }
      }
    } else if (sd.day <= len) {
      set.add(sd.day);
    }
    return set.toList()..sort();
  }

  final sdWd = sd.weekday % 7;
  switch (r['FREQ']) {
    case 'DAILY':
      for (var k = 0; k < 100000; k++) {
        final t = day0 + k * iv * kDay + tod;
        final d = DateTime.fromMillisecondsSinceEpoch(t, isUtc: true);
        if (byM.isNotEmpty && !byM.contains(d.month)) continue;
        if (byDay.isNotEmpty && !byDay.any((b) => b.wd == d.weekday % 7)) continue;
        if (!emit(t)) break;
      }
    case 'WEEKLY':
      final offs = (byDay.isNotEmpty ? byDay.map((b) => b.wd) : [sdWd]).map((w) => (w + 6) % 7).toList()..sort();
      final ws = day0 - ((sdWd + 6) % 7) * kDay;
      wk:
      for (var w = 0; w < 20000; w++) {
        for (final o in offs) {
          if (!emit(ws + w * iv * 7 * kDay + o * kDay + tod)) break wk;
        }
      }
    case 'MONTHLY':
      final y0 = sd.year, m0 = sd.month - 1;
      mo:
      for (var k = 0; k < 6000; k++) {
        final a = m0 + k * iv, y = y0 + a ~/ 12, m = a % 12;
        if (byM.isNotEmpty && !byM.contains(m + 1)) continue;
        for (final d in mDays(y, m)) {
          if (!emit(_utc(y, m, d) + tod)) break mo;
        }
      }
    default: // YEARLY
      final ms = (byM.isNotEmpty ? byM.map((x) => x - 1).toList() : [sd.month - 1])..sort();
      yr:
      for (var k = 0; k < 400; k++) {
        final y = sd.year + k * iv;
        for (final m in ms) {
          final days = (byMD.isNotEmpty || byDay.isNotEmpty) ? mDays(y, m) : (sd.day <= _dim(y, m) ? [sd.day] : <int>[]);
          for (final d in days) {
            if (!emit(_utc(y, m, d) + tod)) break yr;
          }
        }
      }
  }
  return out;
}

/// One event (or occurrence) read from an .ics file or Google Calendar.
class IcsItem {
  final String key, title, loc, notes, link;
  final int start, end;
  final bool allDay;

  /// Set for Google Calendar items.
  final String? gid, calId;
  const IcsItem({
    required this.key,
    required this.title,
    required this.loc,
    required this.notes,
    required this.link,
    required this.start,
    required this.end,
    required this.allDay,
    this.gid,
    this.calId,
  });

  IcsItem withKey(String k) => IcsItem(key: k, title: title, loc: loc, notes: notes, link: link, start: start, end: end, allDay: allDay, gid: gid, calId: calId);

  Map<String, dynamic> toJson() => {'key': key, 'title': title, 'loc': loc, 'notes': notes, 'link': link, 'start': start, 'end': end, 'allDay': allDay};
}

class _VEvent {
  final List<Prop> props;
  final String uid;
  _VEvent(this.props) : uid = (props.where((p) => p.name == 'UID').firstOrNull?.value ?? '').trim();
  Prop? get(String n) => props.where((p) => p.name == n).firstOrNull;
  Iterable<Prop> all(String n) => props.where((p) => p.name == n);
  String? val(String n) => get(n)?.value;
}

final _veventRe = RegExp(r'BEGIN:VEVENT\n([\s\S]*?)\nEND:VEVENT');
final _valarmRe = RegExp(r'BEGIN:VALARM[\s\S]*?END:VALARM\n?');

String _unesc(String? v) => (v ?? '')
    .replaceAll(RegExp(r'\\n', caseSensitive: false), '\n')
    .replaceAllMapped(RegExp(r'\\([,;\\])'), (m) => m[1]!)
    .trim();

List<IcsItem> parseIcs(String text) {
  final src = text.replaceAll(RegExp(r'\r\n?'), '\n').replaceAll(RegExp(r'\n[ \t]'), '');
  final win = syncWin();
  final out = <IcsItem>[];

  final evs = _veventRe.allMatches(src).map((m) {
    final props = <Prop>[];
    for (final line in m[1]!.replaceAll(_valarmRe, '').split('\n')) {
      var i = 0;
      var q = false;
      for (; i < line.length; i++) {
        if (line[i] == '"') {
          q = !q;
        } else if (line[i] == ':' && !q) {
          break;
        }
      }
      if (i >= line.length) continue;
      final parts = line.substring(0, i).split(';');
      final params = <String, String>{};
      for (final p in parts.skip(1)) {
        final k = p.indexOf('=');
        if (k > 0) params[p.substring(0, k).toUpperCase()] = p.substring(k + 1).replaceAll(RegExp(r'^"|"$'), '');
      }
      props.add(Prop(parts[0].toUpperCase(), params, line.substring(i + 1)));
    }
    return _VEvent(props);
  }).toList();

  // Moved/edited single occurrences (RECURRENCE-ID) replace the generated ones.
  final over = <String, Set<int>>{};
  for (final p in evs) {
    final r = pDate(p.get('RECURRENCE-ID'));
    if (r != null && p.uid.isNotEmpty) over.putIfAbsent(p.uid, () => {}).add(mkey(toReal(r.w, r.tz, r.allDay)));
  }

  void push(IcsItem it) {
    if (it.end >= win.start && it.start <= win.end) out.add(it);
  }

  for (final p in evs) {
    final dp = p.get('DTSTART');
    final ds = pDate(dp);
    if (ds == null || (p.val('STATUS') ?? '').trim().toUpperCase() == 'CANCELLED') continue;
    final t = _unesc(p.val('SUMMARY'));
    final title = t.isEmpty ? '(No title)' : t;
    final loc = _unesc(p.val('LOCATION'));
    final notes = clip(_unesc(p.val('DESCRIPTION')), 2000);
    final link = (p.val('URL') ?? '').trim();
    final id = p.uid.isNotEmpty ? p.uid : '$title|${dp!.value}';
    final st = toReal(ds.w, ds.tz, ds.allDay);
    final de = pDate(p.get('DTEND'), ds.tz);
    final du = pDur(p.val('DURATION'));
    var span = 1, dur = kHour;
    if (ds.allDay) {
      span = de != null
          ? ((naive(de.w) - naive(ds.w)) / kDay).round().clamp(1, 1 << 30)
          : du != null
              ? (du / kDay).round().clamp(1, 1 << 30)
              : 1;
      dur = span * kDay;
    } else if (de != null) {
      dur = (toReal(de.w, de.tz, de.allDay) - st).clamp(0, 1 << 52);
    } else if (du != null) {
      dur = du.clamp(0, 1 << 52);
    }
    IcsItem make(int s, String key) =>
        IcsItem(key: key, title: title, loc: loc, notes: notes, link: link, start: s, end: ds.allDay ? addDays(s, span) : s + dur, allDay: ds.allDay);

    final ridProp = p.get('RECURRENCE-ID');
    final rule = p.val('RRULE');
    if (ridProp != null) {
      final rid = pDate(ridProp);
      push(make(st, '$id#${mkey(rid != null ? toReal(rid.w, rid.tz, rid.allDay) : st)}'));
    } else if (rule != null) {
      final ex = <int>{};
      for (final x in p.all('EXDATE')) {
        for (final v in x.value.split(',')) {
          final d = pDate(Prop('EXDATE', x.params, v), ds.tz);
          if (d != null) ex.add(mkey(toReal(d.w, d.tz, d.allDay)));
        }
      }
      final ov = over[id] ?? const <int>{};
      for (final o in expand(rule, ds, dur, win)) {
        final k = mkey(o);
        if (!ex.contains(k) && !ov.contains(k)) push(make(o, '$id#$k'));
      }
    } else {
      push(make(st, id));
    }
  }
  return out;
}

// ---------- local repeats ----------

/// RRULE for a local repeating event. [forExport] writes UNTIL as a UTC
/// timestamp for timed events (RFC 5545 requires it when DTSTART is UTC).
String ruleFor(Event ev, {bool forExport = false}) {
  var r = kRepeat[ev.repeat!.freq]!;
  final u = ev.repeat!.until;
  if (u.isNotEmpty) {
    r += ';UNTIL=${forExport && !ev.allDay ? _utcStamp(addDays(dms(u), 1) - 1000) : u.replaceAll('-', '')}';
  }
  return r;
}

String _utcStamp(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  return '${d.year.toString().padLeft(4, '0')}${pad(d.month)}${pad(d.day)}T${pad(d.hour)}${pad(d.minute)}${pad(d.second)}Z';
}

String _dateOnly(int ms) => dstr(ms).replaceAll('-', '');

// ---------- export ----------

String exportIcs(AppData s) {
  String e(String v) => v.replaceAll('\\', '\\\\').replaceAll(RegExp(r'\r?\n'), '\\n').replaceAllMapped(RegExp(r'([,;])'), (m) => '\\${m[1]}');
  String fold(String l) {
    final p = <String>[];
    while (l.length > 73) {
      p.add(l.substring(0, 73));
      l = ' ${l.substring(73)}';
    }
    p.add(l);
    return p.join('\r\n');
  }

  final out = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//SubwayBoard//EN'];
  final stamp = _utcStamp(nowMs());
  for (final ev in s.events) {
    out.addAll(['BEGIN:VEVENT', 'UID:${(ev.key ?? ev.id).replaceAll(RegExp(r'[\r\n]'), '')}@subwayboard', 'DTSTAMP:$stamp']);
    out.addAll(ev.allDay
        ? ['DTSTART;VALUE=DATE:${_dateOnly(ev.start)}', 'DTEND;VALUE=DATE:${_dateOnly(ev.end)}']
        : ['DTSTART:${_utcStamp(ev.start)}', 'DTEND:${_utcStamp(ev.end)}']);
    if (ev.repeat != null) {
      out.add('RRULE:${ruleFor(ev, forExport: true)}');
      final ex = ev.exdates;
      if (ex != null && ex.isNotEmpty) {
        out.add(ev.allDay
            ? 'EXDATE;VALUE=DATE:${ex.map((k) => _dateOnly(k * kMin)).join(',')}'
            : 'EXDATE:${ex.map((k) => _utcStamp(k * kMin)).join(',')}');
      }
    }
    out.add('SUMMARY:${e(ev.title)}');
    if (ev.loc.isNotEmpty) out.add('LOCATION:${e(ev.loc)}');
    if (ev.notes.isNotEmpty) out.add('DESCRIPTION:${e(ev.notes)}');
    out.addAll(['CATEGORIES:${e(s.lineOf(ev.cat).name)}', 'END:VEVENT']);
  }
  out.add('END:VCALENDAR');
  return '${out.map(fold).join('\r\n')}\r\n';
}
