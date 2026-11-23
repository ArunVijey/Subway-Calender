// Board tab: the departure list for the selected day, or a 7-day agenda.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/store.dart';
import '../core/logic.dart';
import '../core/model.dart';
import '../core/money.dart' show monthKey, monthLong;
import '../core/tasks.dart';
import '../core/util.dart';
import 'haptics.dart';
import 'motion.dart';
import 'settings.dart';
import 'tasks.dart';
import 'theme.dart';
import 'widgets.dart';

class BoardView extends StatefulWidget {
  const BoardView({super.key});
  @override
  State<BoardView> createState() => _BoardViewState();
}

class _BoardViewState extends State<BoardView> with SingleTickerProviderStateMixin {
  /// Drives the staggered entrance; replayed whenever the board epoch changes.
  late final AnimationController _intro = AnimationController(vsync: this, duration: Entrance.total);
  int? _epoch;

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final pal = Pal.of(context);
    if (_epoch != app.boardEpoch) {
      _epoch = app.boardEpoch;
      if (MediaQuery.disableAnimationsOf(context)) {
        _intro.value = 1;
      } else {
        _intro.forward(from: 0);
      }
    }
    final month = app.boardView == 'month';
    // Week and month views share what the day-only controls hide.
    final week = app.boardView == 'week' || month;

