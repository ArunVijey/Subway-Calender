// Data model. JSON layout matches the web app's `subway3` state so backups
// move between the web and native versions in both directions. Unknown keys
// are kept in `extra` and written back out untouched.
import 'package:characters/characters.dart';

import 'money.dart';
import 'tasks.dart';
import 'util.dart';

const kPalette = ['#1d6cf2', '#ff8a00', '#ff5a1f', '#ffd400', '#22c55e', '#e85ad8', '#14b8a6', '#8b5cf6'];
const kLetters = 'ABCDEFGH';

const kRepeat = {
  'daily': 'FREQ=DAILY',
  'weekdays': 'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR',
  'weekly': 'FREQ=WEEKLY',
  'monthly': 'FREQ=MONTHLY',
  'yearly': 'FREQ=YEARLY',
};
const kRepeatLabels = {
  '': 'Never',
  'daily': 'Every day',
  'weekdays': 'Every weekday',
  'weekly': 'Every week',
  'monthly': 'Every month',
  'yearly': 'Every year',
};

/// Reminder minutes → label. -1 = no alerts.
const kRemind = <int, String>{
  -1: 'No alerts',
  0: 'At departure',
  5: '5 min before',
  10: '10 min before',
  15: '15 min before',
  30: '30 min before',
  60: '1 hr before',
};

class Line {
  /// Fixed internal id (A–H) that events point to.
  String id;
  String name, color, kw;

  /// What the badge shows (1–2 characters); defaults to the id. Native-only.
  String label;

  Line({required this.id, required this.name, required this.color, required this.kw, String? label})
      : label = (label == null || label.trim().isEmpty) ? id : cleanLabel(label);

  Line copy() => Line(id: id, name: name, color: color, kw: kw, label: label);
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'color': color, 'kw': kw, if (label != id) 'label': label};
}

/// Badge text: trimmed, uppercase, at most 2 characters (emoji count as one).
String cleanLabel(String s) => s.trim().toUpperCase().characters.take(2).toString();

List<Line> defaultLines() => [
      Line(id: 'A', name: 'Work', color: kPalette[0], kw: 'meeting, sync, standup, review, call, 1:1, interview, client'),
      Line(id: 'B', name: 'Focus', color: kPalette[1], kw: 'focus, deep work, writing, coding, study, research'),
      Line(id: 'C', name: 'Deadlines', color: kPalette[2], kw: 'deadline, due, urgent, submit, launch, asap'),
      Line(id: 'D', name: 'Personal', color: kPalette[3], kw: 'errand, family, personal, home, bank'),
      Line(id: 'E', name: 'Health', color: kPalette[4], kw: 'gym, workout, run, doctor, dentist, yoga'),
      Line(id: 'F', name: 'Social', color: kPalette[5], kw: 'coffee, lunch, dinner, drinks, party, birthday'),
    ];

class Repeat {
  String freq, until; // until: '' or YYYY-MM-DD
  Repeat(this.freq, [this.until = '']);
  Map<String, dynamic> toJson() => {'freq': freq, 'until': until};
}

class Event {
  String id, title, loc, notes, link, cat, source;
  int start, end;
  bool allDay;
  String? key, feed;

  /// Google Calendar event id and calendar id (two-way sync).
  String? gid, calId;
  Repeat? repeat;
  List<int>? exdates;
  int? remind; // null = use the default

  /// Task this event was made with (quick add's "Also: calendar"). The two
  /// stay in step: same name, line, day and time; the task's tick shows here.
  String? task;
  bool catManual, dirty, dirtyNotes, sample;
  Map<String, dynamic> extra;

  // Set only on expanded repeat occurrences (never saved).
  String? seriesId;
  int? occKey;

  Event({
    required this.id,
    this.title = 'Untitled',
    this.loc = '',
    this.notes = '',
    this.link = '',
    required this.cat,
    this.source = 'local',
    required this.start,
    required this.end,
    this.allDay = false,
    this.key,
    this.feed,
    this.gid,
    this.calId,
    this.repeat,
    this.exdates,
    this.remind,
    this.task,
    this.catManual = false,
    this.dirty = false,
    this.dirtyNotes = false,
    this.sample = false,
    Map<String, dynamic>? extra,
    this.seriesId,
    this.occKey,
  }) : extra = extra ?? {};

  Event copy() => Event(
        id: id, title: title, loc: loc, notes: notes, link: link, cat: cat, source: source,
        start: start, end: end, allDay: allDay, key: key, feed: feed, gid: gid, calId: calId,
        repeat: repeat == null ? null : Repeat(repeat!.freq, repeat!.until),
        exdates: exdates == null ? null : List.of(exdates!), remind: remind, task: task,
        catManual: catManual, dirty: dirty, dirtyNotes: dirtyNotes, sample: sample,
        extra: Map.of(extra), seriesId: seriesId, occKey: occKey,
      );

