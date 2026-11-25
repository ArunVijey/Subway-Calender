// The new sheets open and work: quick add (spend and task), the category
// grid, the task editor from a draft, and the repeat sheet.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:subwayboard/app/store.dart';
import 'package:subwayboard/core/money.dart';
import 'package:subwayboard/core/quick.dart';
import 'package:subwayboard/core/tasks.dart';
import 'package:subwayboard/core/util.dart';
import 'package:subwayboard/services/alerts.dart';
import 'package:subwayboard/services/google_auth.dart';
import 'package:subwayboard/ui/pickers.dart';
import 'package:subwayboard/ui/quick_add.dart';
import 'package:subwayboard/ui/tasks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AppState fresh() {
    final app = AppState(Alerts(), GoogleAuth())..s.events = [];
    final m = app.s.money;
    m.cats.add(MCat(id: 'dining', name: 'Dining', emoji: '🍔', color: '#ff8a00'));
    m.accounts.addAll([
      Account(id: 'slice', name: 'Slice', type: 'credit', color: '#f87171'),
      Account(id: 'cash', name: 'Cash', type: 'cash', color: '#22c55e'),
    ]);
    m.defaultAcct = 'slice';
    for (var i = 0; i < 5; i++) {
      m.txns.add(Txn(id: 'l$i', title: 'Lunch', cat: 'dining', at: nowMs() - (i + 1) * kDay, amount: 15000, acct: 'cash'));
    }
    return app;
  }

  Future<BuildContext> host(WidgetTester tester, AppState app) async {
    await tester.binding.setSurfaceSize(const Size(412, 3600));
    late BuildContext ctx;
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: app,
      child: MaterialApp(home: Scaffold(body: Builder(builder: (c) {
        ctx = c;
        return const SizedBox.expand();
      }))),
    ));
    return ctx;
  }

  Future<void> tapIt(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Future<void> done(WidgetTester tester, AppState app) async {
    app.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
  }

  testWidgets('spend: history picks Dining and Cash; logging saves both', (tester) async {
    final app = fresh();
    final ctx = await host(tester, app);
    openQuickAdd(ctx, mode: QMode.spend);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Lunch 180');
    await tester.pumpAndSettle();
    expect(find.textContaining('What you picked for “lunch”'), findsOneWidget);
    expect(find.text('LOG ₹180 · DINING · CASH'), findsOneWidget);
    await tester.tap(find.text('LOG ₹180 · DINING · CASH'));
    await tester.pumpAndSettle();
    final x = app.s.money.txns.firstWhere((t) => t.amount == 18000);
    expect((x.cat, x.acct), ('dining', 'cash'));
    await done(tester, app);
  });

  testWidgets('spend: log and add another keeps the sheet open', (tester) async {
    final app = fresh();
    final ctx = await host(tester, app);
    openQuickAdd(ctx, mode: QMode.spend);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Lunch 120');
    await tester.pumpAndSettle();
    await tapIt(tester, find.text('＋  LOG AND ADD ANOTHER'));
    expect(find.text('1 LOGGED · ADD THE NEXT ONE'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Coffee 60');
    await tester.pumpAndSettle();
    await tapIt(tester, find.textContaining('LOG ₹60'));
    expect(app.s.money.txns.where((t) => t.amount == 12000 || t.amount == 6000).length, 2);
    expect(find.text('1 LOGGED · ADD THE NEXT ONE'), findsNothing); // closed
    await done(tester, app);
  });

  testWidgets('spend: the grid picks a category, and it sticks', (tester) async {
    final app = fresh();
    final ctx = await host(tester, app);
    openQuickAdd(ctx, mode: QMode.spend);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Lunch 180');
    await tester.pumpAndSettle();
    await tester.tap(find.text('ALL ›'));
    await tester.pumpAndSettle();
    expect(find.text('RECENT'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Search categories'), 'fun');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fun').last);
    await tester.pumpAndSettle();
    expect(find.text('Your pick'), findsOneWidget);
    await tester.tap(find.textContaining('LOG ₹180'));
    await tester.pumpAndSettle();
    expect(app.s.money.txns.firstWhere((t) => t.amount == 18000).cat, 'fun');
    await done(tester, app);
  });

  testWidgets('task: More opens the full editor with everything filled in', (tester) async {
    final app = fresh();
    final ctx = await host(tester, app);
    openQuickAdd(ctx, mode: QMode.task);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Pay electricity bill 1st monthly 1200 !1');
    await tester.pumpAndSettle();
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(find.text('NEW TASK'), findsOneWidget);
    expect(find.text('Pay electricity bill'), findsOneWidget);
    expect(find.text('Monthly'), findsWidgets);
    await tapIt(tester, find.textContaining('ADD BILL'));
    final t = app.s.tasks.firstWhere((t) => t.title == 'Pay electricity bill');
    expect((t.repeat, t.prio, t.amount), ('monthly', 1, 120000));
    expect(t.mcat, isNotEmpty);
    await done(tester, app);
  });

  testWidgets('editor: repeat sheet sets every 3 days, ending after 10 times', (tester) async {
    final app = fresh();
    final ctx = await host(tester, app);
    openTaskSheet(ctx, null, draft: Task(id: 'n', title: 'Water plants', cat: app.s.lines.first.id, due: todayStr()));
    await tester.pumpAndSettle();
    await tapIt(tester, find.text('Never').first);
    await tapIt(tester, find.text('Custom'));
    await tapIt(tester, find.text('DAYS'));
    await tapIt(tester, find.byIcon(Icons.add).last);
    await tapIt(tester, find.byIcon(Icons.add).last);
    expect(find.text('3'), findsOneWidget);
    await tapIt(tester, find.text('After'));
    await tapIt(tester, find.text('DONE'));
    expect(find.textContaining('Every 3 days'), findsOneWidget);
    await tapIt(tester, find.text('ADD TASK'));
    final t = app.s.tasks.firstWhere((t) => t.title == 'Water plants');
    expect((t.repeat, t.repLeft), ('c:3:d', 9)); // "After 10×" by default: 9 more after this one
    await done(tester, app);
  });

  testWidgets('category grid on its own', (tester) async {
    final app = fresh();
    final ctx = await host(tester, app);
    String? got;
    pickMoneyCat(ctx, income: false, current: 'food', recent: const ['dining']).then((v) => got = v);
    await tester.pumpAndSettle();
    expect(find.text('RECENT'), findsOneWidget);
    await tester.tap(find.text('Dining').first);
    await tester.pumpAndSettle();
    expect(got, 'dining');
    await done(tester, app);
  });

  testWidgets('widget window: the spend relays its category and account, nothing is written', (tester) async {
    final app = fresh();
    final sent = <Map<String, dynamic>>[];
    app.relay = (a) async => sent.add(a);
    final before = app.s.money.txns.length;
    final ctx = await host(tester, app);
    openQuickAdd(ctx, mode: QMode.spend);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Lunch 220');
    await tester.pumpAndSettle();
    expect(find.text('More'), findsNothing); // no full form in the widget window
    await tester.tap(find.textContaining('Slice'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ALL ›'));
    await tester.pumpAndSettle();
    expect(find.text('New'), findsNothing); // can't make categories from there
    await tester.tap(find.text('Shopping').last);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('LOG ₹220'));
    await tester.pumpAndSettle();
    expect(app.s.money.txns.length, before);
    expect(sent.single['type'], 'txn');
    final x = txnFromJson(sent.single['txn'], app.s.money)!;
    expect((x.cat, x.acct, x.amount), ('shop', 'slice', 22000));
    await done(tester, app);
  });
}