    // The all-day toggle belongs to the selected day (day view only).
    final d0 = dms(app.sel);
    final allDayCount =
        week ? 0 : occurrences(app.s, d0, addDays(d0, 1)).where((e) => e.allDay && (app.activeCat == null || e.cat == app.activeCat)).length;
    final showAllDay = !week && app.showAllDay && allDayCount > 0;
    final thisMonth = monthKey(d0) == monthKey(nowMs());
    final label = month
        ? (thisMonth ? 'THIS MONTH' : 'MONTH')
        : week
            ? (app.sel == todayStr() ? 'THIS WEEK' : 'WEEK')
            : showAllDay
                ? 'ALL-DAY'
                : 'DEPARTURES';
    // Today only: an arrow by DEPARTURES folds the finished departures in and out.
    final doneCount = week || showAllDay || app.sel != todayStr() ? 0 : _done(app, d0).length;
    final labelStyle = cond(15, FontWeight.w800, ls: .08, color: kDim);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const _Head(),
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(children: [
          Expanded(child: LineChips(lines: app.s.lines, active: app.activeCat, onTap: app.toggleCat)),
          AnimatedSize(
            duration: Motion.snappyDur,
            curve: Motion.snappy,
            child: week
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: _AllDayBtn(count: allDayCount, on: showAllDay, onTap: allDayCount == 0 ? null : app.toggleAllDay),
                  ),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 0, 0, 10),
        child: Row(children: [
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              layoutBuilder: (cur, prev) => Stack(alignment: Alignment.centerLeft, children: [...prev, ?cur]),
              child: doneCount == 0
                  ? Text(label, key: ValueKey(label), style: labelStyle)
                  : Align(
                      key: ValueKey('$label-done'),
                      alignment: Alignment.centerLeft,
                      child: Semantics(
                        button: true,
                        expanded: app.showDone,
                        label: app.showDone ? 'Hide finished departures' : 'Show $doneCount finished departures',
                        excludeSemantics: true,
                        child: Pressable(
                          scale: .96,
                          onTap: () {
                            tick();
                            app.toggleDone();
                          },
                          child: Padding(
                            // A bigger tap target than the text, without moving it.
                            padding: const EdgeInsets.fromLTRB(0, 8, 12, 8),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Text(label, style: labelStyle),
                              const SizedBox(width: 6),
                              AnimatedRotation(
                                turns: app.showDone ? .5 : 0,
                                duration: Motion.snappyDur,
                                curve: Motion.snappy,
                                child: const SvgIcon('chev', size: 14, color: kDim),
                              ),
                            ]),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
          Segmented<String>(
            options: const [('day', 'DAY'), ('week', 'WEEK'), ('month', 'MONTH')],
            value: app.boardView,
            onChanged: app.setBoardView,
            track: const Color(0xFF1C1C20),
            thumb: Colors.white,
            on: Colors.black,
            off: kDim,
            style: cond(14, FontWeight.w800, ls: .08),
          ),
        ]),
      ),
      Expanded(
        // The board runs edge to edge, past the page's 18px side padding.
        child: LayoutBuilder(
          builder: (context, box) => OverflowBox(
            minWidth: box.maxWidth + 36,
            maxWidth: box.maxWidth + 36,
            child: _Swipe(
              onSwipe: (n) {
                if (!month) return app.shiftDay(n * (week ? 7 : 1));
                // Same day of the month, kept inside shorter months (Jan 31 → Feb 28).
                final d = DateTime.fromMillisecondsSinceEpoch(d0);
                final last = DateTime(d.year, d.month + n + 1, 0).day;
                app.setSel(dstr(DateTime(d.year, d.month + n, math.min(d.day, last)).millisecondsSinceEpoch));
              },
              child: DecoratedBox(
                decoration: BoxDecoration(color: pal.board, border: Border(top: BorderSide(color: pal.rule, width: 2))),
                child: month
                    ? _MonthPage(day0: d0, intro: _intro)
                    : week
                        ? _WeekPage(day0: d0, intro: _intro)
                        : _DayPage(day0: d0, intro: _intro),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

/// Horizontal swipe = next/previous day (same thresholds as the web app).
class _Swipe extends StatefulWidget {
  final Widget child;
  final ValueChanged<int> onSwipe;
  const _Swipe({required this.child, required this.onSwipe});
  @override
  State<_Swipe> createState() => _SwipeState();
}

class _SwipeState extends State<_Swipe> {
  Offset? _start, _last;
  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (d) => _start = _last = d.globalPosition,
        onHorizontalDragUpdate: (d) => _last = d.globalPosition,
        onHorizontalDragEnd: (_) {
          final s = _start, l = _last;
          _start = _last = null;
          if (s == null || l == null) return;
          final dx = l.dx - s.dx, dy = l.dy - s.dy;
          if (dx.abs() > 60 && dx.abs() > dy.abs() * 1.5) {
            buzz();
            widget.onSwipe(dx < 0 ? 1 : -1);
          }
        },
        child: widget.child,
      );
}

/// Today's timed departures that have already ended, in order (line filter applied).
List<Event> _done(AppState app, int d0) {
  final now = nowMs();
  return occurrences(app.s, d0, addDays(d0, 1))
      .where((e) => !e.allDay && e.end < now && (app.activeCat == null || e.cat == app.activeCat))
      .toList()
    ..sort((a, b) => a.start.compareTo(b.start));
}

/// One day of the departure board.
class _DayPage extends StatelessWidget {
  final int day0;
  final Animation<double> intro;
  const _DayPage({required this.day0, required this.intro});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final pal = Pal.of(context);
    final now = nowMs(), d0 = day0, d1 = addDays(d0, 1), isToday = dstr(d0) == todayStr();
    final all = occurrences(app.s, d0, d1).where((e) => app.activeCat == null || e.cat == app.activeCat).toList();
    final allDay = all.where((e) => e.allDay).toList();
    final showAllDay = app.showAllDay && allDay.isNotEmpty;
    final list = showAllDay ? allDay : (all.where((e) => !e.allDay && !(isToday && e.end < now)).toList()..sort((a, b) => a.start.compareTo(b.start)));

    // Yellow = first live departure. Highlighted = the one right after it (or the first if nothing is live).
    final liveIdx = isToday && !showAllDay ? list.indexWhere((e) => now >= e.start && now <= e.end) : -1;
    final nextIdx = isToday && !showAllDay ? (liveIdx == 0 ? 1 : 0) : -1;

    // Finished departures, folded away until the arrow by DEPARTURES opens them.
    final done = isToday && !showAllDay ? _done(app, d0) : const <Event>[];
    final Widget? doneGroup = done.isEmpty
        ? null
        : Entrance(
            intro: intro,
            index: 0,
            child: _Fold(
              open: app.showDone,
              child: Column(children: [
                for (final ev in done)
                  BoardRow(
                    key: ValueKey('done-${ev.id}'),
                    ev: ev,
                    day0: d0,
                    isToday: isToday,
                    done: true,
                    primaryLive: false,
                    next: false,
                    onTap: () => app.openForm(ev),
                  ),
              ]),
            ),
          );

    // Tasks due this day (and overdue ones, today) ride below the departures.
    final tasks = showAllDay ? const [] : app.tasksFor(dstr(d0));
    final todo = <Widget>[
      if (tasks.isNotEmpty) GroupHead('TO DO', count: tasks.length),
      for (final t in tasks) TaskRow(key: ValueKey('todo-${t.id}|${t.due}'), task: t, swipe: true, showDue: false),
    ];

    if (list.isEmpty) {
      return ListView(padding: const EdgeInsets.only(bottom: 48), children: [
        ?doneGroup,
        Entrance(
          intro: intro,
          index: 0,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: todo.isEmpty ? 60 : 34, horizontal: 24),
            child: Text(
              showAllDay ? 'NO ALL-DAY EVENTS' : isToday ? 'NO MORE DEPARTURES TODAY' : 'NO SCHEDULED DEPARTURES',
              textAlign: TextAlign.center,
              style: cond(14, FontWeight.w700, ls: .06, color: pal.sub),
            ),
          ),
        ),
        for (var i = 0; i < todo.length; i++) Entrance(intro: intro, index: i + 1, child: todo[i]),
      ]);
    }
    final lead = doneGroup == null ? 0 : 1;
    return ListView.builder(
      key: PageStorageKey('day-$d0-$showAllDay'),
      padding: const EdgeInsets.only(bottom: 48),
      itemCount: list.length + lead + todo.length,
      itemBuilder: (ctx, j) {
        if (j < lead) return doneGroup!;
        if (j >= lead + list.length) {
          final i = j - lead - list.length;
          return Entrance(intro: intro, index: list.length + i, child: todo[i]);
        }
        final i = j - lead;
        final ev = list[i];
        return Entrance(
          intro: intro,
          index: i,
          child: BoardRow(
            key: ValueKey(ev.id),
            ev: ev,
            day0: d0,
            isToday: isToday,
            primaryLive: i == liveIdx,
            next: i == nextIdx,
            onTap: () => app.openForm(ev),
          ),
        );
      },
    );
  }
}

/// Unfolds [child] downward from the top edge (height + fade); fully closed, it
/// takes no space and builds nothing.
class _Fold extends StatefulWidget {
  final bool open;
  final Widget child;
  const _Fold({required this.open, required this.child});
  @override
  State<_Fold> createState() => _FoldState();
}

class _FoldState extends State<_Fold> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Motion.smoothDur, value: widget.open ? 1 : 0);

  @override
  void didUpdateWidget(_Fold old) {
    super.didUpdateWidget(old);
    if (widget.open == old.open) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = widget.open ? 1 : 0;
    } else if (widget.open) {
      _c.animateTo(1, curve: Motion.smooth);
    } else {
      _c.animateBack(0, duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          if (_c.value == 0 && !widget.open) return const SizedBox(width: double.infinity);
          return ClipRect(
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: _c.value.clamp(0.0, 1.0),
              // Finished rows sit faded back, like past cards in the week view.
              child: Opacity(opacity: .45 * Curves.easeOut.transform(_c.value.clamp(0.0, 1.0)), child: child),
            ),
          );
        },
        child: widget.child,
      );
}

class _Head extends StatelessWidget {
  const _Head();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = dms(app.sel);
    final isToday = app.sel == todayStr();
    final style = cond(50, FontWeight.w800, ls: -.01, height: .95, color: Colors.white);

