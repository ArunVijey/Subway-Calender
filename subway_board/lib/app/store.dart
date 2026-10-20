// App state: the saved data plus what's on screen. One ChangeNotifier, like
// the web app's global `S` and its render functions.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../core/google.dart';
import '../core/ics.dart';
import '../core/logic.dart';
import '../core/model.dart';
import '../core/util.dart';
import '../services/alerts.dart';
import '../services/google_auth.dart';

class ToastAction {
  final String label;
  final VoidCallback fn;
  const ToastAction(this.label, this.fn);
}

class ToastMsg {
  final String text;
  final ToastAction? action;
  final int seq;
  const ToastMsg(this.text, this.action, this.seq);
}

/// Values read from the Add/Edit form.
class FormValues {
  final String title, cat, loc, notes, repeat, until;
  final int start, end;
  final bool allDay;
  final int? remind;

  /// Google calendar to save to ('' = this device only). Two-way mode only.
  final String calId;
  const FormValues({
    required this.title,
    required this.cat,
    required this.loc,
    required this.notes,
    required this.start,
    required this.end,
    required this.allDay,
    required this.repeat,
    required this.until,
    required this.remind,
    this.calId = '',
  });
}

class AppState extends ChangeNotifier {
  AppState(this.alerts, this.google);

  final Alerts alerts;
  final GoogleAuth google;

  /// Device time zone (IANA), sent to Google with timed events.
  String localTz = 'UTC';
  AppData s = AppData();
  File? _file;

  // ---------- what's on screen ----------
  String sel = todayStr();
  String _lastToday = todayStr();
  String tab = 'board';
  String? activeCat;
  bool showAllDay = false;

  /// Bumped whenever the board should replay its flip-in animation.
  int boardEpoch = 0;

  /// The event (or repeat occurrence) open in the form; null = adding.
  Event? editing;

  /// Bumped each time the form is opened, so it reloads its fields.
  int formSeq = 0;
  bool syncing = false;
  bool use24h = false;
  ToastMsg? toast;
  int _toastSeq = 0;

  Timer? _tick, _syncTimer, _toastTimer, _alertsDebounce, _pushTimer;
  final _alerted = <String>{};

