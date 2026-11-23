// Today's finished departures stay folded away until the arrow by DEPARTURES opens them.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:subwayboard/app/store.dart';
import 'package:subwayboard/core/model.dart';
import 'package:subwayboard/core/util.dart';
import 'package:subwayboard/services/alerts.dart';
import 'package:subwayboard/services/google_auth.dart';
import 'package:subwayboard/ui/board.dart';

void main() {
  testWidgets('finished departures fold in and out', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    final app = AppState(Alerts(), GoogleAuth());
    final now = nowMs(), cat = app.s.lines.first.id;
    // Keep the fixtures inside today even right after midnight or before it.
    final d0 = sod(now), d1 = addDays(d0, 1);
    int at(int min) => (now + min * kMin).clamp(d0 + 1, d1 - 2);
    app.s.events = [
      Event(id: 'a', title: 'Early run', cat: cat, start: d0 + 1, end: d0 + 2),
      Event(id: 'b', title: 'Later thing', cat: cat, start: at(120), end: d1 - 1),
    ];
    if (now - d0 < 2 * kMin) return; // nothing can have finished yet

    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: app,
      child: const MaterialApp(home: Scaffold(body: BoardView())),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Early run'), findsNothing);
    expect(find.text('Later thing'), findsOneWidget);

    await tester.tap(find.text('DEPARTURES'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(app.showDone, isTrue);
    expect(find.text('Early run'), findsOneWidget);
    expect(find.text('ENDED'), findsOneWidget);

    await tester.tap(find.text('DEPARTURES'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Early run'), findsNothing);

    // Other days have no arrow: all their departures are already listed.
    app.shiftDay(1);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(app.showDone, isFalse);
    await tester.tap(find.text('DEPARTURES'), warnIfMissed: false);
    expect(app.showDone, isFalse);

    app.dispose();
    await tester.pumpWidget(const SizedBox());
  });
}
