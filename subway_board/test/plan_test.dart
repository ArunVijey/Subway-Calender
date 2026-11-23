// Tasks, money and quick add: parsing, repeats, the month's numbers, and that
// everything survives a save/load and a backup restore.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:subwayboard/core/budget_import.dart';
import 'package:subwayboard/core/model.dart';
import 'package:subwayboard/core/money.dart';
import 'package:subwayboard/core/quick.dart';
import 'package:subwayboard/core/tasks.dart';
import 'package:subwayboard/core/util.dart';

void main() {
  // Friday 20 Nov 2026, 10:30 local.
  final now = DateTime(2026, 11, 20, 10, 30).millisecondsSinceEpoch;
  setUp(() => nowMs = () => now);

  AppData data() => normalize(null);
  Quick p(String s, QMode m) {
    final d = data();
    return parseQuick(s, m, d, d.money, now: now);
  }

  group('quick add · tasks', () {
    test('day and time come out of the title', () {
      final q = p('Submit HW fri 5pm', QMode.task);
      expect(q.title, 'Submit HW');
      expect(q.due, '2026-11-20'); // it's Friday: today
      expect(q.time, 17 * 60);
    });

    test('weekday means the next one', () {
      final q = p('Submit HW mon 5pm', QMode.task);
      expect(q.title, 'Submit HW');
      expect(q.due, '2026-11-23');
      expect(q.time, 17 * 60);
    });

    test('tomorrow, 24-hour time', () {
      final q = p('Call mom tomorrow at 18:30', QMode.task);
      expect(q.title, 'Call mom');
      expect(q.due, '2026-11-21');
      expect(q.time, 18 * 60 + 30);
    });

    test('a bill: amount with ₹, 1st, monthly', () {
      final q = p('Pay rent ₹15,000 1st monthly', QMode.task);
      expect(q.title, 'Pay rent');
      expect(q.amount, 1500000);
      expect(q.due, '2026-12-01'); // the 1st has passed this month
      expect(q.repeat, 'monthly');
      expect(q.mcat, 'bills');
    });

    test('a bare number is not money unless it looks like a bill', () {
      expect(p('Read chapter 3', QMode.task).amount, isNull);
      expect(p('Read chapter 3', QMode.task).title, 'Read chapter 3');
      expect(p('AS5011 assignment', QMode.task).title, 'AS5011 assignment');
      expect(p('Electricity bill 1200', QMode.task).amount, 120000);
    });

    test('star and #line', () {
      final d = data();
      final q = parseQuick('Read paper ! #focus', QMode.task, d, d.money, now: now);
      expect(q.star, isTrue);
      expect(q.line, 'B');
      expect(q.title, 'Read paper');
    });

    test('a dropped chip stays in the title', () {
      final d = data();
      final q = parseQuick('Dinner fri', QMode.task, d, d.money, ignore: {QKind.date}, now: now);
      expect(q.due, isNull);
      expect(q.title, 'Dinner fri');
    });

    test('dates: 25 dec, dec 25, 3/12, in 3 days, next week', () {
      expect(p('Party 25 dec', QMode.task).due, '2026-12-25');
      expect(p('Party dec 25th', QMode.task).due, '2026-12-25');
      expect(p('Exam 3/12', QMode.task).due, '2026-12-03');
      expect(p('Exam 3/1', QMode.task).due, '2027-01-03');
      expect(p('Renew in 3 days', QMode.task).due, '2026-11-23');
      expect(p('Review next week', QMode.task).due, '2026-11-27');
    });
  });

  group('quick add · events and spends', () {
    test('event with duration and line keyword', () {
      final q = p('Gym tomorrow 6pm for 1h', QMode.event);
      expect(q.title, 'Gym');
      expect(q.due, '2026-11-21');
      expect(q.time, 18 * 60);
      expect(q.dur, 60);
      expect(q.line, 'E'); // Health has "gym"
    });

    test('90m and 1h 30m', () {
      expect(p('Lab 3pm for 90m', QMode.event).dur, 90);
      expect(p('Lab 3pm 1h 30m', QMode.event).dur, 90);
    });

    test('spend: bare number is the amount, category from keywords', () {
      final q = p('Lunch 180', QMode.spend);
      expect(q.title, 'Lunch');
      expect(q.amount, 18000);
      expect(q.mcat, 'food');
    });

    test('spend: 1.2k yesterday, weekday means the last one', () {
      final q = p('Groceries 1.2k yesterday', QMode.spend);
      expect(q.amount, 120000);
      expect(q.due, '2026-11-19');
      expect(p('Uber 240 mon', QMode.spend).due, '2026-11-16');
      expect(p('Uber 240 mon', QMode.spend).mcat, 'travel');
    });

    test('income', () {
      final q = p('+5000 refund', QMode.spend);
      expect(q.amount, 500000);
      expect(q.income, isTrue);
    });
  });

  group('tasks', () {
    test('repeats', () {
      expect(nextDue('2026-11-20', 'daily'), '2026-11-21');
      expect(nextDue('2026-11-20', 'weekdays'), '2026-11-23'); // Fri → Mon
      expect(nextDue('2026-11-20', 'weekly'), '2026-11-27');
      expect(nextDue('2026-01-31', 'monthly'), '2026-02-28');
      expect(nextDue('2028-02-29', 'yearly'), '2029-02-28');
    });

    test('overdue', () {
      final t = Task(id: 'a', title: 'x', cat: 'A', due: '2026-11-19');
      expect(t.overdue(now), isTrue);
      t.due = '2026-11-20';
      expect(t.overdue(now), isFalse);
      t.time = 9 * 60;
      expect(t.overdue(now), isTrue);
    });

    test('due labels', () {
      expect(dueLabel('2026-11-20', now), 'Today');
      expect(dueLabel('2026-11-21', now), 'Tomorrow');
      expect(dueLabel('2026-11-24', now), 'Tue');
      expect(dueLabel('2027-03-02', now), 'Mar 2, 2027');
    });
  });

  group('money', () {
    test('formatting', () {
      expect(fmtMoney(123456700, '₹'), '₹12,34,567');
      expect(fmtMoney(123456750, r'$'), r'$1,234,567.50');
      expect(fmtMoney(18000, '₹'), '₹180');
      expect(fmtMoney(-5000, '₹'), '−₹50');
      expect(parseAmount('1,200'), 120000);
      expect(parseAmount('1.5k'), 150000);
      expect(parseAmount('₹ 99.5'), 9950);
      expect(parseAmount('abc'), isNull);
    });

    test('month numbers and the daily allowance', () {
      final m = Money(currency: '₹', budget: 3000000); // ₹30,000
      m.txns.addAll([
        Txn(id: '1', title: 'Lunch', cat: 'food', at: now - kHour, amount: 20000),
        Txn(id: '2', title: 'Metro', cat: 'travel', at: DateTime(2026, 11, 3).millisecondsSinceEpoch, amount: 980000),
        Txn(id: '3', title: 'Salary', cat: 'other', at: DateTime(2026, 11, 1).millisecondsSinceEpoch, amount: 5000000, income: true),
        Txn(id: '4', title: 'Old', cat: 'food', at: DateTime(2026, 10, 30).millisecondsSinceEpoch, amount: 99999),
      ]);
      final bill = Task(id: 'b', title: 'Wifi', cat: 'A', due: '2026-11-28', amount: 100000);
      final st = monthStats(m, [bill], now, now);
      expect(st.spent, 1000000);
      expect(st.income, 5000000);
      expect(st.today, 20000);
      expect(st.left, 2000000);
      expect(st.upcoming, 100000);
      expect(st.daysLeft, 11); // 20th..30th
      expect(st.perDay, (2000000 - 100000) ~/ 11);
      expect(st.byCat['food'], 20000);
    });

    test('budget falls back to the categories’ limits', () {
      final m = Money(currency: '₹');
      m.cats.first.budget = 500000;
      m.cats[1].budget = 200000;
      expect(m.monthBudget, 700000);
    });
  });

  test('tasks and money survive save → load', () {
    final d = data();
    d.tasks.add(Task(id: 't1', title: 'Pay rent', cat: 'D', due: '2026-12-01', time: 600, repeat: 'monthly', amount: 1500000, mcat: 'bills', star: true, subs: [SubTask(id: 's', title: 'Transfer', done: true)]));
    d.money.budget = 4000000;
    d.money.txns.add(Txn(id: 'x', title: 'Lunch', cat: 'food', at: now, amount: 18000, note: 'with Sam'));
    final back = normalize(jsonDecode(jsonEncode(d.toJson())) as Map<String, dynamic>);
    expect(jsonEncode(back.toJson()), jsonEncode(d.toJson()));
    final t = back.tasks.single;
    expect([t.title, t.due, t.time, t.repeat, t.amount, t.star, t.subs.single.done], ['Pay rent', '2026-12-01', 600, 'monthly', 1500000, true, true]);
  });

  test('an older backup without tasks or money still loads', () {
    final d = normalize({'lines': [], 'events': []});
    expect(d.tasks, isEmpty);
    expect(d.money.cats, isNotEmpty);
  });

  test('budget app backup import', () {
    final money = Money(currency: '₹');
    final text = jsonEncode({
      'version': 7,
      'data': {
        'categories': [
          {'id': 'c1', 'name': 'Food', 'emoji': '🍔', 'colorArgb': 0xFFFF0000, 'kind': 'EXPENSE'},
          {'id': 'c2', 'name': 'Coffee', 'emoji': '☕', 'colorArgb': 0xFF00AA00, 'kind': 'EXPENSE'},
        ],
        'transactions': [
          {'id': 'a', 'accountId': 'x', 'date': DateTime(2026, 11, 2).millisecondsSinceEpoch, 'amountCents': -25000, 'merchant': 'Dominos', 'categoryId': 'c1', 'type': 'EXPENSE', 'notes': ''},
          {'id': 'b', 'accountId': 'x', 'date': 20400, 'amountCents': 9000, 'merchant': 'Blue Tokai', 'categoryId': 'c2', 'type': 'EXPENSE', 'notes': 'latte'},
          {'id': 'c', 'accountId': 'x', 'date': DateTime(2026, 11, 1).millisecondsSinceEpoch, 'amountCents': 5000000, 'merchant': 'Salary', 'type': 'INCOME', 'notes': ''},
          {'id': 'd', 'accountId': 'x', 'date': DateTime(2026, 11, 1).millisecondsSinceEpoch, 'amountCents': 100, 'merchant': 'Move', 'type': 'TRANSFER', 'notes': ''},
        ],
      },
    });
    final r = readBudgetBackup(text, money)!;
    expect(r.txns.length, 3);
    expect(r.newCats.map((c) => c.name), ['Coffee']);
    expect(r.txns[0].cat, 'food');
    expect(r.txns[0].amount, 25000);
    expect(r.txns[1].cat, r.newCats.single.id);
    expect(r.txns[2].income, isTrue);
    expect(readBudgetBackup('{"events": []}', money), isNull);
  });
}