    final String top, bottom;
    if (app.boardView == 'month') {
      top = monthLong(d);
      bottom = '${DateTime.fromMillisecondsSinceEpoch(d).year}';
    } else if (app.boardView == 'week') {
      final end = addDays(d, 6);
      top = isToday ? 'NEXT 7 DAYS' : 'WEEK OF';
      bottom = monthShort(d) == monthShort(end) ? '${monthDay(d)} – ${DateTime.fromMillisecondsSinceEpoch(end).day}' : '${monthDay(d)} – ${monthDay(end)}';
    } else {
      top = weekdayLong(d);
      bottom = monthDay(d);
    }
    final key = ValueKey('${app.boardView}|${app.sel}');

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 20, 0, 18),
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
                  key: key,
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text.rich(
                    TextSpan(style: style, children: [
                      TextSpan(text: '${top.toUpperCase()},'),
                      const WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Padding(padding: EdgeInsets.only(left: 8), child: Opacity(opacity: .8, child: SvgIcon('chev', size: 22))),
                      ),
                      TextSpan(text: '\n${bottom.toUpperCase()}'),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
        Row(children: [
          AnimatedSwitcher(
            duration: Motion.bouncyDur,
            reverseDuration: const Duration(milliseconds: 180),
            switchInCurve: Motion.bouncy,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim.drive(CurveTween(curve: const Interval(0, .4))),
              child: ScaleTransition(scale: anim.drive(Tween(begin: .6, end: 1)), child: child),
            ),
            child: isToday
                ? const SizedBox.shrink(key: ValueKey('no-today'))
                : Pressable(
                    key: const ValueKey('today'),
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

class LineChips extends StatelessWidget {
  final List<Line> lines;
  final String? active;
  final ValueChanged<String> onTap;
  const LineChips({super.key, required this.lines, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(4),
      clipBehavior: Clip.none,
      child: Row(children: [
        for (final l in lines)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Semantics(
              button: true,
              selected: active == l.id,
              label: 'Line ${l.label}, ${l.name}',
              child: Pressable(
                scale: .88,
                onTap: () => onTap(l.id),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 260),
                  opacity: active == null || active == l.id ? 1 : .3,
                  child: AnimatedScale(
                    duration: Motion.bouncyDur,
                    curve: Motion.bouncy,
                    scale: active == l.id ? 1.12 : 1,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black,
                        border: Border.all(color: active == l.id ? Colors.white : Colors.transparent, width: 2),
                      ),
                      child: LineBadge(l, size: 34, fontSize: 15),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

class _AllDayBtn extends StatelessWidget {
  final int count;
  final bool on;
  final VoidCallback? onTap;
  const _AllDayBtn({required this.count, required this.on, required this.onTap});
  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: onTap == null ? .35 : 1,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            decoration: BoxDecoration(color: on ? Colors.white : const Color(0xFF1C1C20), borderRadius: BorderRadius.circular(20)),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 260),
              style: cond(15, FontWeight.w800, ls: .04, color: on ? Colors.black : const Color(0xFFE4E4E7)),
              child: Text('◆ $count ALL-DAY'),
            ),
          ),
        ),
      );
}

/// One departure. Keyed by event id, so the countdown keeps its state and
/// rolls its digits on the 10 s refresh.
class BoardRow extends StatefulWidget {
  final Event ev;
  final int day0;
  final bool isToday, primaryLive, next;

  /// Already over (today's folded-away departures): shows when it ended.
  final bool done;
  final VoidCallback onTap;
  const BoardRow({
    super.key,
    required this.ev,
    required this.day0,
    required this.isToday,
    this.done = false,
    required this.primaryLive,
    required this.next,
    required this.onTap,
  });
  @override
  State<BoardRow> createState() => _BoardRowState();
}

class _BoardRowState extends State<BoardRow> with TickerProviderStateMixin {
  AnimationController? _glow;

  @override
  void dispose() {
    _glow?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final app = context.read<AppState>();
    final ev = widget.ev;
    final now = nowMs(), d0 = widget.day0;
    final live = widget.isToday && !ev.allDay && now >= ev.start && now <= ev.end;
    final primary = widget.primaryLive;
    final reduce = MediaQuery.disableAnimationsOf(context);

    String n, u;
    if (ev.allDay) {
      final tot = ((ev.end - ev.start) / kDay).round();
      n = tot > 1 ? '${((d0 - ev.start) / kDay).round() + 1}/$tot' : 'ALL';
      u = tot > 1 ? 'DAYS' : 'DAY';
    } else if (widget.done) {
      n = hm(ev.end);
      u = 'ENDED';
    } else if (widget.isToday) {
      final m = math.max(1, ((((live ? ev.end : ev.start) - now) / kMin)).ceil());
      n = m >= 60 ? '${m ~/ 60}:${pad(m % 60)}' : '$m';
      u = live ? 'MIN LEFT' : (m >= 60 ? 'HR' : 'MIN');
    } else if (ev.start < d0) {
      n = hm(ev.end);
      u = 'UNTIL';
    } else {
      n = hm(ev.start);
      u = 'SCHED';
    }
    final pct = live ? ((now - ev.start) / math.max(1, ev.end - ev.start)).clamp(0.0, 1.0) : 0.0;
    final link = meetLink(ev);
    final when0 = ev.allDay ? 'All day' : ev.start < d0 ? 'Since ${monthDay(ev.start)}' : fmtT(ev.start, use24h: app.use24h);
    // Made with a task: its tick rides on this row, and a bill shows its amount.
    final task = app.taskOfEvent(ev);
    final ticked = task != null && app.linkDone(task, dstr(math.max(ev.start, d0)));
    final when = task != null && task.isBill ? '$when0 · ${app.cash(task.amount)}${ticked ? ' paid' : ''}' : when0;

    final rowBg = primary ? kYellow : widget.next ? pal.rowNext : pal.row;
    final fg = primary ? Colors.black : pal.text;
    final sub = primary ? const Color(0xFF1C1917) : pal.sub;
    final numColor = primary ? Colors.black : ticked ? pal.sub : widget.next ? pal.nextNum : pal.text;

    if (primary && !reduce) {
      _glow ??= AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
    } else if (_glow != null) {
      _glow!.dispose();
      _glow = null;
    }

    final numStyle = cond(52, FontWeight.w800, ls: -.01, height: .9, color: numColor).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

    Widget content = Padding(
      padding: EdgeInsets.fromLTRB(task != null ? 9 : 20, 18, 20, 18),
      child: Row(children: [
        if (task != null) ...[
          TaskCheck(
            done: ticked,
            color: primary ? Colors.black : inkFor(hexColor(app.lineOf(ev.cat).color), pal),
            size: 24,
            onTap: () => app.tickLinked(ev),
            label: ticked ? (task.repeat.isEmpty ? 'Mark ${task.title} not done' : '${task.title}, done') : 'Complete ${task.title}',
          ),
          const SizedBox(width: 2),
        ],
        LineBadge(app.lineOf(ev.cat), outline: primary),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AnimatedSize(
              duration: Motion.snappyDur,
              curve: Motion.snappy,
              alignment: Alignment.topLeft,
              child: live ? _LiveTag(onYellow: primary, pulse: primary && !reduce) : const SizedBox(width: double.infinity),
            ),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 400),
              style: cond(25, FontWeight.w700, height: 1.1, color: ticked && !primary ? pal.sub : fg).copyWith(
                decoration: ticked ? TextDecoration.lineThrough : TextDecoration.none,
                decorationColor: primary ? fg : pal.sub,
                decorationThickness: 2,
              ),
              child: Text(ev.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            if (ev.loc.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(ev.loc, maxLines: 1, overflow: TextOverflow.ellipsis, style: inter(14, FontWeight.w500, color: sub)),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(children: [
                Flexible(
                  child: Text('${ev.seriesId != null ? '↻ ' : ''}$when',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: cond(16, FontWeight.w700, ls: .02, color: sub)),
                ),
                if (link != null) ...[
                  const SizedBox(width: 6),
                  _JoinChip(link: link),
                ],
              ]),
            ),
          ]),
        ),
        const SizedBox(width: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 60),
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            // Departure-board seam across the drum of rolling digits.
            Stack(children: [
              RollingText(n, style: numStyle, animate: !reduce),
              Positioned.fill(child: Align(alignment: const Alignment(0, .12), child: Container(height: 2, color: rowBg))),
            ]),
            const SizedBox(height: 5),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(u, key: ValueKey(u), style: cond(13, FontWeight.w800, ls: .1, color: sub)),
            ),
          ]),
        ),
      ]),
    );

    Widget row = Stack(children: [
      content,
      if (live) ...[
        Positioned(left: 0, right: 0, bottom: 0, height: 4, child: ColoredBox(color: primary ? const Color(0x21000000) : pal.progTrack)),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 4,
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: pct),
            duration: Motion.smoothDur,
            curve: Motion.smooth,
            builder: (_, v, _) => FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: v.clamp(0.0, 1.0),
              child: ColoredBox(color: primary ? const Color(0xFF111111) : kYellow),
            ),
          ),
        ),
      ],
    ]);

    final glow = _glow;
    // The glow repaints only the row's yellow each frame; the text, badge and
    // countdown on top are kept as a ready layer (RepaintBoundary).
    row = glow != null
        ? AnimatedBuilder(
            animation: glow,
            builder: (_, child) => _RowBox(color: Color.lerp(kYellow, kYellowHi, Curves.easeInOutSine.transform(glow.value))!, rule: pal.rule, child: child!),
            child: RepaintBoundary(child: row),
          )
        : _RowBox(color: rowBg, rule: pal.rule, animate: !reduce, child: row);

    return Semantics(
      button: true,
      label: '${ev.title}, $when, $n $u${task == null ? '' : ticked ? ', done' : ', to do'}',
      child: Pressable(scale: .975, onTap: widget.onTap, child: row),
    );
  }
}

