// The + sheet: one line of text becomes a task, an event or a spend. What the
// parser picks up shows as chips you can tap away; the controls below set the
// rest by hand. "Also" makes more than one from the same line: a task with a
// time gets a calendar slot, an amount becomes a spend logged when it's ticked
// off; an event can carry a to-do (and that spend) the same way. All linked.
//
// Spends always show their category and account. The category starts on what
// you picked for the same title before (your history), then a keyword match,
// and it never changes once you've picked one yourself.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app/store.dart';
import '../core/model.dart';
import '../core/money.dart';
import '../core/quick.dart';
import '../core/tasks.dart';
import '../core/util.dart';
import 'haptics.dart';
import 'lines.dart' show SheetField;
import 'motion.dart';
import 'money.dart';
import 'pickers.dart';
import 'tasks.dart';
import 'theme.dart';
import 'widgets.dart';

Future<void> openQuickAdd(BuildContext context, {QMode? mode}) {
  final app = context.read<AppState>();
  return showSheet<void>(context, (_) => ChangeNotifierProvider.value(value: app, child: _QuickSheet(mode ?? app.quickDefault, host: context)));
}

class _QuickSheet extends StatefulWidget {
  final QMode mode;

  /// The screen that opened the sheet. Not for opening the next sheet: the
  /// tab bar with the + is taken down while the keyboard is up.
  final BuildContext host;
  const _QuickSheet(this.mode, {required this.host});
  @override
  State<_QuickSheet> createState() => _QuickSheetState();
}

class _QuickSheetState extends State<_QuickSheet> {
  late final AppState app = context.read<AppState>();
  late QMode mode = widget.mode;
  final _text = TextEditingController();
  final _focus = FocusNode();
  final _note = TextEditingController();
  final _ignore = <QKind>{};
  final _steps = <(TextEditingController, FocusNode)>[];
  bool _showNote = false;

  // Set by hand; these win over what the text says.
  String? _due, _line, _mcat, _acct;
  int? _time, _prio;
  bool? _star;
  List<int>? _remind;
  RepeatPick? _rep;

  // "Also" switches set by hand; null = follow what the text says.
  bool? _alsoCal, _alsoSpend, _alsoTodo;

  // What past entries say titles mean (built once; cheap enough for thousands).
  late final TitleMemory _memSpend = TitleMemory(app.s.money);
  late final TitleMemory _memIncome = TitleMemory(app.s.money, income: true);
  TitleMemory _mem(bool income) => income ? _memIncome : _memSpend;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
    if (app.relay != null) {
      // The widget's window only gets input focus a beat after it opens, so
      // autofocus alone can leave the keyboard down: ask again then.
      Future.delayed(const Duration(milliseconds: 350), () {
        if (!mounted) return;
        _focus.requestFocus();
        SystemChannels.textInput.invokeMethod('TextInput.show');
      });
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    _note.dispose();
    for (final (c, f) in _steps) {
      c.dispose();
      f.dispose();
    }
    super.dispose();
  }

  Quick get _q => parseQuick(_text.text, mode, app.s, app.s.money, ignore: _ignore);

  void _setMode(QMode m) {
    setState(() {
      mode = m;
      _ignore.clear();
      _alsoCal = _alsoSpend = _alsoTodo = null;
    });
    _focus.requestFocus();
  }

  // ---------- resolved values ----------
  String? _dueOf(Quick q) => _due ?? q.due;
  int? _timeOf(Quick q) => _time ?? q.time;
  String _lineOf(Quick q) => _line ?? q.line ?? app.activeCat ?? app.s.lines.first.id;
  bool _starOf(Quick q) => _star ?? q.star;
  int _prioOf(Quick q) => _prio ?? q.prio;
  String _repOf(Quick q) => _rep?.repeat ?? q.repeat ?? '';

  /// Spends and income: what money category this is and why.
  ({String cat, CatWhy? why, int times, String key}) _catOf(Quick q) {
    final m = app.s.money;
    final income = mode == QMode.spend && q.income;
    // A pick made for the other side (spend ↔ income) no longer applies.
    if (_mcat != null && m.cats.any((c) => c.id == _mcat && c.income == income)) return (cat: _mcat!, why: null, times: 0, key: '');
    if (q.has(QKind.mcat) && q.mcat != null && m.catOf(q.mcat!).income == income) return (cat: q.mcat!, why: CatWhy.keyword, times: 0, key: '#');
    final g = _mem(income).guess(q.title);
    // A bill nothing is known about goes under Bills, as before.
    if (g.why == CatWhy.fallback && mode != QMode.spend && m.cats.any((c) => c.id == 'bills' && !c.archived)) {
      return (cat: 'bills', why: CatWhy.fallback, times: 0, key: '');
    }
    return (cat: g.cat, why: g.why, times: g.times, key: g.key);
  }

