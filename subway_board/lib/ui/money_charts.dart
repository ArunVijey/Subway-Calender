// Charts for the Money tab, drawn by hand so they look like the rest of the
// board: thin rules, yellow ink, condensed labels. Each one draws itself in on
// first show (skipped with reduce-motion).
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/ledger.dart';
import '../core/money.dart';
import '../core/util.dart';
import 'haptics.dart';
import 'motion.dart';
import 'theme.dart';

const kIncomeGreen = Color(0xFF22C55E);

/// Runs [builder] with a 0→1 value that animates in once.
class DrawIn extends StatelessWidget {
  final Widget Function(double t) builder;
  final Object? token;
  const DrawIn({super.key, required this.builder, this.token});
  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return builder(1);
    return TweenAnimationBuilder<double>(
      key: ValueKey(token),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 900),
      curve: Motion.smooth,
      builder: (_, t, _) => builder(t),
    );
  }
}

TextPainter _label(String s, TextStyle style) => TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr)..layout();

// ---------------------------------------------------------------------------
// Spending pace: this month's running total against an even line to the budget.

class PaceChart extends StatelessWidget {
  final List<int> cum, lastCum;
  final int budget;

  /// Index of today (0-based day of month), or -1 for a past month (draws all days).
  final int today;
  final String Function(int) money;
  const PaceChart({super.key, required this.cum, required this.lastCum, required this.budget, required this.today, required this.money});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return SizedBox(
      height: 168,
      child: DrawIn(
        token: '${cum.length}-$budget-${cum.lastOrNull}',
        builder: (t) => CustomPaint(painter: _PacePainter(this, pal, t), size: Size.infinite),
      ),
    );
  }
}

class _PacePainter extends CustomPainter {
  final PaceChart c;
  final Pal pal;
  final double t;
  _PacePainter(this.c, this.pal, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final n = c.cum.length;
    if (n == 0) return;
    const top = 18.0, bottom = 22.0;
    final h = size.height - top - bottom, w = size.width;
    final shown = c.today < 0 ? n : c.today + 1;
    final peak = [c.budget, ...c.cum.take(shown), ...c.lastCum].fold(1, math.max).toDouble() * 1.08;
    double x(int i) => n <= 1 ? 0 : w * i / (n - 1);
    double y(num v) => top + h - h * (v / peak);

    final rule = Paint()
      ..color = pal.rule
      ..strokeWidth = 1;
    for (var k = 0; k <= 2; k++) {
      final yy = top + h * k / 2;
      canvas.drawLine(Offset(0, yy), Offset(w, yy), rule);
    }

    final small = cond(11, FontWeight.w800, ls: .08, color: pal.sub);
    // Even pace: straight from nothing on the 1st to the whole budget on the last day.
    if (c.budget > 0) {
      final p = Paint()
        ..color = pal.sub.withValues(alpha: .55)
        ..strokeWidth = 1.5;
      final a = Offset(0, y(0)), b = Offset(w, y(c.budget));
      const dash = 5.0, gap = 5.0;
      final len = (b - a).distance, dir = (b - a) / len;
      for (var d = 0.0; d < len * t; d += dash + gap) {
        canvas.drawLine(a + dir * d, a + dir * math.min(d + dash, len * t), p);
      }
      final lab = _label('BUDGET ${c.money(c.budget)}', small);
      lab.paint(canvas, Offset(w - lab.width, y(c.budget) - lab.height - 3 < 0 ? 0 : y(c.budget) - lab.height - 3));
    }

    // Last month, for comparison.
    if (c.lastCum.isNotEmpty) {
      final p = Paint()
        ..color = pal.sub.withValues(alpha: .35)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      final path = Path()..moveTo(0, y(0));
      final m = c.lastCum.length;
      for (var i = 0; i < m; i++) {
        path.lineTo(w * i / math.max(1, m - 1), y(c.lastCum[i]));
      }
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, w * t, size.height));
      canvas.drawPath(path, p);
      canvas.restore();
    }

    // This month.
    final upto = math.max(1, (shown * t).ceil());
    final line = Path()..moveTo(0, y(0));
    final area = Path()..moveTo(0, top + h);
    area.lineTo(0, y(0));
    for (var i = 0; i < upto; i++) {
      line.lineTo(x(i), y(c.cum[i]));
      area.lineTo(x(i), y(c.cum[i]));
    }
    area
      ..lineTo(x(upto - 1), top + h)
      ..close();
    final last = c.cum[upto - 1];
    final ahead = c.budget > 0 && last > c.budget * (upto / n);
    final ink = ahead ? const Color(0xFFFF8A00) : kYellow;
    canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [ink.withValues(alpha: .28), ink.withValues(alpha: 0)])
              .createShader(Rect.fromLTWH(0, top, w, h)));
    canvas.drawPath(
        line,
        Paint()
          ..color = ink
          ..strokeWidth = 2.6
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round);
    if (c.today >= 0 && t >= 1) {
      final o = Offset(x(c.today), y(c.cum[c.today]));
      canvas.drawCircle(o, 6, Paint()..color = pal.board);
      canvas.drawCircle(o, 4.5, Paint()..color = ink);
    }

    // Day labels along the bottom.
    for (final i in [0, (n - 1) ~/ 2, n - 1]) {
      final lab = _label('${i + 1}', small);
      final lx = (x(i) - lab.width / 2).clamp(0.0, w - lab.width);
      lab.paint(canvas, Offset(lx, size.height - lab.height));
    }
  }

  @override
  bool shouldRepaint(_PacePainter o) => o.t != t || o.c != c || o.pal != pal;
}

