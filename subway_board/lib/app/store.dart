// App state: the saved data plus what's on screen. One ChangeNotifier, like
// the web app's global `S` and its render functions.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:http/http.dart' as http;

import '../core/google.dart';
import '../core/ics.dart';
import '../core/logic.dart';
import '../core/budget_import.dart';
import '../core/ledger.dart';
import '../core/model.dart';
import '../core/money.dart';
import '../core/quick.dart';
import '../core/tasks.dart';
import '../core/util.dart';
import '../services/alerts.dart';
import '../services/backup.dart';
import '../services/google_auth.dart';
import '../services/platform.dart';
import '../services/widget_bridge.dart';
import '../ui/theme.dart' show setAccent, accentFromHex, accentHex, rebuildAll;
import 'demo.dart';

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

  /// A background copy started by the home-screen widget to apply its ticks:
  /// saves and refreshes the widget, but no timers, sync, alerts or backups.
  bool headless = false;

  /// The widget's quick-add window: reads the data (lines, categories) but
  /// never writes it; new things go through [relay] to whoever owns the data.
  bool noWrite = false;
  Future<void> Function(Map<String, dynamic> action)? relay;

  /// The last relayed add, so the window can wait for it before closing.
  Future<void> relayed = Future.value();
  AppData s = AppData();
  File? _file;

  // ---------- what's on screen ----------
  String sel = todayStr();
  String _lastToday = todayStr();
  String tab = 'today';
  String? activeCat;
  bool showAllDay = false;

  /// Today's finished departures are folded away above the board; the arrow by
  /// DEPARTURES unfolds them. Closes again when the day changes.
  bool showDone = false;

  /// Bumped whenever the board should replay its flip-in animation.
  int boardEpoch = 0;

  /// The event (or repeat occurrence) open in the form; null = adding.
  Event? editing;

  /// Bumped each time the form is opened, so it reloads its fields.
  int formSeq = 0;
  bool syncing = false;
  bool use24h = false;

  /// True for the frame a widget tap lands on: the screen appears without the
  /// tab cross-fade, since the system is already zooming out of the widget.
  bool instantTab = false;
  ToastMsg? toast;
  int _toastSeq = 0;

  Timer? _tick, _syncTimer, _toastTimer, _alertsDebounce, _pushTimer;
  final _alerted = <String>{};

  // ---------- load / save ----------
  Future<void> load({bool headless = false, bool readOnly = false}) async {
    this.headless = headless || readOnly;
    noWrite = readOnly;
    try {
      final loc = Platform.localeName;
      defaultCurrency = () => currencyForLocale(loc);
    } catch (_) {}
    final dir = await AppPlatform.docsDir();
    _file = File('${dir.path}/subway3.json');
    try {
      if (await _file!.exists()) {
        final raw = jsonDecode(await _file!.readAsString()) as Map<String, dynamic>;
        // First run after the upgrade that added tasks and money: keep the old file as it was.
        if (!raw.containsKey('tasks')) {
          final keep = File('${dir.path}/subway3.pre-v2.json');
          if (!await keep.exists()) await _file!.copy(keep.path);
        }
        s = normalize(raw);
        setAccent(accentFromHex(s.settings.extra['accent']));
        // A preview seeded before accounts existed: refresh its demo money.
        if (kDemo && s.money.accounts.isEmpty && !s.money.txns.any((t) => t.src == kBudgetSrc)) seedDemoMoney(s);
      } else if (kDemo) {
        seedDemo(s);
      }
    } catch (e) {
      debugPrint('could not read saved data: $e');
      // Keep the unreadable file for recovery instead of overwriting it.
      try {
        await _file!.copy('${_file!.path}.corrupt-${nowMs()}');
      } catch (_) {}
    }
    if (this.headless) return;
    // Saves the repaired/migrated data shortly, off the launch path.
    _scheduleWrite();
    _tz = FlutterTimezone.getLocalTimezone().then((t) => localTz = t.identifier, onError: (_) => localTz).then((_) {});
    _startClock();
    unawaited(_startSync());
    _scheduleAlerts();
    _maybeAutoBackup();
    WidgetBridge.push(() => s);
    final launch = await WidgetBridge.init(handleWidgetLaunch, onKick: drainWidget);
    if (launch != null) handleWidgetLaunch(launch);
    notifyListeners();
    unawaited(drainWidget());
  }

  Future<void> _tz = Future.value();

  // ---------- clock ----------
  // The screen shows minutes (the top-bar clock, MIN LEFT, LIVE), so it is
  // redrawn on each minute boundary, and not at all while the app is in the
  // background. Calendar sync runs every 10 minutes, also only in front.

  bool _foreground = true;

  void _startClock() {
    _tick?.cancel();
    _syncTimer?.cancel();
    if (headless || !_foreground) return;
    final now = DateTime.now();
    final toNext = 60000 - (now.second * 1000 + now.millisecond) + 50;
    _tick = Timer(Duration(milliseconds: toNext), () {
      _onTick();
      _startClock();
    });
    _syncTimer = Timer.periodic(const Duration(minutes: 10), (_) => runSync());
  }

  /// The app went to the background: stop the clock and sync, save now.
  void paused() {
    if (!_foreground) return;
    _foreground = false;
    _tick?.cancel();
    _syncTimer?.cancel();
    unawaited(flush());
  }

  /// First sync after launch; for Google, quietly restores the last sign-in first.
  Future<void> _startSync() async {
    await _tz;
    if (s.settings.mode == 'api' && clientId.isNotEmpty) {
      await google.restore(clientId);
      notifyListeners();
    }
    await runSync();
  }

  Future<void> _pending = Future.value();
  Timer? _writeTimer;

  /// Saves soon: a burst of changes (a drag, several ticks, a sync merge)
  /// becomes one encode and one disk write instead of one per change.
  void _scheduleWrite() {
    if (_file == null || noWrite) return;
    _writeTimer?.cancel();
    _writeTimer = Timer(const Duration(milliseconds: 350), _write);
  }

  /// Writes any change still waiting, and resolves once it's on disk.
  Future<void> flush() {
    if (_writeTimer?.isActive ?? false) {
      _writeTimer!.cancel();
      return _write();
    }
    return _pending;
  }

  Future<void> _write() {
    _writeTimer?.cancel();
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
    if (noWrite) return;
    if (headless) {
      _write(); // the widget worker may be stopped any moment: write now
      return; // and it pushes the widget itself once its batch is saved
    }
    _scheduleWrite();
    _scheduleAlerts();
    WidgetBridge.push(() => s);
    _maybeAutoBackup();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _syncTimer?.cancel();
    _writeTimer?.cancel();
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
        'tasks': s.tasks.map((t) => t.toJson()).toList(),
        'money': s.money.toJson(),
      });

  /// Saves, redraws, and offers UNDO back to [snapshot]. An edit updates the
  /// screen in place: no epoch bump, so the tab doesn't blank out and replay
  /// its flip-in (that's for moving to another day, month or tab).
  void commit(String snapshot, String msg) {
    save();
    showToast(
      msg,
      ToastAction('UNDO', () {
        _pushTimer?.cancel();
        final restored = normalize({...s.toJson(), ...jsonDecode(snapshot) as Map<String, dynamic>});
        s.events = restored.events;
        s.lines = restored.lines;
        s.hidden = restored.hidden;
        s.pendingDeletes = restored.pendingDeletes;
        s.tasks = restored.tasks;
        s.money = restored.money;
        if (activeCat != null && !s.lines.any((l) => l.id == activeCat)) activeCat = null;
        save();
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
    if (name == tab) return;
    tab = name;
    editing = null;
    draft = null;
    draftTask = null;
    boardEpoch++;
    notifyListeners();
  }

  void openForm(Event? view) {
    if (view != null) {
      draft = null;
      draftTask = null;
    }
    editing = view;
    formSeq++;
    tab = 'add';
    notifyListeners();
  }

  void setSel(String day) {
    if (day == sel) return;
    sel = day;
    showDone = false;
    boardEpoch++;
    notifyListeners();
  }

  void shiftDay(int n) => setSel(dstr(addDays(dms(sel), n)));

  /// A tap on the home-screen widget: opens that event, the add form for that
  /// day, or that day on TODAY.
  void handleWidgetLaunch(WidgetLaunch m) {
    instantTab = true;
    SchedulerBinding.instance.addPostFrameCallback((_) => instantTab = false);
    final day = m['day'];
    if (day != null && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day)) sel = day;
    switch (m['type']) {
      case 'event':
        final d0 = dms(sel);
        final ev = occurrences(s, d0, addDays(d0, 1)).where((e) => e.id == m['id']).firstOrNull;
        if (ev != null) return openForm(ev);
      case 'add':
        return openForm(null);
      case 'task':
      case 'money':
        tab = m['type'] == 'task' ? 'tasks' : 'money';
        if (tab == 'money' && day != null) moneyMonth = monthStart(dms(sel));
        editing = null;
        boardEpoch++;
        notifyListeners();
        return;
    }
    tab = 'today';
    editing = null;
    notifyListeners();
  }

  String get boardView => s.settings.view;

  /// The Today tab: 'day' | 'week'. Shares the selected day with the board.
  String todayView = 'day';

  void setTodayView(String v) {
    if (v == todayView) return;
    todayView = v;
    boardEpoch++;
    notifyListeners();
  }

  void setBoardView(String v) {
    if (v == s.settings.view) return;
    s.settings.view = v;
    save();
    boardEpoch++;
    notifyListeners();
  }

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

  void toggleDone() {
    showDone = !showDone;
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
    _foreground = true;
    _startClock();
    _onTick();
    _scheduleAlerts();
    _maybeAutoBackup();
    WidgetBridge.push(() => s);
    if (nowMs() - s.settings.lastSync > 120000) runSync();
    drainWidget();
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

  /// Drag-reorder on the Lines tab. The first line is the default for new events
  /// (and for imports no keyword matches), and the board's chips follow this order.
  void moveLine(int from, int to) {
    if (from == to || from < 0 || from >= s.lines.length) return;
    final l = s.lines.removeAt(from);
    s.lines.insert(to.clamp(0, s.lines.length), l);
    save();
    notifyListeners();
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
    final linked = ev.task != null ? taskById(ev.task!) : null;
    if (linked != null && master != null && !isRO(s, master)) _taskFollows(linked, ev, master);
    final made = master == null ? draftTask : null;
    if (made != null) {
      _taskFollows(made, ev);
      ev.task = made.id;
      s.tasks.add(made);
    }
    draftTask = null;
    sel = dstr(f.start);
    tab = 'board';
    editing = null;
    commit(sn, master != null ? 'Saved' : (made != null ? 'Added to board + task' : 'Added to board'));
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
  /// [withTask]: also delete the task it was made with (not for 'one').
  void deleteEvent({String? choice, bool withTask = false}) {
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
    final tid = master.task;
    final both = withTask && tid != null && choice != 'one' && s.tasks.any((t) => t.id == tid);
    if (both) s.tasks.removeWhere((t) => t.id == tid);
    tab = 'board';
    editing = null;
    commit(sn, both ? 'Event and task deleted' : 'Deleted');
    if (s.pendingDeletes.isNotEmpty && google.connected) _schedulePush();
  }

  void clearSamples() {
    final sn = snap();
    s.events.removeWhere((e) => e.sample);
    s.tasks.removeWhere((t) => isDemoId(t.id));
    final m = s.money;
    m.txns.removeWhere((t) => isDemoId(t.id));
    m.accounts.removeWhere((a) => isDemoId(a.id));
    m.goals.removeWhere((g) => isDemoId(g.id));
    m.plans.removeWhere((p) => isDemoId(p.id));
    if (isDemoId(m.defaultAcct)) m.defaultAcct = '';
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

  void toggleTodayNet() {
    s.settings.foldTodayNet = !s.settings.foldTodayNet;
    save();
    notifyListeners();
  }

  void toggleHideNet() {
    s.settings.hideNet = !s.settings.hideNet;
    save();
    notifyListeners();
  }

  /// Net worth as the eye by NET WORTH says: the amount, or dots.
  String netCash(int minor, {bool sign = false, bool compact = false}) =>
      s.settings.hideNet ? '${s.money.currency} ••••••' : cash(minor, sign: sign, compact: compact);

  void setHaptics(bool v) {
    s.settings.haptics = v;
    save();
    notifyListeners();
  }

  /// Money notification switches and times ('bills' | 'log' | 'budget').
  void setMoneyAlert(String which, {bool? on, int? minutes}) {
    final st = s.settings;
    switch (which) {
      case 'bills':
        if (on != null) st.billReminders = on;
        if (minutes != null) st.billTime = minutes;
      case 'log':
        if (on != null) st.logReminder = on;
        if (minutes != null) st.logTime = minutes;
      case 'budget':
        if (on != null) st.budgetAlerts = on;
    }
    save();
    notifyListeners();
  }

  void setTheme(String v) {
    s.settings.theme = v;
    save();
    notifyListeners();
  }

  /// The accent picked (null = the Subway yellow), as chosen on the wheel.
  Color? get accentPick => accentFromHex(s.settings.extra['accent']);

  /// Sets the accent everywhere, the widget too. Null resets to yellow.
  void setAccentColor(Color? c) {
    final used = setAccent(c);
    if (c == null) {
      s.settings.extra.remove('accent');
    } else {
      s.settings.extra['accent'] = accentHex(used);
    }
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

  /// The built-in client, or (builds without one) the id pasted in Settings.
  String get clientId => kGoogleClientId.isNotEmpty ? kGoogleClientId : s.settings.clientId;

  /// Sign in (from a tap), refresh the calendar list and sync.
  Future<void> connectGoogle() async {
    await google.connect(clientId);
    notifyListeners();
    try {
      await _gCalendarList();
    } catch (_) {}
    await runSync(manual: true);
  }

  /// Set when the welcome is answered this session (ends a forced preview).
  bool welcomeAnswered = false;

  /// Welcome → "Use without an account": local only, Google can be added in Settings.
  void finishWelcome() {
    welcomeAnswered = true;
    s.settings.welcomed = true;
    save();
    boardEpoch++;
    notifyListeners();
  }

  /// Welcome → "Sign in with Google": two-way sync with the user's calendar.
  /// On failure the app stays local and the error is rethrown for a toast.
  Future<void> welcomeWithGoogle() async {
    final st = s.settings;
    applySync('api', st.feeds.map((f) => f.url).toList(), st.clientId);
    try {
      await connectGoogle();
    } catch (_) {
      st.mode = 'none';
      save();
      notifyListeners();
      rethrow;
    }
    finishWelcome();
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
          s.seriesProps[gid] = {'cat': ev.cat, 'catManual': true, 'remind': ev.remind ?? '', 'task': ?ev.task};
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
        await google.connect(clientId);
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
    // The preview build never writes the real app's backup file.
    if (kDemo) {
      s.settings
        ..autoBackup = false
        ..backupUri = ''
        ..backupName = '';
    }
    setAccent(accentFromHex(s.settings.extra['accent']));
    rebuildAll();
    _alerted.clear();
    activeCat = null;
    save();
    switchTab('board');
    showToast('Backup restored');
  }

  // ---------- tasks ----------

  /// Tasks tab filter: starred only (the line filter is shared with the board's chips).
  bool starOnly = false;
  bool showCompleted = false;

  void toggleStarOnly() {
    starOnly = !starOnly;
    boardEpoch++;
    notifyListeners();
  }

  void toggleCompleted() {
    showCompleted = !showCompleted;
    notifyListeners();
  }

  Task? taskById(String id) => s.tasks.where((t) => t.id == id).firstOrNull;

  void addTask(Task t) {
    final sn = snap();
    s.tasks.add(t);
    commit(sn, t.due.isEmpty ? 'Task added' : 'Task added · ${dueLabel(t.due, nowMs())}');
  }

  /// [onBoard]: true puts the task on the board as a linked event (when it
  /// has a day), false takes that event off; null leaves it as it is.
  void saveTask(Task t, {bool? onBoard}) {
    final sn = snap();
    final i = s.tasks.indexWhere((x) => x.id == t.id);
    final before = i < 0 ? null : s.tasks[i];
    if (i < 0) {
      s.tasks.add(t);
    } else {
      s.tasks[i] = t;
    }
    final evs = linkedEvents(t.id);
    var msg = i < 0 ? 'Task added' : 'Saved';
    if (onBoard == false || (evs.isNotEmpty && t.due.isEmpty)) {
      // No day, no slot on the board.
      for (final ev in evs) {
        _dropEvent(ev);
      }
      if (evs.isNotEmpty) msg = onBoard == false ? 'Saved · off the board' : 'Saved · no date, off the board';
    } else if (evs.isNotEmpty) {
      for (final ev in evs) {
        _eventFollows(ev, before ?? t, t);
      }
    } else if (onBoard == true && t.due.isNotEmpty) {
      final ev = eventFromTask(t);
      s.events = [...s.events, ev];
      msg = '${i < 0 ? 'Task added' : 'Saved'} · on the board ${_when(ev)}';
    }
    commit(sn, msg);
    _pushIfDirty();
  }

  /// [withEvent]: also delete the calendar event it's linked to (else it stays, unlinked).
  void deleteTask(String id, {bool withEvent = false}) {
    final t = taskById(id);
    if (t == null) return;
    final sn = snap();
    s.tasks.remove(t);
    final evs = linkedEvents(id);
    for (final ev in evs) {
      if (withEvent) {
        _dropEvent(ev);
      } else {
        ev.task = null;
      }
    }
    commit(sn, withEvent && evs.isNotEmpty ? 'Task and event deleted' : 'Task deleted');
    if (s.pendingDeletes.isNotEmpty && google.connected) _schedulePush();
  }

  // ---------- home-screen widget actions ----------

  bool _draining = false, _drainAgain = false;

  /// Applies whatever was done on the widget, saves, refreshes the widget and
  /// only then lets the widget forget it (so nothing is lost if this copy of
  /// the app is closed mid-way: the next one applies it again, harmlessly).
  Future<void> drainWidget() async {
    if (_draining) {
      _drainAgain = true;
      return;
    }
    _draining = true;
    try {
      for (var i = 0; i < 6; i++) {
        _drainAgain = false;
        final acts = await WidgetBridge.peekActions();
        if (acts.isEmpty) {
          if (!_drainAgain) break;
          continue;
        }
        applyWidgetActions(acts);
        await flush();
        await WidgetBridge.pushNow(s);
        await WidgetBridge.ackActions([for (final a in acts) '${a['aid']}']);
      }
    } finally {
      _draining = false;
    }
  }

  /// Ticks ({type: tick, task, day, done, at}) and quick adds ({type: add,
  /// task?, event?} / {type: txn, txn}) from the widget. Each one checks the
  /// current state first, so applying it twice changes nothing.
  int applyWidgetActions(List<Map<String, dynamic>> acts) {
    if (acts.isEmpty || noWrite) return 0;
    final sn = snap();
    var n = 0;
    String? msg;
    final lineIds = s.lines.map((l) => l.id).toSet();
    for (final a in acts) {
      switch (a['type']) {
        case 'tick':
          final t = taskById('${a['task']}');
          if (t == null) continue;
          final day = a['day'] is String ? a['day'] as String : todayStr();
          final m = _tickTo(t, day, a['done'] == true, at: (a['at'] as num?)?.toInt());
          if (m != null) {
            n++;
            msg = m;
          }
        case 'add':
          final t = a['task'] == null ? null : taskFromJson(a['task'], lineIds, s.lines.first.id);
          final ev = a['event'] == null ? null : normEvent(a['event'], lineIds, s.lines.first.id);
          if (t != null && taskById(t.id) == null) {
            s.tasks.add(t);
            n++;
          }
          if (ev != null && !s.events.any((e) => e.id == ev.id)) {
            s.events = [...s.events, ev];
            n++;
          }
          msg = 'Added · ${clip(t?.title ?? ev?.title ?? '', 28)}';
        case 'txn':
          final x = txnFromJson(a['txn'], s.money);
          if (x != null && !s.money.txns.any((y) => y.id == x.id)) {
            s.money.txns.add(x);
            n++;
            msg = _txnMsg(x);
          }
      }
    }
    if (n == 0) return 0;
    if (headless) {
      save();
    } else {
      commit(sn, n == 1 && msg != null ? '$msg · from the widget' : '$n changes from the widget');
    }
    return n;
  }

  /// Sets the task's tick as seen on [day] (its row on the board or under TO
  /// DO) to [want]. A repeating task can't be un-ticked from there, and its
  /// future days wait their turn. Returns the toast text, or null when it
  /// already was that way.
  String? _tickTo(Task t, String day, bool want, {int? at}) {
    if (linkDone(t, day) == want) return null;
    if (!want) return t.repeat.isEmpty ? _markDone(t.id, false) : null;
    if (t.repeat.isNotEmpty && day != t.due && day.compareTo(todayStr()) > 0) return null;
    return _markDone(t.id, true, at: at);
  }

  // ---------- task <-> event links ----------

  /// Events made with this task (one, unless Google expanded a series).
  List<Event> linkedEvents(String taskId) => s.events.where((e) => e.task == taskId).toList();

  /// The task an event (or one of its repeats) was made with.
  Task? taskOfEvent(Event ev) {
    final id = ev.task ?? masterOf(ev)?.task;
    return id == null ? null : taskById(id);
  }

  /// Whether the linked task counts as done on [day]. A repeating task is done
  /// for every day before the one it's now due.
  bool linkDone(Task t, String day) => t.repeat.isEmpty ? t.done : (t.due.isNotEmpty && day.compareTo(t.due) < 0);

  /// The tick on a linked board row.
  void tickLinked(Event occ) {
    final t = taskOfEvent(occ);
    if (t == null) return;
    final day = dstr(occ.start);
    final done = linkDone(t, day);
    if (t.repeat.isEmpty) return setTaskDone(t.id, !done);
    if (done) return showToast('Already done · next ${dueLabel(t.due, nowMs()).toLowerCase()}');
    if (day != t.due && day.compareTo(todayStr()) > 0) return showToast('Due ${dueLabel(t.due, nowMs()).toLowerCase()} first');
    setTaskDone(t.id, true);
  }

  /// A new event in the task's slot: its day and time (all day without a
  /// time), [dur] minutes long, repeating the same way when the board can.
  Event eventFromTask(Task t, {int dur = 30}) {
    final d = DateTime.fromMillisecondsSinceEpoch(dms(t.due));
    final allDay = t.time == null;
    final start = allDay ? d.millisecondsSinceEpoch : DateTime(d.year, d.month, d.day, t.time! ~/ 60, t.time! % 60).millisecondsSinceEpoch;
    return Event(
      id: uid(),
      title: t.title,
      cat: t.cat,
      catManual: true,
      start: start,
      end: allDay ? addDays(start, 1) : start + dur * kMin,
      allDay: allDay,
      repeat: kRepeat.containsKey(t.repeat) ? Repeat(t.repeat) : null,
      task: t.id,
    );
  }

  /// Quick add with "Also": a task and/or an event, linked when both.
  void addLinked({Task? task, Event? event}) {
    if (task == null && event == null) return;
    if (relay != null) {
      if (task != null && event != null) event.task = task.id;
      relayed = relay!({'type': 'add', if (task != null) 'task': task.toJson(), if (event != null) 'event': event.toJson()});
      return;
    }
    final sn = snap();
    if (task != null) s.tasks.add(task);
    if (event != null) {
      if (task != null) event.task = task.id;
      s.events = [...s.events, event];
      sel = dstr(event.start);
      if (task == null && tab != 'board') tab = 'board';
    }
    editing = null;
    final now = nowMs();
    final String msg;
    if (task != null && event != null) {
      msg = '${task.isBill ? 'Task + event · ${cash(task.amount)} when done' : 'Task + event added'} · ${_when(event)}';
    } else if (event != null) {
      msg = 'Added to board · ${dueLabel(dstr(event.start), now).toLowerCase()}';
    } else {
      msg = task!.due.isEmpty ? 'Task added' : 'Task added · ${dueLabel(task.due, now)}';
    }
    commit(sn, msg);
  }

  String _when(Event ev) {
    final day = dueLabel(dstr(ev.start), nowMs()).toLowerCase();
    return ev.allDay ? day : '$day ${fmtT(ev.start, use24h: use24h)}';
  }

  static int _minOf(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return d.hour * 60 + d.minute;
  }

  /// Sets a linked task's name, line, day and time from its event. [before] is
  /// the event as it was: a repeating series moves the task by the same days.
  void _taskFollows(Task t, Event ev, [Event? before]) {
    t
      ..title = ev.title
      ..cat = ev.cat
      ..time = ev.allDay ? null : _minOf(ev.start);
    if (before != null && before.repeat != null && ev.repeat != null && t.due.isNotEmpty) {
      final shift = ((sod(ev.start) - sod(before.start)) / kDay).round();
      if (shift != 0) t.due = dstr(addDays(dms(t.due), shift));
    } else {
      t.due = dstr(ev.start);
    }
    final f = ev.repeat?.freq ?? '';
    if (before == null || (before.repeat?.freq ?? '') != f) t.repeat = f;
  }

  /// Moves a linked event after its task changed from [before] to [t]: same
  /// name and line, shifted by the days the due date moved, at the task's time
  /// (all day when the task has none).
  void _eventFollows(Event ev, Task before, Task t) {
    final old = ev.copy();
    ev.title = t.title;
    if (ev.cat != t.cat) {
      ev
        ..cat = t.cat
        ..catManual = true;
    }
    final shift = before.due.isEmpty || t.due.isEmpty ? 0 : ((dms(t.due) - dms(before.due)) / kDay).round();
    final base = DateTime.fromMillisecondsSinceEpoch(addDays(sod(ev.start), shift));
    if (t.time == null) {
      final days = ev.allDay ? ((ev.end - ev.start) / kDay).round().clamp(1, 1 << 30) : 1;
      ev
        ..allDay = true
        ..start = base.millisecondsSinceEpoch
        ..end = addDays(base.millisecondsSinceEpoch, days);
    } else {
      final len = ev.allDay ? 30 * kMin : ev.end - ev.start;
      ev
        ..allDay = false
        ..start = DateTime(base.year, base.month, base.day, t.time! ~/ 60, t.time! % 60).millisecondsSinceEpoch
        ..end = ev.start + len;
    }
    if (before.repeat != t.repeat && ev.source != 'gapi') {
      ev.repeat = kRepeat.containsKey(t.repeat) ? Repeat(t.repeat, ev.repeat?.until ?? '') : null;
    }
    if (ev.repeat == null) {
      ev.exdates = null;
    } else if (ev.exdates != null && ev.start != old.start) {
      final k = mkey(ev.start) - mkey(old.start);
      ev.exdates = ev.exdates!.map((x) => x + k).toList();
    }
    final changed = old.title != ev.title || old.start != ev.start || old.end != ev.end || old.allDay != ev.allDay;
    if (changed && ev.source == 'gapi' && s.settings.mode == 'api') ev.dirty = true;
  }

  /// Takes an event off the board (and out of Google Calendar when it's synced there).
  void _dropEvent(Event ev) {
    if (isGoogleEvent(ev)) s.pendingDeletes.add({'cal': ev.calId ?? ev.feed, 'gid': ev.gid});
    if (ev.key != null) s.hidden[ev.key!] = 1;
    s.events.remove(ev);
  }

  void _pushIfDirty() {
    if (google.connected && (s.events.any((e) => e.dirty) || s.pendingDeletes.isNotEmpty)) _schedulePush();
  }

  /// Ticks a task off (or back on). A bill logs its payment; a repeating task
  /// keeps a done copy and moves on to its next due day.
  void setTaskDone(String id, bool done) {
    final sn = snap();
    final msg = _markDone(id, done);
    if (msg != null) commit(sn, msg);
  }

  /// Marks a task done (or not) without saving; [at] is when it was ticked
  /// (the widget queues ticks). Returns the toast text, or null if nothing changed.
  String? _markDone(String id, bool done, {int? at}) {
    final t = taskById(id);
    if (t == null || t.done == done) return null;
    final now = at ?? nowMs();
    String msg;
    if (done) {
      String? txnId;
      if (t.isBill) {
        final m = s.money;
        var cat = t.mcat.isNotEmpty ? t.mcat : (matchMCat(m, t.title) ?? 'bills');
        if (!m.cats.any((c) => c.id == cat && !c.income)) cat = m.fallbackCat;
        final acct = m.acctOf(t.acct) != null ? t.acct : m.newAcct;
        final x = Txn(id: uid(), title: t.title, cat: cat, at: now, amount: t.amount, task: t.id, acct: acct);
        s.money.txns.add(x);
        txnId = x.id;
      }
      // A repeat that has run its course ends here, like a one-off.
      String? next;
      if (t.repeat.isNotEmpty && (t.repLeft == null || t.repLeft! > 0)) {
        next = nextDue(t.repFromDone || t.due.isEmpty ? dstr(now) : t.due, t.repeat);
        // Long overdue: skip to the next one from today, not one still in the past.
        while (next!.compareTo(dstr(now)) < 0) {
          next = nextDue(next, t.repeat);
        }
        if (t.repUntil.isNotEmpty && next.compareTo(t.repUntil) > 0) next = null;
      }
      if (next != null) {
        // The done copy is the history; the task itself rolls forward.
        s.tasks.add(t.copy()
          ..id = uid()
          ..done = true
          ..doneAt = now
          ..repeat = ''
          ..repUntil = ''
          ..repLeft = null
          ..repFromDone = false
          ..txn = txnId);
        t.due = next;
        if (t.repLeft != null) t.repLeft = t.repLeft! - 1;
        for (final x in t.subs) {
          x.done = false;
        }
        msg = '${t.isBill ? 'Paid' : 'Done'} · next ${dueLabel(next, now).toLowerCase()}';
      } else {
        // A repeat that just ran out ends as a plain done task.
        final ended = t.repeat.isNotEmpty;
        t
          ..done = true
          ..doneAt = now
          ..txn = txnId
          ..repeat = ''
          ..repUntil = ''
          ..repLeft = null
          ..repFromDone = false;
        msg = t.isBill ? 'Paid · ${fmtMoney(t.amount, s.money.currency)} logged' : 'Done · ${clip(t.title, 28)}';
        if (ended) msg = '$msg · that was the last one';
      }
    } else {
      if (t.txn != null) s.money.txns.removeWhere((x) => x.id == t.txn);
      t
        ..done = false
        ..doneAt = 0
        ..txn = null;
      msg = 'Marked not done';
    }
    return msg;
  }

  /// Swipe left on a task: due the day after (from today if it's overdue or undated).
  void postponeTask(String id) {
    final t = taskById(id);
    if (t == null) return;
    final sn = snap();
    final now = nowMs();
    final from = t.due.isEmpty || t.due.compareTo(dstr(now)) < 0 ? dstr(now) : t.due;
    final before = t.copy();
    t.due = dstr(addDays(dms(from), 1));
    for (final ev in linkedEvents(t.id)) {
      _eventFollows(ev, before, t);
    }
    commit(sn, 'Moved to ${dueLabel(t.due, now).toLowerCase()}');
    _pushIfDirty();
  }

  void toggleStar(String id) {
    final t = taskById(id);
    if (t == null) return;
    t.star = !t.star;
    save();
    notifyListeners();
  }

  void toggleSub(String taskId, String subId) {
    final x = taskById(taskId)?.subs.where((x) => x.id == subId).firstOrNull;
    if (x == null) return;
    x.done = !x.done;
    save();
    notifyListeners();
  }

  void clearCompleted() {
    final n = s.tasks.where((t) => t.done).length;
    if (n == 0) return;
    final sn = snap();
    final gone = s.tasks.where((t) => t.done).map((t) => t.id).toSet();
    s.tasks.removeWhere((t) => t.done);
    for (final e in s.events) {
      if (gone.contains(e.task)) e.task = null;
    }
    showCompleted = false;
    commit(sn, 'Cleared $n completed');
  }

  /// Open tasks due on [day] (plus overdue ones when it's today), line filter applied.
  /// A task on the board as a timed event shows its tick on that row instead
  /// of under TO DO, unless today's slot is already over (it comes back then).
  /// [filtered]: only the line picked on the board (the Today tab shows all).
  List<Task> tasksFor(String day, {bool filtered = true}) {
    final today = todayStr();
    final open = s.tasks
        .where((t) =>
            !t.done &&
            (!filtered || activeCat == null || t.cat == activeCat) &&
            (t.due == day || (day == today && t.due.isNotEmpty && t.due.compareTo(today) < 0)))
        .toList();
    if (open.any((t) => t.due == day) && s.events.any((e) => e.task != null)) {
      final d0 = dms(day), now = nowMs();
      final riding = {
        for (final e in occurrences(s, d0, addDays(d0, 1)))
          if (e.task != null && !e.allDay && (day != today || e.end >= now)) e.task,
      };
      open.removeWhere((t) => t.due == day && riding.contains(t.id));
    }
    return open..sort(compareTasks);
  }

  // ---------- money ----------

  /// Month shown on the Money tab (local midnight on the 1st).
  int moneyMonth = monthStart(nowMs());

  void shiftMonth(int n) => setMoneyMonth(addMonths(moneyMonth, n));

  void setMoneyMonth(int ms) {
    final m = monthStart(ms);
    if (m == moneyMonth) return;
    moneyMonth = m;
    boardEpoch++;
    notifyListeners();
  }

  String cash(int minor, {bool sign = false, bool compact = false}) => fmtMoney(minor, s.money.currency, sign: sign, compact: compact);

  MonthStats stats([int? month]) => monthStats(s.money, s.tasks, month ?? moneyMonth, nowMs());

  String _txnMsg(Txn t) => switch (t.type) {
        'income' => 'Income logged · ${cash(t.amount)}',
        'refund' => 'Refund logged · ${cash(t.amount)}',
        'transfer' => 'Transfer logged · ${cash(t.amount)}',
        'adjust' => 'Balance updated',
        'save' => 'Added to goal · ${cash(t.amount)}',
        'unsave' => 'Taken from goal · ${cash(t.amount)}',
        'lent' => 'Lent · ${cash(t.amount)}',
        'borrowed' => 'Borrowed · ${cash(t.amount)}',
        'repay' => 'Repayment logged · ${cash(t.amount)}',
        _ => 'Spend logged · ${cash(t.amount)}',
      };

  void saveTxn(Txn t) {
    if (relay != null) {
      relayed = relay!({'type': 'txn', 'txn': t.toJson()});
      return;
    }
    final sn = snap();
    final i = s.money.txns.indexWhere((x) => x.id == t.id);
    final before = t.isSpend && !t.excluded ? stats(monthStart(t.at)) : null;
    if (i < 0) {
      s.money.txns.add(t);
    } else {
      s.money.txns[i] = t;
    }
    commit(sn, i < 0 ? _txnMsg(t) : 'Saved');
    if (before != null) _budgetAlert(t, before);
  }

  /// A heads-up when a spend takes a category (or the month) past 80% or 100%.
  void _budgetAlert(Txn t, MonthStats before) {
    final after = stats(monthStart(t.at));
    String? msg;
    final lim = after.limit[t.cat] ?? 0;
    if (lim > 0) {
      final b = before.byCat[t.cat] ?? 0, a = after.byCat[t.cat] ?? 0;
      final name = s.money.catOf(t.cat).name;
      if (b <= lim && a > lim) {
        msg = '$name is over budget by ${cash(a - lim)}';
      } else if (b < lim * .8 && a >= lim * .8) {
        msg = '$name: ${cash(lim - a)} left this month';
      }
    }
    if (msg == null && after.budget > 0) {
      if (before.spent <= after.budget && after.spent > after.budget) {
        msg = 'Over this month’s budget by ${cash(after.spent - after.budget)}';
      } else if (before.spent < after.budget * .8 && after.spent >= after.budget * .8) {
        msg = '80% of this month’s budget used';
      }
    }
    if (msg == null) return;
    final m = msg;
    // Also as a notification, so it's still there after the app closes.
    if (s.settings.notify && s.settings.budgetAlerts) alerts.showNow(90000 + t.cat.hashCode % 1000, 'Budget alert', m);
    // Shows after the "logged" toast (which keeps its UNDO for a moment).
    Timer(const Duration(milliseconds: 2400), () => showToast('⚠ $m'));
  }

  void deleteTxn(String id) {
    final t = s.money.txns.where((x) => x.id == id).firstOrNull;
    if (t == null) return;
    final sn = snap();
    s.money.txns.remove(t);
    // The bill stays ticked off; it just no longer points at a payment.
    for (final k in s.tasks) {
      if (k.txn == id) k.txn = null;
    }
    commit(sn, 'Deleted');
  }

  void setCurrency(String c) {
    s.money.currency = c;
    save();
    notifyListeners();
  }

  void setMonthBudget(int minor) {
    final sn = snap();
    s.money.budget = minor;
    commit(sn, minor > 0 ? 'Budget · ${cash(minor)} a month' : 'Monthly budget off');
  }

  void saveMCat(MCat c) {
    final sn = snap();
    final m = s.money;
    final i = m.cats.indexWhere((x) => x.id == c.id);
    if (i < 0) {
      // New spending categories go before "Other"; income ones at the end.
      final o = m.cats.indexWhere((x) => x.id == 'other');
      if (c.income || o < 0) {
        m.cats.add(c);
      } else {
        m.cats.insert(o, c);
      }
    } else {
      m.cats[i] = c;
    }
    // With saved monthly limits (from an import), the new limit applies from this month on.
    if (m.limits.isNotEmpty && !c.income) (m.limits[monthKey(nowMs())] ??= {})[c.id] = c.budget;
    commit(sn, i < 0 ? 'Category added' : 'Category saved');
  }

  void deleteMCat(String id) {
    final m = s.money;
    final c = m.cats.where((x) => x.id == id).firstOrNull;
    if (c == null || m.cats.where((x) => x.income == c.income).length <= 1) return;
    final sn = snap();
    m.cats.remove(c);
    final to = c.income ? m.fallbackIncome : m.fallbackCat;
    for (final t in m.txns) {
      if (t.cat == id) t.cat = to;
    }
    for (final t in s.tasks) {
      if (t.mcat == id) t.mcat = '';
    }
    for (final p in m.plans) {
      p.cats.remove(id);
    }
    commit(sn, 'Category deleted');
  }

  // ---------- accounts ----------

  Map<String, int> balancesNow() => balances(s.money);

  void saveAccount(Account a) {
    final sn = snap();
    final m = s.money;
    final i = m.accounts.indexWhere((x) => x.id == a.id);
    if (i < 0) {
      m.accounts.add(a);
      if (m.newAcct.isEmpty) m.defaultAcct = a.id;
    } else {
      m.accounts[i] = a;
    }
    if (a.archived && m.defaultAcct == a.id) m.defaultAcct = m.liveAccounts.firstOrNull?.id ?? '';
    commit(sn, i < 0 ? 'Account added' : 'Account saved');
  }

  /// Removes the account. Its entries stay (in spending and reports) but no longer point at it.
  void deleteAccount(String id) {
    final sn = snap();
    final m = s.money;
    m.accounts.removeWhere((a) => a.id == id);
    for (final t in m.txns) {
      if (t.acct == id) t.acct = '';
      if (t.to == id) t.to = '';
    }
    for (final p in m.plans) {
      p.accts.remove(id);
    }
    for (final t in s.tasks) {
      if (t.acct == id) t.acct = '';
    }
    if (m.defaultAcct == id) m.defaultAcct = m.liveAccounts.firstOrNull?.id ?? '';
    commit(sn, 'Account deleted');
  }

  void moveAccount(int from, int to) {
    final list = s.money.accounts;
    if (from == to || from < 0 || from >= list.length) return;
    final a = list.removeAt(from);
    list.insert(to.clamp(0, list.length), a);
    save();
    notifyListeners();
  }

  void setDefaultAcct(String id) {
    s.money.defaultAcct = id;
    save();
    notifyListeners();
  }

  /// Sets an account's balance to what the bank says, with a balance update entry for the difference.
  void updateBalance(String acctId, int balance) {
    final now = balancesNow()[acctId] ?? 0;
    final diff = balance - now;
    if (diff == 0) {
      showToast('Balance already matches');
      return;
    }
    final adjCat = s.money.cats.where((c) => c.excluded && !c.income).firstOrNull?.id ?? s.money.fallbackCat;
    saveTxn(Txn(id: uid(), title: 'Balance update', cat: adjCat, at: nowMs(), amount: diff, type: 'adjust', acct: acctId));
  }

  // ---------- goals and loans ----------

  void saveGoal(Goal g, {Txn? first}) {
    final sn = snap();
    final m = s.money;
    final i = m.goals.indexWhere((x) => x.id == g.id);
    if (i < 0) {
      m.goals.add(g);
    } else {
      m.goals[i] = g;
    }
    if (first != null) m.txns.add(first);
    commit(sn, i >= 0 ? 'Saved' : (g.isLoan ? (g.kind == 'lent' ? 'Loan given added' : 'Loan taken added') : 'Goal added'));
  }

  /// Deletes a goal or loan along with its own entries (money into/out of it).
  void deleteGoal(String id) {
    final sn = snap();
    final m = s.money;
    m.goals.removeWhere((g) => g.id == id);
    m.txns.removeWhere((t) => t.goal == id && t.isMove);
    for (final t in m.txns) {
      if (t.goal == id) t.goal = '';
    }
    commit(sn, 'Deleted');
  }

  // ---------- trip and event budgets ----------

  void savePlan(Plan p) {
    final sn = snap();
    final m = s.money;
    final i = m.plans.indexWhere((x) => x.id == p.id);
    if (i < 0) {
      m.plans.add(p);
    } else {
      m.plans[i] = p;
    }
    commit(sn, i < 0 ? 'Budget added' : 'Budget saved');
  }

  void deletePlan(String id) {
    final sn = snap();
    s.money.plans.removeWhere((p) => p.id == id);
    for (final t in s.money.txns) {
      if (t.plan == id) t.plan = '';
    }
    commit(sn, 'Budget deleted');
  }

  // ---------- review ----------

  void markReviewed(String id) {
    final t = s.money.txns.where((x) => x.id == id).firstOrNull;
    if (t == null || !t.review) return;
    t.review = false;
    save();
    notifyListeners();
  }

  void markAllReviewed() {
    final list = s.money.txns.where((t) => t.review).toList();
    if (list.isEmpty) return;
    final sn = snap();
    for (final t in list) {
      t.review = false;
    }
    commit(sn, '${list.length} marked reviewed');
  }

  // ---------- Money tab sections ----------

  void setSection(String id, bool on) {
    for (final x in s.money.sections) {
      if (x.id == id) x.on = on;
    }
    save();
    boardEpoch++;
    notifyListeners();
  }

  void moveSection(int from, int to) {
    final list = s.money.sections;
    if (from == to || from < 0 || from >= list.length) return;
    final x = list.removeAt(from);
    list.insert(to.clamp(0, list.length), x);
    save();
    notifyListeners();
  }

  void resetSections() {
    s.money.sections = defaultSections();
    save();
    boardEpoch++;
    notifyListeners();
  }

  // ---------- automatic backup ----------

  bool backingUp = false;

  /// Why the last automatic or manual backup failed ('' = it didn't).
  String backupError = '';
  Timer? _backupTimer;
  String _localDay = '';

  /// Asks where to keep the daily backup, turns it on and writes the first one.
  Future<void> chooseBackupFile() async {
    final r = await BackupFile.pick('subway-board-backup.json');
    if (r == null) return;
    s.settings
      ..backupUri = r.$1
      ..backupName = r.$2
      ..autoBackup = true;
    save();
    notifyListeners();
    if (await backupNow()) showToast('Backed up to ${r.$2}');
  }

  void setAutoBackup(bool on) {
    s.settings.autoBackup = on;
    save();
    notifyListeners();
  }

  /// Writes the backup now: the picked file (if any) and today's copy on the phone.
  /// [auto] runs refuse to replace a good backup with one that lost most of its transactions.
  Future<bool> backupNow({bool auto = false}) async {
    if (backingUp) return false;
    final st = s.settings;
    final n = s.money.txns.length;
    if (auto && st.lastBackupTxns >= 20 && n < st.lastBackupTxns ~/ 2) {
      backupError = 'Skipped: only $n transactions now vs ${st.lastBackupTxns} in the last backup. Back up by hand if that’s right.';
      notifyListeners();
      return false;
    }
    backingUp = true;
    notifyListeners();
    final text = backupJson();
    try {
      await BackupFile.writeLocal(text, todayStr());
      _localDay = todayStr();
      if (st.backupUri.isNotEmpty) await BackupFile.write(st.backupUri, text);
      st
        ..lastBackup = nowMs()
        ..lastBackupTxns = n;
      backupError = '';
      _write();
      return true;
    } catch (e) {
      backupError = '$e';
      return false;
    } finally {
      backingUp = false;
      notifyListeners();
    }
  }

  /// Once a day: a copy on the phone always; the picked file when daily backup is on.
  void _maybeAutoBackup() {
    final st = s.settings;
    final today = todayStr();
    final fileDue = st.autoBackup && st.backupUri.isNotEmpty && dstr(st.lastBackup) != today;
    if (!fileDue && _localDay == today) return;
    _backupTimer?.cancel();
    _backupTimer = Timer(const Duration(seconds: 6), () async {
      if (fileDue) {
        await backupNow(auto: true);
      } else {
        _localDay = today;
        await BackupFile.writeLocal(backupJson(), today);
      }
    });
  }

  // ---------- import ----------

  /// Adds transactions read from a CSV file (with any categories it needed).
  void importCsv(List<Txn> txns, List<MCat> newCats) {
    final sn = snap();
    final m = s.money;
    final o = m.cats.indexWhere((c) => c.id == 'other');
    m.cats.insertAll(o < 0 ? m.cats.length : o, newCats.where((c) => !c.income));
    m.cats.addAll(newCats.where((c) => c.income));
    m.txns.addAll(txns);
    tab = 'money';
    commit(sn, 'Imported ${txns.length} transaction${txns.length == 1 ? '' : 's'}');
  }

  /// Brings in a Budget app backup. Rows from an earlier import are replaced
  /// (so importing a newer backup refreshes everything); your own entries stay.
  void importBudget(BudgetImport r) {
    final sn = snap();
    final m = s.money;
    final o = m.cats.indexWhere((c) => c.id == 'other');
    m.cats.insertAll(o < 0 ? m.cats.length : o, r.newCats.where((c) => !c.income));
    m.cats.addAll(r.newCats.where((c) => c.income));
    r.catFlags.forEach((id, f) {
      final c = m.cats.where((x) => x.id == id).firstOrNull;
      if (c == null) return;
      c.rollover = f.$1;
      c.excluded = f.$2;
    });
    r.keywords.forEach((id, words) {
      final c = m.cats.where((x) => x.id == id).firstOrNull;
      if (c == null) return;
      final have = c.kw.split(',').map((w) => w.trim().toLowerCase()).toSet();
      final add = words.where((w) => !have.contains(w));
      if (add.isNotEmpty) c.kw = [if (c.kw.trim().isNotEmpty) c.kw.trim(), ...add].join(', ');
    });

    void upsert<T>(List<T> list, List<T> incoming, String Function(T) id) {
      for (final x in incoming) {
        final i = list.indexWhere((y) => id(y) == id(x));
        if (i < 0) {
          list.add(x);
        } else {
          list[i] = x;
        }
      }
    }

    upsert(m.accounts, r.accounts, (a) => a.id);
    upsert(m.goals, r.goals, (g) => g.id);
    upsert(m.plans, r.plans, (p) => p.id);

    final replaced = m.txns.where((t) => t.src == kBudgetSrc).length;
    m.txns
      ..removeWhere((t) => t.src == kBudgetSrc)
      ..addAll(r.txns);
    m.limits.addAll(r.history);
    // Limits for months after the backup: fill in categories that don't have one yet.
    for (final c in m.cats) {
      final l = r.limits[c.id];
      if (l != null && c.budget == 0) c.budget = l;
    }
    s.tasks.addAll(r.bills);

    // Starter categories nothing uses would sit next to the Budget app's own
    // (Transport beside Transit, Fun beside Entertainment): hide them. They
    // come back under Categories → Hide.
    if (r.newCats.isNotEmpty) {
      final starters = defaultMCats().map((c) => c.id).toSet()..remove('other');
      final used = {
        for (final t in m.txns) t.cat,
        for (final t in s.tasks) t.mcat,
        for (final p in m.plans) ...p.cats,
      };
      for (final c in m.cats) {
        if (starters.contains(c.id) && !used.contains(c.id) && c.budget == 0) c.archived = true;
      }
    }

    // New entries go to the account used most for spending lately.
    if (m.newAcct.isEmpty && m.accounts.isNotEmpty) {
      final since = addDays(nowMs(), -90), n = <String, int>{};
      for (final t in m.txns) {
        if (t.at >= since && t.isSpend && t.acct.isNotEmpty) n[t.acct] = (n[t.acct] ?? 0) + 1;
      }
      final top = n.entries.fold<MapEntry<String, int>?>(null, (b, e) => b == null || e.value > b.value ? e : b);
      m.defaultAcct = top?.key ?? m.liveAccounts.firstOrNull?.id ?? '';
    }
    tab = 'money';
    moneyMonth = monthStart(nowMs());
    commit(sn, replaced > 0 ? 'Refreshed · ${r.txns.length} transactions' : 'Imported ${r.txns.length} transactions');
  }
  /// Bills not yet paid: overdue, or due by the end of the viewed month.
  List<Task> unpaidBills([int? month]) {
    final end = dstr(monthEnd(month ?? moneyMonth) - 1);
    return s.tasks.where((t) => !t.done && t.isBill && t.due.isNotEmpty && t.due.compareTo(end) <= 0).toList()..sort(compareTasks);
  }

  // ---------- task list sort ----------

  /// 'due' (default) or 'prio'; kept in settings.
  String get taskSort => s.settings.extra['taskSort'] == 'prio' ? 'prio' : 'due';
  set taskSort(String v) {
    s.settings.extra['taskSort'] = v;
    _scheduleWrite();
    notifyListeners();
  }

  // ---------- quick add ----------

  /// Which kind the + sheet opens on: follows the tab you're on.
  QMode get quickDefault => switch (tab) {
        'tasks' || 'today' => QMode.task,
        'money' => QMode.spend,
        _ => QMode.event,
      };

  /// Prefill for the full event form ("More options" in quick add).
  Event? draft;

  /// Quick add's "Also: to-do / spend" carried into the full form: saved,
  /// linked, with the event (its day, time and name win).
  Task? draftTask;

  void openDraft(Event ev, {Task? task}) {
    draft = ev;
    openForm(null);
    draftTask = task;
  }

  /// Adds an event straight to the board from quick add.
  void addEvent(Event ev) {
    final sn = snap();
    s.events = [...s.events, ev];
    sel = dstr(ev.start);
    if (tab != 'board') tab = 'board';
    editing = null;
    commit(sn, 'Added to board · ${dueLabel(dstr(ev.start), nowMs()).toLowerCase()}');
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
      for (final t in s.tasks) {
        if (t.done || t.due.isEmpty) continue;
        final bill = t.isBill ? ' · ${fmtMoney(t.amount, s.money.currency)}' : '';
        for (final r in t.reminders.toSet()) {
          final at = t.remindAt(r);
          if (at == null || at <= now || at > now + 7 * kDay) continue;
          final when = t.time == null
              ? (r == 0 ? 'Due today' : (r == 1440 ? 'Due tomorrow' : 'Due ${dueLabel(t.due, at).toLowerCase()}'))
              : (r == 0 ? 'Due now' : 'Due ${r >= 1440 ? dueLabel(t.due, at).toLowerCase() : 'in ${remindLabel(r, timed: true).replaceAll(' before', '')}'}');
          final prio = t.prio == 1 ? '⚑ ' : '';
          list.add(Alert(at, '$when: $prio${t.title}', '${lineOf(t.cat).name}$bill${t.time != null && r > 0 ? ' · ${minLabel(t.time!, use24h: use24h)}' : ''}', r > 0));
        }
      }
      final st = s.settings;
      // Bills: a heads-up the morning before and the morning it's due.
      if (st.billReminders) {
        for (final t in s.tasks) {
          if (t.done || !t.isBill || t.due.isEmpty) continue;
          final d0 = dms(t.due);
          for (final (day, word) in [(addDays(d0, -1), 'tomorrow'), (d0, 'today')]) {
            final at = day + st.billTime * kMin;
            if (at <= now || at > now + 7 * kDay) continue;
            list.add(Alert(at, 'Bill due $word: ${t.title}', '${fmtMoney(t.amount, s.money.currency)}${t.repeat.isNotEmpty ? ' · repeats' : ''} · tick it off in Tasks to log it',
                false, kind: 'money'));
          }
        }
      }
      // Evening nudge to log the day's spending (skipped today if something's already logged).
      if (st.logReminder) {
        for (var i = 0; i < 7; i++) {
          final day = addDays(sod(now), i);
          final at = day + st.logTime * kMin;
          if (at <= now) continue;
          if (i == 0 && s.money.txns.any((t) => t.isSpend && t.at >= day && t.at < addDays(day, 1) && t.src.isEmpty)) continue;
          list.add(Alert(at, 'Anything to log today?', 'Take ten seconds to add today’s spending.', false, kind: 'money'));
        }
      }
      list.sort((a, b) => a.at.compareTo(b.at));
      await alerts.schedule(list.take(60).toList(), sound: s.settings.sound);
    });
  }
}

