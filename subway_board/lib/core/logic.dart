// Board logic that doesn't touch the UI: line matching, repeat occurrences,
// and merging imported/synced events into the store.
import 'ics.dart';
import 'model.dart';
import 'util.dart';

final _reEsc = RegExp(r'[.*+?^${}()|[\]\\]');

/// Picks the line whose keyword matches [title]/[loc] as a whole word; the
/// longest matching keyword wins. Null when nothing matches.
String? matchLine(AppData s, String? title, String? loc) {
  final text = ' ${title ?? ''} ${loc ?? ''} '.toLowerCase();
  String? best;
  var score = 0;
  for (final l in s.lines) {
    for (final w in l.kw.split(',').map((w) => w.trim().toLowerCase()).where((w) => w.isNotEmpty)) {
      if (w.length > score &&
          RegExp('(^|[^a-z0-9])${w.replaceAllMapped(_reEsc, (m) => '\\${m[0]}')}(\$|[^a-z0-9])').hasMatch(text)) {
        best = l.id;
        score = w.length;
      }
    }
  }
  return best;
}

String autoCat(AppData s, String? title, String? loc) => matchLine(s, title, loc) ?? s.lines.first.id;

final _meet = RegExp(
  r'''https?://[^\s<>"')]*(zoom\.us|meet\.google\.com|teams\.microsoft\.com|teams\.live\.com|webex\.com|whereby\.com|meet\.jit\.si)[^\s<>"')]*''',
  caseSensitive: false,
);

/// First video-call link found in the event's link, location or notes.
String? meetLink(Event ev) => _meet.firstMatch([ev.link, ev.loc, ev.notes].where((x) => x.isNotEmpty).join(' '))?[0];

/// Events from a read-only iCal link can only have their line and reminder changed.
bool isRO(AppData s, Event ev) => ev.source == 'ical' && s.settings.mode == 'ical';

/// All events and expanded repeat occurrences overlapping [from, to).
List<Event> occurrences(AppData s, int from, int to) {
  final out = <Event>[];
  for (final ev in s.events) {
    final rep = ev.repeat;
    if (rep != null && kRepeat.containsKey(rep.freq)) {
      if (ev.start > to) continue;
      final dur = ev.end - ev.start;
      final ex = (ev.exdates ?? const <int>[]).toSet();
      final starts = expand(ruleFor(ev), IcsDate(ev.allDay, wallL(ev.start), null), dur, Window(from, to));
      for (final st in starts) {
        final k = mkey(st);
        if (ex.contains(k)) continue;
        final e = ev.allDay ? addDays(st, (dur / kDay).round().clamp(1, 1 << 30)) : st + dur;
        if (st < to && e > from) {
          out.add(ev.copy()
            ..id = '${ev.id}::$k'
            ..seriesId = ev.id
            ..occKey = k
            ..start = st
            ..end = e);
        }
      }
    } else if (ev.start < to && (ev.end > from || ev.start >= from)) {
      out.add(ev);
    }
  }
  return out;
}

class MergeResult {
  final int added, updated, removed;
  const MergeResult(this.added, this.updated, this.removed);
}

/// Merges imported items into the store. Items are matched by key; a local
/// event with the same title and start is adopted instead of duplicated.
/// Hidden keys are skipped. With [reconcile], events from this source/feed
/// that are no longer present are removed.
MergeResult merge(AppData s, List<IcsItem> items, String source, String feed, bool reconcile) {
  final seen = <String>{};
  final byKey = <String, int>{};
  for (var i = 0; i < s.events.length; i++) {
    final k = s.events[i].key;
    if (k != null) byKey[k] = i;
  }
  var a = 0, u = 0, r = 0;
  for (final it in items) {
    seen.add(it.key);
    if (s.hidden.containsKey(it.key)) continue;
    final i = byKey[it.key] ??
        s.events.indexWhere((e) =>
            e.key == null &&
            (e.source == 'local' || e.source == 'legacy') &&
            e.repeat == null &&
            e.title == it.title &&
            (e.start - it.start).abs() < kMin);
    if (i >= 0) {
      final p = s.events[i];
      if (p.dirty) continue;
      if (p.source != source || p.title != it.title || p.loc != it.loc || p.notes != it.notes || p.start != it.start || p.end != it.end || p.allDay != it.allDay) {
        u++;
      }
      s.events[i] = p.copy()
        ..key = it.key
        ..title = it.title
        ..loc = it.loc
        ..notes = it.notes
        ..link = it.link
        ..start = it.start
        ..end = it.end
        ..allDay = it.allDay
        ..source = source
        ..feed = feed
        ..gid = it.gid ?? p.gid
        ..calId = it.calId ?? p.calId
        ..sample = false;
      byKey[it.key] = i;
    } else {
      // A repeating event created on this device keeps its line once Google expands it.
      final hint = it.gid != null ? s.seriesProps[it.gid!.split('_').first] : null;
      final h = hint is Map ? hint : const {};
      final hintCat = h['cat'] is String && s.lines.any((l) => l.id == h['cat']) ? h['cat'] as String : null;
      s.events.add(Event(
        id: uid(),
        cat: hintCat ?? autoCat(s, it.title, it.loc),
        catManual: h['catManual'] == true,
        remind: h['remind'] is num ? (h['remind'] as num).round() : null,
        gid: it.gid,
        calId: it.calId,
        key: it.key,
        title: it.title,
        loc: it.loc,
        notes: it.notes,
        link: it.link,
        start: it.start,
        end: it.end,
        allDay: it.allDay,
        source: source,
        feed: feed,
      ));
      byKey[it.key] = s.events.length - 1;
      a++;
    }
  }
  if (reconcile) {
    final b = s.events.length;
    s.events.removeWhere((e) => e.source == source && e.feed == feed && !e.dirty && !seen.contains(e.key));
    r = b - s.events.length;
  }
  return MergeResult(a, u, r);
}

/// Display name for an iCal feed URL (the calendar id for Google links).
String feedName(String url) {
  try {
    final u = Uri.parse(url.replaceFirst(RegExp(r'^webcal:', caseSensitive: false), 'https:'));
    final m = RegExp(r'/ical/([^/]+)').firstMatch(u.path);
    return m != null ? Uri.decodeComponent(m[1]!) : u.host;
  } catch (_) {
    return 'Calendar link';
  }
}