  // ---------- load / save ----------
  Future<void> load() async {
    final dir = await getApplicationDocumentsDirectory();
    _file = File('${dir.path}/subway3.json');
    try {
      if (await _file!.exists()) s = normalize(jsonDecode(await _file!.readAsString()) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('could not read saved data: $e');
      // Keep the unreadable file for recovery instead of overwriting it.
      try {
        await _file!.copy('${_file!.path}.corrupt-${nowMs()}');
      } catch (_) {}
    }
    await _write();
    try {
      localTz = (await FlutterTimezone.getLocalTimezone()).identifier;
    } catch (_) {}
    _tick = Timer.periodic(const Duration(seconds: 10), (_) => _onTick());
    _syncTimer = Timer.periodic(const Duration(minutes: 10), (_) => runSync());
    unawaited(_startSync());
    _scheduleAlerts();
    notifyListeners();
  }

  /// First sync after launch; for Google, quietly restores the last sign-in first.
  Future<void> _startSync() async {
    if (s.settings.mode == 'api' && s.settings.clientId.isNotEmpty) {
      await google.restore(s.settings.clientId);
      notifyListeners();
    }
    await runSync();
  }

  Future<void> _pending = Future.value();
  Future<void> _write() {
    final f = _file;
    if (f == null) return Future.value();
    final text = jsonEncode(s.toJson());
    // Writes are chained so they land in order; tmp + rename keeps the file whole.
    return _pending = _pending.then((_) async {
      try {
        final tmp = File('${f.path}.tmp');
        await tmp.writeAsString(text, flush: true);
        await tmp.rename(f.path);
      } catch (e) {
        debugPrint('save failed: $e');
        showToast('Could not save');
      }
    });
  }

  void save() {
    _write();
    _scheduleAlerts();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _syncTimer?.cancel();
    _toastTimer?.cancel();
    _alertsDebounce?.cancel();
    _pushTimer?.cancel();
    super.dispose();
  }

  // ---------- toast + undo ----------
  void showToast(String text, [ToastAction? action]) {
    toast = ToastMsg(text, action, ++_toastSeq);
    _toastTimer?.cancel();
    _toastTimer = Timer(Duration(milliseconds: action != null ? 5000 : 2600), () {
      toast = null;
      notifyListeners();
    });
    notifyListeners();
  }

  void runToastAction() {
    final a = toast?.action;
    toast = null;
    _toastTimer?.cancel();
    notifyListeners();
    a?.fn();
  }

  String snap() => jsonEncode({
        'events': s.events.map((e) => e.toJson()).toList(),
        'lines': s.lines.map((l) => l.toJson()).toList(),
        'hidden': s.hidden,
        'pendingDeletes': s.pendingDeletes,
      });

  /// Saves, redraws, and offers UNDO back to [snapshot].
  void commit(String snapshot, String msg) {
    save();
    boardEpoch++;
    showToast(
      msg,
      ToastAction('UNDO', () {
        _pushTimer?.cancel();
        final restored = normalize({...s.toJson(), ...jsonDecode(snapshot) as Map<String, dynamic>});
        s.events = restored.events;
        s.lines = restored.lines;
        s.hidden = restored.hidden;
        s.pendingDeletes = restored.pendingDeletes;
        if (activeCat != null && !s.lines.any((l) => l.id == activeCat)) activeCat = null;
        save();
        boardEpoch++;
        showToast('Undone');
      }),
    );
  }

  // ---------- navigation ----------
  void switchTab(String name) {
    if (name == 'add') {
      openForm(null);
      return;
    }
    tab = name;
    editing = null;
    if (name == 'board') boardEpoch++;
    notifyListeners();
  }

  void openForm(Event? view) {
    editing = view;
    formSeq++;
    tab = 'add';
    notifyListeners();
  }

  void setSel(String day) {
    sel = day;
    boardEpoch++;
    notifyListeners();
  }

  void shiftDay(int n) => setSel(dstr(addDays(dms(sel), n)));

  void toggleCat(String id) {
    activeCat = activeCat == id ? null : id;
    boardEpoch++;
    notifyListeners();
  }

  void showLine(String id) {
    activeCat = id;
    switchTab('board');
  }

  void toggleAllDay() {
    showAllDay = !showAllDay;
    boardEpoch++;
    notifyListeners();
  }

  void _onTick() {
    final t = todayStr();
    if (t != _lastToday) {
      if (sel == _lastToday) sel = t;
      _lastToday = t;
    }
    _checkAlerts();
    notifyListeners();
  }

  /// Called when the app comes back to the foreground.
  void resumed() {
    _onTick();
    _scheduleAlerts();
    if (nowMs() - s.settings.lastSync > 120000) runSync();
  }

  // ---------- lines ----------
  Line lineOf(String id) => s.lineOf(id);

  /// Id the next new line will get ('' when all 8 are used).
  String get nextLineId => kLetters.split('').firstWhere((L) => !s.lines.any((l) => l.id == L), orElse: () => '');

  void saveLine(String? editId, String name, String color, String kw, String label) {
    final sn = snap();
    if (editId != null) {
      final l = lineOf(editId);
      l
        ..name = name
        ..color = color
        ..kw = kw
        ..label = label.trim().isEmpty ? l.id : cleanLabel(label);
    } else {
      final id = nextLineId;
      if (id.isEmpty) return;
      s.lines.add(Line(id: id, name: name, color: color, kw: kw, label: label));
    }
    commit(sn, editId != null ? 'Line updated' : 'Line added');
  }

  void deleteLine(String id) {
    final others = s.lines.where((x) => x.id != id).toList();
    if (others.isEmpty) return;
    final sn = snap();
    for (final e in s.events) {
      if (e.cat == id) e.cat = others.first.id;
    }
    s.lines = others;
    if (activeCat == id) activeCat = null;
    commit(sn, 'Line deleted');
  }

  // ---------- events ----------
  Event? masterOf(Event view) {
    final id = view.seriesId ?? view.id;
    return s.events.where((e) => e.id == id).firstOrNull;
  }

  bool readOnly(Event ev) => isRO(s, ev);

  /// Port of saveForm(). Returns an error message, or null when saved.
  String? saveEvent(FormValues f) {
    final view = editing;
    final master = view != null ? masterOf(view) : null;
    if (view != null && master == null) {
      switchTab('board');
      return null;
    }
    if (f.title.isEmpty && !(master != null && isRO(s, master))) return 'Give it a name';
    final sn = snap();
    late Event ev;
    if (master != null && isRO(s, master)) {
      ev = master.copy()
        ..cat = f.cat
        ..catManual = true
        ..remind = f.remind;
    } else if (master != null) {
      ev = master.copy()
        ..title = f.title
        ..loc = f.loc
        ..notes = f.notes
        ..cat = f.cat
        ..allDay = f.allDay
        ..remind = f.remind
        ..catManual = master.catManual || f.cat != master.cat
        ..sample = false;
      if (view!.seriesId != null && f.repeat.isNotEmpty) {
        // Editing one occurrence moves the whole series by the same amount.
        final dayShift = ((sod(f.start) - sod(view.start)) / kDay).round();
        final base = DateTime.fromMillisecondsSinceEpoch(addDays(sod(master.start), dayShift));
        if (f.allDay) {
          ev.start = base.millisecondsSinceEpoch;
          ev.end = addDays(ev.start, ((f.end - f.start) / kDay).round().clamp(1, 1 << 30));
        } else {
          final fs = DateTime.fromMillisecondsSinceEpoch(f.start);
          ev.start = DateTime(base.year, base.month, base.day, fs.hour, fs.minute).millisecondsSinceEpoch;
          ev.end = ev.start + (f.end - f.start);
        }
        final shift = mkey(ev.start) - mkey(master.start);
        if (ev.exdates != null && shift != 0) ev.exdates = ev.exdates!.map((k) => k + shift).toList();
      } else {
        ev.start = f.start;
        ev.end = f.end;
      }
      if (master.source != 'gapi') {
        if (f.repeat.isNotEmpty) {
          ev.repeat = Repeat(f.repeat, f.until);
        } else {
          ev.repeat = null;
          ev.exdates = null;
        }
      }
      final changed = master.title != ev.title ||
          master.loc != ev.loc ||
          master.notes != ev.notes ||
          master.start != ev.start ||
          master.end != ev.end ||
          master.allDay != ev.allDay;
      if (s.settings.mode == 'api') {
        if (master.source == 'gapi' && changed) {
          ev.dirty = true;
          if (master.notes != ev.notes) ev.dirtyNotes = true;
        } else if (master.source != 'gapi' && f.calId.isNotEmpty) {
          ev
            ..dirty = true
            ..calId = f.calId;
        }
      }
    } else {
      ev = Event(
        id: uid(),
        source: 'local',
        title: f.title,
        cat: f.cat,
        loc: f.loc,
        notes: f.notes,
        start: f.start,
        end: f.end,
        allDay: f.allDay,
        remind: f.remind,
        catManual: true,
        repeat: f.repeat.isNotEmpty ? Repeat(f.repeat, f.until) : null,
      );
      if (s.settings.mode == 'api' && f.calId.isNotEmpty) {
        ev
          ..dirty = true
          ..calId = f.calId;
        s.settings.defaultCalId = f.calId;
      }
    }
    if (ev.dirty && ev.calId != null) {
      for (final c in s.settings.calendars) {
        if (c.id == ev.calId) c.enabled = true;
      }
    }
    s.events = master != null ? s.events.map((e) => identical(e, master) ? ev : e).toList() : [...s.events, ev];
    sel = dstr(f.start);
    tab = 'board';
    editing = null;
    commit(sn, master != null ? 'Saved' : 'Added to board');
    if (ev.dirty && google.connected) _schedulePush();
    return null;
  }

  /// Sends local changes to Google shortly after an edit (so UNDO can cancel it).
  void _schedulePush() {
    _pushTimer?.cancel();
    _pushTimer = Timer(const Duration(seconds: 6), () => runSync());
  }

  /// Whether deleting this event should ask "everywhere or just here".
  bool isGoogleEvent(Event ev) => ev.source == 'gapi' && ev.gid != null && s.settings.mode == 'api';

  /// Deletes the event open in the form. [choice] answers the confirmation:
  /// repeats: 'one' | 'all'; Google events: 'all' (everywhere) | 'hide'.
  void deleteEvent({String? choice}) {
    final view = editing;
    if (view == null) return;
    final master = masterOf(view);
    if (master == null) {
      switchTab('board');
      return;
    }
    final sn = snap();
    if (isRO(s, master)) {
      if (master.key != null) s.hidden[master.key!] = 1;
      s.events.remove(master);
    } else if (view.seriesId != null) {
      if (choice == 'one') {
        master.exdates = [...?master.exdates, view.occKey!];
      } else {
        s.events.remove(master);
      }
    } else if (isGoogleEvent(master)) {
      if (choice == 'all') s.pendingDeletes.add({'cal': master.calId ?? master.feed, 'gid': master.gid});
      s.hidden[master.key!] = 1;
      s.events.remove(master);
    } else {
      if (master.key != null) s.hidden[master.key!] = 1;
      s.events.remove(master);
    }
    tab = 'board';
    editing = null;
    commit(sn, 'Deleted');
    if (s.pendingDeletes.isNotEmpty && google.connected) _schedulePush();
  }

  void clearSamples() {
    final sn = snap();
    s.events.removeWhere((e) => e.sample);
    commit(sn, 'Samples cleared');
  }

  // ---------- settings ----------
  void setSound(bool v) {
    s.settings.sound = v;
    save();
    notifyListeners();
    if (v) alerts.chime(boarding: false);
  }

  Future<bool> setNotify(bool v) async {
    if (v && !await alerts.requestPermission()) {
      s.settings.notify = false;
      save();
      notifyListeners();
      return false;
    }
    s.settings.notify = v;
    save();
    notifyListeners();
    return true;
  }

  void setRemindDefault(int v) {
    s.settings.remindDefault = v;
    save();
    notifyListeners();
  }

  void setHaptics(bool v) {
    s.settings.haptics = v;
    save();
    notifyListeners();
  }

  void setTheme(String v) {
    s.settings.theme = v;
    save();
    notifyListeners();
  }

  /// Applies the sync section. Returns the number of events that would be
  /// orphaned by leaving iCal mode (the caller asks before removing them).
  static const _sourceOf = {'ical': 'ical', 'api': 'gapi'};

  int pendingModeSwitchCount(String mode) {
    final old = _sourceOf[s.settings.mode];
    if (mode == s.settings.mode || old == null) return 0;
    return s.events.where((e) => e.source == old).length;
  }

  void applySync(String mode, List<String> urls, String clientId, {bool removeOld = false}) {
    final st = s.settings;
    st.feeds = urls.map((u) => st.feeds.where((f) => f.url == u).firstOrNull ?? Feed('f${uid()}', u)).toList();
    st.clientId = clientId.trim();
    if (mode != st.mode) {
      final old = _sourceOf[st.mode];
      if (removeOld && old != null) s.events.removeWhere((e) => e.source == old);
      st
        ..mode = mode
        ..lastSync = 0
        ..lastSyncError = ''
        ..lastSyncMsg = '';
    }
    save();
    notifyListeners();
  }

  int get hiddenCount => s.hidden.length - s.pendingDeletes.length;

  void restoreHidden() {
    // Deletes still waiting to reach Google stay hidden.
    s.hidden = {
      for (final p in s.pendingDeletes)
        if (p is Map) 'g:${p['cal']}|${p['gid']}': 1
    };
    save();
    notifyListeners();
    if (s.settings.mode != 'none') runSync(manual: true);
  }

  // ---------- iCal sync ----------
  Future<String> fetchIcal(String raw) async {
    final url = raw.trim().replaceFirst(RegExp(r'^webcal:', caseSensitive: false), 'https:');
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(url)) throw 'not a calendar URL';
    final http.Response r;
    try {
      r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw 'timed out';
    } catch (_) {
      throw 'could not connect';
    }
    if (r.statusCode == 404) throw 'link not found (check that it is the secret iCal address)';
    if (r.statusCode != 200) throw 'error ${r.statusCode}';
    final text = utf8.decode(r.bodyBytes, allowMalformed: true);
    if (!RegExp('BEGIN:VCALENDAR', caseSensitive: false).hasMatch(text)) throw "didn't return calendar data";
    return text;
  }

