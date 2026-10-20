// Colors and type, taken from the web app's CSS. Dark is the current web
// look; light keeps the black header but uses the cream board with a beige
// "next" row.
import 'package:flutter/material.dart';

const kBlack = Color(0xFF000000);
const kYellow = Color(0xFFF7C400);
const kYellowHi = Color(0xFFFFDC3D);
const kDim = Color(0xFFA1A1AA);
const kTabIdle = Color(0xFF71717A);
const kRed = Color(0xFFF87171);
const kGreen = Color(0xFF16A34A);

class Pal {
  final bool light;
  // board
  final Color board, row, rowNext, rule, text, sub, nextNum, progTrack;
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
    required this.nextNum,
    required this.progTrack,
    required this.panel,
    required this.ink,
    required this.panelRule,
    required this.field,
    required this.label,
    required this.rowLabel,
    required this.placeholder,
    required this.btn,
  });

  static const dark = Pal._(
    light: false,
    board: Color(0xFF0B0B0D),
    row: Color(0xFF0B0B0D),
    rowNext: Color(0xFF18181C),
    rule: Color(0xFF232328),
    text: Colors.white,
    sub: kDim,
    nextNum: kYellow,
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