  static const _known = {
    'id', 'title', 'loc', 'notes', 'link', 'cat', 'source', 'start', 'end', 'allDay', 'key', 'feed', 'gid', 'calId',
    'repeat', 'exdates', 'remind', 'task', 'catManual', 'dirty', 'dirtyNotes', 'sample', 'seriesId', 'occKey',
  };

  Map<String, dynamic> toJson() => {
        ...extra,
        'id': id, 'title': title, 'loc': loc, 'notes': notes, if (link.isNotEmpty) 'link': link,
        'cat': cat, 'source': source, 'start': start, 'end': end, 'allDay': allDay,
        'key': ?key, 'feed': ?feed, 'gid': ?gid, 'calId': ?calId,
        if (repeat != null) 'repeat': repeat!.toJson(),
        if (exdates != null) 'exdates': exdates,
        'remind': remind ?? '',
        'task': ?task,
        if (catManual) 'catManual': true,
        if (dirty) 'dirty': true,
        if (dirtyNotes) 'dirtyNotes': true,
        if (sample) 'sample': true,
      };
}

class Feed {
  String id, url;
  Feed(this.id, this.url);
  Map<String, dynamic> toJson() => {'id': id, 'url': url};
}

class GCal {
  String id, name;
  bool primary, writable, enabled;
  GCal({required this.id, required this.name, this.primary = false, this.writable = false, this.enabled = false});
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'primary': primary, 'writable': writable, 'enabled': enabled};
}

class Settings {
  /// 'none' | 'ical' (read-only links) | 'api' (Google Calendar two-way).
  String mode = 'none';
  List<Feed> feeds = [];

  /// Web OAuth client id, used as the server client id for Google sign-in.
  String clientId = '';
  List<GCal> calendars = [];
  String defaultCalId = 'primary';
  bool sound = true;
  bool notify = false;
  int remindDefault = 10;
  int lastSync = 0;
  String lastSyncMsg = '';
  String lastSyncError = '';

  /// 'system' | 'dark' | 'light'. Native-only.
  String theme = 'system';

  /// Light vibration on taps. Native-only.
  bool haptics = true;

  /// Board layout: 'day' (departure board) | 'week' (7-day agenda). Native-only.
  String view = 'day';

  /// The first-launch welcome has been answered. Native-only.
  bool welcomed = false;

  /// Automatic daily backup to a file the user picked (Android content URI).
  bool autoBackup = false;
  String backupUri = '', backupName = '';
  int lastBackup = 0, lastBackupTxns = 0;

  /// Money notifications: bills due (morning), the evening log nudge, budget alerts.
  bool billReminders = true, logReminder = true, budgetAlerts = true;

  /// Minutes after midnight for the bill heads-up and the evening nudge.
  int billTime = 9 * 60, logTime = 21 * 60;

  /// Money tab: net worth shown as dots (the eye by NET WORTH).
  bool hideNet = false;

  /// Today tab: the net-worth numbers and graph folded away (the arrow by NET
  /// WORTH there). Its own switch, separate from the Money tab's eye.
  bool foldTodayNet = false;
  Map<String, dynamic> extra = {};

  Map<String, dynamic> toJson() => {
        ...extra,
        'mode': mode,
        'feeds': feeds.map((f) => f.toJson()).toList(),
        'clientId': clientId,
        'calendars': calendars.map((c) => c.toJson()).toList(),
        'defaultCalId': defaultCalId,
        'sound': sound,
        'notify': notify,
        'remindDefault': remindDefault,
        'lastSync': lastSync,
        'lastSyncMsg': lastSyncMsg,
        'lastSyncError': lastSyncError,
        'theme': theme,
        'haptics': haptics,
        'view': view,
        'welcomed': welcomed,
        'autoBackup': autoBackup,
        'backupUri': backupUri,
        'backupName': backupName,
        'lastBackup': lastBackup,
        'lastBackupTxns': lastBackupTxns,
        'billReminders': billReminders,
        'logReminder': logReminder,
        'budgetAlerts': budgetAlerts,
        'billTime': billTime,
        'logTime': logTime,
        if (hideNet) 'hideNet': true,
        if (foldTodayNet) 'foldTodayNet': true,
      };
}

class AppData {
  int v = 3;
  List<Line> lines = defaultLines();
  List<Event> events = [];
  Map<String, int> hidden = {};
  List<dynamic> pendingDeletes = [];
  Map<String, dynamic> seriesProps = {};
  Settings settings = Settings();

