// CSV import: parsing, column guessing, date formats, signs and duplicates.
// Set CASHEW_FILE to also check a real Cashew export.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:subwayboard/core/csv_import.dart';
import 'package:subwayboard/core/money.dart';
import 'package:subwayboard/core/util.dart';

void main() {
  test('quotes, commas inside quotes, CRLF and a BOM', () {
    final rows = parseCsv('﻿date,title,amount\r\n2026-11-03,"Dinner, with ""Sam""",-450\r\n\r\n2026-11-04,Metro,-40');
    expect(rows.length, 3);
    expect(rows[1][1], 'Dinner, with "Sam"');
    expect(rows[2], ['2026-11-04', 'Metro', '-40']);
  });

  test('semicolons and tabs are detected', () {
    expect(parseCsv('a;b;c\n1;2;3')[1], ['1', '2', '3']);
    expect(parseCsv('a\tb\n1\t2')[1], ['1', '2']);
  });

  test('bank statement: debit / credit columns, day-first dates', () {
    final rows = parseCsv('Txn Date,Narration,Withdrawal Amt,Deposit Amt,Closing Balance\n'
        '03/11/2026,UPI-SWIGGY,450.00,,10000\n'
        '15/11/2026,SALARY NOV,,"50,000.00",60000\n'
        '16/11/2026,ATM,"1,000.00",,59000');
    final map = guessMap(rows.first);
    expect([map.date, map.title, map.debit, map.credit, map.amount], [0, 1, 2, 3, -1]);
    final r = buildCsvImport(rows.skip(1).toList(), map, Money(currency: '₹'), dateFormat: 'auto', reviewed: true);
    expect(r.txns.length, 3);
    expect(dstr(r.txns[0].at), '2026-11-03');
    expect([r.txns[0].type, r.txns[0].amount], ['spend', 45000]);
    expect([r.txns[1].type, r.txns[1].amount], ['income', 5000000]);
    expect(r.txns[2].amount, 100000);
    expect(r.txns.every((t) => !t.review && t.src == 'csv'), isTrue);
  });

  test('positive spending, month-first dates, categories created once', () {
    final rows = parseCsv('Date,Payee,Amount,Category\n11/03/2026,Starbucks,5.50,Coffee\n11/20/2026,Blue Tokai,4.00,Coffee');
    final m = Money(currency: r'$');
    final r = buildCsvImport(rows.skip(1).toList(), guessMap(rows.first), m, dateFormat: 'MM/dd/yyyy', expensesPositive: true);
    expect(r.txns.map((t) => t.type), ['spend', 'spend']);
    expect(dstr(r.txns[1].at), '2026-11-20');
    expect(r.newCats.single.name, 'Coffee');
    expect(r.txns.every((t) => t.cat == r.newCats.single.id), isTrue);
    expect(r.txns.every((t) => t.review), isTrue);
  });

  test('duplicates of existing entries are skipped', () {
    final rows = parseCsv('date,title,amount\n2026-11-03,Lunch,-180');
    final m = Money(currency: '₹');
    m.txns.add(Txn(id: 'x', title: 'Lunch', cat: 'food', at: DateTime(2026, 11, 3, 13).millisecondsSinceEpoch, amount: 18000));
    final r = buildCsvImport(rows.skip(1).toList(), guessMap(rows.first), m, dateFormat: 'auto');
    expect(r.txns, isEmpty);
    expect(r.dupes, 1);
  });

  test('amount formats', () {
    expect(parseSigned('(45.00)'), -4500);
    expect(parseSigned('-₹1,200.50'), -120050);
    expect(parseSigned('120 DR'), -12000);
    expect(parseSigned('120 CR'), 12000);
    expect(parseSigned(''), isNull);
  });

  test('date formats', () {
    expect(dstr(parseDate('2026-11-03 18:20:00.000', 'yyyy-MM-dd')!), '2026-11-03');
    expect(DateTime.fromMillisecondsSinceEpoch(parseDate('03/11/2026 6:20 PM', 'dd/MM/yyyy')!).hour, 18);
    expect(dstr(parseDate('3 Nov 2026', 'd MMM yyyy')!), '2026-11-03');
    expect(dstr(parseDate('03-Nov-26', 'd MMM yyyy')!), '2026-11-03');
    expect(detectDateFormat(['13/11/2026', '01/02/2026']), 'dd/MM/yyyy');
    expect(detectDateFormat(['11/13/2026']), 'MM/dd/yyyy');
  });

  final cashew = Platform.environment['CASHEW_FILE'];
  test('real Cashew export', () {
    final rows = parseCsv(File(cashew!).readAsStringSync());
    final map = guessMap(rows.first);
    final r = buildCsvImport(rows.skip(1).toList(), map, Money(currency: '₹'), dateFormat: 'auto');
    final byType = <String, int>{};
    for (final t in r.txns) {
      byType[t.type] = (byType[t.type] ?? 0) + 1;
    }
    // ignore: avoid_print
    print('rows ${rows.length - 1} → ${r.txns.length} $byType · skipped ${r.skipped} · dupes ${r.dupes} · new cats ${r.newCats.map((c) => c.name).join(', ')}');
    expect(r.txns.length, greaterThan(1000));
  }, skip: cashew == null ? 'set CASHEW_FILE to run' : false);
}
