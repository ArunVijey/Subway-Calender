// Accent colour: any pick stays readable under black text, resets cleanly,
// is saved with the settings and travels to the home-screen widget.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:subwayboard/app/store.dart';
import 'package:subwayboard/core/model.dart';
import 'package:subwayboard/services/alerts.dart';
import 'package:subwayboard/services/google_auth.dart';
import 'package:subwayboard/services/widget_bridge.dart';
import 'package:subwayboard/ui/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => setAccent(null));

  double contrastWithBlack(Color c) => (c.computeLuminance() + .05) / .05;

  test('dark picks are lifted until black text reads (7:1 or better), hue kept', () {
    for (final c in const [Color(0xFF0A1A5C), Color(0xFF5B21B6), Color(0xFF7F1D1D), Color(0xFF064E3B)]) {
      final used = setAccent(c);
      expect(contrastWithBlack(used), greaterThanOrEqualTo(7));
      expect(HSLColor.fromColor(used).hue, closeTo(HSLColor.fromColor(c).hue, 2));
      expect(kYellowHi.computeLuminance(), greaterThan(used.computeLuminance()));
      // Ink on the cream board reads too.
      final cream = const Color(0xFFF6F3EC).computeLuminance();
      expect((cream + .05) / (kAccentInk.computeLuminance() + .05), greaterThanOrEqualTo(4.5));
    }
  });

  test('bright picks stay as they are; reset brings the yellow back', () {
    expect(setAccent(const Color(0xFF38BDF8)), const Color(0xFF38BDF8));
    setAccent(null);
    expect(kYellow, kDefaultAccent);
    expect(kYellowHi, const Color(0xFFFFDC3D));
  });

  test('saved in settings, and the widget gets it', () {
    final app = AppState(Alerts(), GoogleAuth())..s.events = [];
    app.setAccentColor(const Color(0xFF38BDF8));
    expect(app.s.settings.extra['accent'], '#38bdf8');
    expect(app.accentPick, const Color(0xFF38BDF8));
    final back = normalize(jsonDecode(jsonEncode(app.s.toJson())) as Map<String, dynamic>);
    expect(back.settings.extra['accent'], '#38bdf8');
    final snap = jsonDecode(WidgetBridge.snapshot(app.s)) as Map<String, dynamic>;
    expect(snap['accent'], '#38bdf8');
    expect(snap['accentHi'], isNot('#38bdf8'));
    app.setAccentColor(null);
    expect(app.s.settings.extra.containsKey('accent'), isFalse);
    expect((jsonDecode(WidgetBridge.snapshot(app.s)) as Map)['accent'], '#f7c400');
    app.dispose();
  });

  test('bad saved values fall back to the yellow', () {
    expect(accentFromHex('#12'), isNull);
    expect(accentFromHex(42), isNull);
    expect(accentFromHex('#38BDF8'), const Color(0xFF38BDF8));
  });
}