  /// To-dos (native-only; web backups without them load as an empty list).
  List<Task> tasks = [];

  /// Budget, categories and transactions (native-only).
  Money money = Money();

  Map<String, dynamic> toJson() => {
        'v': v,
        'lines': lines.map((l) => l.toJson()).toList(),
        'events': events.map((e) => e.toJson()).toList(),
        'hidden': hidden,
        'pendingDeletes': pendingDeletes,
        'seriesProps': seriesProps,
        'settings': settings.toJson(),
        'tasks': tasks.map((t) => t.toJson()).toList(),
        'money': money.toJson(),
      };

  Line lineOf(String id) => lines.firstWhere((l) => l.id == id, orElse: () => lines.first);
}

// ---------- parsing / repair (port of normalize, normEvent, fromV2) ----------

num? _num(dynamic v) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v.trim());
  if (v is bool) return v ? 1 : 0;
  return null;
}

bool _truthy(dynamic v) => v != null && v != false && v != 0 && v != '';

String _str(dynamic v, String fallback) => v == null ? fallback : (v is String ? v : v.toString());

Event? normEvent(dynamic raw, Set<String> ids, String fallbackCat) {
  if (raw is! Map) return null;
  final e = Map<String, dynamic>.from(raw);
  final s = _num(e['start']);
  if (s == null || !s.isFinite) return null;
  var start = s.round();
  final en = _num(e['end']);
  var end = (en == null || !en.isFinite || en < s) ? start + kHour : en.round();
  final allDay = _truthy(e['allDay']);
  if (allDay) {
    final s0 = sod(start);
    final days = (((sod(end - 1) - s0) / kDay).round() + 1).clamp(1, 1 << 30);
    end = addDays(s0, days);
    start = s0;
  }
  Repeat? repeat;
  final r = e['repeat'];
  if (r is Map && kRepeat.containsKey(r['freq'])) repeat = Repeat(r['freq'] as String, _str(r['until'], ''));
  final rem = _num(e['remind']);
  final cat = e['cat'];
  final extra = Map<String, dynamic>.from(e)..removeWhere((k, _) => Event._known.contains(k));
  return Event(
    id: e['id'] == null ? uid() : e['id'].toString(),
    title: _str(e['title'], 'Untitled'),
    loc: _str(e['loc'], ''),
    notes: _str(e['notes'], ''),
    link: _str(e['link'], ''),
    cat: cat is String && ids.contains(cat) ? cat : fallbackCat,
    source: _truthy(e['source']) ? e['source'].toString() : 'local',
    start: start,
    end: end,
    allDay: allDay,
    key: e['key']?.toString(),
    feed: e['feed']?.toString(),
    gid: e['gid']?.toString(),
    calId: e['calId']?.toString(),
    repeat: repeat,
    exdates: e['exdates'] is List ? (e['exdates'] as List).map(_num).whereType<num>().map((n) => n.round()).toList() : null,
    remind: e['remind'] == '' ? null : rem?.round(),
    task: e['task'] is String && (e['task'] as String).isNotEmpty ? e['task'] as String : null,
    catManual: _truthy(e['catManual']),
    dirty: _truthy(e['dirty']),
    dirtyNotes: _truthy(e['dirtyNotes']),
    sample: _truthy(e['sample']),
    extra: extra,
  );
}

final _hex = RegExp(r'^#[0-9a-f]{6}$', caseSensitive: false);

