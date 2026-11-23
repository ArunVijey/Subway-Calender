// Optional check against a real Budget app backup. Run with
//   BUDGET_FILE=path/to/budget-backup.json flutter test test/real_budget_test.dart
// Prints counts and balances; skipped when the variable isn't set.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:subwayboard/core/budget_import.dart';
import 'package:subwayboard/core/ledger.dart';
import 'package:subwayboard/core/money.dart';
import 'package:subwayboard/core/util.dart';

void main() {
  final path = Platform.environment['BUDGET_FILE'];
  test('real budget backup imports cleanly', () {
    final text = File(path!).readAsStringSync();
    final raw = jsonDecode(text) as Map<String, dynamic>;
    final money = Money(currency: '₹');
    final r = readBudgetBackup(text, money)!;
    final byType = <String, int>{};
    for (final t in r.txns) {
      byType[t.type] = (byType[t.type] ?? 0) + 1;
    }
    final days = r.txns.map((t) => dstr(t.at)).toList()..sort();
    // ignore: avoid_print
    print('txns ${r.txns.length} $byType · accounts ${r.accounts.length} · new cats ${r.newCats.length} · '
        'months of limits ${r.history.length} · bills ${r.bills.length} · goals ${r.goals.length} · plans ${r.plans.length} · '
        'skipped ${r.skipped} · ${days.first} → ${days.last}');

    // Every row is accounted for: transfers are two rows each, merged into one.
    // (Some transfers have only one side, money to or from outside; those stay as they are.)
    final all = raw['transactions'] as List;
    final rows = all.length;
    final ids = {for (final t in all) t['id']};
    final pairs = all.where((t) => t['type'] == 'TRANSFER' && ids.contains(t['transferPairId']) && (t['amountCents'] as num) > 0).length;
    expect(r.txns.length + r.skipped, rows - pairs);
    expect(r.txns.every((t) => t.type == 'adjust' || t.amount > 0), isTrue);

    money
      ..accounts.addAll(r.accounts)
      ..cats.addAll(r.newCats)
      ..goals.addAll(r.goals)
      ..plans.addAll(r.plans)
      ..txns.addAll(r.txns);
    expect(r.txns.every((t) => money.cats.any((c) => c.id == t.cat)), isTrue);

    // Balances equal the Budget app's: opening balance plus the sum of the account's rows.
    final want = <String, int>{};
    for (final a in raw['accounts'] as List) {
      want['bud-a-${a['id']}'] = (a['openingBalanceCents'] as num).round();
    }
    for (final t in raw['transactions'] as List) {
      final k = 'bud-a-${t['accountId']}';
      if (want.containsKey(k)) want[k] = want[k]! + (t['amountCents'] as num).round();
    }
    final bal = balances(money);
    for (final a in money.accounts) {
      // ignore: avoid_print
      print('  ${a.name.padRight(14)} ${fmtMoney(bal[a.id]!, '₹').padLeft(14)}');
      expect(bal[a.id], want[a.id], reason: a.name);
    }
    // ignore: avoid_print
    print('  net worth ${fmtMoney(netWorth(money, bal), '₹')}');
  }, skip: path == null ? 'set BUDGET_FILE to run' : false);
}
