// Reads a backup file from the Budget app (com.budget.app, Settings → Back Up
// Now there) and turns everything in it into Money data: accounts,
// categories (with rollover / excluded flags), every transaction type,
// each month's limits, recurring payments (as bills), goals, loans and custom
// budgets. The Budget app itself is never touched; this only reads its file.
//
// Importing again refreshes: rows from an earlier import are replaced, while
// anything typed into this app stays.
import 'dart:convert';

import 'money.dart';
import 'tasks.dart';
import 'util.dart';

class BudgetImport {
  final List<Txn> txns;
  final List<Account> accounts;
  final List<MCat> newCats;

  /// Flags from the Budget app for categories that already existed here: id → (rollover, excluded).
  final Map<String, (bool, bool)> catFlags;

  /// Extra keywords for categories (from the Budget app's merchant rules): id → words.
  final Map<String, List<String>> keywords;

  /// Every month's category limits: 'YYYY-MM' → our category id → minor units.
  final Map<String, Map<String, int>> history;

  /// Limits from the latest month that had any: our category id → minor units.
  final Map<String, int> limits;

  /// Active recurring payments, as repeating bill tasks.
  final List<Task> bills;
  final List<Goal> goals;
  final List<Plan> plans;

  /// Transactions the file had that couldn't be read.
  final int skipped;

  const BudgetImport({
    required this.txns,
    this.accounts = const [],
    this.newCats = const [],
    this.catFlags = const {},
    this.keywords = const {},
    this.history = const {},
    this.limits = const {},
    this.bills = const [],
    this.goals = const [],
    this.plans = const [],
    this.skipped = 0,
  });

  int get transfers => txns.where((t) => t.type == 'transfer').length;
}

const kBudgetSrc = 'budget-app';