  Future<void> runSync({bool manual = false}) async {
    final st = s.settings;
    if (syncing || st.mode == 'none') return;
    if (st.mode == 'api') return _runGoogleSync(manual);
    syncing = true;
    notifyListeners();
    try {
      if (st.feeds.isEmpty) throw 'Add an iCal link';
      var a = 0, u = 0, r = 0;
      final errs = <String>[];
      for (final f in List.of(st.feeds)) {
        try {
          final items = parseIcs(await fetchIcal(f.url)).map((it) => it.withKey('${f.id}:${it.key}')).toList();
          final m = merge(s, items, 'ical', f.id, true);
          a += m.added;
          u += m.updated;
          r += m.removed;
        } catch (e) {
          errs.add('${feedName(f.url)}: $e');
        }
      }
      final ids = st.feeds.map((f) => f.id).toSet();
      final b = s.events.length;
      s.events.removeWhere((e) => e.source == 'ical' && !ids.contains(e.feed));
      r += b - s.events.length;
      st
        ..lastSync = nowMs()
        ..lastSyncMsg = '$a new, $u updated, $r removed'
        ..lastSyncError = errs.join(' · ');
    } catch (e) {
      st.lastSyncError = e.toString();
    } finally {
      syncing = false;
      save();
      notifyListeners();
    }
  }

