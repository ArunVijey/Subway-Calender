// One line, several things: a task with a calendar slot and a spend logged
// when it's ticked off, all kept in step.
import 'package:flutter_test/flutter_test.dart';
import 'package:subwayboard/app/store.dart';
import 'package:subwayboard/core/model.dart';
import 'package:subwayboard/core/quick.dart';
import 'package:subwayboard/core/tasks.dart';
import 'package:subwayboard/core/util.dart';
import 'package:subwayboard/services/alerts.dart';
import 'package:subwayboard/services/google_auth.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Sat 21 Nov 2026, 11:00 local.
  final t0 = DateTime(2026, 11, 21, 11).millisecondsSinceEpoch;
  final real = nowMs;
  setUp(() => nowMs = () => t0);
  tearDown(() => nowMs = real);

  AppState fresh() => AppState(Alerts(), GoogleAuth())..s.events = [];

  group('parser reads a closing amount', () {
    final data = AppData();
    Quick p(String s, [QMode m = QMode.task]) => parseQuick(s, m, data, data.money, now: t0);

    test('task: time and price', () {
      final q = p('Laptop Service 3pm 3700');
      expect(q.title, 'Laptop Service');
      expect(q.time, 15 * 60);
      expect(q.amount, 370000);
    });
    test('event reads it too', () {
      final q = p('Laptop Service 3pm 3700', QMode.event);
      expect(q.amount, 370000);
      expect(q.title, 'Laptop Service');
    });
    test('counts, years and small numbers stay in the title', () {
      expect(p('Read chapter 30').amount, isNull);
      expect(p('Read page 120').amount, isNull);
      expect(p('Tax return 2026').amount, isNull);
      expect(p('Tax return 2026').title, 'Tax return 2026');
      expect(p('Call 5 people').amount, isNull);
      expect(p('Buy 2 apples').amount, isNull);
      expect(p('Do 50 pushups').amount, isNull);
    });
    test('a number mid-line still needs a bill word or a currency mark', () {
      expect(p('Pay 2000 to Ravi').amount, 200000);
      expect(p('Send 2000 to Ravi').amount, isNull);
      expect(p('Send ₹2000 to Ravi').amount, 200000);
    });
    test('"for 2h" sizes a task, but a bare "2h" stays', () {
      expect(p('Study for 2h tomorrow 6pm').dur, 120);
      expect(p('Run 2h').dur, isNull);
      expect(p('Gym 6pm 1h', QMode.event).dur, 60);
    });
    test('spends are unchanged', () {
      final q = p('Metro 40', QMode.spend);
      expect(q.amount, 4000);
      expect(p('+5000 refund', QMode.spend).income, isTrue);
    });
  });

  testWidgets('task + event + spend: linked, one tick logs the payment', (tester) async {
    final app = fresh();
    final cat = app.s.lines.first.id;
    final t = Task(id: 'lap', title: 'Laptop Service', cat: cat, due: '2026-11-21', time: 15 * 60, amount: 370000);
    app.addLinked(task: t, event: app.eventFromTask(t));
    final ev = app.s.events.single;
    expect(ev.task, 'lap');
    expect(ev.allDay, isFalse);
    expect(ev.start, DateTime(2026, 11, 21, 15).millisecondsSinceEpoch);
    expect(ev.end - ev.start, 30 * kMin);
    expect(app.s.money.txns, isEmpty, reason: 'nothing logged until done');

    // It rides on the board row, not under TO DO.
    expect(app.tasksFor('2026-11-21'), isEmpty);

    app.tickLinked(ev);
    expect(app.taskById('lap')!.done, isTrue);
    expect(app.linkDone(app.taskById('lap')!, '2026-11-21'), isTrue);
    expect(app.s.money.txns.single.amount, 370000);

    app.tickLinked(ev); // un-tick takes the spend back
    expect(app.taskById('lap')!.done, isFalse);
    expect(app.s.money.txns, isEmpty);
    app.dispose();
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('once today\'s slot is over, the tick comes back to TO DO', (tester) async {
    final app = fresh();
    final t = Task(id: 'x', title: 'Morning call', cat: app.s.lines.first.id, due: '2026-11-21', time: 9 * 60);
    app.addLinked(task: t, event: app.eventFromTask(t));
    expect(app.tasksFor('2026-11-21').map((t) => t.id), ['x']);
    app.dispose();
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('editing the task moves its event; editing the event moves the task', (tester) async {
    final app = fresh();
    final t = Task(id: 'a', title: 'Dentist', cat: app.s.lines.first.id, due: '2026-11-23', time: 10 * 60);
    app.addLinked(task: t, event: app.eventFromTask(t, dur: 45));
    app.saveTask(t.copy()
      ..title = 'Dentist (Dr Rao)'
      ..due = '2026-11-25'
      ..time = 16 * 60 + 30);
    var ev = app.s.events.single;
    expect(ev.title, 'Dentist (Dr Rao)');
    expect(ev.start, DateTime(2026, 11, 25, 16, 30).millisecondsSinceEpoch);
    expect(ev.end - ev.start, 45 * kMin, reason: 'keeps its length');

    app.postponeTask('a');
    ev = app.s.events.single;
    expect(app.taskById('a')!.due, '2026-11-26');
    expect(dstr(ev.start), '2026-11-26');

    // Now from the event form.
    app.openForm(ev);
    final s = DateTime(2026, 11, 27, 8).millisecondsSinceEpoch;
    expect(app.saveEvent(FormValues(title: 'Dentist', cat: ev.cat, loc: '', notes: '', start: s, end: s + kHour, allDay: false, repeat: '', until: '', remind: null)), isNull);
    final task = app.taskById('a')!;
    expect(task.title, 'Dentist');
    expect(task.due, '2026-11-27');
    expect(task.time, 8 * 60);
    app.dispose();
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('no date takes it off the board; the switch puts it back', (tester) async {
    final app = fresh();
    final t = Task(id: 'a', title: 'Pick up parcel', cat: app.s.lines.first.id, due: '2026-11-22', time: 12 * 60);
    app.addLinked(task: t, event: app.eventFromTask(t));
    app.saveTask(t.copy()
      ..due = ''
      ..time = null);
    expect(app.s.events, isEmpty);
    app.saveTask(app.taskById('a')!.copy()..due = '2026-11-24', onBoard: true);
    expect(app.s.events.single.task, 'a');
    expect(app.s.events.single.allDay, isTrue, reason: 'no time: all day');
    app.saveTask(app.taskById('a')!.copy(), onBoard: false);
    expect(app.s.events, isEmpty);
    app.dispose();
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('deleting asks: both go, or the other stays unlinked', (tester) async {
    final app = fresh();
    Task mk(String id) => Task(id: id, title: id, cat: app.s.lines.first.id, due: '2026-11-22', time: 12 * 60);
    final a = mk('a'), b = mk('b');
    app.addLinked(task: a, event: app.eventFromTask(a));
    app.addLinked(task: b, event: app.eventFromTask(b));

    app.deleteTask('a', withEvent: true);
    expect(app.s.events.where((e) => e.title == 'a'), isEmpty);

    app.deleteTask('b');
    expect(app.s.events.single.title, 'b');
    expect(app.s.events.single.task, isNull);

    final c = mk('c');
    app.addLinked(task: c, event: app.eventFromTask(c));
    app.openForm(app.s.events.firstWhere((e) => e.task == 'c'));
    app.deleteEvent(withTask: true);
    expect(app.taskById('c'), isNull);
    app.dispose();
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('a repeating task: past slots read done, the tick rolls it on', (tester) async {
    final app = fresh();
    final t = Task(id: 'g', title: 'Gym', cat: app.s.lines.first.id, due: '2026-11-21', time: 18 * 60, repeat: 'daily');
    app.addLinked(task: t, event: app.eventFromTask(t));
    final ev = app.s.events.single;
    expect(ev.repeat?.freq, 'daily');
    expect(app.linkDone(t, '2026-11-21'), isFalse);
    final occ = ev.copy()
      ..seriesId = ev.id
      ..id = '${ev.id}::x';
    app.tickLinked(occ);
    expect(app.taskById('g')!.due, '2026-11-22');
    expect(app.linkDone(app.taskById('g')!, '2026-11-21'), isTrue);
    expect(app.linkDone(app.taskById('g')!, '2026-11-22'), isFalse);
    expect(app.s.events.single.start, ev.start, reason: 'the series stays put');
    app.dispose();
    await tester.pump(const Duration(minutes: 1));
  });

  test('the link survives a save and load', () {
    final ev = Event(id: 'e', title: 'x', cat: 'A', start: 0, end: kHour, task: 't1');
    final back = normEvent(ev.toJson(), {'A'}, 'A')!;
    expect(back.task, 't1');
    expect(back.extra.containsKey('task'), isFalse);
  });
}
