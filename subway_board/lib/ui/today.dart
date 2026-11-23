// Today tab: the day in one place, like the home-screen widget. Up top the
// Money hero (net worth, spent this month) and the net-worth graph; then the
// day's departures, its to-dos and the money logged. WEEK lays out seven days
// the same way. Shares the selected day with the board.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/store.dart';
import '../core/logic.dart';
import '../core/money.dart';
import '../core/quick.dart';
import '../core/util.dart';
import 'board.dart';
import 'haptics.dart';
import 'money.dart';
import 'money_charts.dart';
import 'money_pages.dart';
import 'money_sections.dart';
import 'motion.dart';
import 'quick_add.dart';
import 'tasks.dart';
import 'theme.dart';
import 'widgets.dart';

class TodayView extends StatefulWidget {
  const TodayView({super.key});
  @override
  State<TodayView> createState() => _TodayViewState();
}

class _TodayViewState extends State<TodayView> with SingleTickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(vsync: this, duration: Entrance.total);
  int? _epoch;
  Offset? _s0, _s1;

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    // Replays the flip-in when the day or view changes (not on edits).
    if (_epoch != app.boardEpoch) {
      _epoch = app.boardEpoch;
      if (MediaQuery.disableAnimationsOf(context)) {
        _intro.value = 1;
      } else {
        _intro.forward(from: 0);
      }
    }
    final week = app.todayView == 'week';
    final d0 = dms(app.sel);
    final c = MoneyCtx(app, month: monthStart(nowMs()));

    final items = <Widget>[];
    var k = 0;
    Widget enter(Widget w) => Entrance(intro: _intro, index: k++, child: w);

    // The graph folds away with the numbers (the arrow by NET WORTH up top).
    if (c.m.accounts.isNotEmpty && !app.s.settings.foldTodayNet) {
      items.add(enter(GroupHead('NET WORTH', first: true, trailing: HeadAction('ACCOUNTS', () => openAccountsList(context)))));
      items.add(enter(Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 6), child: NetWorthCard(m: c.m, money: c.cash))));
    }
    for (final w in week ? _week(context, app, d0) : _day(context, app, d0, first: items.isEmpty)) {
      items.add(enter(w));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Head(week: week),
      MoneyHero(c: c, today: true),
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          _Step(left: true, label: week ? 'Previous week' : 'Previous day', onTap: () => app.shiftDay(week ? -7 : -1)),
          const SizedBox(width: 8),
          _Step(left: false, label: week ? 'Next week' : 'Next day', onTap: () => app.shiftDay(week ? 7 : 1)),
          const Spacer(),
          Segmented<String>(
            options: const [('day', 'DAY'), ('week', 'WEEK')],
            value: app.todayView,
            onChanged: app.setTodayView,
            track: const Color(0xFF1C1C20),
            thumb: Colors.white,
            on: Colors.black,
            off: kDim,
            style: cond(14, FontWeight.w800, ls: .08),
          ),
        ]),
      ),
      Expanded(
        // Swipe sideways for the next / previous day (or week), like the board.
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: (d) => _s0 = _s1 = d.globalPosition,
          onHorizontalDragUpdate: (d) => _s1 = d.globalPosition,
          onHorizontalDragEnd: (_) {
            final a = _s0, b = _s1;
            _s0 = _s1 = null;
            if (a == null || b == null) return;
            final dx = b.dx - a.dx, dy = b.dy - a.dy;
            if (dx.abs() > 60 && dx.abs() > dy.abs() * 1.5) {
              tick();
              app.shiftDay((dx < 0 ? 1 : -1) * (week ? 7 : 1));
            }
          },
          child: EdgePanel(
            child: ListView(
              key: PageStorageKey('today-${app.todayView}-${app.sel}'),
              padding: const EdgeInsets.only(bottom: 120),
              children: items,
            ),
          ),
        ),
      ),
    ]);
  }

  // ---------- one day ----------

  List<Widget> _day(BuildContext context, AppState app, int d0, {required bool first}) {
    final day = dstr(d0), now = nowMs(), isToday = day == todayStr();
    final evs = occurrences(app.s, d0, addDays(d0, 1));
    final allDay = evs.where((e) => e.allDay).toList()..sort((a, b) => a.start.compareTo(b.start));
    final timed = evs.where((e) => !e.allDay).toList()..sort((a, b) => a.start.compareTo(b.start));
    // Today: what's over folds away (the arrow by DEPARTURES brings it back,
    // marked ENDED, like the board); the rest counts down.
    final ended = isToday ? timed.where((e) => e.end < now).toList() : const [];
    final ahead = isToday ? timed.where((e) => e.end >= now).toList() : timed;
    final liveIdx = isToday ? ahead.indexWhere((e) => now >= e.start && now <= e.end) : -1;
    final nextIdx = isToday ? (liveIdx == 0 ? 1 : 0) : -1;

    final out = <Widget>[
      GroupHead('DEPARTURES', count: evs.isEmpty ? null : evs.length, first: first, trailing: ended.isEmpty ? null : _EndedFold(count: ended.length)),
    ];
    if (evs.isEmpty) out.add(MoneyHint(isToday ? 'Nothing on the board today.' : 'Nothing on the board.'));
    BoardRow row(e, {bool done = false, bool live = false, bool next = false}) => BoardRow(
          key: ValueKey('today-ev-${e.id}'),
          ev: e,
          day0: d0,
          isToday: isToday,
          done: done,
          primaryLive: live,
          next: next,
          onTap: () => app.openForm(e),
        );
    for (final e in allDay) {
      out.add(row(e));
    }
    if (app.showDone) {
      for (final e in ended) {
        out.add(row(e, done: true));
      }
    }
    for (var i = 0; i < ahead.length; i++) {
      out.add(row(ahead[i], live: i == liveIdx, next: i == nextIdx));
    }

    // To-dos: due (or overdue, today), then the ones ticked off this day. One
    // that's a departure today ticks on its row above instead.
    final open = app.tasksFor(day, filtered: false);
    final riding = {for (final e in evs) ?e.task};
    final done = app.s.tasks.where((t) => t.done && t.doneAt > 0 && dstr(t.doneAt) == day && !riding.contains(t.id)).toList()
      ..sort((a, b) => b.doneAt.compareTo(a.doneAt));
    out.add(GroupHead('TO DO', count: open.isEmpty ? null : open.length));
    if (open.isEmpty && done.isEmpty) out.add(const MoneyHint('Nothing due.'));
    for (final t in open) {
      out.add(TaskRow(key: ValueKey('today-t-${t.id}|${t.due}'), task: t, swipe: true, showDue: false));
    }
    for (final t in done) {
      out.add(TaskRow(key: ValueKey('today-d-${t.id}'), task: t));
    }

    // Money logged this day, newest first.
    final m = app.s.money;
    final txns = m.txns.where((t) => t.at >= d0 && t.at < addDays(d0, 1)).toList()..sort((a, b) => b.at.compareTo(a.at));
    final spent = txns.fold(0, (a, t) => a + spendOf(t, m));
    out.add(GroupHead('MONEY', count: txns.isEmpty ? null : txns.length, trailing: spent > 0 ? HeadSum('${app.cash(spent)} SPENT') : null));
    if (txns.isEmpty) {
      out.add(MoneyHint('Nothing logged.', action: 'LOG', onAction: () => openQuickAdd(context, mode: QMode.spend)));
    }
    for (final t in txns) {
      out.add(TxnRow(key: ValueKey('today-x-${t.id}'), txn: t));
    }
    return out;
  }

  // ---------- seven days ----------

  List<Widget> _week(BuildContext context, AppState app, int d0) {
    final pal = Pal.of(context);
    final m = app.s.money;
    final out = <Widget>[];
    Widget pad(Widget w, {double bottom = 8}) => Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, bottom), child: w);
    for (var i = 0; i < 7; i++) {
      final d = addDays(d0, i), d1 = addDays(d, 1), day = dstr(d);
      final evs = occurrences(app.s, d, d1);
      final sorted = [
        ...evs.where((e) => e.allDay).toList()..sort((a, b) => a.start.compareTo(b.start)),
        ...evs.where((e) => !e.allDay).toList()..sort((a, b) => a.start.compareTo(b.start)),
      ];
      final tasks = app.tasksFor(day, filtered: false);
      final txns = m.txns.where((t) => t.at >= d && t.at < d1).toList()..sort((a, b) => b.at.compareTo(a.at));
      final spent = txns.fold(0, (a, t) => a + spendOf(t, m));
      final summary = [
        if (evs.isNotEmpty) '${evs.length} ${evs.length == 1 ? 'DEPARTURE' : 'DEPARTURES'}',
        if (tasks.isNotEmpty) '${tasks.length} TO DO',
        if (spent > 0) app.cash(spent),
      ].join('  ·  ');
      out.add(pad(
        DayHeader(
          day: d,
          count: evs.length,
          first: i == 0 && m.accounts.isEmpty,
          summary: summary,
          onTap: () {
            app.setSel(day);
            app.setTodayView('day');
          },
        ),
        bottom: 0,
      ));
      if (sorted.isEmpty && tasks.isEmpty && txns.isEmpty) {
        out.add(pad(Container(
          height: 46,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: pal.rule, width: 1.4)),
          child: Text('NOTHING PLANNED', style: cond(14, FontWeight.w700, ls: .08, color: pal.sub.withValues(alpha: .8))),
        )));
      }
      for (final e in sorted) {
        out.add(pad(AgendaCard(key: ValueKey('wk-ev-${e.id}@$d'), ev: e, day0: d, onTap: () => app.openForm(e))));
      }
      for (final t in tasks) {
        out.add(pad(AgendaTask(key: ValueKey('wk-t-${t.id}@$d'), task: t)));
      }
      for (final t in txns) {
        out.add(pad(_AgendaTxn(key: ValueKey('wk-x-${t.id}'), txn: t)));
      }
    }
    return out;
  }
}