  String _mcatOf(Quick q) => _catOf(q).cat;

  String _acctOf(Quick q) {
    final m = app.s.money;
    if (_acct != null && (_acct!.isEmpty || m.acctOf(_acct!) != null)) return _acct!;
    return _mem(mode == QMode.spend && q.income).acctFor(q.title, _mcatOf(q));
  }

  // ---------- "also" ----------
  /// Task mode: a slot on the board too. On by itself once there's a time.
  bool _calOn(Quick q) => mode == QMode.task && (_alsoCal ?? _timeOf(q) != null);

  /// Task or event: the amount read is logged as a spend when it's ticked off.
  bool _spendOn(Quick q) => mode != QMode.spend && q.amount != null && (_alsoSpend ?? true);

  /// Event mode: a to-do to tick off too (always, when there's a spend).
  bool _todoOn(Quick q) => mode == QMode.event && (_spendOn(q) || (_alsoTodo ?? false));

  Future<void> _toggleCal(Quick q) async {
    tick();
    if (_calOn(q)) return setState(() => _alsoCal = false);
    // A slot needs a time; ask for one first.
    if (_timeOf(q) == null) {
      final cur = (DateTime.now().hour + 1) * 60;
      final x = await pickTime(context, TimeOfDay(hour: (cur ~/ 60) % 24, minute: 0));
      if (x == null || !mounted) return;
      _time = x.hour * 60 + x.minute;
      _ignore.remove(QKind.time);
    }
    setState(() => _alsoCal = true);
  }

  void _toggleSpend(Quick q) {
    tick();
    setState(() => _alsoSpend = !_spendOn(q));
  }

  void _toggleTodo(Quick q) {
    tick();
    setState(() {
      if (_todoOn(q)) {
        _alsoTodo = false;
        if (_spendOn(q)) _alsoSpend = false; // a spend rides on the to-do's tick
      } else {
        _alsoTodo = true;
      }
    });
  }

  List<SubTask> _subs() => [
        for (final (c, _) in _steps)
          if (c.text.trim().isNotEmpty) SubTask(id: uid(), title: c.text.trim()),
      ];

  /// The to-do an event carries: same name, line, day, time and repeat.
  Task _taskFor(Event ev, Quick q) {
    final spend = _spendOn(q);
    final d = DateTime.fromMillisecondsSinceEpoch(ev.start);
    return Task(
      id: uid(),
      title: ev.title,
      cat: ev.cat,
      due: dstr(ev.start),
      time: ev.allDay ? null : d.hour * 60 + d.minute,
      repeat: ev.repeat?.freq ?? '',
      amount: spend ? q.amount! : 0,
      mcat: spend ? _mcatOf(q) : '',
      acct: spend ? _acctOf(q) : '',
    );
  }

  /// The task this line makes (task mode), or null with a nudge.
  Task? _buildTask(Quick q, {bool quiet = false}) {
    final now = nowMs();
    final title = q.title.trim();
    if (title.isEmpty && !quiet) {
      _nudge('Type the task first');
      return null;
    }
    var due = _dueOf(q) ?? '';
    final time = _timeOf(q);
    final repeat = _repOf(q);
    // A time with no day means the next time it comes round.
    if (due.isEmpty && time != null) due = sod(now) + time * kMin > now ? dstr(now) : dstr(addDays(sod(now), 1));
    if (due.isEmpty && (repeat.isNotEmpty || _remind != null)) due = dstr(now);
    final spend = _spendOn(q);
    return Task(
      id: uid(),
      title: title,
      notes: clip(_note.text.trim(), 2000),
      cat: _lineOf(q),
      due: due,
      time: due.isEmpty ? null : time,
      star: _starOf(q),
      prio: _prioOf(q),
      repeat: repeat,
      repFromDone: _rep?.fromDone ?? false,
      repUntil: _rep?.until ?? '',
      repLeft: _rep?.left,
      remind: due.isEmpty ? null : _remind,
      amount: spend ? q.amount! : 0,
      mcat: spend ? _mcatOf(q) : '',
      acct: spend ? _acctOf(q) : '',
      subs: _subs(),
    );
  }