  // ---------- Google Calendar (two-way) ----------
  bool get gConnected => google.connected;

  /// Sign in (from a tap), refresh the calendar list and sync.
  Future<void> connectGoogle() async {
    await google.connect(s.settings.clientId);
    notifyListeners();
    try {
      await _gCalendarList();
    } catch (_) {}
    await runSync(manual: true);
  }

  Future<void> disconnectGoogle() async {
    await google.disconnect();
    notifyListeners();
  }

  void setCalendarEnabled(String id, bool on) {
    for (final c in s.settings.calendars) {
      if (c.id == id) c.enabled = on;
    }
    save();
    notifyListeners();
  }

  String _calPath(String calId) => '/calendars/${Uri.encodeComponent(calId)}/events';

  Future<List<IcsItem>> _gPull(String calId) async {
    final win = syncWin(), items = <IcsItem>[];
    var page = '';
    do {
      final q = {
        'timeMin': DateTime.fromMillisecondsSinceEpoch(win.start, isUtc: true).toIso8601String(),
        'timeMax': DateTime.fromMillisecondsSinceEpoch(win.end, isUtc: true).toIso8601String(),
        'singleEvents': 'true',
        'orderBy': 'startTime',
        'maxResults': '2500',
        if (page.isNotEmpty) 'pageToken': page,
      };
      final d = await google.api('${_calPath(calId)}?${Uri(queryParameters: q).query}');
      for (final ge in (d?['items'] as List? ?? const [])) {
        if (ge is Map<String, dynamic>) {
          final it = fromGoogle(ge, calId);
          if (it != null) items.add(it);
        }
      }
      page = (d?['nextPageToken'] as String?) ?? '';
    } while (page.isNotEmpty);
    return items;
  }