/// One line, like the Money tab's month heading: "TODAY NOV 21", "SAT NOV 21",
/// "WEEK NOV 21 – 27". Tap for a date; TODAY jumps back.
class _Head extends StatelessWidget {
  final bool week;
  const _Head({required this.week});
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = dms(app.sel);
    final isToday = app.sel == todayStr();
    final String main, rest;
    if (week) {
      final end = addDays(d, 6);
      main = isToday ? 'THIS WEEK' : 'WEEK';
      rest = monthShort(d) == monthShort(end) ? '${monthDay(d)} – ${DateTime.fromMillisecondsSinceEpoch(end).day}' : '${monthDay(d)} – ${monthDay(end)}';
    } else {
      main = isToday ? 'TODAY' : weekdayShort(d);
      rest = monthDay(d);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 20, 0, 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Semantics(
            button: true,
            label: 'Pick a date',
            child: Pressable(
              scale: .98,
              onTap: () async {
                final picked = await pickDate(context, DateTime.fromMillisecondsSinceEpoch(d));
                if (picked != null) app.setSel(dstr(picked.millisecondsSinceEpoch));
              },
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                layoutBuilder: (cur, prev) => Stack(alignment: Alignment.topLeft, children: [...prev, ?cur]),
                child: FittedBox(
                  key: ValueKey('$week|${app.sel}'),
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text.rich(TextSpan(style: cond(50, FontWeight.w800, ls: -.01, height: .95, color: Colors.white), children: [
                    TextSpan(text: main.toUpperCase()),
                    TextSpan(text: ' ${rest.toUpperCase()}', style: const TextStyle(color: Color(0xFF52525B))),
                    const WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Padding(padding: EdgeInsets.only(left: 8), child: Opacity(opacity: .8, child: SvgIcon('chev', size: 22))),
                    ),
                  ])),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Row(children: [
          AnimatedSwitcher(
            duration: Motion.bouncyDur,
            reverseDuration: const Duration(milliseconds: 180),
            switchInCurve: Motion.bouncy,
            transitionBuilder: (c, a) => FadeTransition(opacity: a, child: ScaleTransition(scale: a.drive(Tween(begin: .6, end: 1)), child: c)),
            child: isToday
                ? const SizedBox.shrink(key: ValueKey('now'))
                : Pressable(
                    key: const ValueKey('back'),
                    onTap: () => app.setSel(todayStr()),
                    child: Container(
                      height: 40,
                      margin: const EdgeInsets.only(right: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: kYellow, borderRadius: BorderRadius.circular(20)),
                      child: Text('TODAY', style: cond(15, FontWeight.w800, ls: .06, color: Colors.black)),
                    ),
                  ),
          ),
          const GearButton(),
        ]),
      ]),
    );
  }
}