  /// How many spends this sheet has logged with "add another".
  int _logged = 0;

  void _submit({bool again = false}) {
    final q = _q;
    final now = nowMs();
    final title = q.title.trim();
    switch (mode) {
      case QMode.task:
        final t = _buildTask(q);
        if (t == null) return;
        final cal = _calOn(q) && t.time != null;
        Navigator.pop(context);
        app.addLinked(task: t, event: cal ? app.eventFromTask(t, dur: q.dur ?? 30) : null);
      case QMode.event:
        if (title.isEmpty) return _nudge('Name the event first');
        final ev = _event(q, title);
        final t = _todoOn(q) ? _taskFor(ev, q) : null;
        Navigator.pop(context);
        app.addLinked(task: t, event: ev);
      case QMode.spend:
        final amt = q.amount;
        if (amt == null || amt <= 0) return _nudge('Add an amount, like “Lunch 180”');
        final due = _dueOf(q);
        final at = due == null || due == dstr(now) ? now : dms(due) + 13 * kHour;
        final txn = Txn(id: uid(), title: title, cat: _mcatOf(q), at: at, amount: amt, income: q.income, acct: _acctOf(q), note: _note.text.trim());
        if (!again) {
          Navigator.pop(context);
          app.saveTxn(txn);
          return;
        }
        // Keep going: same day and account, a fresh line and category.
        app.saveTxn(txn);
        tick();
        setState(() {
          _logged++;
          _text.clear();
          _note.clear();
          _showNote = false;
          _mcat = null;
          _ignore.clear();
        });
        _focus.requestFocus();
    }
  }

  Event _event(Quick q, String title) {
    final now = nowMs();
    final day = _dueOf(q) ?? (app.tab == 'board' ? app.sel : dstr(now));
    final d0 = dms(day);
    final t = _timeOf(q);
    final int start;
    if (t != null) {
      start = d0 + t * kMin;
    } else if (day == dstr(now)) {
      start = (now / 900000).ceil() * 900000;
    } else {
      start = d0 + 9 * kHour;
    }
    final line = _lineOf(q);
    return Event(
      id: uid(),
      title: title,
      cat: line,
      catManual: _line != null || q.has(QKind.line),
      start: start,
      end: start + (q.dur ?? 30) * kMin,
      repeat: q.repeat != null && kRepeat.containsKey(q.repeat) ? Repeat(q.repeat!) : null,
      notes: _note.text.trim(),
    );
  }

  void _nudge(String msg) {
    buzz();
    app.showToast(msg);
    _focus.requestFocus();
  }

  void _drop(QKind k) {
    tick();
    setState(() {
      _ignore.add(k);
      switch (k) {
        case QKind.date:
          _due = null;
        case QKind.time:
          _time = null;
        case QKind.line:
          _line = null;
        case QKind.mcat:
          _mcat = null;
        case QKind.star:
          _star = null;
        case QKind.prio:
          _prio = null;
        case QKind.repeat:
          _rep = null;
        default:
      }
    });
  }

  Future<void> _pickDate(Quick q) async {
    final cur = _dueOf(q);
    final d = await pickDate(context, DateTime.fromMillisecondsSinceEpoch(cur == null || cur.isEmpty ? sod(nowMs()) : dms(cur)));
    if (d != null) {
      setState(() {
        _due = dstr(d.millisecondsSinceEpoch);
        _ignore.remove(QKind.date);
      });
    }
  }

  Future<void> _pickTime(Quick q) async {
    final cur = _timeOf(q) ?? (DateTime.now().hour + 1) * 60;
    final x = await pickTime(context, TimeOfDay(hour: (cur ~/ 60) % 24, minute: cur % 60));
    if (x != null) {
      setState(() {
        _time = x.hour * 60 + x.minute;
        _ignore.remove(QKind.time);
      });
    }
  }

  Future<void> _pickLine(Quick q) async {
    final x = await pickOption<String>(context, 'Line', [for (final l in app.s.lines) (l.id, '${l.label} · ${l.name}')], _lineOf(q));
    if (x != null) setState(() => _line = x);
  }

  Future<void> _pickCat(Quick q) async {
    final income = mode == QMode.spend && q.income;
    final x = await pickMoneyCat(context, income: income, current: _mcatOf(q), recent: _mem(income).recentCats);
    if (x != null && mounted) setState(() => _mcat = x);
  }