  Future<void> _gCalendarList() async {
    final d = await google.api('/users/me/calendarList?minAccessRole=reader&maxResults=250');
    final st = s.settings;
    final prev = {for (final c in st.calendars) c.id: c};
    st.calendars = [
      for (final c in (d?['items'] as List? ?? const []))
        if (c is Map && c['id'] is String)
          GCal(
            id: c['id'],
            name: (c['summaryOverride'] ?? c['summary'] ?? c['id']) as String,
            primary: c['primary'] == true,
            writable: c['accessRole'] == 'owner' || c['accessRole'] == 'writer',
            enabled: prev[c['id']]?.enabled ?? c['primary'] == true,
          )
    ];
    final prim = st.calendars.where((c) => c.primary).firstOrNull;
    if (prim != null && (st.defaultCalId == 'primary' || !st.calendars.any((c) => c.id == st.defaultCalId))) {
      final old = st.defaultCalId;
      st.defaultCalId = prim.id;
      // Events synced before the calendar list was known were filed under "primary".
      if (old == 'primary') {
        for (final e in s.events) {
          if (e.source == 'gapi' && e.feed == 'primary') {
            e
              ..feed = prim.id
              ..calId = prim.id
              ..key = 'g:${prim.id}|${e.gid}';
          }
        }
      }
    }
    save();
  }