// ---------------------------------------------------------------------------
// Income vs spending: paired bars per month. Tap a month to open it.

class FlowChart extends StatelessWidget {
  final List<FlowMonth> months;
  final int selected;
  final ValueChanged<int>? onTap;
  final String Function(int) money;
  const FlowChart({super.key, required this.months, required this.selected, this.onTap, required this.money});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final peak = months.fold(1, (a, m) => math.max(a, math.max(m.income, m.spent))).toDouble();
    return SizedBox(
      height: 176,
      child: DrawIn(
        token: '${months.length}-${months.lastOrNull?.month0}-$peak',
        builder: (t) => Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final m in months)
            Expanded(
              child: Semantics(
                button: onTap != null,
                label: '${monthLong(m.month0)}: in ${money(m.income)}, out ${money(m.spent)}',
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onTap == null ? null : () => onTap!(m.month0),
                  child: Column(children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Expanded(child: _Bar(frac: t * m.income / peak, color: kIncomeGreen)),
                          const SizedBox(width: 3),
                          Expanded(child: _Bar(frac: t * m.spent / peak, color: m.month0 == selected ? kYellow : pal.text.withValues(alpha: .82))),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(monthLong(m.month0).substring(0, 3).toUpperCase(),
                        style: cond(12, FontWeight.w800, ls: .08, color: m.month0 == selected ? (pal.light ? pal.text : kYellow) : pal.sub)),
                    Text(m.net == 0 ? '—' : money(m.net), maxLines: 1, style: cond(11, FontWeight.w700, color: m.net >= 0 ? kIncomeGreen : kRed)),
                  ]),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final double frac;
  final Color color;
  const _Bar({required this.frac, required this.color});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (_, box) => Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            height: math.max(frac > 0 ? 2.0 : 0.0, box.maxHeight * frac.clamp(0.0, 1.0)),
            decoration: BoxDecoration(color: color, borderRadius: const BorderRadius.vertical(top: Radius.circular(3))),
          ),
        ),
      );
}

// ---------------------------------------------------------------------------
// Share of spending: one stacked bar, biggest categories first.