class _RowBox extends StatelessWidget {
  final Color color, rule;
  final bool animate;
  final Widget child;
  const _RowBox({required this.color, required this.rule, required this.child, this.animate = false});
  @override
  Widget build(BuildContext context) {
    final deco = BoxDecoration(color: color, border: Border(bottom: BorderSide(color: rule)));
    // Rows that become "next" fade into their new color.
    return animate
        ? AnimatedContainer(duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic, decoration: deco, child: child)
        : DecoratedBox(decoration: deco, child: child);
  }
}

class _JoinChip extends StatelessWidget {
  final String link;
  const _JoinChip({required this.link});
  @override
  Widget build(BuildContext context) => Pressable(
        scale: .9,
        onTap: () => launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
          decoration: BoxDecoration(color: kGreen, borderRadius: BorderRadius.circular(4)),
          child: Text('JOIN', style: cond(10, FontWeight.w800, ls: .06, color: Colors.white)),
        ),
      );
}

/// The LIVE tag. On the yellow row (and agenda cards) it pulses.
class _LiveTag extends StatefulWidget {
  final bool onYellow, pulse, compact;
  const _LiveTag({required this.onYellow, required this.pulse, this.compact = false});
  @override
  State<_LiveTag> createState() => _LiveTagState();
}

