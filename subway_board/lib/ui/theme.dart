// Colors and type, taken from the web app's CSS. Dark is the current web
// look; light keeps the black header but uses the cream board with a beige
// "next" row.
import 'package:flutter/material.dart';

const kBlack = Color(0xFF000000);
// ---------- accent ----------
// The Subway yellow is the default accent; Settings → Display → Accent colour
// swaps it everywhere (and on the widget). Black text and marks sit on the
// accent all over, so any pick is lifted until black reads well on it.

const kDefaultAccent = Color(0xFFF7C400);

/// The accent (named for the original yellow; it's whatever is chosen).
Color kYellow = kDefaultAccent;

/// The bright end of the live row's breathing glow.
Color kYellowHi = const Color(0xFFFFDC3D);

/// The accent as text or a thin mark on the cream (light) board.
Color kAccentInk = const Color(0xFF8A6D00);

/// A deeper accent for filled marks on the cream board.
Color kAccentDeep = const Color(0xFFE0A800);

/// Lightest black text should need on the accent (contrast about 7:1).
const _minLum = .30;

/// [c] lifted (lighter, same hue) until black text reads well on it.
Color readableAccent(Color c) {
  var h = HSLColor.fromColor(c.withValues(alpha: 1));
  var out = h.toColor();
  for (var i = 0; i < 60 && out.computeLuminance() < _minLum; i++) {
    h = h.withLightness((h.lightness + .01).clamp(0.0, 1.0));
    out = h.toColor();
  }
  return out;
}

/// Sets the accent everywhere; returns the color actually used.
Color setAccent(Color? c) {
  if (c == null || c.toARGB32() == kDefaultAccent.toARGB32()) {
    kYellow = kDefaultAccent;
    kYellowHi = const Color(0xFFFFDC3D);
    kAccentInk = const Color(0xFF8A6D00);
    kAccentDeep = const Color(0xFFE0A800);
    return kYellow;
  }
  final base = readableAccent(c);
  final h = HSLColor.fromColor(base);
  kYellow = base;
  // Same steps the yellow takes: a lighter glow, a dark ink, a deeper fill.
  kYellowHi = h.withLightness((h.lightness + .11).clamp(0.0, .93)).withSaturation((h.saturation + .05).clamp(0.0, 1.0)).toColor();
  // Dark enough to read on the cream board (4.5:1 or better), whatever the hue.
  const cream = 0.8975; // luminance of #F6F3EC
  var ink = h.withLightness(.30);
  while ((cream + .05) / (ink.toColor().computeLuminance() + .05) < 4.6 && ink.lightness > .05) {
    ink = ink.withLightness(ink.lightness - .01);
  }
  kAccentInk = ink.toColor();
  kAccentDeep = h.withLightness((h.lightness - .07).clamp(.25, 1.0)).toColor();
  return base;
}

/// The accent saved in settings ('#rrggbb'), or null for the Subway yellow.
Color? accentFromHex(Object? v) {
  if (v is! String || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(v)) return null;
  return Color(int.parse(v.substring(1), radix: 16) | 0xFF000000);
}

/// Rebuilds every widget so the new accent shows at once (sheets stay open).
void rebuildAll() {
  void mark(Element e) {
    e.markNeedsBuild();
    e.visitChildren(mark);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(mark);
}

String accentHex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
const kDim = Color(0xFFA1A1AA);
const kTabIdle = Color(0xFF71717A);
const kRed = Color(0xFFF87171);
const kGreen = Color(0xFF16A34A);

class Pal {
  final bool light;
  // board
  final Color board, row, rowNext, rule, text, sub, progTrack;
  final Color? _nextNum;

  /// The next departure's countdown: the accent on the dark board.
  Color get nextNum => _nextNum ?? kYellow;
  // form / settings / sheets
  final Color panel, ink, panelRule, field, label, rowLabel, placeholder, btn;

  const Pal._({
    required this.light,
    required this.board,
    required this.row,
    required this.rowNext,
    required this.rule,
    required this.text,
    required this.sub,
    Color? nextNum,
    required this.progTrack,
    required this.panel,
    required this.ink,
    required this.panelRule,
    required this.field,
    required this.label,
    required this.rowLabel,
    required this.placeholder,
    required this.btn,
    // ignore: prefer_initializing_formals
  }) : _nextNum = nextNum;

  static const dark = Pal._(
    light: false,
    board: Color(0xFF0B0B0D),
    row: Color(0xFF0B0B0D),
    rowNext: Color(0xFF18181C),
    rule: Color(0xFF232328),
    text: Colors.white,
    sub: kDim,
    nextNum: null,
    progTrack: Color(0x1FFFFFFF),
    panel: Color(0xFF141416),
    ink: Colors.white,
    panelRule: Color(0xFF26262B),
    field: Color(0xFF232328),
    label: kDim,
    rowLabel: Color(0xFFD4D4D8),
    placeholder: Color(0xFF52525B),
    btn: Color(0xFF26262B),
  );

  static const lightPal = Pal._(
    light: true,
    board: Color(0xFFF6F3EC),
    row: Color(0xFFF6F3EC),
    rowNext: Color(0xFFEBE3CF),
    rule: Color(0xFFE2DDD1),
    text: Color(0xFF111111),
    sub: Color(0xFF57534E),
    nextNum: Color(0xFF111111),
    progTrack: Color(0x14000000),
    panel: Color(0xFFF6F3EC),
    ink: Color(0xFF111111),
    panelRule: Color(0xFFE2DDD1),
    field: Color(0xFFE9E4D8),
    label: Color(0xFF57534E),
    rowLabel: Color(0xFF292524),
    placeholder: Color(0xFFA8A29E),
    btn: Color(0xFFE2DDD1),
  );

  static Pal of(BuildContext context) => PalScope.of(context);
}

class PalScope extends InheritedWidget {
  final Pal pal;
  const PalScope({super.key, required this.pal, required super.child});
  static Pal of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<PalScope>()?.pal ?? Pal.dark;
  @override
  bool updateShouldNotify(PalScope old) => old.pal != pal;
}

/// Barlow Condensed (display type). [ls] is letter-spacing in em, like the CSS.
TextStyle cond(double size, FontWeight w, {double ls = 0, Color? color, double? height}) => TextStyle(
      fontFamily: 'BarlowCondensed',
      fontSize: size,
      fontWeight: w,
      letterSpacing: ls * size,
      color: color,
      height: height,
    );

/// Inter (body type, variable font).
TextStyle inter(double size, FontWeight w, {double ls = 0, Color? color, double? height}) => TextStyle(
      fontFamily: 'Inter',
      fontSize: size,
      fontWeight: w,
      fontVariations: [FontVariation.weight(w.value.toDouble())],
      letterSpacing: ls * size,
      color: color,
      height: height,
    );

Color hexColor(String hex) => Color(int.parse(hex.substring(1), radix: 16) | 0xFF000000);

const kEase = Cubic(.22, 1, .36, 1);