class ShareBar extends StatelessWidget {
  final List<(Color, int)> parts;
  const ShareBar({super.key, required this.parts});
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final total = parts.fold(0, (a, p) => a + p.$2);
    return DrawIn(
      token: total,
      builder: (t) => ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          height: 16,
          child: Stack(children: [
            Positioned.fill(child: ColoredBox(color: pal.progTrack)),
            FractionallySizedBox(
              widthFactor: t,
              child: Row(children: [
                for (final (color, v) in parts)
                  if (v > 0)
                    Expanded(
                      flex: math.max(1, (v * 1000 / math.max(1, total)).round()),
                      child: Container(margin: const EdgeInsets.only(right: 2), color: color),
                    ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Daily moons: each day of the month as a moon, fuller the more was spent.

class MoonGrid extends StatelessWidget {
  final List<int> daily;
  final int month0;

  /// Index of today, or -1 when the whole month is in the past (or [future] = true for all).
  final int today;
  final void Function(int day)? onTap;
  const MoonGrid({super.key, required this.daily, required this.month0, required this.today, this.onTap});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final peak = daily.fold(0, math.max);
    final lead = DateTime.fromMillisecondsSinceEpoch(month0).weekday - 1; // Monday first
    final cells = lead + daily.length;
    final rows = (cells / 7).ceil();
    final head = cond(11, FontWeight.w800, ls: .1, color: pal.sub);
    return DrawIn(
      token: '$month0-$peak',
      builder: (t) => Column(children: [
        Row(children: [for (final d in const ['M', 'T', 'W', 'T', 'F', 'S', 'S']) Expanded(child: Center(child: Text(d, style: head)))]),
        const SizedBox(height: 6),
        for (var r = 0; r < rows; r++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              for (var c = 0; c < 7; c++)
                Expanded(child: _moonCell(context, pal, r * 7 + c - lead, peak, t)),
            ]),
          ),
      ]),
    );
  }

  Widget _moonCell(BuildContext context, Pal pal, int i, int peak, double t) {
    if (i < 0 || i >= daily.length) return const SizedBox(height: 46);
    final future = today >= 0 && i > today;
    final f = future || peak <= 0 ? 0.0 : daily[i] / peak;
    final isToday = i == today;
    return Semantics(
      button: onTap != null && !future,
      label: 'Day ${i + 1}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap == null || future ? null : () => onTap!(i),
        child: SizedBox(
          height: 46,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CustomPaint(painter: _MoonPainter(f * t, pal, future: future, today: isToday)),
            ),
            const SizedBox(height: 2),
            Text('${i + 1}', style: cond(11, FontWeight.w700, color: isToday ? (pal.light ? pal.text : kYellow) : (future ? pal.placeholder : pal.sub))),
          ]),
        ),
      ),
    );
  }
}

class _MoonPainter extends CustomPainter {
  final double f;
  final Pal pal;
  final bool future, today;
  _MoonPainter(this.f, this.pal, {required this.future, required this.today});

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2 - 1.5;
    final c = size.center(Offset.zero);
    canvas.drawCircle(c, r, Paint()..color = future ? Colors.transparent : pal.progTrack);
    if (future) {
      canvas.drawCircle(
          c,
          r,
          Paint()
            ..color = pal.rule
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2);
    }
    final lit = f.clamp(0.0, 1.0);
    if (lit > 0.001) {
      final ink = pal.light ? const Color(0xFFE0A800) : kYellow;
      if (lit >= .999) {
        canvas.drawCircle(c, r, Paint()..color = ink);
      } else {
        // Lit on the right, the terminator an ellipse that sweeps across as the moon fills.
        final rx = r * (1 - 2 * lit).abs();
        final path = Path()
          ..moveTo(c.dx, c.dy - r)
          ..arcToPoint(Offset(c.dx, c.dy + r), radius: Radius.circular(r), clockwise: true);
        if (rx < .5) {
          path.lineTo(c.dx, c.dy - r);
        } else {
          path.arcToPoint(Offset(c.dx, c.dy - r), radius: Radius.elliptical(rx, r), clockwise: lit > .5);
        }
        path.close();
        canvas.drawPath(path, Paint()..color = ink);
      }
    }
    if (today) {
      canvas.drawCircle(
          c,
          r + 1,
          Paint()
            ..color = pal.light ? pal.text : Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6);
    }
  }

  @override
  bool shouldRepaint(_MoonPainter o) => o.f != f || o.pal != pal || o.future != future || o.today != today;
}