class _LiveTagState extends State<_LiveTag> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void initState() {
    super.initState();
    if (widget.pulse) _c.repeat();
  }

  @override
  void didUpdateWidget(_LiveTag old) {
    super.didUpdateWidget(old);
    if (widget.pulse && !_c.isAnimating) _c.repeat();
    if (!widget.pulse && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.compact;
    final ring = widget.onYellow ? Colors.black : kYellow;
    final tag = Container(
      padding: EdgeInsets.symmetric(vertical: c ? 2 : 3, horizontal: c ? 6 : 7),
      decoration: BoxDecoration(color: widget.onYellow ? Colors.black : kYellow, borderRadius: BorderRadius.circular(3)),
      child: Text('LIVE', style: cond(c ? 11 : 13, FontWeight.w800, ls: .1, color: widget.onYellow ? kYellow : Colors.black)),
    );
    final body = !widget.pulse
        ? tag
        // Its own layer, so the pulse doesn't repaint the row around it.
        : RepaintBoundary(
            child: AnimatedBuilder(
            animation: _c,
            builder: (_, child) {
              final v = Curves.easeOutCubic.transform(_c.value);
              return Transform.scale(
                scale: 1 + .06 * math.sin(_c.value * math.pi), // 1 → 1.06 → 1
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    boxShadow: [BoxShadow(color: ring.withValues(alpha: .5 * (1 - v)), spreadRadius: 6 * v)],
                  ),
                  child: child,
                ),
              );
            },
            child: tag,
          ),
          );
    return c ? body : Padding(padding: const EdgeInsets.only(bottom: 6), child: body);
  }
}

// ---------------------------------------------------------------------------
// Week view: a 7-day agenda starting at the selected day.

class _WeekPage extends StatelessWidget {
  final int day0;
  final Animation<double> intro;
  const _WeekPage({required this.day0, required this.intro});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final items = <Widget>[];
    var k = 0;
    Widget enter(Widget w) => Entrance(intro: intro, index: k++, child: w);

    for (var i = 0; i < 7; i++) {
      final d = addDays(day0, i), d1 = addDays(d, 1);
      final evs = occurrences(app.s, d, d1).where((e) => app.activeCat == null || e.cat == app.activeCat).toList();
      final allDay = evs.where((e) => e.allDay).toList()..sort((a, b) => a.start.compareTo(b.start));
      final timed = evs.where((e) => !e.allDay).toList()..sort((a, b) => a.start.compareTo(b.start));
      items.add(enter(DayHeader(
        day: d,
        count: evs.length,
        first: i == 0,
        onTap: () {
          app.setSel(dstr(d));
          app.setBoardView('day');
        },
      )));
      final tasks = app.tasksFor(dstr(d));
      if (evs.isEmpty && tasks.isEmpty) items.add(enter(const _EmptyDay()));
      for (final ev in [...allDay, ...timed]) {
        items.add(enter(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AgendaCard(key: ValueKey('${ev.id}@$d'), ev: ev, day0: d, onTap: () => app.openForm(ev)),
        )));
      }
      for (final t in tasks) {
        items.add(enter(Padding(padding: const EdgeInsets.only(bottom: 8), child: AgendaTask(key: ValueKey('t${t.id}@$d'), task: t))));
      }
    }
    return ListView(key: PageStorageKey('week-$day0'), padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: items);
  }
}

