// The app's line icons (24×24, stroked like the web app's inline SVGs), drawn
// straight onto the canvas. Each icon's path data is parsed once and cached,
// so there's no SVG parser in the app and no per-build parsing.
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// One icon: its shapes, and how they're painted (24-unit coordinates).
class _Icon {
  final List<_Shape> shapes;
  final bool fill, stroke;
  final double width;
  final StrokeCap cap;
  final StrokeJoin join;
  const _Icon(this.shapes, {this.fill = false, this.stroke = true, this.width = 2, this.cap = StrokeCap.butt, this.join = StrokeJoin.miter});
}

sealed class _Shape {
  const _Shape();
  void addTo(Path p);
}

class _Circle extends _Shape {
  final double cx, cy, r;
  const _Circle(this.cx, this.cy, this.r);
  @override
  void addTo(Path p) => p.addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r));
}

class _Rect extends _Shape {
  final double x, y, w, h, rx;
  const _Rect(this.x, this.y, this.w, this.h, this.rx);
  @override
  void addTo(Path p) => p.addRRect(RRect.fromRectXY(Rect.fromLTWH(x, y, w, h), rx, rx));
}

class _D extends _Shape {
  final String d;
  const _D(this.d);
  @override
  void addTo(Path p) => p.addPath(parseSvgPath(d), Offset.zero);
}

const _round = StrokeCap.round, _rj = StrokeJoin.round;

const Map<String, _Icon> _icons = {
  'gear': _Icon([
    _Circle(12, 12, 3),
    _D('M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09a1.65 1.65 0 0 0-1-1.51 1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09a1.65 1.65 0 0 0 1.51-1 1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z'),
  ], width: 2, cap: _round, join: _rj),
  'grid': _Icon([_Rect(3, 3, 8, 8, 2), _Rect(13, 3, 8, 8, 2), _Rect(3, 13, 8, 8, 2), _Rect(13, 13, 8, 8, 2)], fill: true, stroke: false),
  'lines': _Icon([_Circle(6, 5, 2.2), _Circle(18, 5, 2.2), _Circle(12, 19, 2.2), _D('M6 7.2c0 5 6 4 6 9.6M18 7.2c0 5-6 4-6 9.6')], width: 2.2, cap: _round),
  'plus': _Icon([_D('M12 5v14M5 12h14')], width: 2.6, cap: _round),
  'reset': _Icon([_D('M3 12a9 9 0 1 0 3-6.7'), _D('M3 4v5h5')], width: 2.2, cap: _round, join: _rj),
  'chev': _Icon([_D('M6 9l6 6 6-6')], width: 3, cap: _round, join: _rj),
  'tasks': _Icon([_Circle(12, 12, 9), _D('M8 12.3l2.7 2.7L16.2 9.5')], width: 2.2, cap: _round, join: _rj),
  'money': _Icon([_Rect(3, 6, 18, 13, 3), _D('M3 10h18'), _D('M16 15h2'), _D('M7 6V5a2 2 0 0 1 2-2h6a2 2 0 0 1 2 2v1')], width: 2.2, cap: _round, join: _rj),
  'star': _Icon([_D('M12 3.2l2.7 5.6 6.1.8-4.5 4.2 1.1 6.1L12 17l-5.4 2.9 1.1-6.1-4.5-4.2 6.1-.8z')], width: 2, join: _rj),
  'star-on': _Icon([_D('M12 3.2l2.7 5.6 6.1.8-4.5 4.2 1.1 6.1L12 17l-5.4 2.9 1.1-6.1-4.5-4.2 6.1-.8z')], fill: true, width: 2, join: _rj),
  'check': _Icon([_D('M5.5 12.5l4.2 4.2L18.5 8')], width: 3.2, cap: _round, join: _rj),
  'cal': _Icon([_Rect(3.5, 5, 17, 15.5, 3), _D('M3.5 10h17M8 3v4M16 3v4')], width: 2.2, cap: _round, join: _rj),
  'clock': _Icon([_Circle(12, 12, 8.5), _D('M12 7.5V12l3 2')], width: 2.2, cap: _round),
  'repeat': _Icon([_D('M17 2.5l3 3-3 3'), _D('M4 11.5v-1a5 5 0 0 1 5-5h11'), _D('M7 21.5l-3-3 3-3'), _D('M20 12.5v1a5 5 0 0 1-5 5H4')], width: 2.2, cap: _round, join: _rj),
  'arrow': _Icon([_D('M5 12h14M13 6l6 6-6 6')], width: 2.6, cap: _round, join: _rj),
  'today': _Icon([_Rect(3.5, 3.5, 17, 17, 4), _D('M8 9h8M8 12.5h8M8 16h5')], width: 2.2, cap: _round, join: _rj),
  'up': _Icon([_D('M12 19V5M6 11l6-6 6 6')], width: 2.8, cap: _round, join: _rj),
};

final _paths = <String, Path>{};

Path _pathOf(String name) => _paths.putIfAbsent(name, () {
      final p = Path();
      for (final s in _icons[name]!.shapes) {
        s.addTo(p);
      }
      return p;
    });

/// A 24×24 line icon from the set above, in [color].
class SvgIcon extends StatelessWidget {
  final String name;
  final double size;
  final Color color;
  const SvgIcon(this.name, {super.key, this.size = 22, this.color = const Color(0xFFFFFFFF)});

  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size, child: CustomPaint(painter: _IconPainter(name, color)));
}

