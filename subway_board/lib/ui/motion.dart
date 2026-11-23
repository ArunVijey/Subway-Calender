// Motion toolkit: SwiftUI-style springs, press feedback, rolling digits and
// staggered entrances. Everything checks reduce-motion.
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import 'haptics.dart';

/// A spring as a [Curve], so implicit animations can use it. [span] is how
/// long the spring takes to settle; give the animation that duration.
class SpringCurve extends Curve {
  final SpringSimulation _sim;
  final double _span;
  SpringCurve(Duration response, double bounce, Duration span)
      : _sim = SpringSimulation(SpringDescription.withDurationAndBounce(duration: response, bounce: bounce), 0, 1, 0),
        _span = span.inMicroseconds / 1e6;

  @override
  double transformInternal(double t) => _sim.x(t * _span);
}

/// The SwiftUI presets: smooth (no bounce), snappy (a little) and bouncy.
abstract final class Motion {
  static const smoothDur = Duration(milliseconds: 700);
  static const snappyDur = Duration(milliseconds: 550);
  static const bouncyDur = Duration(milliseconds: 800);

  static final Curve smooth = SpringCurve(const Duration(milliseconds: 450), 0, smoothDur);
  static final Curve snappy = SpringCurve(const Duration(milliseconds: 350), .15, snappyDur);
  static final Curve bouncy = SpringCurve(const Duration(milliseconds: 450), .28, bouncyDur);

  /// Used for presses, where the spring runs as a real simulation.
  static final SpringDescription pressSpring = SpringDescription.withDurationAndBounce(duration: const Duration(milliseconds: 300), bounce: .2);
}

/// Shrinks slightly while pressed and springs back on release, like a UIKit
/// button. A quick tap still shows a short dip. Vibrates on tap.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  const Pressable({super.key, required this.child, this.onTap, this.scale = .96});
  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController.unbounded(vsync: this);

  void _to(double target, [double velocity = 0]) {
    if (MediaQuery.disableAnimationsOf(context)) return;
    _c.animateWith(SpringSimulation(Motion.pressSpring, _c.value, target, velocity));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _to(1) : null,
      // Released before the press showed: kick it down so the tap is still seen.
      onTapUp: enabled ? (_) => _to(0, _c.value < .5 ? 9 : 0) : null,
      onTapCancel: enabled ? () => _to(0) : null,
      onTap: tapped(widget.onTap),
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, child) => Transform.scale(scale: 1 - (1 - widget.scale) * _c.value.clamp(-.5, 1.5), child: child),
        child: widget.child,
      ),
    );
  }
}

/// Flips a board row down into place (rotateX -80° → 0), staggered 50 ms by
/// [index], like the departure board redrawing. Driven by a shared [intro]
/// controller; once it completes, rows render untouched.
class Entrance extends StatelessWidget {
  static const total = Duration(milliseconds: 900);
  static const _each = 400.0, _gap = 50.0, _maxIndex = 10;
  static const _ease = Cubic(.22, 1, .36, 1);

  final Animation<double> intro;
  final int index;
  final Widget child;
  const Entrance({super.key, required this.intro, required this.index, required this.child});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: intro,
        builder: (_, child) {
          if (intro.value >= 1) return child!;
          final ms = intro.value * total.inMilliseconds - math.min(index, _maxIndex) * _gap;
          final v = _ease.transform((ms / _each).clamp(0.0, 1.0));
          if (v >= 1) return child!;
          return Opacity(
            opacity: v,
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 1 / 600)
                ..rotateX(-80 * math.pi / 180 * (1 - v)),
              child: child,
            ),
          );
        },
        child: child,
      );
}

/// Text whose characters roll to their new value, like SwiftUI's
/// `.contentTransition(.numericText())`. Counting down rolls downward.
class RollingText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final bool animate;
  const RollingText(this.text, {super.key, required this.style, this.animate = true});
  @override
  State<RollingText> createState() => _RollingTextState();
}