/// Null when [text] doesn't look like a Budget app backup. [existingTasks] and
/// [lineId] are for the recurring payments (skipped if already imported).
BudgetImport? readBudgetBackup(String text, Money into, {Set<String> existingTasks = const {}, String lineId = 'D'}) {
  dynamic root;
  try {
    root = jsonDecode(text);
  } catch (_) {
    return null;
  }
  final txRows = _findList(root, const ['transactions', 'txns', 'transaction']);
  if (txRows == null) return null;

  // ---- accounts
  final acctMap = <String, String>{};
  final accounts = <Account>[];
  final acctRows = [for (final a in _findList(root, const ['accounts']) ?? const []) if (a is Map) a]
    ..sort((a, b) => (_num(a['sortOrder']) ?? 0).compareTo(_num(b['sortOrder']) ?? 0));
  for (final a in acctRows) {
    final id = a['id']?.toString();
    if (id == null) continue;
    final ours = 'bud-a-$id';
    acctMap[id] = ours;
    accounts.add(Account(
      id: ours,
      name: clip((a['name'] ?? 'Account').toString().trim(), 28),
      type: switch (a['type']?.toString().toUpperCase()) {
        'CHECKING' => 'checking',
        'SAVINGS' => 'savings',
        'CREDIT' => 'credit',
        'CASH' => 'cash',
        'INVESTMENT' => 'investment',
        'LOAN' => 'loan',
        'PROPERTY' => 'property',
        _ => 'other',
      },
      color: _argbHex(a['colorArgb']) ?? '#1d6cf2',
      opening: _num(a['openingBalanceCents'])?.round() ?? 0,
      archived: _truthy(a['isArchived']),
      created: _num(a['createdAt'])?.round(),
    ));
  }

  // ---- categories: theirs → ours (matched by name, else a new one)
  final map = <String, String>{};
  final newCats = <MCat>[];
  final flags = <String, (bool, bool)>{};
  final catRows = [for (final c in _findList(root, const ['categories', 'category']) ?? const []) if (c is Map) c]
    ..sort((a, b) => (_num(a['sortOrder']) ?? 0).compareTo(_num(b['sortOrder']) ?? 0));
  for (final c in catRows) {
    final id = c['id']?.toString();
    final name = c['name']?.toString().trim() ?? '';
    if (id == null || name.isEmpty) continue;
    final income = c['kind']?.toString().toUpperCase() == 'INCOME';
    final rollover = _truthy(c['rollover']), excluded = _truthy(c['excludedFromBudget']);
    final same = [...into.cats, ...newCats].where((x) => x.name.toLowerCase() == name.toLowerCase() && x.income == income).firstOrNull;
    if (same != null) {
      map[id] = same.id;
      if (into.cats.contains(same)) flags[same.id] = (rollover, excluded);
      continue;
    }
    final mc = MCat(
      id: 'b${id.hashCode.toUnsigned(32).toRadixString(36)}',
      name: clip(name, 24),
      emoji: (c['emoji']?.toString().trim().isNotEmpty ?? false) ? c['emoji'].toString().trim() : '•',
      color: _argbHex(c['colorArgb']) ?? '#71717a',
      income: income,
      rollover: rollover,
      excluded: excluded,
      archived: _truthy(c['isArchived']),
    );
    newCats.add(mc);
    map[id] = mc.id;
  }
  final allCats = Money(cats: [...into.cats, ...newCats]);

  // ---- goals and loans
  final goalMap = <String, String>{};
  final goalKind = <String, String>{};
  final goals = <Goal>[];
  for (final g in _findList(root, const ['goals']) ?? const []) {
    if (g is! Map || g['id'] == null) continue;
    final id = g['id'].toString();
    final kind = switch (g['kind']?.toString().toUpperCase()) { 'LENT' => 'lent', 'BORROWED' => 'borrowed', _ => 'save' };
    final start = _when(g['startDate']), end = _when(g['endDate']);
    final ours = 'bud-g-$id';
    goalMap[id] = ours;
    goalKind[ours] = kind;
    goals.add(Goal(
      id: ours,
      name: clip((g['name'] ?? 'Goal').toString().trim(), 32),
      emoji: (g['emoji']?.toString().trim().isNotEmpty ?? false) ? g['emoji'].toString().trim() : (kind == 'save' ? '🎯' : '🤝'),
      color: _argbHex(g['colorArgb']) ?? '#22c55e',
      kind: kind,
      target: _num(g['targetCents'])?.round().abs() ?? 0,
      offset: _num(g['offsetCents'])?.round() ?? 0,
      start: start,
      end: end ?? 0,
      longTerm: kind != 'save' && end != null && start != null && end - start > 365 * kDay,
      archived: _truthy(g['isArchived']),
    ));
  }

  // ---- custom budgets
  final planMap = <String, String>{};
  final plans = <Plan>[];
  for (final p in _findList(root, const ['customBudgets', 'custombudgets']) ?? const []) {
    if (p is! Map || p['id'] == null) continue;
    final start = _when(p['startDate']);
    if (start == null) continue;
    final ours = 'bud-p-${p['id']}';
    planMap[p['id'].toString()] = ours;
    plans.add(Plan(
      id: ours,
      name: clip((p['name'] ?? 'Budget').toString().trim(), 32),
      emoji: (p['emoji']?.toString().trim().isNotEmpty ?? false) ? p['emoji'].toString().trim() : '🧳',
      color: _argbHex(p['colorArgb']) ?? '#1d6cf2',
      period: switch (p['period']?.toString().toUpperCase()) { 'WEEKLY' => 'weekly', 'MONTHLY' => 'monthly', 'YEARLY' => 'yearly', 'DAILY' => 'daily', _ => 'custom' },
      mode: p['mode']?.toString().toUpperCase() == 'ALL' ? 'all' : 'added',
      amount: _num(p['amountCents'])?.round().abs() ?? 0,
      start: start,
      end: _when(p['endDate']) ?? 0,
      cats: [for (final c in _ids(p['categoryIds'])) ?map[c]],
      accts: [for (final a in _ids(p['accountIds'])) ?acctMap[a]],
      pinned: _truthy(p['pinned']),
      archived: _truthy(p['isArchived']),
    ));
  }

  // ---- transactions
  final rows = [for (final r in txRows) if (r is Map) r];
  final byId = {for (final r in rows) if (r['id'] != null) r['id'].toString(): r};
  final out = <Txn>[];
  var skipped = 0;
  for (final r in rows) {
    final type = r['type']?.toString().toUpperCase() ?? 'REGULAR';
    final cents = _num(r['amountCents'])?.round() ?? (_num(r['amount']) == null ? null : (_num(r['amount'])! * 100).round());
    final at = _when(r['date'] ?? r['at'] ?? r['timestamp'], minutes: _num(r['timeMinutes'])?.toInt());
    if (cents == null || at == null || cents == 0) {
      skipped++;
      continue;
    }
    final rid = r['id']?.toString() ?? '${at}_$cents';
    final title = (r['merchant'] ?? r['title'] ?? r['name'] ?? '').toString().trim();
    final acct = acctMap[r['accountId']?.toString()] ?? '';
    final goal = goalMap[r['goalId']?.toString()] ?? '';
    final kind = goalKind[goal];

    String? to;
    String from = acct;
    String t;
    if (type == 'TRANSFER') {
      // Two rows, one per account, each pointing at the other. Keep the outgoing one.
      final pairId = r['transferPairId']?.toString();
      final pair = pairId == null ? null : byId[pairId];
      if (pair != null && cents > 0) continue;
      t = 'transfer';
      if (cents < 0) {
        to = pair == null ? '' : (acctMap[pair['accountId']?.toString()] ?? '');
      } else {
        from = '';
        to = acct;
      }
      // Neither side is an account we know: nothing to show for it.
      if (from.isEmpty && to.isEmpty) {
        skipped++;
        continue;
      }
    } else if (type == 'ADJUSTMENT') {
      t = 'adjust';
    } else if (type == 'LENT') {
      t = cents < 0 ? 'lent' : 'repay';
    } else if (type == 'BORROWED') {
      t = cents > 0 ? 'borrowed' : 'repay';
    } else if (kind == 'lent') {
      t = cents < 0 ? 'lent' : 'repay';
    } else if (kind == 'borrowed') {
      t = cents > 0 ? 'borrowed' : 'repay';
    } else if (kind == 'save') {
      t = cents < 0 ? 'save' : 'unsave';
    } else if (type == 'INCOME') {
      t = 'income';
    } else {
      // Spending is negative; a positive regular row is money back (a refund).
      t = cents < 0 ? 'spend' : 'refund';
    }

    final theirCat = r['categoryId']?.toString();
    final cat = map[theirCat] ??
        (t == 'income'
            ? (matchMCat(allCats, title, income: true) ?? allCats.fallbackIncome)
            : (matchMCat(allCats, title) ?? allCats.fallbackCat));
    out.add(Txn(
      id: 'bud:$rid',
      title: title,
      cat: cat,
      note: (r['notes'] ?? r['note'] ?? '').toString().trim(),
      at: at,
      amount: t == 'adjust' ? cents : cents.abs(),
      type: t,
      acct: from,
      to: to ?? '',
      tags: _tags(r['tags']),
      review: r['reviewed'] == false || r['reviewed'] == 0,
      excluded: _truthy(r['excluded']),
      goal: goal,
      plan: planMap[r['budgetId']?.toString()] ?? '',
      src: kBudgetSrc,
    ));
  }

  // ---- monthly limits (monthIndex = year × 12 + month, January = 0)
  final history = <String, Map<String, int>>{};
  for (final b in _findList(root, const ['budgets']) ?? const []) {
    if (b is! Map) continue;
    final mi = _num(b['monthIndex'])?.toInt();
    final ours = map[b['categoryId']?.toString()];
    final amt = _num(b['amountCents'])?.round().abs() ?? 0;
    if (mi == null || ours == null || amt <= 0) continue;
    final key = '${mi ~/ 12}-${pad(mi % 12 + 1)}';
    final m = history.putIfAbsent(key, () => {});
    m[ours] = (m[ours] ?? 0) + amt;
  }
  final latest = (history.keys.toList()..sort()).lastOrNull;
  final limits = latest == null ? <String, int>{} : Map.of(history[latest]!);

  // ---- merchant rules → keywords
  final keywords = <String, List<String>>{};
  for (final n in _findList(root, const ['nameRules', 'namerules']) ?? const []) {
    if (n is! Map) continue;
    final ours = map[n['categoryId']?.toString()];
    final word = n['merchantKey']?.toString().trim().toLowerCase() ?? '';
    if (ours != null && word.isNotEmpty) keywords.putIfAbsent(ours, () => []).add(word);
  }

  // ---- recurring payments → bills that repeat, due on their next date
  final bills = <Task>[];
  final today = dstr(sod(nowMs()));
  for (final r in _findList(root, const ['recurrings']) ?? const []) {
    if (r is! Map || r['isActive'] == false) continue;
    final id = 'bud-rec-${r['id']}';
    if (existingTasks.contains(id)) continue;
    final repeat = switch (r['cadence']?.toString().toUpperCase()) {
      'DAILY' => 'daily',
      'WEEKLY' => 'weekly',
      'BIWEEKLY' => 'biweekly',
      'QUARTERLY' => 'quarterly',
      'YEARLY' || 'ANNUALLY' => 'yearly',
      _ => 'monthly',
    };
    final anchor = _when(r['anchorDate']);
    final amt = _num(r['amountCents'])?.round().abs() ?? 0;
    final name = r['name']?.toString().trim() ?? '';
    if (anchor == null || amt == 0 || name.isEmpty) continue;
    var due = dstr(anchor);
    while (due.compareTo(today) < 0) {
      due = nextDue(due, repeat);
    }
    bills.add(Task(
      id: id,
      title: name,
      cat: lineId,
      due: due,
      repeat: repeat,
      amount: amt,
      mcat: map[r['categoryId']?.toString()] ?? '',
      acct: acctMap[r['accountId']?.toString()] ?? '',
    ));
  }

  return BudgetImport(
    txns: out,
    accounts: accounts,
    newCats: newCats,
    catFlags: flags,
    keywords: keywords,
    history: history,
    limits: limits,
    bills: bills,
    goals: goals,
    plans: plans,
    skipped: skipped,
  );
}