/// "2 ENDED ⌄" by DEPARTURES: shows or folds away what's already over today.
/// The same switch as the board's, so the two agree.
class _EndedFold extends StatelessWidget {
  final int count;
  const _EndedFold({required this.count});
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final pal = Pal.of(context);
    final open = app.showDone;
    return Semantics(
      button: true,
      expanded: open,
      label: open ? 'Hide finished departures' : 'Show $count finished departures',
      excludeSemantics: true,
      child: Pressable(
        scale: .94,
        onTap: () {
          tick();
          app.toggleDone();
        },
        child: Padding(
          // A bigger tap target than the text, without moving the heading.
          padding: const EdgeInsets.fromLTRB(12, 6, 0, 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(open ? 'HIDE ENDED' : '$count ENDED', style: cond(15, FontWeight.w800, ls: .06, color: pal.sub)),
            const SizedBox(width: 6),
            AnimatedRotation(
              turns: open ? .5 : 0,
              duration: Motion.snappyDur,
              curve: Motion.snappy,
              child: SvgIcon('chev', size: 14, color: pal.sub),
            ),
          ]),
        ),
      ),
    );
  }
}

/// ‹ or › beside the DAY / WEEK switch.
class _Step extends StatelessWidget {
  final bool left;
  final String label;
  final VoidCallback onTap;
  const _Step({required this.left, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: Pressable(
          scale: .85,
          onTap: () {
            tick();
            onTap();
          },
          child: Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFF2A2A30), width: 1.4)),
            child: Transform.rotate(angle: left ? math.pi / 2 : -math.pi / 2, child: const SvgIcon('chev', size: 16)),
          ),
        ),
      );
}

/// Money logged, in the week agenda: an outlined card like AgendaTask.
class _AgendaTxn extends StatelessWidget {
  final Txn txn;
  const _AgendaTxn({super.key, required this.txn});
  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final pal = Pal.of(context);
    final t = txn;
    final cat = app.s.money.catOf(t.cat);
    final plus = t.income || t.type == 'refund';
    final title = t.title.trim().isEmpty ? cat.name : t.title.trim();
    return Semantics(
      button: true,
      label: '$title, ${app.cash(t.amount)}',
      excludeSemantics: true,
      child: Pressable(
        scale: .97,
        onTap: () => openTxnSheet(context, t),
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 8, 14, 8),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: pal.rule, width: 1.4)),
          child: Row(children: [
            CatBadge(cat, size: 32),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: cond(20, FontWeight.w700, height: 1.15, color: pal.text)),
                Text('${cat.name}  ·  ${fmtT(t.at, use24h: app.use24h)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: inter(13, FontWeight.w600, color: pal.sub)),
              ]),
            ),
            const SizedBox(width: 10),
            Text('${plus ? '+' : ''}${app.cash(t.amount)}',
                style: cond(20, FontWeight.w800, color: plus ? kIncomeGreen : pal.text).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
        ),
      ),
    );
  }
}