AppData normalize(Map<String, dynamic>? s) {
  final d = AppData();
  if (s == null) return d;
  final ls = s['lines'];
  if (ls is List && ls.isNotEmpty) {
    final out = <Line>[];
    var i = 0;
    for (final l in ls) {
      if (l is Map && l['id'] is String && kLetters.contains(l['id']) && (l['id'] as String).length == 1) {
        final name = _truthy(l['name']) ? l['name'].toString() : 'Line ${l['id']}';
        final color = l['color'] is String && _hex.hasMatch(l['color']) ? l['color'] as String : kPalette[i % 8];
        out.add(Line(id: l['id'], name: clip(name, 24), color: color, kw: _truthy(l['kw']) ? l['kw'].toString() : '', label: l['label'] is String ? l['label'] : null));
      }
      i++;
    }
    if (out.isNotEmpty) d.lines = out;
  }
  final ids = d.lines.map((l) => l.id).toSet();
  final evs = s['events'];
  if (evs is List) d.events = evs.map((e) => normEvent(e, ids, d.lines.first.id)).whereType<Event>().toList();
  final h = s['hidden'];
  if (h is Map) d.hidden = h.map((k, v) => MapEntry(k.toString(), 1));
  if (s['pendingDeletes'] is List) d.pendingDeletes = List.of(s['pendingDeletes']);
  if (s['seriesProps'] is Map) d.seriesProps = Map<String, dynamic>.from(s['seriesProps']);
  if (s['tasks'] is List) d.tasks = (s['tasks'] as List).map((t) => taskFromJson(t, ids, d.lines.first.id)).whereType<Task>().toList();
  if (s.containsKey('money')) d.money = moneyFromJson(s['money']);

  final st = d.settings;
  final os = s['settings'];
  if (os is Map) {
    st.extra = Map<String, dynamic>.from(os)
      ..removeWhere((k, _) => const {'mode', 'feeds', 'clientId', 'calendars', 'defaultCalId', 'sound', 'notify', 'remindDefault', 'lastSync', 'lastSyncMsg', 'lastSyncError', 'theme', 'haptics', 'view', 'welcomed', 'autoBackup', 'backupUri', 'backupName', 'lastBackup', 'lastBackupTxns', 'billReminders', 'logReminder', 'budgetAlerts', 'billTime', 'logTime', 'hideNet', 'foldTodayNet'}.contains(k));
    st.mode = const ['ical', 'api'].contains(os['mode']) ? os['mode'] as String : 'none';
    st.clientId = _str(os['clientId'], '').trim();
    if (os['calendars'] is List) {
      st.calendars = [
        for (final c in os['calendars'])
          if (c is Map && c['id'] is String)
            GCal(id: c['id'], name: _str(c['name'], c['id']), primary: c['primary'] == true, writable: c['writable'] == true, enabled: c['enabled'] == true)
      ];
    }
    if (os['defaultCalId'] is String && (os['defaultCalId'] as String).isNotEmpty) st.defaultCalId = os['defaultCalId'];
    if (os['feeds'] is List) {
      st.feeds = [
        for (final f in os['feeds'])
          if (f is Map && f['url'] is String) Feed(_str(f['id'], 'f${uid()}'), f['url'])
      ];
    }
    if (os['sound'] is bool) st.sound = os['sound'];
    if (os['notify'] is bool) st.notify = os['notify'];
    final rd = _num(os['remindDefault']);
    if (rd != null && kRemind.containsKey(rd.round())) st.remindDefault = rd.round();
    st.lastSync = _num(os['lastSync'])?.round() ?? 0;
    st.lastSyncMsg = _str(os['lastSyncMsg'], '');
    st.lastSyncError = _str(os['lastSyncError'], '');
    if (const ['system', 'dark', 'light'].contains(os['theme'])) st.theme = os['theme'];
    if (os['haptics'] is bool) st.haptics = os['haptics'];
    if (const ['day', 'week', 'month'].contains(os['view'])) st.view = os['view'];
    if (os['autoBackup'] is bool) st.autoBackup = os['autoBackup'];
    st.backupUri = _str(os['backupUri'], '');
    st.backupName = _str(os['backupName'], '');
    st.lastBackup = _num(os['lastBackup'])?.round() ?? 0;
    st.lastBackupTxns = _num(os['lastBackupTxns'])?.round() ?? 0;
    if (os['billReminders'] is bool) st.billReminders = os['billReminders'];
    if (os['logReminder'] is bool) st.logReminder = os['logReminder'];
    if (os['budgetAlerts'] is bool) st.budgetAlerts = os['budgetAlerts'];
    final bt = _num(os['billTime'])?.round(), lt = _num(os['logTime'])?.round();
    if (bt != null && bt >= 0 && bt < 1440) st.billTime = bt;
    if (lt != null && lt >= 0 && lt < 1440) st.logTime = lt;
    st.hideNet = os['hideNet'] == true;
    st.foldTodayNet = os['foldTodayNet'] == true;
  }
  // Saved data (older installs, web backups) predates the welcome: don't show it again.
  st.welcomed = os is Map && os['welcomed'] is bool ? os['welcomed'] as bool : true;
  return d;
}

/// Older web backups (v2) stored lines as {A: 'name'} and keywords in settings.
Map<String, dynamic> fromV2(Map<String, dynamic> o) {
  final defs = defaultLines();
  final names = o['lines'] is Map ? o['lines'] as Map : const {};
  final kw = (o['settings'] is Map && o['settings']['keywords'] is Map) ? o['settings']['keywords'] as Map : const {};
  return {
    ...o,
    'lines': [
      for (var i = 0; i < 5; i++)
        {
          'id': defs[i].id,
          'name': names[defs[i].id] ?? defs[i].name,
          'color': kPalette[i],
          'kw': kw[defs[i].id] ?? defs[i].kw,
        }
    ],
  };
}