// Month view: a calendar grid (dots in each day's line colors, a ring for
// tasks due), and the picked day's agenda underneath.

class _MonthPage extends StatelessWidget {
  final int day0;
  final Animation<double> intro;
  const _MonthPage({required this.day0, required this.intro});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final pal = Pal.of(context);
    final d = DateTime.fromMillisecondsSinceEpoch(day0);
    final first = DateTime(d.year, d.month).millisecondsSinceEpoch;
    final days = DateTime(d.year, d.month + 1, 0).day;
    final lead = DateTime(d.year, d.month).weekday - 1; // Monday first
    final today = todayStr();

    // Each day's line colors (distinct, in board order) and open tasks due.
    final evs = occurrences(app.s, first, addDays(first, days)).where((e) => app.activeCat == null || e.cat == app.activeCat);
    final colors = <String, List<String>>{};
    for (final e in evs) {
      // Multi-day events mark every day they cover.
      for (var t = sod(e.start); t < e.end && t < addDays(first, days); t = addDays(t, 1)) {
        if (t < first) continue;
        final k = dstr(t);
        final list = colors.putIfAbsent(k, () => []);
        if (!list.contains(e.cat)) list.add(e.cat);
      }
    }
    final taskDays = <String, int>{};
    for (final t in app.s.tasks) {
      if (t.done || t.due.isEmpty || (app.activeCat != null && t.cat != app.activeCat)) continue;
      taskDays[t.due] = (taskDays[t.due] ?? 0) + 1;
    }

    Widget cell(int i) {
      if (i < 0 || i >= days) return const Expanded(child: SizedBox(height: 56));
      final t = DateTime(d.year, d.month, i + 1).millisecondsSinceEpoch;
      final k = dstr(t);
      final sel = k == app.sel, isToday = k == today;
      final lines = (colors[k] ?? const <String>[]).map(app.lineOf).toList();
      final hasTasks = (taskDays[k] ?? 0) > 0;
      final numColor = sel ? (pal.light ? Colors.white : Colors.black) : (isToday ? (pal.light ? pal.text : kYellow) : pal.text);
      return Expanded(
        child: Semantics(
          button: true,
          selected: sel,
          label: '${weekdayLong(t)} ${monthDay(t)}${lines.isNotEmpty ? ', ${(colors[k] ?? const []).length} lines busy' : ''}${hasTasks ? ', tasks due' : ''}',
          excludeSemantics: true,
          child: Pressable(
            scale: .9,
            onTap: () {
              if (sel) {
                app.setBoardView('day');
              } else {
                app.setSel(k);
              }
            },
            child: SizedBox(
              height: 56,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: sel ? (pal.light ? const Color(0xFF111111) : Colors.white) : Colors.transparent,
                    border: isToday && !sel ? Border.all(color: pal.light ? pal.text : kYellow, width: 2) : null,
                  ),
                  child: Text('${i + 1}', style: cond(19, FontWeight.w800, color: numColor).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 6,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    for (final l in lines.take(3))
                      Container(width: 6, height: 6, margin: const EdgeInsets.symmetric(horizontal: 1.5), decoration: BoxDecoration(color: hexColor(l.color), shape: BoxShape.circle)),
                    if (hasTasks)
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.symmetric(horizontal: 1.5),
                        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: pal.sub, width: 1.4)),
                      ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      );
    }

    final rows = ((lead + days) / 7).ceil();
    final headStyle = cond(12, FontWeight.w800, ls: .1, color: pal.sub);
    final grid = Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
      child: Column(children: [
        Row(children: [for (final w in const ['M', 'T', 'W', 'T', 'F', 'S', 'S']) Expanded(child: Center(child: Text(w, style: headStyle)))]),
        const SizedBox(height: 4),
        for (var r = 0; r < rows; r++) Row(children: [for (var c = 0; c < 7; c++) cell(r * 7 + c - lead)]),
      ]),
    );

