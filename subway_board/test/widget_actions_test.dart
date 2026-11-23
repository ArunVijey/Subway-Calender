// What's done on the home-screen widget: ticks and quick adds are applied by
// whichever copy of the app gets them, and applying one twice changes nothing.
// The snapshot carries each day's tasks and money for the widget to draw.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:subwayboard/app/store.dart';
import 'package:subwayboard/core/money.dart';
import 'package:subwayboard/core/tasks.dart';
import 'package:subwayboard/core/util.dart';
import 'package:subwayboard/services/alerts.dart';
import 'package:subwayboard/services/google_auth.dart';
import 'package:subwayboard/services/widget_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Sat 21 Nov 2026, 11:00 local.
  final t0 = DateTime(2026, 11, 21, 11).millisecondsSinceEpoch;
  final real = nowMs;
  setUp(() => nowMs = () => t0);
  tearDown(() => nowMs = real);

  AppState fresh() => AppState(Alerts(), GoogleAuth())
    ..s.events = []
    ..s.tasks = []
    ..s.money.txns.clear();

  Future<void> settle(WidgetTester tester, AppState app) async {
    app.dispose();
    await tester.pump(const Duration(minutes: 1));
  }

  testWidgets('a tick from the widget logs the bill once, however often it arrives', (tester) async {
    final app = fresh();
    app.s.tasks.add(Task(id: 'rent', title: 'Rent', cat: app.s.lines.first.id, due: '2026-11-21', amount: 1500000));
    final tick = {'aid': 'a1', 'type': 'tick', 'task': 'rent', 'day': '2026-11-21', 'done': true, 'at': t0 - 60000};
    expect(app.applyWidgetActions([tick]), 1);
    expect(app.taskById('rent')!.done, isTrue);
    expect(app.s.money.txns.single.amount, 1500000);
    expect(app.s.money.txns.single.at, t0 - 60000, reason: 'logged when it was ticked, not when applied');

    // The app was closed before the widget heard back: it arrives again.
    expect(app.applyWidgetActions([tick]), 0);
    expect(app.s.money.txns, hasLength(1));

    // Un-tick from the widget takes the spend back.
    expect(app.applyWidgetActions([{...tick, 'aid': 'a2', 'done': false}]), 1);
    expect(app.s.money.txns, isEmpty);
    await settle(tester, app);
  });

  testWidgets('repeating: the tick rolls it on, and a repeat of the tick does nothing', (tester) async {
    final app = fresh();
    app.s.tasks.add(Task(id: 'g', title: 'Gym', cat: app.s.lines.first.id, due: '2026-11-21', repeat: 'daily'));
    final tick = {'aid': 'a', 'type': 'tick', 'task': 'g', 'day': '2026-11-21', 'done': true};
    expect(app.applyWidgetActions([tick]), 1);
    expect(app.taskById('g')!.due, '2026-11-22');
    expect(app.applyWidgetActions([tick]), 0);
    expect(app.taskById('g')!.due, '2026-11-22');
    // Its done day can't be un-ticked from the widget (that would duplicate it).
    expect(app.applyWidgetActions([{...tick, 'done': false}]), 0);
    // A future day waits its turn.
    expect(app.applyWidgetActions([{...tick, 'day': '2026-11-24'}]), 0);
    await settle(tester, app);
  });

  testWidgets('quick adds from the widget window arrive once', (tester) async {
    final app = fresh();
    final cat = app.s.lines.first.id;
    final t = Task(id: 'qt', title: 'Laptop service', cat: cat, due: '2026-11-21', time: 900, amount: 370000);
    final ev = app.eventFromTask(t)..id = 'qe';
    final x = Txn(id: 'qx', title: 'Metro', cat: app.s.money.fallbackCat, at: t0, amount: 4000);
    final acts = [
      {'aid': '1', 'type': 'add', 'task': t.toJson(), 'event': ev.toJson()},
      {'aid': '2', 'type': 'txn', 'txn': x.toJson()},
    ];
    expect(app.applyWidgetActions(acts), 3);
    expect(app.s.events.single.task, 'qt', reason: 'still linked');
    expect(app.s.money.txns.single.amount, 4000);
    expect(app.applyWidgetActions(acts), 0);
    expect(app.s.tasks, hasLength(1));
    expect(app.s.events, hasLength(1));
    expect(app.s.money.txns, hasLength(1));
    await settle(tester, app);
  });

  testWidgets('the quick-add window relays instead of writing', (tester) async {
    final app = fresh();
    final sent = <Map<String, dynamic>>[];
    app.relay = (a) async => sent.add(a);
    final t = Task(id: 'r', title: 'Call bank', cat: app.s.lines.first.id, due: '2026-11-22', time: 600);
    app.addLinked(task: t, event: app.eventFromTask(t));
    app.saveTxn(Txn(id: 'm', title: 'Tea', cat: app.s.money.fallbackCat, at: t0, amount: 2000));
    expect(app.s.tasks, isEmpty);
    expect(app.s.money.txns, isEmpty);
    expect(sent.map((a) => a['type']), ['add', 'txn']);
    expect((sent.first['event'] as Map)['task'], 'r');
    await settle(tester, app);
  });

  testWidgets('the snapshot has each day\'s tasks and money', (tester) async {
    final app = fresh();
    final cat = app.s.lines.first.id;
    final t = Task(id: 'lap', title: 'Laptop service', cat: cat, due: '2026-11-21', time: 900, amount: 370000);
    app.s.tasks.addAll([
      t,
      Task(id: 'hw', title: 'Submit HW', cat: cat, due: '2026-11-20'),
      Task(id: 'old', title: 'Long done', cat: cat, due: '2026-10-01', done: true, doneAt: DateTime(2026, 10, 1).millisecondsSinceEpoch),
    ]);
    app.s.events = [app.eventFromTask(t)];
    final food = app.s.money.spendCats.first;
    app.s.money.txns.addAll([
      Txn(id: 'z', title: 'Zomato', cat: food.id, at: DateTime(2026, 11, 20, 22).millisecondsSinceEpoch, amount: 38900),
      Txn(id: 'm', title: '', cat: food.id, at: DateTime(2026, 11, 21, 9).millisecondsSinceEpoch, amount: 18000),
      Txn(id: 'p', title: 'Salary', cat: app.s.money.fallbackIncome, at: DateTime(2026, 11, 21, 10).millisecondsSinceEpoch, amount: 5000000, income: true),
    ]);
    final snap = jsonDecode(WidgetBridge.snapshot(app.s)) as Map<String, dynamic>;
    expect(snap['v'], 2);
    final tasks = {for (final t in snap['tasks'] as List) t['id']: t};
    expect(tasks.keys, containsAll(['lap', 'hw']));
    expect(tasks.containsKey('old'), isFalse, reason: 'done before the window');
    expect(tasks['lap']['amt'], '₹3,700');
    final ev = (snap['events'] as List).single;
    expect(ev['task'], 'lap');
    expect(ev['done'], false);
    expect(ev['amt'], '₹3,700');
    final txns = {for (final x in snap['txns'] as List) x['id']: x};
    expect(txns['m']['title'], food.name, reason: 'untitled spends show their category');
    expect(txns['p']['amt'], '+₹50,000');
    expect(txns['p']['plus'], true);
    expect(snap['days']['2026-11-21']['spent'], '₹180');
    expect(snap['days']['2026-11-21']['in'], '+₹50,000');
    expect(snap['days']['2026-11-20']['spent'], '₹389');
    await settle(tester, app);
  });
}
