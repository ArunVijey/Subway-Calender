// CSV import: reads a spreadsheet of transactions (Cashew, a bank statement,
// another money app, or this app's own export), guesses which column is
// which, and turns the rows into Money entries. Duplicates of entries already
// here are skipped, so importing the same file twice adds nothing.
import 'money.dart';
import 'util.dart';

/// Splits CSV text into rows of cells. Handles quotes, "" inside quotes,
/// CRLF, a byte-order mark, and picks the delimiter (, ; or tab).
List<List<String>> parseCsv(String text) {
  if (text.startsWith('﻿')) text = text.substring(1);
  final firstLine = text.split('\n').first;
  final delim = ['\t', ';', ','].reduce((a, b) => firstLine.split(a).length >= firstLine.split(b).length ? a : b);
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(ch);
      }
    } else if (ch == '"') {
      quoted = true;
    } else if (ch == delim) {
      row.add(cell.toString().trim());
      cell.clear();
    } else if (ch == '\n' || ch == '\r') {
      if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(cell.toString().trim());
      cell.clear();
      if (row.any((c) => c.isNotEmpty)) rows.add(row);
      row = <String>[];
    } else {
      cell.write(ch);
    }
  }
  row.add(cell.toString().trim());
  if (row.any((c) => c.isNotEmpty)) rows.add(row);
  return rows;
}

/// Which column holds what (-1 = none).
class CsvMap {
  int date = -1, time = -1, amount = -1, debit = -1, credit = -1, title = -1, note = -1, category = -1, account = -1, type = -1, tags = -1;

  static const fields = <String, String>{
    'date': 'Date',
    'time': 'Time',
    'amount': 'Amount',
    'debit': 'Money out (debit)',
    'credit': 'Money in (credit)',
    'title': 'Title / description',
    'note': 'Note',
    'category': 'Category',
    'account': 'Account',
    'type': 'Type / income',
    'tags': 'Tags',
  };

  int operator [](String f) => switch (f) {
        'date' => date,
        'time' => time,
        'amount' => amount,
        'debit' => debit,
        'credit' => credit,
        'title' => title,
        'note' => note,
        'category' => category,
        'account' => account,
        'type' => type,
        _ => tags,
      };

  void operator []=(String f, int i) {
    switch (f) {
      case 'date':
        date = i;
      case 'time':
        time = i;
      case 'amount':
        amount = i;
      case 'debit':
        debit = i;
      case 'credit':
        credit = i;
      case 'title':
        title = i;
      case 'note':
        note = i;
      case 'category':
        category = i;
      case 'account':
        account = i;
      case 'type':
        type = i;
      default:
        tags = i;
    }
  }

  bool get usable => date >= 0 && (amount >= 0 || debit >= 0 || credit >= 0);
}

