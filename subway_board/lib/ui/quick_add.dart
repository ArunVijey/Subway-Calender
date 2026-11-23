// The + sheet: one line of text becomes a task, an event or a spend. What the
// parser picks up shows as chips you can tap away; the buttons below set the
// rest by hand. "Also" makes more than one from the same line: a task with a
// time gets a calendar slot, an amount becomes a spend logged when it's ticked
// off; an event can carry a to-do (and that spend) the same way. All linked.
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
import 'motion.dart';
import 'money.dart';
import 'tasks.dart';
import 'theme.dart';
import 'widgets.dart';

Future<void> openQuickAdd(BuildContext context, {QMode? mode}) {
  final app = context.read<AppState>();
  return showSheet<void>(context, (_) => ChangeNotifierProvider.value(value: app, child: _QuickSheet(mode ?? app.quickDefault, host: context)));
}

class _QuickSheet extends StatefulWidget {
  final QMode mode;

  /// The screen that opened the sheet; still mounted after the sheet closes.
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
  final _ignore = <QKind>{};

  // Set by hand; these win over what the text says.
  String? _due, _line, _mcat;
  int? _time;
  bool? _star;

  // "Also" switches set by hand; null = follow what the text says.
  bool? _alsoCal, _alsoSpend, _alsoTodo;

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
  String _mcatOf(Quick q) {
    final m = app.s.money;
    if (_mcat != null) return _mcat!;
    if (q.income) return matchMCat(m, q.title, income: true) ?? m.fallbackIncome;
    return q.mcat ?? m.fallbackCat;
  }
  bool _starOf(Quick q) => _star ?? q.star;

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
      mcat: spend && (_mcat != null || q.mcat != null) ? _mcatOf(q) : '',
    );
  }

  void _submit() {
    final q = _q;
    final now = nowMs();
    final title = q.title.trim();
    switch (mode) {
      case QMode.task:
        if (title.isEmpty) return _nudge('Type the task first');
        var due = _dueOf(q) ?? '';
        final time = _timeOf(q);
        // A time with no day means the next time it comes round.
        if (due.isEmpty && time != null) due = sod(now) + time * kMin > now ? dstr(now) : dstr(addDays(sod(now), 1));
        if (due.isEmpty && q.repeat != null) due = dstr(now);
        final cal = _calOn(q) && time != null;
        final spend = _spendOn(q);
        final t = Task(
          id: uid(),
          title: title,
          cat: _lineOf(q),
          due: due,
          time: due.isEmpty ? null : time,
          star: _starOf(q),
          repeat: q.repeat ?? '',
          amount: spend ? q.amount! : 0,
          mcat: spend && (_mcat != null || q.mcat != null) ? _mcatOf(q) : '',
        );
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
        Navigator.pop(context);
        app.saveTxn(Txn(id: uid(), title: title, cat: _mcatOf(q), at: at, amount: amt, income: q.income, acct: app.s.money.newAcct));
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
      repeat: q.repeat != null ? Repeat(q.repeat!) : null,
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
        default:
      }
    });
  }

  Future<void> _pickDate(Quick q) async {
    final cur = _dueOf(q);
    final d = await pickDate(context, DateTime.fromMillisecondsSinceEpoch(cur == null ? sod(nowMs()) : dms(cur)));
    if (d != null) setState(() => _due = dstr(d.millisecondsSinceEpoch));
  }

  Future<void> _pickTime(Quick q) async {
    final cur = _timeOf(q) ?? (DateTime.now().hour + 1) * 60;
    final x = await pickTime(context, TimeOfDay(hour: (cur ~/ 60) % 24, minute: cur % 60));
    if (x != null) setState(() => _time = x.hour * 60 + x.minute);
  }

  Future<void> _pickLine(Quick q) async {
    final x = await pickOption<String>(context, 'Line', [for (final l in app.s.lines) (l.id, '${l.label} · ${l.name}')], _lineOf(q));
    if (x != null) setState(() => _line = x);
  }

  Future<void> _pickCat(Quick q) async {
    final x = await pickOption<String>(context, 'Category', [for (final c in q.income ? app.s.money.incomeCats : app.s.money.spendCats) (c.id, '${c.emoji}  ${c.name}')], _mcatOf(q));
    if (x != null) setState(() => _mcat = x);
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final q = _q;
    final now = nowMs();
    final due = _dueOf(q), time = _timeOf(q);
    final line = app.lineOf(_lineOf(q));
    final cat = app.s.money.catOf(_mcatOf(q));

    // Chips for what was read (or set), each with an ✕.
    final chips = <(QKind, String, Widget?)>[];
    if (due != null) chips.add((QKind.date, dueLabel(due, now), SvgIcon('cal', size: 15, color: pal.ink)));
    if (time != null && mode != QMode.spend) chips.add((QKind.time, minLabel(time, use24h: app.use24h), SvgIcon('clock', size: 15, color: pal.ink)));
    if (q.dur != null) chips.add((QKind.dur, q.dur! % 60 == 0 ? '${q.dur! ~/ 60} hr' : (q.dur! > 60 ? '${q.dur! ~/ 60} hr ${q.dur! % 60} min' : '${q.dur} min'), null));
    if (q.repeat != null) chips.add((QKind.repeat, kTaskRepeatLabels[q.repeat]!, SvgIcon('repeat', size: 15, color: pal.ink)));
    if (q.amount != null) chips.add((QKind.amount, '${q.income && mode == QMode.spend ? '+' : ''}${app.cash(q.amount!)}', null));
    if (mode != QMode.spend && (_line != null || q.has(QKind.line) || (q.line != null && _text.text.isNotEmpty))) {
      chips.add((QKind.line, line.name, LineBadge(line, size: 18, fontSize: 9)));
    }
    if ((mode == QMode.spend || q.amount != null) && (_mcat != null || q.mcat != null)) chips.add((QKind.mcat, cat.name, Text(cat.emoji, style: const TextStyle(fontSize: 14))));
    if (_starOf(q) && mode == QMode.task) chips.add((QKind.star, 'Starred', const SvgIcon('star-on', size: 15, color: kYellow)));

    final hint = switch (mode) {
      QMode.task => 'Submit HW fri 5pm',
      QMode.event => 'Gym tomorrow 6pm for 1h',
      QMode.spend => 'Lunch 180',
    };
    final cal = _calOn(q), spend = _spendOn(q), todo = _todoOn(q);
    final money = spend ? ' · ${app.cash(q.amount!)}' : '';
    final cta = switch (mode) {
      QMode.task => cal ? 'Add task + event$money' : (spend ? 'Add bill$money' : 'Add task'),
      QMode.event => 'Add to board${todo ? ' + task' : ''}$money',
      QMode.spend => q.amount != null ? '${q.income ? 'Log income' : 'Log'} ${app.cash(q.amount!)}' : 'Log spend',
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
          label: 'Spend ${app.cash(q.amount!)}${spend ? ' · when done' : ''}',
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
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(color: on ? (pal.light ? const Color(0xFF111111) : Colors.white) : pal.field, borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                icon,
                const SizedBox(width: 6),
                Text(label, style: inter(13.5, FontWeight.w700, color: on ? (pal.light ? Colors.white : Colors.black) : pal.ink)),
              ]),
            ),
          ),
        );

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
      const SizedBox(height: 14),
      TextField(
        controller: _text,
        focusNode: _focus,
        autofocus: true,
        textCapitalization: mode == QMode.spend ? TextCapitalization.none : TextCapitalization.sentences,
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
      AnimatedSize(
        duration: Motion.snappyDur,
        curve: Motion.snappy,
        alignment: Alignment.topLeft,
        child: chips.isEmpty
            ? const SizedBox(width: double.infinity, height: 8)
            : Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 4),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final (k, label, icon) in chips)
                    _ParsedChip(key: ValueKey(k), label: label, icon: icon, onClear: () => _drop(k)),
                ]),
              ),
      ),
      if (also.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            ExcludeSemantics(child: Text('ALSO', style: cond(13, FontWeight.w800, ls: .12, color: pal.label))),
            const SizedBox(width: 10),
            Expanded(child: Wrap(spacing: 8, runSpacing: 8, children: also)),
          ]),
        ),
      const SizedBox(height: 12),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        child: Row(children: [
          if (mode != QMode.spend) ...[
            tool('Date', SvgIcon('cal', size: 16, color: due != null ? (pal.light ? Colors.white : Colors.black) : pal.ink), () => _pickDate(q), on: due != null),
            const SizedBox(width: 8),
            tool('Time', SvgIcon('clock', size: 16, color: time != null ? (pal.light ? Colors.white : Colors.black) : pal.ink), () => _pickTime(q), on: time != null),
            const SizedBox(width: 8),
            tool(line.name, LineBadge(line, size: 20, fontSize: 10), () => _pickLine(q)),
          ] else ...[
            tool(cat.name, Text(cat.emoji, style: const TextStyle(fontSize: 15)), () => _pickCat(q)),
            const SizedBox(width: 8),
            tool('Date', SvgIcon('cal', size: 16, color: due != null ? (pal.light ? Colors.white : Colors.black) : pal.ink), () => _pickDate(q), on: due != null),
          ],
          if (mode == QMode.task) ...[
            const SizedBox(width: 8),
            tool('Star', SvgIcon(_starOf(q) ? 'star-on' : 'star', size: 16, color: _starOf(q) ? kYellow : pal.ink), () {
              tick();
              setState(() => _star = !_starOf(q));
            }),
          ],
          // "More" opens the full form, which the widget's quick-add window doesn't have.
          if (mode == QMode.event && app.relay == null) ...[
            const SizedBox(width: 8),
            tool('More', Icon(Icons.tune, size: 16, color: pal.ink), () {
              final ev = _event(q, q.title.trim());
              final t = _todoOn(q) ? _taskFor(ev, q) : null;
              Navigator.pop(context);
              app.openDraft(ev, task: t);
            }),
          ],
          if (mode == QMode.spend && app.relay == null) ...[
            const SizedBox(width: 8),
            tool('More', Icon(Icons.tune, size: 16, color: pal.ink), () {
              final due = _dueOf(q);
              final host = widget.host;
              Navigator.pop(context);
              if (host.mounted) {
                openTxnSheet(host, null,
                    title: q.title.trim(), amount: q.amount, cat: _mcatOf(q), income: q.income, at: due == null || due == todayStr() ? null : dms(due) + 13 * kHour);
              }
            }),
          ],
        ]),
      ),
      SheetBtn(cta, kind: BtnKind.yellow, onTap: _submit),
      Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(
          switch (mode) {
            QMode.task => 'Try “Laptop service 3pm 3700”, “Rent ₹15000 1st monthly”',
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