// ---------------------------------------------------------------------------
// Net worth, the way the Budget app draws it: the figure and its change for
// the range, a smooth day-by-day line (red when it fell, green when it rose)
// with a fading fill, a glowing dot on today, the scale on the right, dates
// along the bottom, and 1M / 3M / 6M / 1Y / All. Drag along the line to read
// any day.

const _kRanges = [('1M', 1, 'Past Month'), ('3M', 3, 'Past 3 Months'), ('6M', 6, 'Past 6 Months'), ('1Y', 12, 'Past Year'), ('All', 0, 'All Time')];

/// The range picked last, kept while the app is open.
int _nwRange = 0;

const kLossRed = Color(0xFFFF453A);
const kGainGreen = Color(0xFF30D158);

class NetWorthCard extends StatefulWidget {
  final Money m;
  final String Function(int v, {bool sign, bool compact}) money;
  const NetWorthCard({super.key, required this.m, required this.money});
  @override
  State<NetWorthCard> createState() => _NetWorthCardState();
}

class _NetWorthCardState extends State<NetWorthCard> {
  int? _scrub;

  List<(int, int)> _series(int now) {
    final m = widget.m;
    final months = _kRanges[_nwRange].$2;
    final start = historyStart(m) ?? sod(now);
    // Like the Budget app: the last 30 / 90 / 180 / 365 days, today included.
    final days = const {1: 30, 3: 90, 6: 180, 12: 365}[months];
    var from = days == null ? start : addDays(sod(now), -(days - 1));
    // Nothing before the history starts (the line would just be flat).
    if (from < start && months != 0) from = math.max(from, addDays(start, -1));
    final s = netWorthDaily(m, from, now);
    return s.length >= 2 ? s : [(addDays(sod(now), -1), s.isEmpty ? 0 : s.first.$2), ...s];
  }

