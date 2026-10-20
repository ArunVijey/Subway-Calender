// Board tab: the departure list for the selected day.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/store.dart';
import '../core/logic.dart';
import '../core/model.dart';
import '../core/util.dart';
import 'settings.dart';
import 'haptics.dart';
import 'theme.dart';
import 'widgets.dart';

class BoardView extends StatelessWidget {
  const BoardView({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final pal = Pal.of(context);
    final now = nowMs(), d0 = dms(app.sel), d1 = addDays(d0, 1), isToday = app.sel == todayStr();
    final all = occurrences(app.s, d0, d1).where((e) => app.activeCat == null || e.cat == app.activeCat).toList();
    final allDay = all.where((e) => e.allDay).toList();
    final showAllDay = app.showAllDay && allDay.isNotEmpty;
    final list = showAllDay ? allDay : (all.where((e) => !e.allDay && !(isToday && e.end < now)).toList()..sort((a, b) => a.start.compareTo(b.start)));

    // Yellow = first live departure. Highlighted = the one right after it (or the first if nothing is live).
    final liveIdx = isToday && !showAllDay ? list.indexWhere((e) => now >= e.start && now <= e.end) : -1;
    final nextIdx = isToday && !showAllDay ? (liveIdx == 0 ? 1 : 0) : -1;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const _Head(),
      Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Row(children: [
          Expanded(child: _Chips(lines: app.s.lines, active: app.activeCat, onTap: app.toggleCat)),
          const SizedBox(width: 10),
          _AllDayBtn(count: allDay.length, on: showAllDay, onTap: allDay.isEmpty ? null : app.toggleAllDay),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(showAllDay ? 'ALL-DAY' : 'DEPARTURES', style: cond(15, FontWeight.w800, ls: .08, color: kDim)),
          Text('TIME', style: cond(15, FontWeight.w800, ls: .08, color: kDim)),
        ]),
      ),
      Expanded(
        // The board runs edge to edge, past the page's 18px side padding.
        child: LayoutBuilder(
          builder: (context, box) => OverflowBox(
            minWidth: box.maxWidth + 36,
            maxWidth: box.maxWidth + 36,
            child: _Swipe(
              onSwipe: app.shiftDay,
              child: Container(
                decoration: BoxDecoration(color: pal.board, border: Border(top: BorderSide(color: pal.rule, width: 2))),
                child: list.isEmpty
                    ? ListView(children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
                          child: Text(
                            showAllDay ? 'NO ALL-DAY EVENTS' : isToday ? 'NO MORE DEPARTURES TODAY' : 'NO SCHEDULED DEPARTURES',
                            textAlign: TextAlign.center,
                            style: cond(14, FontWeight.w700, ls: .06, color: pal.sub),
                          ),
                        ),
                      ])
                    : ListView.builder(
                        key: PageStorageKey('board-${app.sel}'),
                        padding: EdgeInsets.zero,
                        itemCount: list.length,
                        itemBuilder: (ctx, i) {
                          final ev = list[i];
                          return BoardRow(
                            key: ValueKey('${app.boardEpoch}|${ev.id}'),
                            ev: ev,
                            index: i,
                            day0: d0,
                            isToday: isToday,
                            primaryLive: i == liveIdx,
                            next: i == nextIdx,
                            onTap: () => app.openForm(ev),
                          );
                        },
                      ),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

class _Head extends StatelessWidget {
  const _Head();
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = dms(app.sel);
    final isToday = app.sel == todayStr();
    final style = cond(50, FontWeight.w800, ls: -.01, height: .95, color: Colors.white);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 20, 0, 18),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Semantics(
            button: true,
            label: 'Pick a date',
            child: GestureDetector(
              onTap: tapped(() async {
                final picked = await pickDate(context, DateTime.fromMillisecondsSinceEpoch(d));
                if (picked != null) app.setSel(dstr(picked.millisecondsSinceEpoch));
              }),
              child: Text.rich(
                TextSpan(style: style, children: [
                  TextSpan(text: '${weekdayLong(d).toUpperCase()},'),
                  const WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(padding: EdgeInsets.only(left: 8), child: Opacity(opacity: .8, child: SvgIcon('chev', size: 22))),
                  ),
                  TextSpan(text: '\n${monthDay(d).toUpperCase()}'),
                ]),
              ),
            ),
          ),
        ),
        Row(children: [
          if (!isToday)
            GestureDetector(
              onTap: tapped(() => app.setSel(todayStr())),
              child: Container(
                height: 40,
                margin: const EdgeInsets.only(right: 10),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: kYellow, borderRadius: BorderRadius.circular(20)),
                child: Text('TODAY', style: cond(15, FontWeight.w800, ls: .06, color: Colors.black)),
              ),
            ),
          const GearButton(),
        ]),
      ]),
    );
  }
}