    // The picked day, as in the week agenda.
    final sel = dms(app.sel);
    final dayEvs = occurrences(app.s, sel, addDays(sel, 1)).where((e) => app.activeCat == null || e.cat == app.activeCat).toList()
      ..sort((a, b) => a.allDay != b.allDay ? (a.allDay ? -1 : 1) : a.start.compareTo(b.start));
    final tasks = app.tasksFor(app.sel);
    final items = <Widget>[];
    var k = 0;
    Widget enter(Widget w) => Entrance(intro: intro, index: k++, child: w);
    items.add(enter(DayHeader(day: sel, count: dayEvs.length, first: true, onTap: () => app.setBoardView('day'))));
    if (dayEvs.isEmpty && tasks.isEmpty) items.add(enter(const _EmptyDay()));
    for (final ev in dayEvs) {
      items.add(enter(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: AgendaCard(key: ValueKey('${ev.id}@$sel'), ev: ev, day0: sel, onTap: () => app.openForm(ev)),
      )));
    }
    for (final t in tasks) {
      items.add(enter(Padding(padding: const EdgeInsets.only(bottom: 8), child: AgendaTask(key: ValueKey('t${t.id}@$sel'), task: t))));
    }

    return ListView(key: PageStorageKey('month-${monthKey(day0)}'), padding: const EdgeInsets.only(bottom: 32), children: [
      grid,
      Container(height: 1, margin: const EdgeInsets.symmetric(horizontal: 16), color: pal.rule),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: items)),
    ]);
  }
}

/// Day heading in the agenda; tapping it opens that day on the board.
class DayHeader extends StatelessWidget {
  final int day, count;
  final bool first;
  final VoidCallback onTap;

  /// Replaces "N DEPARTURES" (the Today tab's "3 DEPARTURES · 2 TO DO · ₹569").
  final String? summary;
  const DayHeader({super.key, required this.day, required this.count, required this.first, required this.onTap, this.summary});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final isToday = dstr(day) == todayStr();
    final dt = DateTime.fromMillisecondsSinceEpoch(day);
    final big = cond(23, FontWeight.w800, ls: .02, color: isToday && !pal.light ? kYellow : pal.text);
    return Semantics(
      button: true,
      label: 'Open ${weekdayLong(day)} ${monthDay(day)}',
      child: Pressable(
        scale: .98,
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(2, first ? 14 : 22, 2, 10),
          child: Row(children: [
            Text('${weekdayShort(day).toUpperCase()} ${dt.day}', style: big),
            const SizedBox(width: 7),
            Text(monthShort(day).toUpperCase(), style: big.copyWith(color: pal.sub)),
            if (isToday) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 7),
                decoration: BoxDecoration(color: kYellow, borderRadius: BorderRadius.circular(3)),
                child: Text('TODAY', style: cond(12, FontWeight.w800, ls: .1, color: Colors.black)),
              ),
            ],
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                summary ?? (count > 0 ? '$count ${count == 1 ? 'DEPARTURE' : 'DEPARTURES'}' : ''),
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: cond(12, FontWeight.w800, ls: .1, color: pal.sub),
              ),
            ),
            const SizedBox(width: 4),
            Opacity(opacity: .5, child: Transform.rotate(angle: -math.pi / 2, child: SvgIcon('chev', size: 14, color: pal.sub))),
          ]),
        ),
      ),
    );
  }
}

/// A task in the week agenda: an outlined card with a round check.
class AgendaTask extends StatelessWidget {
  final Task task;
  const AgendaTask({super.key, required this.task});
  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final pal = Pal.of(context);
    final t = task;
    final line = app.lineOf(t.cat);
    final overdue = t.overdue(nowMs());
    final sub = [
      if (overdue) dueLabel(t.due, nowMs()),
      if (t.time != null) minLabel(t.time!, use24h: app.use24h),
      if (t.isBill) app.cash(t.amount),
      if (t.repeat.isNotEmpty) '↻',
    ].join('  ·  ');
    return Semantics(
      button: true,
      label: 'Task: ${t.title}',
      child: Pressable(
        scale: .97,
        onTap: () => openTaskSheet(context, t),
        child: Container(
          padding: const EdgeInsets.fromLTRB(2, 2, 14, 2),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: pal.rule, width: 1.4)),
          child: Row(children: [
            TaskCheck(done: false, color: inkFor(hexColor(line.color), pal), size: 22, onTap: () => app.setTaskDone(t.id, true), label: 'Complete ${t.title}'),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: cond(20, FontWeight.w700, height: 1.15, color: pal.text)),
                if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: inter(13, FontWeight.w600, color: overdue ? kRed : pal.sub)),
              ]),
            ),
            if (t.star) const SvgIcon('star-on', size: 18, color: kYellow),
          ]),
        ),
      ),
    );
  }
}

class _EmptyDay extends StatelessWidget {
  const _EmptyDay();
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Container(
      height: 46,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: pal.rule, width: 1.4)),
      child: Text('NO DEPARTURES', style: cond(14, FontWeight.w700, ls: .08, color: pal.sub.withValues(alpha: .8))),
    );
  }
}