  List<GCal> _enabledCals() {
    final st = s.settings;
    final list = st.calendars.where((c) => c.enabled).toList();
    if (!list.any((c) => c.id == st.defaultCalId)) {
      list.add(st.calendars.where((c) => c.id == st.defaultCalId).firstOrNull ?? GCal(id: st.defaultCalId, name: st.defaultCalId));
    }
    return list;
  }

  /// Sends edited/new events and pending deletes to Google.
  Future<void> _flushPending() async {
    for (final ev in s.events.where((e) => e.dirty).toList()) {
      final cal = ev.calId ?? s.settings.defaultCalId;
      final body = toGoogle(ev, localTz);
      if (ev.gid != null) {
        await google.api('${_calPath(cal)}/${Uri.encodeComponent(ev.gid!)}', method: 'PATCH', body: body, missingOk: true);
      } else {
        final c = await google.api(_calPath(cal), method: 'POST', body: body);
        final gid = c!['id'] as String;
        if (ev.repeat != null) {
          // Google expands the series; its instances come back on the pull with this line.
          s.seriesProps[gid] = {'cat': ev.cat, 'catManual': true, 'remind': ev.remind ?? ''};
          s.events.remove(ev);
          save();
          continue;
        }
        ev
          ..gid = gid
          ..calId = cal
          ..feed = cal
          ..key = 'g:$cal|$gid'
          ..source = 'gapi';
      }
      ev
        ..dirty = false
        ..dirtyNotes = false;
      save();
    }
    for (final p in List.of(s.pendingDeletes)) {
      if (p is! Map) continue;
      await google.api('${_calPath(p['cal'] as String)}/${Uri.encodeComponent(p['gid'] as String)}', method: 'DELETE', missingOk: true);
      s.pendingDeletes.remove(p);
      s.hidden.remove('g:${p['cal']}|${p['gid']}');
      save();
    }
  }

  Future<void> _runGoogleSync(bool manual) async {
    final st = s.settings;
    syncing = true;
    notifyListeners();
    try {
      if (!google.connected) {
        if (!manual) throw 'Not connected. Tap the top bar to reconnect';
        await google.connect(st.clientId);
      }
      await _flushPending();
      if (st.calendars.isEmpty) {
        try {
          await _gCalendarList();
        } catch (_) {}
      }
      var a = 0, u = 0, r = 0;
      final errs = <String>[];
      final cals = _enabledCals();
      for (final c in cals) {
        try {
          final m = merge(s, await _gPull(c.id), 'gapi', c.id, true);
          a += m.added;
          u += m.updated;
          r += m.removed;
        } catch (e) {
          if (e == kExpired) rethrow;
          errs.add('${c.name}: $e');
        }
      }
      final ids = cals.map((c) => c.id).toSet();
      final b = s.events.length;
      s.events.removeWhere((e) => e.source == 'gapi' && !ids.contains(e.feed) && !e.dirty);
      r += b - s.events.length;
      st
        ..lastSync = nowMs()
        ..lastSyncMsg = '$a new, $u updated, $r removed'
        ..lastSyncError = errs.join(' · ');
    } catch (e) {
      st.lastSyncError = e.toString();
    } finally {
      syncing = false;
      save();
      notifyListeners();
    }
  }