List? _findList(dynamic v, List<String> keys, [int depth = 0]) {
  if (depth > 4) return null;
  final want = keys.map((k) => k.toLowerCase()).toSet();
  if (v is Map) {
    for (final k in v.keys) {
      if (want.contains(k.toString().toLowerCase()) && v[k] is List) return v[k] as List;
    }
    for (final x in v.values) {
      final r = _findList(x, keys, depth + 1);
      if (r != null) return r;
    }
  }
  return null;
}

num? _num(dynamic v) => v is num ? v : (v is String ? num.tryParse(v) : null);
bool _truthy(dynamic v) => v == true || v == 1 || v == 'true';

/// "a,b" / "a b" / ["a","b"] → ids.
List<String> _ids(dynamic v) => v is List
    ? [for (final x in v) if (x != null && x.toString().isNotEmpty) x.toString()]
    : v is String
        ? v.split(RegExp(r'[,;|]')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList()
        : const [];

List<String> _tags(dynamic v) => {for (final t in _ids(v)) t.replaceFirst(RegExp('^#'), '').toLowerCase()}.toList();

/// Epoch day (plus [minutes] into that day), seconds or milliseconds, or an ISO date string → ms.
int? _when(dynamic v, {int? minutes}) {
  if (v is String) {
    final n = num.tryParse(v);
    if (n == null) return DateTime.tryParse(v)?.millisecondsSinceEpoch;
    v = n;
  }
  if (v is! num) return null;
  if (v < 100000) {
    final d = DateTime.fromMillisecondsSinceEpoch((v * kDay).round(), isUtc: true);
    final m = minutes != null && minutes >= 0 && minutes < 1440 ? minutes : 12 * 60;
    return DateTime(d.year, d.month, d.day, m ~/ 60, m % 60).millisecondsSinceEpoch;
  }
  if (v < 100000000000) return (v * 1000).round();
  return v.round();
}

String? _argbHex(dynamic v) {
  final n = _num(v)?.toInt();
  if (n == null) return null;
  return '#${(n & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
}