class _IconPainter extends CustomPainter {
  final String name;
  final Color color;
  const _IconPainter(this.name, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final icon = _icons[name]!;
    final path = _pathOf(name);
    // Like an SVG viewBox with the default preserveAspectRatio (meet, centred).
    final k = math.min(size.width, size.height) / 24;
    canvas.save();
    canvas.translate((size.width - 24 * k) / 2, (size.height - 24 * k) / 2);
    canvas.scale(k);
    if (icon.fill) canvas.drawPath(path, Paint()..color = color..isAntiAlias = true);
    if (icon.stroke) {
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..isAntiAlias = true
          ..style = PaintingStyle.stroke
          ..strokeWidth = icon.width
          ..strokeCap = icon.cap
          ..strokeJoin = icon.join,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_IconPainter o) => o.name != name || o.color != color;
}

/// Parses SVG path data (M L H V C S Q T A Z, absolute and relative).
Path parseSvgPath(String d) {
  final p = Path();
  var i = 0;
  final n = d.length;

  bool isSep(int c) => c == 0x20 || c == 0x2C || c == 0x09 || c == 0x0A || c == 0x0D;
  void skip() {
    while (i < n && isSep(d.codeUnitAt(i))) {
      i++;
    }
  }

  bool atNumber() {
    skip();
    if (i >= n) return false;
    final c = d.codeUnitAt(i);
    return (c >= 0x30 && c <= 0x39) || c == 0x2D || c == 0x2B || c == 0x2E;
  }

  double num() {
    skip();
    final start = i;
    if (i < n && (d[i] == '-' || d[i] == '+')) i++;
    var dot = false;
    while (i < n) {
      final c = d.codeUnitAt(i);
      if (c >= 0x30 && c <= 0x39) {
        i++;
      } else if (c == 0x2E && !dot) {
        dot = true;
        i++;
      } else if ((c == 0x65 || c == 0x45) && i + 1 < n) {
        i++;
        if (d[i] == '-' || d[i] == '+') i++;
      } else {
        break;
      }
    }
    return double.parse(d.substring(start, i));
  }

  bool flag() {
    skip();
    return d[i++] == '1';
  }

  var x = 0.0, y = 0.0, sx = 0.0, sy = 0.0; // current point, subpath start
  var cx = 0.0, cy = 0.0; // last control point (for S / T)
  var last = '';
  var cmd = '';
  while (true) {
    skip();
    if (i >= n) break;
    final ch = d[i];
    if (RegExp(r'[A-Za-z]').hasMatch(ch)) {
      cmd = ch;
      i++;
    } else if (cmd.isEmpty) {
      break;
    }
    final rel = cmd == cmd.toLowerCase();
    final ox = rel ? x : 0.0, oy = rel ? y : 0.0;
    switch (cmd.toUpperCase()) {
      case 'M':
        x = ox + num();
        y = oy + num();
        p.moveTo(x, y);
        sx = x;
        sy = y;
        // Further pairs after a moveto are linetos.
        cmd = rel ? 'l' : 'L';
      case 'L':
        x = ox + num();
        y = oy + num();
        p.lineTo(x, y);
      case 'H':
        x = ox + num();
        p.lineTo(x, y);
      case 'V':
        y = oy + num();
        p.lineTo(x, y);
      case 'C':
        final x1 = ox + num(), y1 = oy + num(), x2 = ox + num(), y2 = oy + num();
        x = ox + num();
        y = oy + num();
        p.cubicTo(x1, y1, x2, y2, x, y);
        cx = x2;
        cy = y2;
      case 'S':
        final reflect = last == 'C' || last == 'S';
        final x1 = reflect ? 2 * x - cx : x, y1 = reflect ? 2 * y - cy : y;
        final x2 = ox + num(), y2 = oy + num();
        x = ox + num();
        y = oy + num();
        p.cubicTo(x1, y1, x2, y2, x, y);
        cx = x2;
        cy = y2;
      case 'Q':
        final x1 = ox + num(), y1 = oy + num();
        x = ox + num();
        y = oy + num();
        p.quadraticBezierTo(x1, y1, x, y);
        cx = x1;
        cy = y1;
      case 'T':
        final reflect = last == 'Q' || last == 'T';
        final x1 = reflect ? 2 * x - cx : x, y1 = reflect ? 2 * y - cy : y;
        x = ox + num();
        y = oy + num();
        p.quadraticBezierTo(x1, y1, x, y);
        cx = x1;
        cy = y1;
      case 'A':
        final rx = num(), ry = num(), rot = num();
        final large = flag(), sweep = flag();
        final nx = ox + num(), ny = oy + num();
        if (rx == 0 || ry == 0) {
          p.lineTo(nx, ny);
        } else {
          p.arcToPoint(Offset(nx, ny), radius: Radius.elliptical(rx.abs(), ry.abs()), rotation: rot, largeArc: large, clockwise: sweep);
        }
        x = nx;
        y = ny;
      case 'Z':
        p.close();
        x = sx;
        y = sy;
      default:
        return p;
    }
    last = cmd.toUpperCase();
    // Z takes no numbers; anything else may repeat with implicit commands.
    if (last == 'Z' && atNumber()) break;
  }
  return p;
}
