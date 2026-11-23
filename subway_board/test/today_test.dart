// The Today tab: the money hero and graph, then the day's departures, to-dos
// and money logged; WEEK lays out seven days the same way.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:subwayboard/app/store.dart';
import 'package:subwayboard/core/model.dart';
import 'package:subwayboard/core/money.dart';
import 'package:subwayboard/core/tasks.dart';
import 'package:subwayboard/core/util.dart';
import 'package:subwayboard/services/alerts.dart';
import 'package:subwayboard/services/google_auth.dart';
import 'package:subwayboard/ui/money.dart';
import 'package:subwayboard/ui/today.dart';

void main() {
  testWidgets('day and week show events, to-dos and money together', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 2400));
    final app = AppState(Alerts(), GoogleAuth());
    final now = nowMs(), d0 = sod(now), cat = app.s.lines.first.id;
    final m = app.s.money;
    m.accounts.add(Account(id: 'acc', name: 'Bank', type: 'bank', color: '#1d6cf2', opening: 1000000, created: addDays(d0, -40)));
    final food = m.spendCats.first;
    app.s.events = [Event(id: 'e1', title: 'Lab meeting', cat: cat, start: addDays(d0, 1) + 15 * kHour, end: addDays(d0, 1) + 16 * kHour)];
    app.s.tasks = [Task(id: 't1', title: 'Pay rent', cat: cat, due: dstr(addDays(d0, 1)), amount: 1500000)];
    m.txns.add(Txn(id: 'x1', title: 'Lunch', cat: food.id, at: addDays(d0, 1) + 13 * kHour, amount: 18000, acct: 'acc'));
    app.sel = dstr(addDays(d0, 1));

    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: app,
      child: const MaterialApp(home: Scaffold(backgroundColor: Colors.black, body: Padding(padding: EdgeInsets.symmetric(horizontal: 18), child: TodayView()))),
    ));
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('NET WORTH'), findsWidgets);
    expect(find.text('DEPARTURES'), findsOneWidget);
    expect(find.text('Lab meeting'), findsOneWidget);
    expect(find.text('TO DO'), findsOneWidget);
    expect(find.text('Pay rent'), findsOneWidget);
    expect(find.text('MONEY'), findsOneWidget);
    expect(find.text('Lunch'), findsOneWidget);
    expect(find.text('₹180 SPENT'), findsOneWidget);

    app.setTodayView('week');
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Lab meeting'), findsOneWidget);
    expect(find.text('Pay rent'), findsOneWidget);
    expect(find.text('Lunch'), findsOneWidget);
    expect(find.textContaining('1 DEPARTURE'), findsOneWidget);

    app.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('the arrow by NET WORTH folds it away here, apart from the Money tab eye', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 2400));
    final app = AppState(Alerts(), GoogleAuth());
    app.s.events = [];
    app.s.money.accounts.add(Account(id: 'acc', name: 'Bank', color: '#1d6cf2', opening: 123456700, created: addDays(sod(nowMs()), -40)));
    // The Money tab's eye is on: the Today tab doesn't care.
    app.s.settings.hideNet = true;
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: app,
      child: const MaterialApp(home: Scaffold(backgroundColor: Colors.black, body: Padding(padding: EdgeInsets.symmetric(horizontal: 18), child: TodayView()))),
    ));
    await tester.pump(const Duration(seconds: 2));
    expect(find.textContaining('12,34,567'), findsWidgets);
    expect(find.byIcon(Icons.visibility_off_outlined), findsNothing, reason: 'no eye on this tab');

    await tester.tap(find.byType(TodayNetFold));
    await tester.pump(const Duration(seconds: 2));
    expect(app.s.settings.foldTodayNet, isTrue);
    expect(app.s.settings.hideNet, isTrue, reason: 'the Money tab keeps its own switch');
    expect(find.textContaining('12,34,567'), findsNothing, reason: 'numbers and graph folded away');
    expect(find.text('NET WORTH'), findsOneWidget, reason: 'one slim line to open it again');
    expect(normalize(app.s.toJson()).settings.foldTodayNet, isTrue, reason: 'remembered');

    await tester.tap(find.byType(TodayNetFold));
    await tester.pump(const Duration(seconds: 2));
    expect(find.textContaining('12,34,567'), findsWidgets);

    app.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('today, ended departures fold away behind the arrow by DEPARTURES', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 2400));
    final app = AppState(Alerts(), GoogleAuth());
    final now = nowMs(), cat = app.s.lines.first.id;
    if (now - sod(now) < 3 * kHour) return; // too early in the day for something to have ended
    app.s.tasks = [];
    app.s.events = [
      Event(id: 'old', title: 'Morning lecture', cat: cat, start: now - 2 * kHour, end: now - kHour),
      Event(id: 'new', title: 'Evening run', cat: cat, start: now + kHour, end: now + 2 * kHour),
    ];
    app.sel = todayStr();
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: app,
      child: const MaterialApp(home: Scaffold(backgroundColor: Colors.black, body: Padding(padding: EdgeInsets.symmetric(horizontal: 18), child: TodayView()))),
    ));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Morning lecture'), findsNothing);
    expect(find.text('Evening run'), findsOneWidget);
    expect(find.text('1 ENDED'), findsOneWidget);

    await tester.tap(find.text('1 ENDED'));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Morning lecture'), findsOneWidget);
    expect(find.text('ENDED'), findsOneWidget);
    expect(find.text('HIDE ENDED'), findsOneWidget);

    app.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
  });
}