  // ---------- import / export ----------
  MergeResult importIcs(String text) {
    final r = merge(s, parseIcs(text).map((it) => it.withKey('file:${it.key}')).toList(), 'file', 'file', false);
    save();
    boardEpoch++;
    notifyListeners();
    return r;
  }

  /// One-time copy of a Google Calendar via its secret iCal address.
  Future<MergeResult> importFromUrl(String url) async => importIcs(await fetchIcal(url));

  String exportIcsText() => exportIcs(s);

  String backupJson() => const JsonEncoder.withIndent('  ').convert({
        'app': 'subway-board',
        'version': 3,
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'state': s.toJson(),
      });

  /// Parses a backup file. Returns the state map and its export date, or null if it isn't a backup.
  (Map<String, dynamic>, String?)? readBackup(String text) {
    try {
      final data = jsonDecode(text);
      if (data is! Map) return null;
      final st = data['state'] is Map ? data['state'] : data;
      if (st is! Map || st['events'] is! List) return null;
      return (Map<String, dynamic>.from(st), data['exportedAt'] as String?);
    } catch (_) {
      return null;
    }
  }

  void restoreBackup(Map<String, dynamic> st) {
    s = normalize(st['lines'] is List ? st : fromV2(st));
    _alerted.clear();
    activeCat = null;
    save();
    switchTab('board');
    showToast('Backup restored');
  }

  // ---------- reminders ----------
  int _remindFor(Event ev) => ev.remind ?? s.settings.remindDefault;

  /// Chime while the app is open (when notifications aren't already doing it).
  void _checkAlerts() {
    if (!s.settings.sound || s.settings.notify) return;
    final now = nowMs();
    for (final ev in occurrences(s, now - kDay, now + 2 * kDay)) {
      if (ev.allDay) continue;
      final r = _remindFor(ev);
      if (r < 0) continue;
      final k1 = '${ev.id}@${ev.start}p', k2 = '${ev.id}@${ev.start}', t = ev.start - r * kMin;
      if (r > 0 && now >= t && now < ev.start && _alerted.add(k1) && now - t < 120000) alerts.chime(boarding: true);
      if (now >= ev.start && now <= ev.end && _alerted.add(k2) && now - ev.start < 120000) alerts.chime(boarding: false);
    }
  }

  void _scheduleAlerts() {
    _alertsDebounce?.cancel();
    _alertsDebounce = Timer(const Duration(milliseconds: 800), () async {
      if (!s.settings.notify || !await alerts.enabled()) {
        await alerts.cancelAll();
        return;
      }
      final now = nowMs();
      final list = <Alert>[];
      for (final ev in occurrences(s, now, now + 7 * kDay)) {
        if (ev.allDay) continue;
        final r = _remindFor(ev);
        if (r < 0) continue;
        final where = ev.loc.isNotEmpty ? ' · ${ev.loc}' : '';
        final t = ev.start - r * kMin;
        if (r > 0 && t > now) list.add(Alert(t, 'Now boarding: ${ev.title}', 'Departs ${fmtT(ev.start, use24h: use24h)}$where', true));
        if (ev.start > now) list.add(Alert(ev.start, 'Now departing: ${ev.title}', '${lineOf(ev.cat).name} · until ${fmtT(ev.end, use24h: use24h)}', false));
      }
      list.sort((a, b) => a.at.compareTo(b.at));
      await alerts.schedule(list.take(60).toList(), sound: s.settings.sound);
    });
  }
}