  Future<void> _pickAcct(Quick q) async {
    final x = await pickAccount(context, app.s.money, _acctOf(q), title: mode == QMode.spend && q.income ? 'Into account' : 'Pay from');
    if (x != null && mounted) setState(() => _acct = x);
  }

  Future<void> _pickRepeat(Quick q) async {
    final x = await pickRepeat(context, repeat: _repOf(q), fromDone: _rep?.fromDone ?? false, until: _rep?.until ?? '', left: _rep?.left, due: _dueOf(q) ?? '');
    if (x == null || !mounted) return;
    setState(() {
      _rep = x;
      _ignore.add(QKind.repeat); // the sheet's choice replaces what the text said
    });
  }

  Future<void> _pickRemind(Quick q) async {
    final timed = _timeOf(q) != null;
    final x = await pickReminders(context, _remind ?? const [0], timed: timed);
    if (x == null || !mounted) return;
    setState(() {
      _remind = x;
      if (_dueOf(q) == null && x.isNotEmpty) _due = todayStr();
    });
  }

  Future<void> _pickPrio(Quick q) async {
    final x = await pickOption<int>(context, 'Priority', const [(1, '🔴  P1 · do first'), (2, '🟠  P2'), (3, '🔵  P3'), (0, 'None')], _prioOf(q));
    if (x != null && mounted) {
      setState(() {
        _prio = x;
        _ignore.add(QKind.prio);
      });
    }
  }

  void _addStep() {
    tick();
    final c = TextEditingController(), f = FocusNode();
    setState(() => _steps.add((c, f)));
    WidgetsBinding.instance.addPostFrameCallback((_) => f.requestFocus());
  }

  /// Opens the full task editor with everything filled in.
  void _more(Quick q) {
    final t = _buildTask(q, quiet: true)!;
    final cal = _calOn(q) && t.time != null;
    final host = Navigator.of(context).context; // the tab bar that opened this is gone while typing
    Navigator.pop(context);
    if (host.mounted) openTaskSheet(host, null, draft: t, onBoard: cal);
  }