class _RollingTextState extends State<RollingText> {
  bool _down = true;

  static num? _value(String s) => num.tryParse(s.replaceAll(RegExp(r'[^0-9]'), ''));

  @override
  void didUpdateWidget(RollingText old) {
    super.didUpdateWidget(old);
    final a = _value(old.text), b = _value(widget.text);
    if (a != null && b != null && a != b) _down = b < a;
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.text;
    return AnimatedSize(
      duration: Motion.snappyDur,
      curve: Motion.snappy,
      alignment: Alignment.centerRight,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        // Keyed from the right so the ones digit stays the ones digit when the length changes.
        for (var i = 0; i < t.length; i++) _RollChar(key: ValueKey(t.length - i), char: t[i], style: widget.style, down: _down, animate: widget.animate),
      ]),
    );
  }
}

class _RollChar extends StatefulWidget {
  final String char;
  final TextStyle style;
  final bool down, animate;
  const _RollChar({super.key, required this.char, required this.style, required this.down, required this.animate});
  @override
  State<_RollChar> createState() => _RollCharState();
}

class _RollCharState extends State<_RollChar> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Motion.snappyDur, value: 1);
  String? _old;

  @override
  void didUpdateWidget(_RollChar old) {
    super.didUpdateWidget(old);
    if (old.char != widget.char && widget.animate) {
      _old = old.char;
      _c.forward(from: 0);
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
        builder: (_, _) {
          final cur = Text(widget.char, style: widget.style);
          if (_c.value >= 1 || _old == null) return cur;
          final v = Motion.snappy.transform(_c.value);
          final h = (widget.style.fontSize ?? 14) * .75;
          final dir = widget.down ? -1.0 : 1.0; // new digit enters from above when counting down
          Widget part(String ch, double y, double o) {
            final op = o.clamp(0.0, 1.0);
            return Opacity(
              opacity: op,
              child: Transform.translate(
                offset: Offset(0, y),
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaY: 3.5 * (1 - op), tileMode: TileMode.decal),
                  child: Text(ch, style: widget.style),
                ),
              ),
            );
          }

          return ClipRect(
            child: Stack(clipBehavior: Clip.none, children: [
              part(widget.char, dir * h * (1 - v), v),
              Positioned(left: 0, top: 0, child: part(_old!, -dir * h * v, 1 - v)),
            ]),
          );
        },
      );
}

/// Pill segmented control with a spring-driven thumb (UISegmentedControl feel).
class Segmented<T> extends StatelessWidget {
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  final Color track, thumb, on, off;
  final TextStyle style;
  final double segWidth, height;
  const Segmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    required this.track,
    required this.thumb,
    required this.on,
    required this.off,
    required this.style,
    this.segWidth = 62,
    this.height = 34,
  });

  @override
  Widget build(BuildContext context) {
    final i = math.max(0, options.indexWhere((o) => o.$1 == value));
    final n = options.length;
    return Container(
      width: segWidth * n + 6,
      height: height,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: track, borderRadius: BorderRadius.circular(height / 2)),
      child: Stack(children: [
        AnimatedAlign(
          duration: Motion.snappyDur,
          curve: Motion.snappy,
          alignment: Alignment(n == 1 ? 0 : -1 + 2 * i / (n - 1), 0),
          child: Container(
            width: segWidth,
            height: height - 6,
            decoration: BoxDecoration(
              color: thumb,
              borderRadius: BorderRadius.circular((height - 6) / 2),
              boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2))],
            ),
          ),
        ),
        Row(children: [
          for (final (v, label) in options)
            Semantics(
              button: true,
              selected: v == value,
              label: label,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (v == value) return;
                  tick();
                  onChanged(v);
                },
                child: SizedBox(
                  width: segWidth,
                  height: height - 6,
                  child: Center(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 220),
                      style: style.copyWith(color: v == value ? on : off),
                      child: Text(label),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ]),
    );
  }
}
