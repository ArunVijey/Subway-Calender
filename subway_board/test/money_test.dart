// Money: the Budget app import, account balances, goals and loans, rollover,
// trip/event budgets and the saved layout.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:subwayboard/core/budget_import.dart';
import 'package:subwayboard/core/ledger.dart';
import 'package:subwayboard/core/model.dart';
import 'package:subwayboard/core/money.dart';
import 'package:subwayboard/core/util.dart';

int epochDay(DateTime d) => (DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch / kDay).round();

void main() {
  final now = DateTime(2026, 11, 21, 15).millisecondsSinceEpoch;
  setUp(() => nowMs = () => now);

  String backup() => jsonEncode({
        'version': 2,
        'accounts': [
          {'id': 'bank', 'name': 'SBI', 'type': 'CHECKING', 'openingBalanceCents': 1000000, 'colorArgb': -13722021, 'sortOrder': 0},
          {'id': 'card', 'name': 'Slice', 'type': 'CREDIT', 'openingBalanceCents': 0, 'colorArgb': -2739318, 'sortOrder': 1},
        ],
        'categories': [
          {'id': 'food', 'name': 'Food', 'emoji': '🍽️', 'kind': 'EXPENSE', 'rollover': true},
          {'id': 'fix', 'name': 'Balance Correction', 'emoji': '⚖️', 'kind': 'EXPENSE', 'excludedFromBudget': true},
          {'id': 'chess', 'name': 'Chess', 'emoji': '♟️', 'kind': 'EXPENSE'},
          {'id': 'inc-salary', 'name': 'Salary', 'emoji': '💼', 'kind': 'INCOME'},
        ],
        'transactions': [
          {'id': 's1', 'accountId': 'card', 'date': epochDay(DateTime(2026, 11, 3)), 'timeMinutes': 600, 'amountCents': -25000, 'merchant': 'Dominos', 'categoryId': 'food', 'type': 'REGULAR', 'reviewed': true, 'tags': 'friends, weekend'},
          {'id': 's2', 'accountId': 'card', 'date': epochDay(DateTime(2026, 11, 4)), 'amountCents': 4000, 'merchant': 'Refund', 'categoryId': 'food', 'type': 'REGULAR', 'reviewed': false},
          {'id': 'i1', 'accountId': 'bank', 'date': epochDay(DateTime(2026, 11, 1)), 'amountCents': 5000000, 'merchant': 'Stipend', 'type': 'INCOME', 'reviewed': true},
          {'id': 't-out', 'accountId': 'bank', 'date': epochDay(DateTime(2026, 11, 10)), 'amountCents': -21000, 'merchant': 'Card bill', 'type': 'TRANSFER', 'transferPairId': 't-in', 'reviewed': true},
          {'id': 't-in', 'accountId': 'card', 'date': epochDay(DateTime(2026, 11, 10)), 'amountCents': 21000, 'merchant': 'Card bill', 'type': 'TRANSFER', 'transferPairId': 't-out', 'reviewed': true},
          {'id': 'adj', 'accountId': 'bank', 'date': epochDay(DateTime(2026, 11, 12)), 'amountCents': -900, 'merchant': 'Balance update', 'categoryId': 'fix', 'type': 'ADJUSTMENT', 'reviewed': true},
          {'id': 'old', 'accountId': 'card', 'date': epochDay(DateTime(2026, 10, 5)), 'amountCents': -100000, 'merchant': 'Groceries', 'categoryId': 'food', 'type': 'REGULAR', 'reviewed': true},
          {'id': 'lend', 'accountId': 'bank', 'date': epochDay(DateTime(2026, 11, 2)), 'amountCents': -50000, 'merchant': 'Sam', 'type': 'LENT', 'goalId': 'g-sam', 'reviewed': true},
          {'id': 'back', 'accountId': 'bank', 'date': epochDay(DateTime(2026, 11, 9)), 'amountCents': 20000, 'merchant': 'Sam', 'type': 'LENT', 'goalId': 'g-sam', 'reviewed': true},
        ],
        'budgets': [
          {'categoryId': 'food', 'monthIndex': 2026 * 12 + 9, 'amountCents': 200000},
          {'categoryId': 'food', 'monthIndex': 2026 * 12 + 10, 'amountCents': 150000},
        ],
        'recurrings': [
          {'id': 'emi', 'name': 'Ather EMI', 'amountCents': 972600, 'cadence': 'MONTHLY', 'anchorDate': epochDay(DateTime(2026, 8, 5)), 'categoryId': 'food', 'accountId': 'bank', 'isActive': true},
          {'id': 'yt', 'name': 'YouTube', 'amountCents': 5000, 'cadence': 'QUARTERLY', 'anchorDate': epochDay(DateTime(2026, 9, 1)), 'isActive': true},
        ],
        'goals': [
          {'id': 'g-sam', 'name': 'Sam', 'kind': 'LENT', 'targetCents': 0, 'startDate': epochDay(DateTime(2026, 11, 2)), 'offsetCents': 0, 'isArchived': false},
          {'id': 'g-trip', 'name': 'Goa', 'kind': 'SAVE', 'targetCents': 3000000, 'startDate': epochDay(DateTime(2026, 9, 1)), 'endDate': epochDay(DateTime(2027, 3, 1)), 'offsetCents': 500000},
        ],
        'customBudgets': [
          {'id': 'cb', 'name': 'Diwali', 'amountCents': 800000, 'period': 'CUSTOM', 'startDate': epochDay(DateTime(2026, 11, 1)), 'endDate': epochDay(DateTime(2026, 11, 7)), 'mode': 'ALL', 'categoryIds': 'food', 'pinned': true},
        ],
        'nameRules': [
          {'merchantKey': 'dominos', 'categoryId': 'food', 'type': 'REGULAR'},
        ],
      });

  group('Budget app import', () {
    test('reads every kind of row', () {
      final m = Money(currency: '₹');
      final r = readBudgetBackup(backup(), m)!;
      expect(r.accounts.map((a) => a.name), ['SBI', 'Slice']);
      expect(r.accounts[1].type, 'credit');
      // The transfer's two rows become one; nothing else is dropped.
      expect(r.txns.length, 8);
      final byId = {for (final t in r.txns) t.id: t};
      expect(byId['bud:s1']!.type, 'spend');
      expect(byId['bud:s1']!.cat, 'food');
      expect(byId['bud:s1']!.tags, ['friends', 'weekend']);
      expect(DateTime.fromMillisecondsSinceEpoch(byId['bud:s1']!.at).hour, 10);
      expect(byId['bud:s2']!.type, 'refund');
      expect(byId['bud:s2']!.review, isTrue);
      expect(byId['bud:i1']!.type, 'income');
      expect(byId['bud:i1']!.cat, 'inc-salary');
      final tr = byId['bud:t-out']!;
      expect(tr.type, 'transfer');
      expect([tr.acct, tr.to], ['bud-a-bank', 'bud-a-card']);
      expect(byId.containsKey('bud:t-in'), isFalse);
      expect(byId['bud:adj']!.amount, -900);
      expect(byId['bud:lend']!.type, 'lent');
      expect(byId['bud:back']!.type, 'repay');
      // Categories: Food matched, the rest new (with their flags).
      expect(r.newCats.map((c) => c.name), containsAll(['Balance Correction', 'Chess']));
      expect(r.newCats.firstWhere((c) => c.name == 'Balance Correction').excluded, isTrue);
      expect(r.catFlags['food'], (true, false));
      // Two months of limits, the latest as the standing one.
      expect(r.history.keys, containsAll(['2026-10', '2026-11']));
      expect(r.limits['food'], 150000);
      // Recurring payments → repeating bills, next due date in the future.
      expect(r.bills.map((b) => b.title), ['Ather EMI', 'YouTube']);
      expect(r.bills[0].due, '2026-12-05');
      expect(r.bills[0].acct, 'bud-a-bank');
      expect(r.bills[1].repeat, 'quarterly');
      expect(r.bills[1].due, '2026-12-01');
      expect(r.goals.map((g) => g.kind), ['lent', 'save']);
      expect(r.plans.single.mode, 'all');
      expect(r.plans.single.cats, ['food']);
      expect(r.keywords['food'], ['dominos']);
    });

    test('balances match the Budget app (opening + every row)', () {
      final m = Money(currency: '₹');
      final r = readBudgetBackup(backup(), m)!;
      m.accounts.addAll(r.accounts);
      m.cats.addAll(r.newCats);
      m.goals.addAll(r.goals);
      m.txns.addAll(r.txns);
      final bal = balances(m);
      // Bank: 10,000 + 50,000 − 210 − 9 − 500 + 200
      expect(bal['bud-a-bank'], 1000000 + 5000000 - 21000 - 900 - 50000 + 20000);
      // Card: −250 + 40 + 210 − 1,000
      expect(bal['bud-a-card'], -25000 + 4000 + 21000 - 100000);
      // Sam still owes 300; Goa has the 5,000 that was already saved (not new money).
      expect(goalAmount(m, m.goalOf('bud-g-g-sam')!), 30000);
      expect(netWorth(m, bal), bal['bud-a-bank']! + bal['bud-a-card']! + 30000);
    });

    test('importing again refreshes instead of doubling', () {
      final d = AppData();
      final m = d.money;
      BudgetImport read() => readBudgetBackup(backup(), m)!;
      void apply(BudgetImport r) {
        m.txns
          ..removeWhere((t) => t.src == kBudgetSrc)
          ..addAll(r.txns);
      }

      apply(read());
      m.txns.add(Txn(id: 'mine', title: 'Chai', cat: 'food', at: now, amount: 2000));
      apply(read());
      expect(m.txns.where((t) => t.src == kBudgetSrc).length, 8);
      expect(m.txns.where((t) => t.id == 'mine').length, 1);
    });

    test('not a backup', () {
      expect(readBudgetBackup('{"events": []}', Money()), isNull);
      expect(readBudgetBackup('nope', Money()), isNull);
    });
  });

  group('month numbers', () {
    test('refunds come off, excluded categories and moves stay out', () {
      final m = Money(currency: '₹');
      final r = readBudgetBackup(backup(), m)!;
      m.accounts.addAll(r.accounts);
      m.cats.addAll(r.newCats);
      m.goals.addAll(r.goals);
      m.txns.addAll(r.txns);
      m.limits.addAll(r.history);
      m.cats.firstWhere((c) => c.id == 'food').rollover = true;
      final st = monthStats(m, const [], monthStart(now), now);
      expect(st.spent, 25000 - 4000);
      expect(st.byCat['food'], 21000);
      expect(st.income, 5000000);
      // Food: 1,500 this month + (2,000 − 1,000) left over from October.
      expect(st.limit['food'], 150000 + 100000);
    });

    test('limits carry forward from the month they were set (like the Budget app)', () {
      final m = Money(currency: '₹');
      m.cats.firstWhere((c) => c.id == 'travel').budget = 50000;
      m.limits['2026-10'] = {'food': 200000, 'fun': 150000};
      m.limits['2026-11'] = {'food': 300000};
      final food = m.cats.firstWhere((c) => c.id == 'food'), fun = m.cats.firstWhere((c) => c.id == 'fun'), travel = m.cats.firstWhere((c) => c.id == 'travel');
      final nov = monthStart(now);
      expect(m.limitIn(food, nov), 300000);
      expect(m.limitIn(fun, nov), 150000); // set in October, still on
      expect(m.limitIn(fun, addMonths(nov, 2)), 150000);
      expect(m.limitIn(food, addMonths(nov, -1)), 200000);
      expect(m.limitIn(fun, addMonths(nov, -2)), 0); // before it was set
      expect(m.limitIn(travel, nov), 50000); // never in a saved month
    });

    test('left today is worked out from the morning', () {
      final m = Money(currency: '₹', budget: 1000000);
      m.txns.add(Txn(id: 'a', title: 'Earlier', cat: 'food', at: DateTime(2026, 11, 5).millisecondsSinceEpoch, amount: 100000));
      m.txns.add(Txn(id: 'b', title: 'Lunch', cat: 'food', at: DateTime(2026, 11, 21, 13).millisecondsSinceEpoch, amount: 20000));
      final st = monthStats(m, const [], monthStart(now), now);
      expect(st.daysLeft, 10);
      expect(st.todayAllowance, (1000000 - 100000) ~/ 10);
      expect(st.leftToday, 90000 - 20000);
    });
  });

  group('plans', () {
    test('one-off window and spends counted', () {
      final m = Money(currency: '₹');
      final p = Plan(id: 'p', name: 'Goa', color: '#ff5a1f', amount: 1000000, start: DateTime(2026, 11, 18).millisecondsSinceEpoch, end: DateTime(2026, 11, 24).millisecondsSinceEpoch);
      m.plans.add(p);
      m.txns.addAll([
        Txn(id: 'a', title: 'Shack', cat: 'food', at: now, amount: 30000, plan: 'p'),
        Txn(id: 'b', title: 'Lunch', cat: 'food', at: now, amount: 10000),
      ]);
      final (from, to) = planWindow(p, now);
      expect(dstr(from), '2026-11-18');
      expect(dstr(to), '2026-11-25');
      expect(planSpent(m, p, now), 30000);
      expect(planState(p, now), 'live');
      p.mode = 'all';
      expect(planSpent(m, p, now), 40000);
      p.cats = ['travel'];
      expect(planSpent(m, p, now), 0);
    });

    test('repeating windows roll forward', () {
      final weekly = Plan(id: 'w', name: 'Week', color: '#000000', period: 'weekly', start: DateTime(2026, 11, 2).millisecondsSinceEpoch);
      expect(dstr(planWindow(weekly, now).$1), '2026-11-16');
      final monthly = Plan(id: 'm', name: 'Month', color: '#000000', period: 'monthly', start: DateTime(2026, 1, 25).millisecondsSinceEpoch);
      final (a, b) = planWindow(monthly, now);
      expect([dstr(a), dstr(b)], ['2026-10-25', '2026-11-25']);
    });
  });

  test('goals: per month to reach the target', () {
    final m = Money(currency: '₹');
    final g = Goal(id: 'g', name: 'Laptop', color: '#8b5cf6', target: 600000, end: DateTime(2027, 4, 21).millisecondsSinceEpoch);
    m.goals.add(g);
    m.txns.add(Txn(id: 'a', title: '', cat: 'other', at: now, amount: 100000, type: 'save', goal: 'g'));
    expect(goalAmount(m, g), 100000);
    expect(perMonthToGoal(m, g, now), 100000); // 5,000 left over 5 months
  });

  test('cash flow buckets months', () {
    final m = Money(currency: '₹');
    m.txns.addAll([
      Txn(id: 'a', title: 'Pay', cat: 'inc-salary', at: DateTime(2026, 10, 1, 10).millisecondsSinceEpoch, amount: 500000, income: true),
      Txn(id: 'b', title: 'Rent', cat: 'bills', at: DateTime(2026, 10, 2, 10).millisecondsSinceEpoch, amount: 200000),
      Txn(id: 'c', title: 'Lunch', cat: 'food', at: DateTime(2026, 11, 2, 10).millisecondsSinceEpoch, amount: 30000),
    ]);
    final f = cashflow(m, monthStart(now), 2);
    expect([f[0].income, f[0].spent, f[1].income, f[1].spent], [500000, 200000, 0, 30000]);
  });

  test('everything survives save → load, sections included', () {
    final d = AppData();
    final m = d.money;
    m.accounts.add(Account(id: 'a', name: 'HDFC', color: '#1d6cf2', type: 'credit', opening: -5000));
    m.goals.add(Goal(id: 'g', name: 'Sam', color: '#ff8a00', kind: 'lent', longTerm: true));
    m.plans.add(Plan(id: 'p', name: 'Goa', color: '#ff5a1f', amount: 9000, start: now, cats: ['food'], mode: 'all'));
    m.limits['2026-10'] = {'food': 200000};
    m.defaultAcct = 'a';
    m.sections
      ..removeWhere((s) => s.id == 'moons')
      ..insert(0, MoneySection('moons', false));
    m.txns.add(Txn(id: 't', title: 'Card bill', cat: 'bills', at: now, amount: 5000, type: 'transfer', acct: 'a', tags: ['x'], review: true, excluded: true, plan: 'p'));
    final back = normalize(jsonDecode(jsonEncode(d.toJson())) as Map<String, dynamic>).money;
    expect(back.accounts.single.opening, -5000);
    expect(back.goals.single.longTerm, isTrue);
    expect(back.plans.single.cats, ['food']);
    expect(back.limits['2026-10'], {'food': 200000});
    expect(back.defaultAcct, 'a');
    expect(back.sections.first.id, 'moons');
    expect(back.sections.first.on, isFalse);
    expect(back.sections.length, kMoneySections.length);
    final t = back.txns.single;
    expect([t.type, t.acct, t.tags, t.review, t.excluded, t.plan], ['transfer', 'a', ['x'], true, true, 'p']);
  });

  test('older saves gain income categories and every section', () {
    final m = moneyFromJson({
      'currency': '₹',
      'cats': [
        {'id': 'food', 'name': 'Food', 'emoji': '🍜', 'color': '#ff8a00'},
        {'id': 'other', 'name': 'Other', 'emoji': '•', 'color': '#71717a'},
      ],
      'txns': [
        {'id': 'x', 'title': 'Stipend', 'cat': 'other', 'at': now, 'amount': 100, 'income': true},
      ],
    });
    expect(m.incomeCats, isNotEmpty);
    expect(m.fallbackCat, 'other');
    expect(m.txns.single.income, isTrue);
    expect(m.sections.map((s) => s.id), kMoneySections.keys);
  });
}