/// Guesses the columns from the header names.
CsvMap guessMap(List<String> header) {
  final m = CsvMap();
  final h = [for (final x in header) x.toLowerCase().replaceAll(RegExp(r'[^a-z ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim()];
  int find(List<String> exact, [List<String> contains = const []]) {
    for (final e in exact) {
      final i = h.indexOf(e);
      if (i >= 0) return i;
    }
    for (final c in contains) {
      final i = h.indexWhere((x) => x.contains(c));
      if (i >= 0) return i;
    }
    return -1;
  }

  m.date = find(['date', 'transaction date', 'txn date', 'value date', 'posted date', 'booking date'], ['date']);
  m.time = find(['time', 'transaction time']);
  m.debit = find(['debit', 'withdrawal', 'withdrawal amt', 'withdrawals', 'dr', 'debit amount', 'money out', 'outflow', 'paid out']);
  m.credit = find(['credit', 'deposit', 'deposit amt', 'deposits', 'cr', 'credit amount', 'money in', 'inflow', 'paid in']);
  m.amount = find(['amount', 'amt', 'value', 'sum', 'transaction amount'], ['amount']);
  if (m.amount >= 0 && (m.amount == m.debit || m.amount == m.credit)) m.amount = -1;
  m.title = find(['title', 'description', 'merchant', 'payee', 'narration', 'particulars', 'name', 'details', 'transaction details'], ['description', 'narration']);
  m.note = find(['note', 'notes', 'memo', 'remarks', 'comment']);
  m.category = find(['category', 'category name', 'categories']);
  m.account = find(['account', 'account name', 'wallet']);
  m.type = find(['type', 'income', 'transaction type', 'kind']);
  m.tags = find(['tags', 'labels', 'tag']);
  return m;
}

const kDateFormats = ['auto', 'yyyy-MM-dd', 'dd/MM/yyyy', 'MM/dd/yyyy', 'dd-MM-yyyy', 'dd.MM.yyyy', 'd MMM yyyy'];

const _mon = {'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, 'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12};

/// Local ms for [s] in format [fmt] (one of [kDateFormats] other than auto), or null.
int? parseDate(String s, String fmt, {String time = ''}) {
  final t = s.trim();
  if (t.isEmpty) return null;
  int? y, mo, d, hh, mm;
  // A time inside the date cell ("2026-11-03 18:20:00", "03/11/2026 6:20 PM").
  final tm = RegExp(r'(\d{1,2}):(\d{2})(?::\d{2})?\s*([ap]\.?m\.?)?', caseSensitive: false).firstMatch('$t $time');
  if (tm != null) {
    hh = int.parse(tm[1]!);
    mm = int.parse(tm[2]!);
    final ap = tm[3]?.toLowerCase();
    if (ap != null && ap.startsWith('p') && hh < 12) hh += 12;
    if (ap != null && ap.startsWith('a') && hh == 12) hh = 0;
  }
  final datePart = t.split(RegExp(r'[ T]')).first;
  final nums = RegExp(r'\d+').allMatches(datePart).map((m) => int.parse(m[0]!)).toList();
  switch (fmt) {
    case 'yyyy-MM-dd':
      if (nums.length < 3 || nums[0] < 1000) return null;
      (y, mo, d) = (nums[0], nums[1], nums[2]);
    case 'dd/MM/yyyy' || 'dd-MM-yyyy' || 'dd.MM.yyyy':
      if (nums.length < 3) return null;
      (d, mo, y) = (nums[0], nums[1], nums[2]);
    case 'MM/dd/yyyy':
      if (nums.length < 3) return null;
      (mo, d, y) = (nums[0], nums[1], nums[2]);
    case 'd MMM yyyy':
      final m = RegExp(r'(\d{1,2})[\s\-/]*([a-z]{3})[a-z]*[\s\-/,]*(\d{2,4})', caseSensitive: false).firstMatch(t);
      if (m == null) return null;
      d = int.parse(m[1]!);
      mo = _mon[m[2]!.toLowerCase()];
      y = int.parse(m[3]!);
    default:
      return null;
  }
  if (y < 100) y += 2000;
  if (mo == null || mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  return DateTime(y, mo, d, hh ?? 12, mm ?? 0).millisecondsSinceEpoch;
}

/// The format that reads every non-empty date in [samples] (day-first wins a tie).
String detectDateFormat(List<String> samples) {
  final xs = samples.where((s) => s.trim().isNotEmpty).take(200).toList();
  for (final f in kDateFormats.skip(1)) {
    if (xs.isNotEmpty && xs.every((s) => parseDate(s, f) != null)) return f;
  }
  return 'dd/MM/yyyy';
}

/// "1,234.50", "(45.00)", "-₹200", "120 DR", "₹ 1.2k" → signed minor units.
int? parseSigned(String s) {
  var t = s.trim().toLowerCase();
  if (t.isEmpty) return null;
  var neg = false;
  if (t.startsWith('(') && t.endsWith(')')) {
    neg = true;
    t = t.substring(1, t.length - 1);
  }
  if (t.endsWith('dr')) {
    neg = true;
    t = t.substring(0, t.length - 2);
  } else if (t.endsWith('cr')) {
    t = t.substring(0, t.length - 2);
  }
  t = t.replaceAll(RegExp(r'[^0-9.\-k]'), '');
  if (t.startsWith('-')) {
    neg = !neg;
    t = t.substring(1);
  }
  final v = parseAmount(t);
  if (v == null) return null;
  return neg ? -v : v;
}

class CsvResult {
  final List<Txn> txns;
  final List<MCat> newCats;
  final int skipped, dupes;
  const CsvResult(this.txns, this.newCats, this.skipped, this.dupes);
}

/// Turns the rows (header excluded) into transactions.
/// [expensesPositive]: the file lists spending as positive numbers.
/// [acct]: the account for rows that don't name a known one.
/// [reviewed]: false puts them in To Review.
CsvResult buildCsvImport(
  List<List<String>> rows,
  CsvMap map,
  Money m, {
  required String dateFormat,
  bool expensesPositive = false,
  String acct = '',
  bool reviewed = false,
  bool createCats = true,
}) {
  String cell(List<String> r, int i) => i >= 0 && i < r.length ? r[i] : '';
  final fmt = dateFormat == 'auto' ? detectDateFormat([for (final r in rows) cell(r, map.date)]) : dateFormat;
  final newCats = <MCat>[];
  final out = <Txn>[];
  var skipped = 0, dupes = 0;
  // Entries already here, counted, so a re-import skips them but a file's own
  // repeated rows (two coffees on one day) all come in.
  final have = <String, int>{};
  for (final t in m.txns) {
    final k = '${dstr(t.at)}|${t.amount.abs()}|${t.title.trim().toLowerCase()}';
    have[k] = (have[k] ?? 0) + 1;
  }
  final seen = <String, int>{};
  final acctByName = {for (final a in m.accounts) a.name.toLowerCase(): a.id};
  var colorIx = 0;

  for (final r in rows) {
    final at = parseDate(cell(r, map.date), fmt, time: cell(r, map.time));
    int? v;
    if (map.debit >= 0 || map.credit >= 0) {
      final dr = parseSigned(cell(r, map.debit))?.abs() ?? 0, cr = parseSigned(cell(r, map.credit))?.abs() ?? 0;
      v = cr - dr;
      if (dr == 0 && cr == 0) v = map.amount >= 0 ? parseSigned(cell(r, map.amount)) : null;
    } else {
      v = parseSigned(cell(r, map.amount));
    }
    if (at == null || v == null || v == 0) {
      skipped++;
      continue;
    }
    final typeCell = cell(r, map.type).toLowerCase();
    final title = cell(r, map.title);
    // Which way the money went.
    String type;
    if (kTxnTypes.contains(typeCell)) {
      type = typeCell; // this app's own export
    } else if (typeCell == 'true' || typeCell.contains('income') || typeCell.contains('credit') || typeCell == 'cr') {
      type = 'income';
    } else if (typeCell.contains('transfer')) {
      type = 'transfer';
    } else if (typeCell == 'false' || typeCell.contains('expense') || typeCell.contains('debit') || typeCell == 'dr') {
      type = v > 0 && !expensesPositive ? 'refund' : 'spend';
    } else {
      final out = expensesPositive ? v > 0 : v < 0;
      type = out ? 'spend' : 'income';
    }
    final amount = v.abs();
    final key = '${dstr(at)}|$amount|${title.trim().toLowerCase()}';
    if ((have[key] ?? 0) > 0) {
      have[key] = have[key]! - 1;
      dupes++;
      continue;
    }
    final nth = seen[key] = (seen[key] ?? 0) + 1;
    final id = 'csv:${'$key#$nth'.hashCode.toUnsigned(32).toRadixString(36)}';

    // Category: by name, else a new one (if allowed), else by keyword.
    final income = type == 'income';
    final catName = cell(r, map.category).trim();
    String? cat;
    if (catName.isNotEmpty) {
      // By name, whichever kind it is (some apps use one category both ways).
      final same = [...m.cats, ...newCats].where((c) => c.name.toLowerCase() == catName.toLowerCase());
      cat = (same.where((c) => c.income == income).firstOrNull ?? same.firstOrNull)?.id;
      if (cat == null && createCats && type != 'transfer') {
        final c = MCat(
          id: 'c${uid()}${newCats.length}',
          name: clip(catName, 24),
          emoji: income ? '💰' : '•',
          color: kPaletteMoney[colorIx++ % kPaletteMoney.length],
          income: income,
        );
        newCats.add(c);
        cat = c.id;
      }
    }
    cat ??= income ? (matchMCat(m, title, income: true) ?? m.fallbackIncome) : (matchMCat(m, title) ?? m.fallbackCat);

    final named = acctByName[cell(r, map.account).trim().toLowerCase()];
    final adjusted = type == 'adjust' ? v : amount;
    out.add(Txn(
      id: id,
      title: clip(title, 80),
      cat: cat,
      note: cell(r, map.note),
      at: at,
      amount: adjusted,
      type: type == 'transfer' && v > 0 ? 'transfer' : type,
      acct: type == 'transfer' && v > 0 ? '' : (named ?? acct),
      to: type == 'transfer' && v > 0 ? (named ?? acct) : '',
      tags: [for (final g in cell(r, map.tags).split(RegExp(r'[,;\s]+'))) if (g.trim().isNotEmpty) g.trim().replaceFirst('#', '').toLowerCase()],
      review: !reviewed,
      src: 'csv',
    ));
  }
  return CsvResult(out, newCats, skipped, dupes);
}