  /// Puts a past title in place of what's typed so far, keeping the amount and date.
  void _useTitle(Quick q, String title) {
    tick();
    final t = _text.text;
    final i = q.title.isEmpty ? -1 : t.toLowerCase().indexOf(q.title.toLowerCase());
    final next = i >= 0 ? t.replaceRange(i, i + q.title.length, title) : '$title $t';
    _text.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: next.length));
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final q = _q;
    final now = nowMs();
    final m = app.s.money;
    final due = _dueOf(q), time = _timeOf(q);
    final line = app.lineOf(_lineOf(q));
    final prio = _prioOf(q);
    final rep = _repOf(q);
    final onBg = pal.light ? const Color(0xFF111111) : Colors.white;
    final onFg = pal.light ? Colors.white : Colors.black;

    // Chips for what was read (or set), each with an ✕.
    final chips = <(QKind, String, Widget?)>[];
    if (due != null) chips.add((QKind.date, dueLabel(due, now), SvgIcon('cal', size: 15, color: pal.ink)));
    if (time != null && mode != QMode.spend) chips.add((QKind.time, minLabel(time, use24h: app.use24h), SvgIcon('clock', size: 15, color: pal.ink)));
    if (q.dur != null) chips.add((QKind.dur, _durText(q.dur!), null));
    if (rep.isNotEmpty && mode != QMode.spend) chips.add((QKind.repeat, repeatLabel(rep), SvgIcon('repeat', size: 15, color: pal.ink)));
    if (q.amount != null) chips.add((QKind.amount, '${q.income && mode == QMode.spend ? '+' : ''}${app.cash(q.amount!)}', null));
    if (mode != QMode.spend && (_line != null || q.has(QKind.line) || (q.line != null && _text.text.isNotEmpty))) {
      chips.add((QKind.line, line.name, LineBadge(line, size: 18, fontSize: 9)));
    }
    if (prio > 0 && mode == QMode.task) chips.add((QKind.prio, 'P$prio', PrioFlag(prio)));
    if (_starOf(q) && mode == QMode.task) chips.add((QKind.star, 'Starred', SvgIcon('star-on', size: 15, color: kYellow)));

    final hint = switch (mode) {
      QMode.task => 'Submit HW fri 5pm',
      QMode.event => 'Gym tomorrow 6pm for 1h',
      QMode.spend => 'Lunch 180',
    };
    final cal = _calOn(q), spend = _spendOn(q), todo = _todoOn(q);
    final money = spend ? ' · ${app.cash(q.amount!)}' : '';
    final income = mode == QMode.spend && q.income;
    final catInfo = (mode == QMode.spend || spend) ? _catOf(q) : null;
    final cat = catInfo == null ? null : m.catOf(catInfo.cat);
    final acct = (mode == QMode.spend || spend) ? _acctOf(q) : '';
    final acctName = m.acctOf(acct)?.name;
    final cta = switch (mode) {
      QMode.task => cal ? 'Add task + event$money' : (spend ? 'Add bill$money' : 'Add task'),
      QMode.event => 'Add to board${todo ? ' + task' : ''}$money',
      QMode.spend => q.amount != null
          ? '${income ? 'Log income' : 'Log'} ${app.cash(q.amount!)} · ${cat!.name}${acctName != null ? ' · $acctName' : ''}'
          : (income ? 'Log income' : 'Log spend'),
    };

    // "Also": what else this line makes, each a switch.
    final dur = q.dur ?? 30;
    final also = <Widget>[
      if (mode == QMode.task)
        _AlsoChip(
          key: const ValueKey('also-cal'),
          on: cal,
          label: cal && time != null ? 'Calendar · ${minLabel(time, use24h: app.use24h)}${dur != 30 ? ' · ${_durText(dur)}' : ''}' : 'Calendar',
          semantics: cal ? 'Also on the calendar, on. Tap to turn off' : 'Also add to the calendar',
          onTap: () => _toggleCal(q),
        ),
      if (mode == QMode.event)
        _AlsoChip(
          key: const ValueKey('also-todo'),
          on: todo,
          label: 'To-do',
          semantics: todo ? 'Also a to-do, on. Tap to turn off' : 'Also add a to-do to tick off',
          onTap: () => _toggleTodo(q),
        ),
      if (mode != QMode.spend && q.amount != null)
        _AlsoChip(
          key: const ValueKey('also-spend'),
          on: spend,
          label: '${app.cash(q.amount!)}${spend ? ' when done' : ' spend'}',
          semantics: spend ? 'Also log ${app.cash(q.amount!)} when it is done, on. Tap to turn off' : 'Also log ${app.cash(q.amount!)} as a spend when done',
          onTap: () => _toggleSpend(q),
        ),
    ];

    Widget tool(String label, Widget icon, VoidCallback onTap, {bool on = false}) => Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          child: Pressable(
            scale: .9,
            onTap: onTap,
            child: AnimatedContainer(
              duration: Motion.snappyDur,
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 11),
              decoration: BoxDecoration(color: on ? onBg : pal.field, borderRadius: BorderRadius.circular(18)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                icon,
                const SizedBox(width: 6),
                Text(label, style: inter(13, FontWeight.w700, color: on ? onFg : pal.ink)),
              ]),
            ),
          ),
        );
    Color ic(bool on) => on ? onFg : pal.ink;

    Widget label(String text, {String? action, VoidCallback? onAction}) => Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 4),
          child: Row(children: [
            Text(text, style: inter(11, FontWeight.w800, ls: .1, color: pal.label)),
            const Spacer(),
            if (action != null)
              Pressable(
                onTap: onAction,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                  child: Text(action, style: cond(14, FontWeight.w800, ls: .1, color: pal.light ? kAccentInk : kYellow)),
                ),
              ),
          ]),
        );

    // Why the category is what it is, in words.
    String? why;
    if (catInfo != null) {
      why = switch (catInfo.why) {
        null => 'Your pick',
        CatWhy.history => catInfo.times > 1 ? 'What you picked for “${catInfo.key}” · ${catInfo.times} times' : 'What you picked for “${catInfo.key}” last time',
        CatWhy.keyword => catInfo.key == '#' ? 'From the #tag' : 'Matched a keyword of ${cat!.name}',
        CatWhy.fallback => q.title.isEmpty ? null : 'Nothing to go on yet · tap the right one',
      };
    }
    final tag = catInfo?.why == CatWhy.history ? 'USUAL' : null;

    final suggestions = mode == QMode.spend && _text.text.trim().isNotEmpty
        ? _mem(income).complete(q.title).where((s) => s.toLowerCase() != q.title.toLowerCase()).toList()
        : const <String>[];

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Segmented<QMode>(
          options: const [(QMode.task, 'TASK'), (QMode.event, 'EVENT'), (QMode.spend, 'SPEND')],
          value: mode,
          onChanged: _setMode,
          track: pal.field,
          thumb: kYellow,
          on: Colors.black,
          off: pal.label,
          style: cond(15, FontWeight.w800, ls: .08),
          segWidth: 78,
          height: 38,
        ),
        const Spacer(),
        Pressable(
          scale: .85,
          onTap: () => Navigator.pop(context),
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: pal.btn, shape: BoxShape.circle),
            child: Text('✕', style: TextStyle(fontSize: 14, color: pal.ink)),
          ),
        ),
      ]),
      const SizedBox(height: 12),
      TextField(
        controller: _text,
        focusNode: _focus,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        keyboardType: TextInputType.text,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        maxLines: null,
        style: inter(23, FontWeight.w700, color: pal.ink),
        cursorColor: kYellow,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: inter(23, FontWeight.w700, color: pal.placeholder),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
        ),
      ),
      // Past titles that start the same way: one tap fills it in (and its category).
      if (suggestions.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: SizedBox(
            height: 32,
            child: ListView(scrollDirection: Axis.horizontal, clipBehavior: Clip.none, children: [
              for (final s in suggestions)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Pressable(
                    scale: .92,
                    onTap: () => _useTitle(q, s),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: pal.label.withValues(alpha: .45))),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.history_rounded, size: 15, color: pal.label),
                        const SizedBox(width: 5),
                        Text(s, style: inter(13, FontWeight.w600, color: pal.ink)),
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      AnimatedSize(
        duration: Motion.snappyDur,
        curve: Motion.snappy,
        alignment: Alignment.topLeft,
        child: chips.isEmpty
            ? const SizedBox(width: double.infinity, height: 6)
            : Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 2),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final (k, label, icon) in chips) _ParsedChip(key: ValueKey(k), label: label, icon: icon, onClear: () => _drop(k)),
                ]),
              ),
      ),

      // ---------- spend: category, account, date ----------
      if (mode == QMode.spend) ...[
        label(income ? 'INCOME CATEGORY' : 'CATEGORY', action: 'ALL ›', onAction: () => _pickCat(q)),
        CatStrip(
          cats: stripOrder(m, income: income, selected: catInfo!.cat, recent: _mem(income).recentCats),
          selected: catInfo.cat,
          tag: tag,
          onPick: (id) {
            tick();
            setState(() => _mcat = id);
          },
          onAll: () => _pickCat(q),
        ),
        if (why != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(children: [
              Icon(catInfo.why == CatWhy.fallback ? Icons.help_outline_rounded : Icons.check_rounded, size: 14, color: catInfo.why == CatWhy.fallback ? kYellow : pal.label),
              const SizedBox(width: 5),
              Expanded(child: Text(why, maxLines: 1, overflow: TextOverflow.ellipsis, style: inter(12, FontWeight.w500, color: pal.label))),
            ]),
          ),
        if (m.accounts.any((a) => !a.archived)) ...[
          label(income ? 'INTO ACCOUNT' : 'FROM ACCOUNT'),
          AcctChips(m: m, selected: acct, onPick: (id) => setState(() => _acct = id)),
        ],
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          tool(due == null ? 'Today' : dueLabel(due, now), SvgIcon('cal', size: 15, color: ic(due != null)), () => _pickDate(q), on: due != null),
          tool('Note', Icon(Icons.notes_rounded, size: 16, color: ic(_showNote)), () => setState(() => _showNote = !_showNote), on: _showNote),
          if (app.relay == null)
            tool('More', Icon(Icons.tune, size: 16, color: pal.ink), () {
              final host = Navigator.of(context).context; // the tab bar that opened this is gone while typing
              final c = _mcatOf(q), a = _acctOf(q), note = _note.text.trim();
              Navigator.pop(context);
              if (host.mounted) {
                openTxnSheet(host, null,
                    title: q.title.trim(), amount: q.amount, cat: c, income: q.income, acct: a, note: note, at: due == null || due == todayStr() ? null : dms(due) + 13 * kHour);
              }
            }),
        ]),
      ],

      // ---------- task / event: when, and the rest ----------
      if (mode != QMode.spend) ...[
        const SizedBox(height: 8),
        DatePresets(
          value: due,
          onPick: (d) => setState(() {
            _due = due == d ? null : d;
            if (_due == null) {
              _ignore.add(QKind.date);
            } else {
              _ignore.remove(QKind.date);
            }
          }),
          onMore: () => _pickDate(q),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          tool(time == null ? 'Time' : minLabel(time, use24h: app.use24h), SvgIcon('clock', size: 15, color: ic(time != null)), () => _pickTime(q), on: time != null),
          if (mode == QMode.task) ...[
            tool(
              _remind == null ? 'Remind' : (_remind!.isEmpty ? 'No reminder' : '${remindLabel(_remind!.first, timed: time != null)}${_remind!.length > 1 ? ' +${_remind!.length - 1}' : ''}'),
              Icon(_remind?.isNotEmpty == true ? Icons.notifications_active_rounded : Icons.notifications_none_rounded, size: 16, color: ic(_remind?.isNotEmpty == true)),
              () => _pickRemind(q),
              on: _remind?.isNotEmpty == true,
            ),
            tool(rep.isEmpty ? 'Repeat' : repeatLabel(rep), SvgIcon('repeat', size: 15, color: ic(rep.isNotEmpty)), () => _pickRepeat(q), on: rep.isNotEmpty),
          ],
          tool(line.name, LineBadge(line, size: 20, fontSize: 10), () => _pickLine(q)),
          if (mode == QMode.task) ...[
            tool(prio == 0 ? 'Priority' : 'P$prio', prio == 0 ? Icon(Icons.outlined_flag_rounded, size: 16, color: pal.ink) : PrioFlag(prio, size: 16), () => _pickPrio(q)),
            tool('Star', SvgIcon(_starOf(q) ? 'star-on' : 'star', size: 15, color: _starOf(q) ? kYellow : pal.ink), () {
              tick();
              setState(() => _star = !_starOf(q));
            }),
            tool('Steps', Icon(Icons.checklist_rounded, size: 16, color: pal.ink), _addStep),
          ],
          tool('Note', Icon(Icons.notes_rounded, size: 16, color: ic(_showNote)), () => setState(() => _showNote = !_showNote), on: _showNote),
          // "More" opens the full form, which the widget's quick-add window doesn't have.
          if (app.relay == null)
            tool('More', Icon(Icons.tune, size: 16, color: pal.ink), () {
              if (mode == QMode.task) return _more(q);
              final ev = _event(q, q.title.trim());
              final t = _todoOn(q) ? _taskFor(ev, q) : null;
              Navigator.pop(context);
              app.openDraft(ev, task: t);
            }),
        ]),
        if (also.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              ExcludeSemantics(child: Text('ALSO', style: cond(13, FontWeight.w800, ls: .12, color: pal.label))),
              const SizedBox(width: 10),
              Expanded(child: Wrap(spacing: 8, runSpacing: 8, children: also)),
            ]),
          ),
        // A bill: which category it's logged under and which account pays.
        if (spend && cat != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              _MiniChip(text: '${cat.emoji}  ${cat.name}', color: hexColor(cat.color), onTap: () => _pickCat(q)),
              if (m.accounts.any((a) => !a.archived)) _MiniChip(text: acctText(m, acct, none: 'No account'), onTap: () => _pickAcct(q)),
              Text('when paid', style: inter(12, FontWeight.w500, color: pal.label)),
            ]),
          ),
        if (_steps.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Column(children: [
              for (final (i, (c, f)) in _steps.indexed)
                Row(children: [
                  Container(
                    width: 18,
                    height: 18,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: hexColor(line.color), width: 2)),
                  ),
                  Expanded(
                    child: TextField(
                      controller: c,
                      focusNode: f,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => _addStep(),
                      style: inter(15, FontWeight.w500, color: pal.ink),
                      cursorColor: kYellow,
                      decoration: InputDecoration(
                        hintText: 'Step ${i + 1}',
                        hintStyle: inter(15, FontWeight.w500, color: pal.placeholder),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                  Pressable(
                    scale: .8,
                    onTap: () => setState(() {
                      final x = _steps.removeAt(i);
                      x.$1.dispose();
                      x.$2.dispose();
                    }),
                    child: Padding(padding: const EdgeInsets.all(6), child: Icon(Icons.close, size: 17, color: pal.label)),
                  ),
                ]),
            ]),
          ),
      ],
      if (_showNote)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: SheetField(controller: _note, hint: mode == QMode.task ? 'Details' : 'Note', maxLines: 3),
        ),
      SheetBtn(cta, kind: BtnKind.yellow, onTap: _submit),
      if (mode == QMode.spend && app.relay == null && (q.amount != null || _logged > 0))
        Center(
          child: Pressable(
            onTap: q.amount != null ? () => _submit(again: true) : null,
            child: Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 2),
              child: Text(
                q.amount != null ? '＋  LOG AND ADD ANOTHER' : '$_logged LOGGED · ADD THE NEXT ONE',
                style: cond(15, FontWeight.w800, ls: .08, color: q.amount != null ? (pal.light ? kAccentInk : kYellow) : pal.label),
              ),
            ),
          ),
        ),
      if (_text.text.isEmpty && _logged == 0)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            switch (mode) {
              QMode.task => 'Try “Rent ₹15000 1st monthly”, “Gym every 2 days !1”',
              QMode.event => 'Try “Lab meeting wed 3pm for 90m #work” or “Dinner fri 8pm ₹1200”',
              QMode.spend => 'Try “Metro 40”, “Groceries 1.2k yesterday”, “+5000 refund”',
            },
            textAlign: TextAlign.center,
            style: inter(12.5, FontWeight.w500, height: 1.45, color: pal.label),
          ),
        ),
    ]);
  }
}