class _Chips extends StatelessWidget {
  final List<Line> lines;
  final String? active;
  final ValueChanged<String> onTap;
  const _Chips({required this.lines, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(3),
      child: Row(children: [
        for (final l in lines)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Semantics(
              button: true,
              selected: active == l.id,
              label: 'Line ${l.label}, ${l.name}',
              child: GestureDetector(
                onTap: tapped(() => onTap(l.id)),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: active == null || active == l.id ? 1 : .3,
                  child: AnimatedScale(
                    duration: const Duration(milliseconds: 200),
                    scale: active == l.id ? 1.1 : 1,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
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
  Widget build(BuildContext context) => GestureDetector(
        onTap: tapped(onTap),
        child: Opacity(
          opacity: onTap == null ? .35 : 1,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            decoration: BoxDecoration(color: on ? Colors.white : const Color(0xFF1C1C20), borderRadius: BorderRadius.circular(20)),
            child: Text('◆ $count ALL-DAY', style: cond(15, FontWeight.w800, ls: .04, color: on ? Colors.black : const Color(0xFFE4E4E7))),
          ),
        ),
      );
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

/// One departure. Keyed by board epoch + event id, so it plays the flip-in
/// when the board is redrawn and keeps state (digit flips) on the 10 s refresh.
class BoardRow extends StatefulWidget {
  final Event ev;
  final int index, day0;
  final bool isToday, primaryLive, next;
  final VoidCallback onTap;
  const BoardRow({
    super.key,
    required this.ev,
    required this.index,
    required this.day0,
    required this.isToday,
    required this.primaryLive,
    required this.next,
    required this.onTap,
  });
  @override
  State<BoardRow> createState() => _BoardRowState();
}

class _BoardRowState extends State<BoardRow> with TickerProviderStateMixin {
  late final AnimationController _flap = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
  AnimationController? _glow;

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: math.min(widget.index, 10) * 50), () {
      if (mounted) _flap.forward();
    });
  }

  @override
  void dispose() {
    _flap.dispose();
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
    final when = ev.allDay ? 'All day' : ev.start < d0 ? 'Since ${monthDay(ev.start)}' : fmtT(ev.start, use24h: app.use24h);

    final rowBg = primary ? kYellow : widget.next ? pal.rowNext : pal.row;
    final fg = primary ? Colors.black : pal.text;
    final sub = primary ? const Color(0xFF1C1917) : pal.sub;
    final numColor = primary ? Colors.black : widget.next ? pal.nextNum : pal.text;

    if (primary && !reduce) {
      _glow ??= AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
    } else if (_glow != null) {
      _glow!.dispose();
      _glow = null;
    }

    Widget content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
      child: Row(children: [
        LineBadge(app.lineOf(ev.cat), outline: primary),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (live) _LiveTag(onYellow: primary, pulse: primary && !reduce),
            Text(ev.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: cond(25, FontWeight.w700, height: 1.1, color: fg)),
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
                  GestureDetector(
                    onTap: tapped(() => launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
                      decoration: BoxDecoration(color: kGreen, borderRadius: BorderRadius.circular(4)),
                      child: Text('JOIN', style: cond(10, FontWeight.w800, ls: .06, color: Colors.white)),
                    ),
                  ),
                ],
              ]),
            ),
          ]),
        ),
        const SizedBox(width: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 60),
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            FlipNumber(text: n, color: numColor, seam: rowBg, animate: !reduce),
            const SizedBox(height: 5),
            Text(u, style: cond(13, FontWeight.w800, ls: .1, color: sub)),
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
            duration: const Duration(milliseconds: 600),
            curve: Curves.ease,
            builder: (_, v, _) => FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: v,
              child: ColoredBox(color: primary ? const Color(0xFF111111) : kYellow),
            ),
          ),
        ),
      ],
    ]);

    final glow = _glow;
    row = glow != null
        ? AnimatedBuilder(
            animation: glow,
            builder: (_, child) => _RowBox(color: Color.lerp(kYellow, kYellowHi, Curves.easeInOut.transform(glow.value))!, rule: pal.rule, child: child!),
            child: row,
          )
        : _RowBox(color: rowBg, rule: pal.rule, child: row);

    row = Semantics(
      button: true,
      label: '${ev.title}, $when, $n $u',
      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: tapped(widget.onTap), child: row),
    );

    if (reduce) return row;
    return AnimatedBuilder(
      animation: _flap,
      builder: (_, child) {
        final t = kEase.transform(_flap.value);
        return Opacity(
          opacity: t,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 1 / 600)
              ..rotateX(-80 * math.pi / 180 * (1 - t)),
            child: child,
          ),
        );
      },
      child: row,
    );
  }
}

