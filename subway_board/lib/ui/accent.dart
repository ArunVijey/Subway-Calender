// Accent colour: a hue/saturation wheel, a row of swatches and a live preview
// of the board's own pieces. Applying it swaps the Subway yellow everywhere,
// the home-screen widget included. Colours are kept bright enough for the
// black text that sits on the accent.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/store.dart';
import 'haptics.dart';
import 'motion.dart';
import 'theme.dart';
import 'widgets.dart';

void openAccentPicker(BuildContext context) {
  final app = context.read<AppState>();
  showSheet<void>(context, (_) => ChangeNotifierProvider.value(value: app, child: const _AccentSheet()));
}

/// Picks that look good on the board (all readable with black text).
const kAccentSwatches = [
  Color(0xFFF7C400), // Subway yellow
  Color(0xFFFF9F1A), // amber
  Color(0xFFFF6B4A), // coral
  Color(0xFFFF5C8A), // pink
  Color(0xFFC084FC), // violet
  Color(0xFF7C9CFF), // periwinkle
  Color(0xFF38BDF8), // sky
  Color(0xFF2DD4BF), // teal
  Color(0xFF4ADE80), // mint
  Color(0xFFBEF264), // lime
];

class _AccentSheet extends StatefulWidget {
  const _AccentSheet();
  @override
  State<_AccentSheet> createState() => _AccentSheetState();
}

class _AccentSheetState extends State<_AccentSheet> with SingleTickerProviderStateMixin {
  late final AppState app = context.read<AppState>();
  late HSVColor _hsv = HSVColor.fromColor(app.accentPick ?? kDefaultAccent);

  // The live row's breathing, as on the board.
  late final AnimationController _glow = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  Color get _picked => _hsv.toColor();

  /// What the pick becomes once lifted for black text, and its glow.
  (Color, Color) get _shown {
    final base = readableAccent(_picked);
    final h = HSLColor.fromColor(base);
    final hi = _picked.toARGB32() == kDefaultAccent.toARGB32()
        ? const Color(0xFFFFDC3D)
        : h.withLightness((h.lightness + .11).clamp(0.0, .93)).withSaturation((h.saturation + .05).clamp(0.0, 1.0)).toColor();
    return (_picked.toARGB32() == kDefaultAccent.toARGB32() ? kDefaultAccent : base, hi);
  }

  void _fromWheel(Offset local, double size) {
    final c = Offset(size / 2, size / 2);
    final d = local - c;
    final r = size / 2;
    final hue = (math.atan2(d.dy, d.dx) * 180 / math.pi + 360) % 360;
    // The middle is white; keep some colour so it never matches the white "on" chips.
    final sat = (d.distance / r).clamp(.25, 1.0);
    setState(() => _hsv = HSVColor.fromAHSV(1, hue, sat, 1));
  }