String _durText(int m) => m % 60 == 0 ? '${m ~/ 60} hr' : (m > 60 ? '${m ~/ 60} hr ${m % 60} min' : '$m min');

/// A small rounded chip that opens a picker (a bill's category or account).
class _MiniChip extends StatelessWidget {
  final String text;
  final Color? color;
  final VoidCallback onTap;
  const _MiniChip({required this.text, required this.onTap, this.color});
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final c = color;
    return Pressable(
      scale: .92,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: c ?? pal.field, borderRadius: BorderRadius.circular(16)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(text, style: inter(13, FontWeight.w700, color: c == null ? pal.ink : (c.computeLuminance() > .4 ? Colors.black : Colors.white))),
          const SizedBox(width: 3),
          Icon(Icons.expand_more_rounded, size: 16, color: c == null ? pal.label : (c.computeLuminance() > .4 ? Colors.black54 : Colors.white70)),
        ]),
      ),
    );
  }
}

/// An "Also" switch: outlined with a + when off, solid yellow with a tick when on.
class _AlsoChip extends StatelessWidget {
  final bool on;
  final String label, semantics;
  final VoidCallback onTap;
  const _AlsoChip({super.key, required this.on, required this.label, required this.semantics, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final reduce = MediaQuery.disableAnimationsOf(context);
    final fg = on ? Colors.black : pal.ink;
    return Semantics(
      button: true,
      toggled: on,
      label: semantics,
      excludeSemantics: true,
      child: Pressable(
        scale: .92,
        onTap: onTap,
        child: AnimatedContainer(
          duration: reduce ? Duration.zero : Motion.snappyDur,
          curve: Motion.snappy,
          height: 36,
          padding: const EdgeInsets.fromLTRB(10, 0, 12, 0),
          decoration: BoxDecoration(
            color: on ? kYellow : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: on ? kYellow : pal.label.withValues(alpha: .55), width: 1.4),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AnimatedSwitcher(
              duration: reduce ? Duration.zero : Motion.snappyDur,
              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
              child: on
                  ? SvgIcon('check', key: const ValueKey('on'), size: 14, color: fg)
                  : Icon(Icons.add, key: const ValueKey('off'), size: 16, color: fg),
            ),
            const SizedBox(width: 6),
            Text(label, style: inter(13.5, FontWeight.w700, color: fg)),
          ]),
        ),
      ),
    );
  }
}

class _ParsedChip extends StatelessWidget {
  final String label;
  final Widget? icon;
  final VoidCallback onClear;
  const _ParsedChip({super.key, required this.label, required this.icon, required this.onClear});
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final reduce = MediaQuery.disableAnimationsOf(context);
    final chip = Semantics(
      button: true,
      label: '$label, tap to remove',
      excludeSemantics: true,
      child: Pressable(
        scale: .9,
        onTap: onClear,
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
          decoration: BoxDecoration(
            color: kYellow.withValues(alpha: pal.light ? .35 : .16),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kYellow.withValues(alpha: .7), width: 1.2),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[icon!, const SizedBox(width: 6)],
            Text(label, style: inter(13.5, FontWeight.w700, color: pal.ink)),
            const SizedBox(width: 4),
            Icon(Icons.close, size: 14, color: pal.label),
          ]),
        ),
      ),
    );
    if (reduce) return chip;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Motion.bouncyDur,
      curve: Motion.bouncy,
      builder: (_, v, child) => Transform.scale(scale: .7 + .3 * v, child: Opacity(opacity: v.clamp(0.0, 1.0), child: child)),
      child: chip,
    );
  }
}