class _RowBox extends StatelessWidget {
  final Color color, rule;
  final Widget child;
  const _RowBox({required this.color, required this.rule, required this.child});
  @override
  Widget build(BuildContext context) =>
      DecoratedBox(decoration: BoxDecoration(color: color, border: Border(bottom: BorderSide(color: rule))), child: child);
}

/// The LIVE tag. On the yellow row it pulses.
class _LiveTag extends StatefulWidget {
  final bool onYellow, pulse;
  const _LiveTag({required this.onYellow, required this.pulse});
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
    final tag = Container(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 7),
      decoration: BoxDecoration(color: widget.onYellow ? Colors.black : kYellow, borderRadius: BorderRadius.circular(3)),
      child: Text('LIVE', style: cond(13, FontWeight.w800, ls: .1, color: widget.onYellow ? kYellow : Colors.black)),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: !widget.pulse
          ? tag
          : AnimatedBuilder(
              animation: _c,
              builder: (_, child) {
                final v = _c.value;
                final s = 1 + .07 * math.sin(v * math.pi); // 1 → 1.07 → 1
                return Transform.scale(
                  scale: s,
                  alignment: Alignment.center,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .55 * (1 - v)), spreadRadius: 5 * v)],
                    ),
                    child: child,
                  ),
                );
              },
              child: tag,
            ),
    );
  }
}

/// Split-flap number: each character flips when it changes.
class FlipNumber extends StatefulWidget {
  final String text;
  final Color color, seam;
  final bool animate;
  const FlipNumber({super.key, required this.text, required this.color, required this.seam, required this.animate});
  @override
  State<FlipNumber> createState() => _FlipNumberState();
}

class _FlipNumberState extends State<FlipNumber> with TickerProviderStateMixin {
  final _ctl = <AnimationController>[];

  AnimationController _make() =>
      AnimationController(vsync: this, duration: const Duration(milliseconds: 550), value: 1);

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < widget.text.length; i++) {
      _ctl.add(_make());
    }
  }

  @override
  void didUpdateWidget(FlipNumber old) {
    super.didUpdateWidget(old);
    final a = old.text, b = widget.text;
    if (a == b) return;
    final resized = a.length != b.length;
    while (_ctl.length < b.length) {
      _ctl.add(_make());
    }
    while (_ctl.length > b.length) {
      _ctl.removeLast().dispose();
    }
    if (!widget.animate) return;
    for (var j = 0; j < b.length; j++) {
      if (resized || a[j] != b[j]) _ctl[j].forward(from: 0);
    }
  }

  @override
  void dispose() {
    for (final c in _ctl) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = cond(52, FontWeight.w800, ls: -.01, height: .9, color: widget.color).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var j = 0; j < widget.text.length; j++)
        AnimatedBuilder(
          animation: _ctl[j],
          builder: (_, child) {
            final t = kEase.transform(_ctl[j].value);
            return Opacity(
              opacity: .2 + .8 * t,
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 1 / 300)
                  ..rotateX(-math.pi / 2 * (1 - t)),
                child: child,
              ),
            );
          },
          child: Stack(children: [
            Text(widget.text[j], style: style),
            Positioned.fill(
              child: Align(
                alignment: const Alignment(0, .12),
                child: Container(height: 2, color: widget.seam),
              ),
            ),
          ]),
        ),
    ]);
  }
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