  void _apply(Color? c) {
    tick();
    app.setAccentColor(c);
    rebuildAll();
    Navigator.pop(context);
    app.showToast(c == null ? 'Back to Subway yellow' : 'Accent colour set');
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final (accent, hi) = _shown;
    final lifted = readableAccent(_picked).toARGB32() != _picked.toARGB32() && _picked.toARGB32() != kDefaultAccent.toARGB32();
    final current = app.accentPick;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SheetHead('Accent colour'),

        // ---------- preview: the board's own pieces ----------
        Container(
          decoration: BoxDecoration(
            color: pal.light ? const Color(0xFFF6F3EC) : const Color(0xFF0B0B0D),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: pal.panelRule),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AnimatedBuilder(
                animation: _glow,
                builder: (_, _) => Container(
                  color: Color.lerp(accent, hi, Curves.easeInOutSine.transform(_glow.value)),
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black, width: 2.5),
                        ),
                        child: Text('A', style: cond(17, FontWeight.w800, color: Colors.black)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              color: Colors.black,
                              child: Text('LIVE', style: cond(12, FontWeight.w800, ls: .1, color: accent)),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Compressible Flow',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: cond(21, FontWeight.w700, color: Colors.black),
                            ),
                          ],
                        ),
                      ),
                      Text('34', style: cond(38, FontWeight.w800, color: Colors.black)),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(16)),
                      child: Text('SPEND', style: cond(14, FontWeight.w800, ls: .08, color: Colors.black)),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.fromLTRB(9, 5, 8, 5),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: pal.light ? .35 : .16),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: accent.withValues(alpha: .7), width: 1.2),
                      ),
                      child: Text('₹180 ✕', style: inter(13, FontWeight.w700, color: pal.light ? const Color(0xFF111111) : Colors.white)),
                    ),
                    const Spacer(),
                    Container(
                      width: 44,
                      height: 26,
                      padding: const EdgeInsets.all(3),
                      alignment: Alignment.centerRight,
                      decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(13)),
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                      child: const Icon(Icons.add, color: Colors.black, size: 24),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ---------- wheel ----------
        const SizedBox(height: 18),
        Center(
          child: LayoutBuilder(
            builder: (context, box) {
              final size = math.min(260.0, box.maxWidth);
              final r = size / 2;
              final ang = _hsv.hue * math.pi / 180;
              final dist = _hsv.saturation * r;
              final thumb = Offset(r + math.cos(ang) * dist, r + math.sin(ang) * dist);
              return Semantics(
                label: 'Colour wheel. Drag to pick a colour',
                child: GestureDetector(
                  onPanDown: (d) => _fromWheel(d.localPosition, size),
                  onPanUpdate: (d) => _fromWheel(d.localPosition, size),
                  onPanEnd: (_) => tick(),
                  child: SizedBox(
                    width: size,
                    height: size,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Positioned.fill(child: CustomPaint(painter: _WheelPainter())),
                        Positioned(
                          left: thumb.dx - 17,
                          top: thumb.dy - 17,
                          child: IgnorePointer(
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: _picked,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 3.5),
                                boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 8, offset: Offset(0, 2))],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            lifted ? 'Lifted a little so black text stays readable on it.' : 'Drag around the wheel, or pick one below.',
            textAlign: TextAlign.center,
            style: inter(12.5, FontWeight.w500, color: pal.label),
          ),
        ),

        // ---------- swatches ----------
        const SizedBox(height: 14),
        // Two even rows of five.
        Center(
          child: SizedBox(
            width: 5 * 44 + 4 * 14,
            child: Wrap(
              spacing: 14,
              runSpacing: 12,
              children: [
                for (final c in kAccentSwatches)
                  Semantics(
                    button: true,
                    selected: _picked.toARGB32() == c.toARGB32(),
                    label: c == kDefaultAccent ? 'Subway yellow' : 'Colour swatch',
                    excludeSemantics: true,
                    child: Pressable(
                      scale: .85,
                      onTap: () {
                        tick();
                        setState(() => _hsv = HSVColor.fromColor(c));
                      },
                      child: AnimatedContainer(
                        duration: Motion.snappyDur,
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(color: _picked.toARGB32() == c.toARGB32() ? pal.ink : Colors.transparent, width: 3),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _AccentBtn(label: 'Use this colour', color: accent, onTap: () => _apply(_picked.toARGB32() == kDefaultAccent.toARGB32() ? null : _picked)),
        if (current != null) SheetBtn('Back to Subway yellow', onTap: () => _apply(null)),
      ],
    );
  }
}

/// The main button, drawn in the colour being picked (SheetBtn uses the current one).
class _AccentBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _AccentBtn({required this.label, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.snappyDur,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)),
        child: Text(label.toUpperCase(), style: cond(16, FontWeight.w800, ls: .06, color: Colors.black)),
      ),
    ),
  );
}

/// Hue around the ring, white towards the middle.
class _WheelPainter extends CustomPainter {
  const _WheelPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()..shader = SweepGradient(colors: [for (var h = 0; h <= 360; h += 30) HSVColor.fromAHSV(1, h % 360 * 1.0, 1, 1).toColor()]).createShader(rect),
    );
    canvas.drawCircle(c, r, Paint()..shader = const RadialGradient(colors: [Colors.white, Color(0x00FFFFFF)]).createShader(rect));
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x33000000),
    );
  }

  @override
  bool shouldRepaint(_WheelPainter old) => false;
}