  void _scrubAt(double dx, double width, int n) {
    final chartW = width - _NetPainter.axisW;
    final i = (dx / chartW * (n - 1)).round().clamp(0, n - 1);
    if (i != _scrub) {
      tick();
      setState(() => _scrub = i);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final now = nowMs();
    final s = _series(now);
    final first = s.first.$2, last = s.last.$2;
    final up = last >= first;
    final ink = up ? kGainGreen : kLossRed;
    final i = _scrub?.clamp(0, s.length - 1);
    final shown = i == null ? last : s[i].$2;
    final change = shown - first;
    final pct = first == 0 ? null : (change * 100 / first.abs());
    int whole(int v) => (v / 100).round() * 100;
    final label = i == null ? _kRanges[_nwRange].$3 : _dayLabel(s[i].$1);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(widget.money(whole(shown)), style: cond(44, FontWeight.w800, height: 1, color: pal.text).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
      const SizedBox(height: 6),
      Text.rich(
        TextSpan(children: [
          TextSpan(
            text: '${widget.money(whole(change), sign: true)}${pct == null ? '' : ' (${change >= 0 ? '+' : '−'}${pct.abs() >= 100 ? pct.abs().ceil() : pct.abs().toStringAsFixed(1)}%)'}',
            style: TextStyle(color: change >= 0 ? kGainGreen : kLossRed),
          ),
          TextSpan(text: '  $label', style: TextStyle(color: pal.sub)),
        ]),
        style: inter(15, FontWeight.w600),
      ),
      const SizedBox(height: 14),
      LayoutBuilder(
        builder: (context, box) => Semantics(
          label: 'Net worth chart, ${_kRanges[_nwRange].$3.toLowerCase()}. Drag to read a day.',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (d) => _scrubAt(d.localPosition.dx, box.maxWidth, s.length),
            onHorizontalDragUpdate: (d) => _scrubAt(d.localPosition.dx, box.maxWidth, s.length),
            onHorizontalDragEnd: (_) => setState(() => _scrub = null),
            onHorizontalDragCancel: () => setState(() => _scrub = null),
            onLongPressStart: (d) => _scrubAt(d.localPosition.dx, box.maxWidth, s.length),
            onLongPressMoveUpdate: (d) => _scrubAt(d.localPosition.dx, box.maxWidth, s.length),
            onLongPressEnd: (_) => setState(() => _scrub = null),
            child: SizedBox(
              height: 190,
              child: DrawIn(
                token: '$_nwRange-${s.length}-$last',
                builder: (t) => CustomPaint(
                  painter: _NetPainter(s, pal, t, ink, i, (v) => widget.money(v, compact: true), months: _kRanges[_nwRange].$2),
                  size: Size.infinite,
                ),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 16),
      LayoutBuilder(
        builder: (context, box) => Segmented<int>(
          options: [for (var k = 0; k < _kRanges.length; k++) (k, _kRanges[k].$1)],
          value: _nwRange,
          onChanged: (k) => setState(() {
            _nwRange = k;
            _scrub = null;
          }),
          track: pal.field,
          thumb: pal.light ? Colors.white : const Color(0xFF52525B),
          on: pal.text,
          off: pal.sub,
          style: inter(15, FontWeight.w700),
          segWidth: (box.maxWidth - 6) / _kRanges.length,
          height: 44,
        ),
      ),
    ]);
  }
}

String _dayLabel(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${weekdayShort(ms)}, ${d.day} ${monthShort(ms)}${d.year != DateTime.now().year ? ' ${d.year}' : ''}';
}

class _NetPainter extends CustomPainter {
  static const axisW = 64.0;
  final List<(int, int)> s;
  final Pal pal;
  final double t;
  final Color ink;
  final int? scrub;
  final String Function(int) money;
  final int months;
  _NetPainter(this.s, this.pal, this.t, this.ink, this.scrub, this.money, {required this.months});

  @override
  void paint(Canvas canvas, Size size) {
    const top = 8.0, bottom = 26.0;
    final w = size.width - axisW, h = size.height - top - bottom;
    final values = s.map((p) => p.$2);
    var lo = values.reduce(math.min), hi = values.reduce(math.max);
    if (hi == lo) {
      hi += 100;
      lo -= 100;
    }
    final pad = (hi - lo) * .06;
    final yMax = hi + pad, yMin = lo - pad;
    double x(int i) => s.length == 1 ? 0 : w * i / (s.length - 1);
    double y(num v) => top + h * (1 - (v - yMin) / (yMax - yMin));

    // Scale: top, middle, bottom, with labels on the right.
    final rule = Paint()
      ..color = pal.rule
      ..strokeWidth = 1;
    final small = inter(12, FontWeight.w600, color: pal.sub);
    for (final v in [hi, (hi + lo) / 2, lo]) {
      final yy = y(v);
      canvas.drawLine(Offset(0, yy), Offset(w, yy), rule);
      final lab = _label(money(v.round()).toUpperCase(), small);
      lab.paint(canvas, Offset(w + 8, (yy - lab.height / 2).clamp(0.0, size.height - bottom - lab.height)));
    }

    // Smooth line through the days (monotone, so it never overshoots a real value).
    final pts = [for (var i = 0; i < s.length; i++) Offset(x(i), y(s[i].$2))];
    final line = _monotone(pts);
    final area = Path.from(line)
      ..lineTo(pts.last.dx, top + h)
      ..lineTo(pts.first.dx, top + h)
      ..close();

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(-4, 0, (w + 8) * t, size.height));
    canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [ink.withValues(alpha: pal.light ? .22 : .32), ink.withValues(alpha: 0)])
              .createShader(Rect.fromLTWH(0, top, w, h)));
    canvas.drawPath(
        line,
        Paint()
          ..color = ink
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round);
    canvas.restore();

    // The day being read, or today: a dot with a soft halo.
    if (t >= 1) {
      final i = scrub ?? s.length - 1;
      final p = pts[i];
      if (scrub != null) {
        final guide = Paint()
          ..color = pal.sub.withValues(alpha: .6)
          ..strokeWidth = 1.2;
        for (var yy = top; yy < top + h; yy += 8) {
          canvas.drawLine(Offset(p.dx, yy), Offset(p.dx, math.min(yy + 4, top + h)), guide);
        }
      }
      canvas.drawCircle(p, 11, Paint()..color = ink.withValues(alpha: .28));
      canvas.drawCircle(p, 6.5, Paint()..color = ink);
      canvas.drawCircle(
          p,
          6.5,
          Paint()
            ..color = pal.board
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
    }

    // Four dates along the bottom.
    final n = s.length;
    for (var k = 0; k < 4; k++) {
      final i = ((n - 1) * k / 3).round();
      final d = DateTime.fromMillisecondsSinceEpoch(s[i].$1);
      final text = months == 0 || months >= 12 ? "${monthShort(s[i].$1)} '${(d.year % 100).toString().padLeft(2, '0')}" : '${d.day} ${monthShort(s[i].$1)}';
      final lab = _label(text, small);
      lab.paint(canvas, Offset((x(i) - lab.width / 2).clamp(0.0, w - lab.width), size.height - lab.height));
    }
  }

  @override
  bool shouldRepaint(_NetPainter o) => o.t != t || o.s != s || o.pal != pal || o.scrub != scrub || o.ink != ink;
}

/// A smooth path through [p] that keeps each segment monotone (Fritsch–Carlson).
Path _monotone(List<Offset> p) {
  final path = Path()..moveTo(p.first.dx, p.first.dy);
  final n = p.length;
  if (n < 3) {
    for (final q in p.skip(1)) {
      path.lineTo(q.dx, q.dy);
    }
    return path;
  }
  final dx = [for (var i = 0; i < n - 1; i++) p[i + 1].dx - p[i].dx];
  final m = [for (var i = 0; i < n - 1; i++) dx[i] == 0 ? 0.0 : (p[i + 1].dy - p[i].dy) / dx[i]];
  final tan = List<double>.filled(n, 0);
  tan[0] = m[0];
  tan[n - 1] = m[n - 2];
  for (var i = 1; i < n - 1; i++) {
    tan[i] = m[i - 1] * m[i] <= 0 ? 0 : (m[i - 1] + m[i]) / 2;
  }
  for (var i = 0; i < n - 1; i++) {
    if (m[i] == 0) {
      tan[i] = 0;
      tan[i + 1] = 0;
      continue;
    }
    final a = tan[i] / m[i], b = tan[i + 1] / m[i];
    final r = a * a + b * b;
    if (r > 9) {
      final k = 3 / math.sqrt(r);
      tan[i] = k * a * m[i];
      tan[i + 1] = k * b * m[i];
    }
  }
  for (var i = 0; i < n - 1; i++) {
    final h = dx[i] / 3;
    path.cubicTo(p[i].dx + h, p[i].dy + tan[i] * h, p[i + 1].dx - h, p[i + 1].dy - tan[i + 1] * h, p[i + 1].dx, p[i + 1].dy);
  }
  return path;
}
/// Thin progress bar in the board's style.
class MoneyBar extends StatelessWidget {
  final double frac;
  final Color color;
  final double height;