/// Agenda card: filled with the line color (outlined for all-day events),
/// title over "time at place". The ongoing event turns yellow with progress.
class AgendaCard extends StatelessWidget {
  final Event ev;
  final int day0;
  final VoidCallback onTap;
  const AgendaCard({super.key, required this.ev, required this.day0, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final app = context.read<AppState>();
    final line = app.lineOf(ev.cat);
    final c = hexColor(line.color);
    final onC = darkTextOn(line.color) ? Colors.black : Colors.white;
    final now = nowMs();
    final reduce = MediaQuery.disableAnimationsOf(context);
    final live = !ev.allDay && now >= ev.start && now <= ev.end;
    final past = !ev.allDay && ev.end < now;
    String t(int ms) => fmtT(ms, use24h: app.use24h);

    final fg = live ? Colors.black : ev.allDay ? pal.text : onC;
    final String sub;
    if (ev.allDay) {
      final tot = ((ev.end - ev.start) / kDay).round();
      final when = tot > 1 ? 'Day ${((day0 - ev.start) / kDay).round() + 1} of $tot' : 'All day';
      sub = ev.loc.isNotEmpty ? '$when · ${ev.loc}' : when;
    } else {
      final when = ev.start < day0 ? 'Until ${t(ev.end)}' : t(ev.start);
      sub = ev.loc.isNotEmpty ? '$when at ${ev.loc}' : ev.start < day0 ? when : '$when – ${t(ev.end)}';
    }
    final link = meetLink(ev);
    final pct = live ? ((now - ev.start) / math.max(1, ev.end - ev.start)).clamp(0.0, 1.0) : 0.0;
    final radius = BorderRadius.circular(14);
    final task = app.taskOfEvent(ev);
    final ticked = task != null && app.linkDone(task, dstr(math.max(ev.start, day0)));
    final subLine = task != null && task.isBill ? '$sub · ${app.cash(task.amount)}${ticked ? ' paid' : ''}' : sub;

    final body = Stack(children: [
          Padding(
            padding: EdgeInsets.fromLTRB(task != null ? 3 : 14, task != null ? 4 : 11, 12, task != null ? 5 : 12),
            child: Row(children: [
              if (task != null)
                TaskCheck(
                  done: ticked,
                  color: fg,
                  size: 22,
                  onTap: () => app.tickLinked(ev),
                  label: ticked ? (task.repeat.isEmpty ? 'Mark ${task.title} not done' : '${task.title}, done') : 'Complete ${task.title}',
                ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    if (live) ...[
                      _LiveTag(onYellow: true, pulse: !reduce, compact: true),
                      const SizedBox(width: 7),
                    ],
                    Flexible(
                      child: Text(ev.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: cond(21, FontWeight.w700, height: 1.15, color: fg).copyWith(
                            decoration: ticked ? TextDecoration.lineThrough : TextDecoration.none,
                            decorationColor: fg,
                            decorationThickness: 2,
                          )),
                    ),
                  ]),
                  const SizedBox(height: 2),
                  Text('${ev.seriesId != null ? '↻ ' : ''}$subLine',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: inter(13.5, FontWeight.w600, color: fg.withValues(alpha: .82))),
                ]),
              ),
              if (link != null) ...[
                const SizedBox(width: 8),
                _JoinChip(link: link),
              ],
              const SizedBox(width: 10),
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                // On the yellow live card the badge keeps the line color, so the line still reads.
                decoration: BoxDecoration(shape: BoxShape.circle, color: ev.allDay || live ? c : onC.withValues(alpha: .18)),
                child: Text(line.label, style: cond(13, FontWeight.w800, color: ev.allDay || live ? onC : fg)),
              ),
            ]),
          ),
          if (live)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 3,
              child: ColoredBox(
                color: const Color(0x21000000),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: pct),
                  duration: Motion.smoothDur,
                  curve: Motion.smooth,
                  builder: (_, v, _) => FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: v.clamp(0.0, 1.0),
                    child: const ColoredBox(color: Color(0xFF111111)),
                  ),
                ),
              ),
            ),
        ]);

    BoxDecoration deco(Color color) => BoxDecoration(color: color, borderRadius: radius, border: ev.allDay ? Border.all(color: c, width: 1.6) : null);
    final card = ClipRRect(
      borderRadius: radius,
      child: live
          ? _Breathe(animate: !reduce, builder: (color) => DecoratedBox(decoration: deco(color), child: RepaintBoundary(child: body)))
          : DecoratedBox(decoration: deco(ev.allDay ? c.withValues(alpha: pal.light ? .14 : .16) : c), child: body),
    );

    return Semantics(
      button: true,
      label: '${ev.title}, $subLine${task == null ? '' : ticked ? ', done' : ', to do'}',
      child: Pressable(
        scale: .97,
        onTap: onTap,
        child: AnimatedOpacity(duration: const Duration(milliseconds: 400), opacity: past ? .45 : 1, child: card),
      ),
    );
  }
}

/// Yellow that breathes between kYellow and kYellowHi (3 s), like the live row.
class _Breathe extends StatefulWidget {
  final bool animate;
  final Widget Function(Color) builder;
  const _Breathe({required this.animate, required this.builder});
  @override
  State<_Breathe> createState() => _BreatheState();
}

class _BreatheState extends State<_Breathe> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => !widget.animate
      ? widget.builder(kYellow)
      : AnimatedBuilder(animation: _c, builder: (_, _) => widget.builder(Color.lerp(kYellow, kYellowHi, Curves.easeInOutSine.transform(_c.value))!));
}

/// Settings gear used on the Board and Lines headers.
class GearButton extends StatelessWidget {
  const GearButton({super.key});
  @override
  Widget build(BuildContext context) => CircleBtn(
        label: 'Settings',
        onTap: () => openSettings(context),
        child: const SvgIcon('gear', size: 22),
      );
}
