// v2.4: adding things. Spends learn their category and account from your own
// history; tasks get priority, reminders and custom repeats that can end.
import 'package:flutter_test/flutter_test.dart';
import 'package:subwayboard/app/store.dart';
import 'package:subwayboard/core/model.dart';
import 'package:subwayboard/core/money.dart';
import 'package:subwayboard/core/quick.dart';
import 'package:subwayboard/core/tasks.dart';
import 'package:subwayboard/core/util.dart';
import 'package:subwayboard/services/alerts.dart';
import 'package:subwayboard/services/google_auth.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Wed 25 Nov 2026, 10:00 local.
  final t0 = DateTime(2026, 11, 25, 10).millisecondsSinceEpoch;
  final real = nowMs;
  setUp(() => nowMs = () => t0);
  tearDown(() => nowMs = real);

  int daysAgo(int d) => t0 - d * kDay;

  /// Money like the user's: built-in cats plus imported ones without keywords.
  Money money() {
    final m = Money();
    m.cats.addAll([
      MCat(id: 'dining', name: 'Dining', emoji: '🍔', color: '#ff8a00'),
      MCat(id: 'groc', name: 'Groceries', emoji: '🥑', color: '#22c55e'),
      MCat(id: 'transit', name: 'Transit', emoji: '🚌', color: '#1d6cf2'),
    ]);
    m.accounts.addAll([
      Account(id: 'slice', name: 'Slice', type: 'credit', color: '#f87171'),
      Account(id: 'cash', name: 'Cash', type: 'cash', color: '#22c55e'),
      Account(id: 'sbi', name: 'SBI', color: '#1d6cf2'),
    ]);
    m.defaultAcct = 'sbi';
    var n = 0;
    void add(String title, String cat, String acct, int ago) => m.txns.add(Txn(id: 'x${n++}', title: title, cat: cat, at: daysAgo(ago), amount: 10000, acct: acct));
    // Months of "Lunch" under Dining, then two recent ones the old guess put in Food.
    for (var i = 30; i < 200; i += 3) {
      add('Lunch', 'dining', 'slice', i);
    }
    add('Lunch', 'food', 'slice', 3);
    add('Lunch', 'food', 'slice', 2);
    add('Cab', 'transit', 'cash', 1);
    add('Cab home', 'transit', 'cash', 5);
    add('Groceries', 'groc', 'cash', 4);
    return m;
  }

  group('history picks the category', () {
    test('your usual category beats the keyword list', () {
      final mem = TitleMemory(money());
      final g = mem.guess('Lunch');
      expect(g.cat, 'dining');
      expect(g.why, CatWhy.history);
      expect(g.times, greaterThan(50));
    });
    test('imported categories win their own titles', () {
      final mem = TitleMemory(money());
      expect(mem.guess('Groceries').cat, 'groc'); // keywords alone say Food
      expect(mem.guess('groceries 640').cat, 'groc'); // numbers don't matter
    });
    test('leading words match a longer title', () {
      final mem = TitleMemory(money());
      expect(mem.guess('Lunch with Sam').cat, 'dining');
      expect(mem.guess('Cab to the airport').cat, 'transit');
    });
    test('a known name in the middle counts; filler words alone do not', () {
      final mem = TitleMemory(money());
      expect(mem.guess('Pay cab driver').cat, 'transit'); // "cab" seen before
      expect(mem.guess('Pay something').why, isNot(CatWhy.history));
    });
    test('keywords next, then the fallback', () {
      final mem = TitleMemory(money());
      final k = mem.guess('Netflix');
      expect(k.why, CatWhy.keyword);
      expect(k.cat, 'fun');
      final f = mem.guess('Zxqv thing');
      expect(f.why, CatWhy.fallback);
      expect(f.cat, 'other');
    });
    test('archived categories are never guessed', () {
      final m = money();
      m.cats.firstWhere((c) => c.id == 'dining').archived = true;
      expect(TitleMemory(m).guess('Lunch').cat, 'food');
    });
    test('account: last used for the title, then the category, then the default', () {
      final mem = TitleMemory(money());
      expect(mem.acctFor('Lunch', 'dining'), 'slice');
      expect(mem.acctFor('Cab', 'transit'), 'cash');
      expect(mem.acctFor('Bus pass', 'transit'), 'cash'); // by category
      expect(mem.acctFor('New thing', 'fun'), 'sbi'); // default
    });
    test('recent categories and title completion', () {
      final mem = TitleMemory(money());
      expect(mem.recentCats.first, 'transit');
      expect(mem.complete('ca'), ['Cab', 'Cab home']);
      expect(mem.complete('l'), isEmpty); // needs 2 letters
      expect(mem.complete('lunch'), isEmpty); // already exact
    });
  });

  group('custom repeats', () {
    test('every N days, months, years', () {
      expect(nextDue('2026-11-25', 'c:3:d'), '2026-11-28');
      expect(nextDue('2026-01-31', 'c:2:m'), '2026-03-31');
      expect(nextDue('2026-11-25', 'c:2:y'), '2028-11-25');
      expect(nextDue('2026-11-25', 'c:2:w'), '2026-12-09');
    });
    test('every 2 weeks on Tue and Fri', () {
      // Wed 25 Nov → Fri 27 Nov (same week), then skip a week → Tue 8 Dec.
      expect(nextDue('2026-11-25', 'c:2:w:2,5'), '2026-11-27');
      expect(nextDue('2026-11-27', 'c:2:w:2,5'), '2026-12-08');
      expect(nextDue('2026-12-08', 'c:2:w:2,5'), '2026-12-11');
    });
    test('presets come back as presets; labels read well', () {
      expect(makeRepeat(1, 'd'), 'daily');
      expect(makeRepeat(2, 'w'), 'biweekly');
      expect(makeRepeat(1, 'w', [1, 2, 3, 4, 5]), 'weekdays');
      expect(makeRepeat(3, 'd'), 'c:3:d');
      expect(repeatLabel('c:3:d'), 'Every 3 days');
      expect(repeatLabel('c:2:w:2,5'), 'Every 2 weeks on Tue, Fri');
      expect(isTaskRepeat('c:0:d'), isFalse);
      expect(isTaskRepeat('c:2:x'), isFalse);
    });
  });

  group('ticking off a repeat', () {
    AppState fresh() => AppState(Alerts(), GoogleAuth())..s.events = [];

    test('counts from when it was done', () {
      final app = fresh();
      app.s.tasks.add(Task(id: 'h', title: 'Haircut', cat: 'D', due: '2026-11-10', repeat: 'c:4:w', repFromDone: true));
      app.setTaskDone('h', true);
      expect(app.taskById('h')!.due, '2026-12-23'); // 4 weeks from today, not from the 10th
    });
    test('stops after its last date', () {
      final app = fresh();
      app.s.tasks.add(Task(id: 'r', title: 'Pay rent', cat: 'D', due: '2026-11-25', repeat: 'monthly', repUntil: '2026-12-31'));
      app.setTaskDone('r', true);
      expect(app.taskById('r')!.due, '2026-12-25');
      expect(app.taskById('r')!.done, isFalse);
      app.setTaskDone('r', true);
      expect(app.taskById('r')!.done, isTrue); // January is past the end
      expect(app.taskById('r')!.repeat, ''); // now a plain done task: it can be un-ticked
      app.setTaskDone('r', false);
      expect(app.taskById('r')!.done, isFalse);
    });
    test('stops after N times', () {
      final app = fresh();
      app.s.tasks.add(Task(id: 'p', title: 'Physio', cat: 'E', due: '2026-11-25', repeat: 'daily', repLeft: 1));
      app.setTaskDone('p', true);
      expect(app.taskById('p')!.due, '2026-11-26');
      expect(app.taskById('p')!.repLeft, 0);
      app.setTaskDone('p', true);
      expect(app.taskById('p')!.done, isTrue);
      // Two done entries in the history: the copy and the last one.
      expect(app.s.tasks.where((t) => t.title == 'Physio' && t.done).length, 2);
    });
    test('a bill pays from its own account and category', () {
      final app = fresh();
      app.s.money = money();
      app.s.tasks.add(Task(id: 'b', title: 'Wifi', cat: 'D', due: '2026-11-25', amount: 99900, mcat: 'bills', acct: 'cash'));
      app.setTaskDone('b', true);
      final x = app.s.money.txns.last;
      expect((x.cat, x.acct, x.amount), ('bills', 'cash', 99900));
    });
  });

  group('parser', () {
    final data = AppData();
    Quick p(String s, [QMode m = QMode.task]) => parseQuick(s, m, data, data.money, now: t0);

    test('every N and priority', () {
      final q = p('Gym every 2 days !1');
      expect(q.title, 'Gym');
      expect(q.repeat, 'c:2:d');
      expect(q.prio, 1);
      expect(p('Water plants every other week').repeat, 'biweekly');
      expect(p('Backup every 3 months p2').repeat, 'quarterly');
      expect(p('Backup every 3 months p2').prio, 2);
      expect(p('Call mom every week').repeat, 'weekly');
    });
    test('a lone ! is still a star', () {
      final q = p('Submit form !');
      expect(q.star, isTrue);
      expect(q.prio, 0);
    });
    test('events keep to the board’s repeats', () {
      final q = p('Standup every 2 days', QMode.event);
      expect(q.repeat, isNull);
    });
  });

  group('saved tasks', () {
    test('new fields round-trip; old tasks load as before', () {
      final t = Task(id: 'a', title: 'A', cat: 'A', due: '2026-11-25', time: 600, repeat: 'c:2:w:2,5', repFromDone: true, repUntil: '2027-03-31', repLeft: 9, prio: 2, remind: [1440, 0]);
      final back = taskFromJson(t.toJson(), {'A'}, 'A')!;
      expect(back.repeat, 'c:2:w:2,5');
      expect((back.repFromDone, back.repUntil, back.repLeft, back.prio), (true, '2027-03-31', 9, 2));
      expect(back.remind, [1440, 0]);
      final old = taskFromJson({'id': 'o', 'title': 'Old', 'cat': 'A', 'due': '2026-11-25', 'time': 600, 'repeat': 'weekly'}, {'A'}, 'A')!;
      expect((old.prio, old.remind, old.repLeft, old.repUntil), (0, null, null, ''));
      expect(old.reminders, [0]); // the old "due now" default
      expect(taskFromJson({'id': 'x', 'title': 'X', 'cat': 'A', 'repeat': 'c:9:q'}, {'A'}, 'A')!.repeat, '');
    });
    test('reminder times: before the time, or days ahead at 9:00', () {
      final timed = Task(id: 'a', title: 'A', cat: 'A', due: '2026-11-26', time: 15 * 60);
      expect(timed.remindAt(60), DateTime(2026, 11, 26, 14).millisecondsSinceEpoch);
      final day = Task(id: 'b', title: 'B', cat: 'A', due: '2026-11-26');
      expect(day.reminders, isEmpty);
      expect(day.remindAt(1440), DateTime(2026, 11, 25, 9).millisecondsSinceEpoch);
    });
  });
}