  /// Optional marker (0–1), e.g. where today falls in the period.
  final double? mark;
  const MoneyBar({super.key, required this.frac, required this.color, this.height = 6, this.mark});
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final reduce = MediaQuery.disableAnimationsOf(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(children: [
          Positioned.fill(child: ColoredBox(color: pal.progTrack)),
          TweenAnimationBuilder<double>(
            tween: Tween(end: frac.clamp(0.0, 1.0)),
            duration: reduce ? Duration.zero : Motion.smoothDur,
            curve: Motion.smooth,
            builder: (_, v, _) => FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: v, heightFactor: 1, child: ColoredBox(color: color)),
          ),
          if (mark != null)
            Align(
              alignment: Alignment(-1 + 2 * mark!.clamp(0.0, 1.0), 0),
              child: Container(width: 2, color: (pal.light ? Colors.black : Colors.white).withValues(alpha: .7)),
            ),
        ]),
      ),
    );
  }
}

/// Days from [from] to [to] as "Nov 18 – 24" / "Nov 28 – Dec 3".
String rangeLabel(int from, int to) {
  final a = DateTime.fromMillisecondsSinceEpoch(from), b = DateTime.fromMillisecondsSinceEpoch(to);
  if (a.year == b.year && a.month == b.month) return a.day == b.day ? monthDay(from) : '${monthDay(from)} – ${b.day}';
  return '${monthDay(from)} – ${monthDay(to)}';
}
