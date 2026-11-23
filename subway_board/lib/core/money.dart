// Money: accounts, categories with monthly limits, transactions, savings
// goals and loans, trip/event budgets, and the month's numbers. Amounts are
// integer minor units (paise/cents) so sums never drift.
//
// The shape follows the Budget app (com.budget.app) closely enough that its
// backups import without losing anything: transfers, refunds, balance
// updates, money lent/borrowed, goals, custom budgets and past months' limits.
import 'dart:math' as math;

import 'tasks.dart';
import 'util.dart';

// ---------------------------------------------------------------------------
// Categories

class MCat {
  String id, name, emoji, color, kw;

  /// Monthly limit in minor units; 0 = no limit. Months with their own saved
  /// limits ([Money.limits]) use those instead.
  int budget;

  /// Unspent (or overspent) money carries into the next month.
  bool rollover;

  /// Spending here doesn't count against the monthly budget.
  bool excluded;

  /// An income category (Salary, Refunds…) rather than a spending one.
  bool income;
  bool archived;

  MCat({
    required this.id,
    required this.name,
    required this.emoji,
    required this.color,
    this.kw = '',
    this.budget = 0,
    this.rollover = false,
    this.excluded = false,
    this.income = false,
    this.archived = false,
  });

  MCat copy() => MCat(
      id: id, name: name, emoji: emoji, color: color, kw: kw, budget: budget,
      rollover: rollover, excluded: excluded, income: income, archived: archived);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        'color': color,
        'kw': kw,
        'budget': budget,
        if (rollover) 'rollover': true,
        if (excluded) 'excluded': true,
        if (income) 'income': true,
        if (archived) 'archived': true,
      };
}

// ---------------------------------------------------------------------------
// Accounts

const kAcctTypes = <String, String>{
  'checking': 'Bank account',
  'savings': 'Savings',
  'credit': 'Credit card',
  'cash': 'Cash',
  'wallet': 'Wallet',
  'investment': 'Investment',
  'loan': 'Loan',
  'property': 'Property',
  'other': 'Other',
};

class Account {
  String id, name, type, color;

  /// Balance before the first transaction (minor units, may be negative).
  int opening;
  bool archived;
  int created;

  Account({required this.id, required this.name, this.type = 'checking', required this.color, this.opening = 0, this.archived = false, int? created})
      : created = created ?? nowMs();

  Account copy() => Account(id: id, name: name, type: type, color: color, opening: opening, archived: archived, created: created);

  /// Credit cards and loans are debts: their balance is usually below zero.
  bool get debt => type == 'credit' || type == 'loan';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'color': color,
        if (opening != 0) 'opening': opening,
        if (archived) 'archived': true,
        'created': created,
      };
}

// ---------------------------------------------------------------------------
// Transactions

/// spend · income · refund (money back into a category) · transfer (acct → to)
/// · adjust (balance update, signed) · save / unsave (into / out of a goal)
/// · lent / borrowed (start or add to a loan) · repay (part of a loan back).
const kTxnTypes = ['spend', 'income', 'refund', 'transfer', 'adjust', 'save', 'unsave', 'lent', 'borrowed', 'repay'];

class Txn {
  String id, title, cat, note;

  /// When it happened (ms).
  int at;

  /// Positive, except for [type] 'adjust' where the sign is the change.
  int amount;

  String type;

  /// Account the money moved in or out of ('' = none). For a transfer this is
  /// where it came from, and [to] is where it went.
  String acct, to;
  List<String> tags;

  /// Waiting in To Review (imported, or a bill logged automatically).
  bool review;

  /// Left out of budgets and reports.
  bool excluded;

  /// Goal or loan this belongs to; trip/event budget it's counted under.
  String goal, plan;

  /// The bill task that logged it, if any.
  String? task;

  /// Where it came from: '' (typed here) or 'budget-app' (imported).
  String src;

  Txn({
    required this.id,
    required this.title,
    required this.cat,
    this.note = '',
    required this.at,
    required this.amount,
    bool income = false,
    String? type,
    this.acct = '',
    this.to = '',
    List<String>? tags,
    this.review = false,
    this.excluded = false,
    this.goal = '',
    this.plan = '',
    this.task,
    this.src = '',
  })  : type = type ?? (income ? 'income' : 'spend'),
        tags = tags ?? [];

  bool get income => type == 'income';
  set income(bool v) => type = v ? 'income' : 'spend';

  /// Spending or a refund: counts in categories, budgets and reports.
  bool get isSpend => type == 'spend' || type == 'refund';

  /// Moves money between your own pots: never spending or income.
  bool get isMove => const {'transfer', 'adjust', 'save', 'unsave', 'lent', 'borrowed', 'repay'}.contains(type);

  Txn copy() => Txn(
        id: id, title: title, cat: cat, note: note, at: at, amount: amount, type: type, acct: acct, to: to,
        tags: List.of(tags), review: review, excluded: excluded, goal: goal, plan: plan, task: task, src: src,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'cat': cat,
        if (note.isNotEmpty) 'note': note,
        'at': at,
        'amount': amount,
        if (type == 'income') 'income': true,
        if (type != 'spend' && type != 'income') 'type': type,
        if (acct.isNotEmpty) 'acct': acct,
        if (to.isNotEmpty) 'to': to,
        if (tags.isNotEmpty) 'tags': tags,
        if (review) 'review': true,
        if (excluded) 'excluded': true,
        if (goal.isNotEmpty) 'goal': goal,
        if (plan.isNotEmpty) 'plan': plan,
        'task': ?task,
        if (src.isNotEmpty) 'src': src,
      };
}

// ---------------------------------------------------------------------------
// Goals and loans

/// 'save' (a savings goal) · 'lent' (money someone owes you) · 'borrowed' (money you owe).
class Goal {
  String id, name, emoji, color, kind;

  /// Savings target, or the loan's original amount (0 = none).
  int target;

  /// Amount already there before tracking started (savings), or owed at the start (loans).
  int offset;

  /// Target date (ms, 0 = none) and when it started.
  int end, start;

  /// Loans: an EMI-style loan that runs for months or years.
  bool longTerm;
  bool archived;

  Goal({
    required this.id,
    required this.name,
    this.emoji = '🎯',
    required this.color,
    this.kind = 'save',
    this.target = 0,
    this.offset = 0,
    this.end = 0,
    int? start,
    this.longTerm = false,
    this.archived = false,
  }) : start = start ?? nowMs();

  bool get isLoan => kind == 'lent' || kind == 'borrowed';

  Goal copy() => Goal(
      id: id, name: name, emoji: emoji, color: color, kind: kind, target: target, offset: offset,
      end: end, start: start, longTerm: longTerm, archived: archived);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        'color': color,
        'kind': kind,
        if (target != 0) 'target': target,
        if (offset != 0) 'offset': offset,
        if (end != 0) 'end': end,
        'start': start,
        if (longTerm) 'longTerm': true,
        if (archived) 'archived': true,
      };
}

// ---------------------------------------------------------------------------
// Trip and event budgets ("custom budgets" in the Budget app)

/// [period]: 'custom' (from [start] to [end]) or a repeating window
/// ('daily' | 'weekly' | 'monthly' | 'yearly') that starts again from [start].
/// [mode]: 'all' counts every spend that matches its dates, categories and
/// accounts; 'added' only the ones you put in it.
class Plan {
  String id, name, emoji, color, period, mode;
  int amount, start, end;
  List<String> cats, accts;
  bool pinned, archived;

  Plan({
    required this.id,
    required this.name,
    this.emoji = '🧳',
    required this.color,
    this.period = 'custom',
    this.mode = 'added',
    this.amount = 0,
    required this.start,
    this.end = 0,
    List<String>? cats,
    List<String>? accts,
    this.pinned = true,
    this.archived = false,
  })  : cats = cats ?? [],
        accts = accts ?? [];

  Plan copy() => Plan(
      id: id, name: name, emoji: emoji, color: color, period: period, mode: mode, amount: amount,
      start: start, end: end, cats: List.of(cats), accts: List.of(accts), pinned: pinned, archived: archived);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        'color': color,
        'period': period,
        'mode': mode,
        'amount': amount,
        'start': start,
        if (end != 0) 'end': end,
        if (cats.isNotEmpty) 'cats': cats,
        if (accts.isNotEmpty) 'accts': accts,
        if (pinned) 'pinned': true,
        if (archived) 'archived': true,
      };
}

// ---------------------------------------------------------------------------
// Money tab layout

/// Sections of the Money tab, in their default order.
const kMoneySections = <String, String>{
  'review': 'To review',
  'accounts': 'Accounts',
  'networth': 'Net worth',
  'bills': 'Upcoming bills',
  'budgets': 'Category budgets',
  'pace': 'Spending pace',
  'plans': 'Trip & event budgets',
  'goals': 'Savings goals',
  'loans': 'Loans',
  'cashflow': 'Income vs spending',
  'breakdown': 'Spending by category',
  'moons': 'Daily moons',
  'activity': 'Transactions',
};

const kMoneySectionHints = <String, String>{
  'review': 'Imported and auto-logged entries to check',
  'bills': 'Bills due in the next 30 days',
  'budgets': 'Each category against its monthly limit',
  'pace': 'Spending so far against an even pace',
  'accounts': 'Balances, swipe through your accounts',
  'plans': 'Pinned budgets for trips and events',
  'goals': 'Progress toward what you’re saving for',
  'loans': 'Money lent and borrowed',
  'cashflow': 'Money in and out, month by month',
  'breakdown': 'Where this month’s money went',
  'moons': 'Each day’s spending as a moon',
  'networth': 'Assets minus debts over time',
  'activity': 'This month’s log, day by day',
};

class MoneySection {
  final String id;
  bool on;
  MoneySection(this.id, this.on);
  Map<String, dynamic> toJson() => {'id': id, 'on': on};
}

List<MoneySection> defaultSections() => [for (final id in kMoneySections.keys) MoneySection(id, true)];

// ---------------------------------------------------------------------------

class Money {
  /// Currency symbol shown before amounts.
  String currency;

  /// Overall monthly budget in minor units; 0 = none (then the categories' limits add up).
  int budget;
  List<MCat> cats;
  List<Txn> txns;
  List<Account> accounts;
  List<Goal> goals;
  List<Plan> plans;

  /// Limits set in particular months: 'YYYY-MM' → category id → minor units.
  /// Each carries forward until a later month sets that category again (see [limitIn]).
  Map<String, Map<String, int>> limits;

  /// Account new entries go to ('' = none).
  String defaultAcct;

  /// Order and visibility of the Money tab's sections.
  List<MoneySection> sections;

  Money({
    String? currency,
    this.budget = 0,
    List<MCat>? cats,
    List<Txn>? txns,
    List<Account>? accounts,
    List<Goal>? goals,
    List<Plan>? plans,
    Map<String, Map<String, int>>? limits,
    this.defaultAcct = '',
    List<MoneySection>? sections,
  })  : currency = currency ?? defaultCurrency(),
        cats = cats ?? defaultMCats(),
        txns = txns ?? [],
        accounts = accounts ?? [],
        goals = goals ?? [],
        plans = plans ?? [],
        limits = limits ?? {},
        sections = sections ?? defaultSections();

  Map<String, dynamic> toJson() => {
        'currency': currency,
        'budget': budget,
        'cats': cats.map((c) => c.toJson()).toList(),
        'txns': txns.map((t) => t.toJson()).toList(),
        if (accounts.isNotEmpty) 'accounts': accounts.map((a) => a.toJson()).toList(),
        if (goals.isNotEmpty) 'goals': goals.map((g) => g.toJson()).toList(),
        if (plans.isNotEmpty) 'plans': plans.map((p) => p.toJson()).toList(),
        if (limits.isNotEmpty) 'limits': limits,
        if (defaultAcct.isNotEmpty) 'defaultAcct': defaultAcct,
        'sections': sections.map((s) => s.toJson()).toList(),
      };

  /// Where spending with no category (or a deleted one) goes.
  String get fallbackCat => cats.where((c) => c.id == 'other').firstOrNull?.id ?? spendCats.firstOrNull?.id ?? cats.first.id;

  /// Where income with no category goes.
  String get fallbackIncome => incomeCats.firstOrNull?.id ?? fallbackCat;

  MCat catOf(String id) => cats.where((c) => c.id == id).firstOrNull ?? cats.firstWhere((c) => c.id == fallbackCat);

  Iterable<MCat> get spendCats => cats.where((c) => !c.income && !c.archived);
  Iterable<MCat> get incomeCats => cats.where((c) => c.income && !c.archived);

  Account? acctOf(String id) => id.isEmpty ? null : accounts.where((a) => a.id == id).firstOrNull;
  Goal? goalOf(String id) => id.isEmpty ? null : goals.where((g) => g.id == id).firstOrNull;
  Plan? planOf(String id) => id.isEmpty ? null : plans.where((p) => p.id == id).firstOrNull;

  Iterable<Account> get liveAccounts => accounts.where((a) => !a.archived);

  /// The account new entries go to, if it still exists.
  String get newAcct => acctOf(defaultAcct)?.archived == false ? defaultAcct : '';

  /// The limit a category has in [month0] (local midnight on the 1st), before rollover.
  /// Like the Budget app, a limit set in some month carries on into later months
  /// until it's changed; categories never given one in a saved month use [MCat.budget].
  int limitIn(MCat c, int month0) {
    final key = monthKey(month0);
    String? best;
    for (final k in limits.keys) {
      if (k.compareTo(key) <= 0 && limits[k]!.containsKey(c.id) && (best == null || k.compareTo(best) > 0)) best = k;
    }
    return best != null ? limits[best]![c.id]! : c.budget;
  }

  bool sectionOn(String id) => sections.where((s) => s.id == id).firstOrNull?.on ?? true;

  /// The standing monthly budget: the overall one, or the categories' limits added up
  /// (no rollover or saved months; [monthStats] works those out).
  int get monthBudget => budget > 0 ? budget : spendCats.where((c) => !c.excluded).fold(0, (a, c) => a + c.budget);
}

const kCurrencies = ['₹', r'$', '€', '£', '¥', 'AED ', 'S\$', 'A\$'];

/// Currency from the phone's region ('en_IN' → ₹).
String Function() defaultCurrency = () => '₹';

String currencyForLocale(String locale) {
  final region = locale.split(RegExp('[_-]')).skip(1).firstOrNull?.toUpperCase() ?? '';
  return switch (region) {
    'IN' => '₹',
    'US' => r'$',
    'GB' => '£',
    'JP' || 'CN' => '¥',
    'AE' => 'AED ',
    'SG' => 'S\$',
    'AU' => 'A\$',
    'DE' || 'FR' || 'IT' || 'ES' || 'NL' || 'IE' || 'AT' || 'BE' || 'FI' || 'PT' || 'GR' => '€',
    _ => '₹',
  };
}

List<MCat> defaultMCats() => [
      MCat(id: 'food', name: 'Food', emoji: '🍜', color: '#ff8a00',
          kw: 'food, lunch, dinner, breakfast, coffee, tea, snack, swiggy, zomato, groceries, grocery, restaurant, cafe, chai, biryani, pizza'),
      MCat(id: 'travel', name: 'Transport', emoji: '🚇', color: '#1d6cf2',
          kw: 'uber, ola, rapido, metro, bus, train, cab, auto, taxi, fuel, petrol, diesel, parking, toll, flight'),
      MCat(id: 'shop', name: 'Shopping', emoji: '🛍️', color: '#e85ad8', kw: 'amazon, flipkart, myntra, clothes, shoes, shopping, gift'),
      MCat(id: 'bills', name: 'Bills', emoji: '🧾', color: '#14b8a6',
          kw: 'rent, electricity, wifi, internet, broadband, phone, recharge, bill, emi, insurance, water, gas, subscription, fees, fee'),
      MCat(id: 'fun', name: 'Fun', emoji: '🎬', color: '#8b5cf6', kw: 'movie, netflix, spotify, game, games, concert, party, drinks, outing'),
      MCat(id: 'health', name: 'Health', emoji: '💊', color: '#22c55e', kw: 'doctor, medicine, pharmacy, gym, hospital, dentist, clinic'),
      MCat(id: 'other', name: 'Other', emoji: '•', color: '#71717a'),
      ...defaultIncomeCats(),
    ];

List<MCat> defaultIncomeCats() => [
      MCat(id: 'inc-salary', name: 'Salary', emoji: '💼', color: '#16a34a', kw: 'salary, stipend, payroll, paycheck', income: true),
      MCat(id: 'inc-refunds', name: 'Refunds', emoji: '↩️', color: '#14b8a6', kw: 'refund, cashback, reversal', income: true),
      MCat(id: 'inc-other', name: 'Other income', emoji: '💰', color: '#ffd400', kw: 'received, gift, interest, freelance', income: true),
    ];

const kPaletteMoney = ['#ff8a00', '#1d6cf2', '#e85ad8', '#14b8a6', '#8b5cf6', '#22c55e', '#ff5a1f', '#ffd400', '#f87171', '#38bdf8', '#a3e635', '#71717a'];

// ---------------------------------------------------------------------------
// Reading saved data

num? _n(dynamic v) => v is num ? v : (v is String ? num.tryParse(v) : null);
final _hex = RegExp(r'^#[0-9a-f]{6}$', caseSensitive: false);
String _s(dynamic v) => v is String ? v : '';
String _color(dynamic v, String fallback) => v is String && _hex.hasMatch(v) ? v : fallback;
List<String> _strs(dynamic v) => [if (v is List) for (final x in v) if (x is String && x.isNotEmpty) x];

Money moneyFromJson(dynamic raw) {
  if (raw is! Map) return Money();
  final cats = <MCat>[
    if (raw['cats'] is List)
      for (final c in raw['cats'])
        if (c is Map && c['id'] is String && c['name'] is String)
          MCat(
            id: c['id'],
            name: clip(c['name'], 24),
            emoji: c['emoji'] is String && (c['emoji'] as String).isNotEmpty ? c['emoji'] : '•',
            color: _color(c['color'], '#71717a'),
            kw: _s(c['kw']),
            budget: (_n(c['budget'])?.round() ?? 0).clamp(0, 1 << 50),
            rollover: c['rollover'] == true,
            excluded: c['excluded'] == true,
            income: c['income'] == true,
            archived: c['archived'] == true,
          ),
  ];
  // Saved before income categories existed: add the defaults after the spending ones.
  if (cats.isNotEmpty && !cats.any((c) => c.income)) cats.addAll(defaultIncomeCats().where((d) => !cats.any((c) => c.id == d.id)));

  final m = Money(
    currency: raw['currency'] is String && (raw['currency'] as String).isNotEmpty ? raw['currency'] : null,
    budget: (_n(raw['budget'])?.round() ?? 0).clamp(0, 1 << 50),
    cats: cats.isEmpty ? null : cats,
    defaultAcct: _s(raw['defaultAcct']),
  );

  if (raw['accounts'] is List) {
    for (final a in raw['accounts']) {
      if (a is! Map || a['id'] is! String) continue;
      m.accounts.add(Account(
        id: a['id'],
        name: clip(_s(a['name']).isEmpty ? 'Account' : a['name'], 28),
        type: kAcctTypes.containsKey(a['type']) ? a['type'] : 'other',
        color: _color(a['color'], '#1d6cf2'),
        opening: _n(a['opening'])?.round() ?? 0,
        archived: a['archived'] == true,
        created: _n(a['created'])?.round(),
      ));
    }
  }
  if (raw['goals'] is List) {
    for (final g in raw['goals']) {
      if (g is! Map || g['id'] is! String) continue;
      m.goals.add(Goal(
        id: g['id'],
        name: clip(_s(g['name']).isEmpty ? 'Goal' : g['name'], 32),
        emoji: _s(g['emoji']).isEmpty ? '🎯' : g['emoji'],
        color: _color(g['color'], '#22c55e'),
        kind: const ['save', 'lent', 'borrowed'].contains(g['kind']) ? g['kind'] : 'save',
        target: (_n(g['target'])?.round() ?? 0).abs(),
        offset: _n(g['offset'])?.round() ?? 0,
        end: _n(g['end'])?.round() ?? 0,
        start: _n(g['start'])?.round(),
        longTerm: g['longTerm'] == true,
        archived: g['archived'] == true,
      ));
    }
  }
  if (raw['plans'] is List) {
    for (final p in raw['plans']) {
      if (p is! Map || p['id'] is! String) continue;
      final start = _n(p['start'])?.round();
      if (start == null) continue;
      m.plans.add(Plan(
        id: p['id'],
        name: clip(_s(p['name']).isEmpty ? 'Budget' : p['name'], 32),
        emoji: _s(p['emoji']).isEmpty ? '🧳' : p['emoji'],
        color: _color(p['color'], '#1d6cf2'),
        period: const ['custom', 'daily', 'weekly', 'monthly', 'yearly'].contains(p['period']) ? p['period'] : 'custom',
        mode: p['mode'] == 'all' ? 'all' : 'added',
        amount: (_n(p['amount'])?.round() ?? 0).abs(),
        start: start,
        end: _n(p['end'])?.round() ?? 0,
        cats: _strs(p['cats']),
        accts: _strs(p['accts']),
        pinned: p['pinned'] == true,
        archived: p['archived'] == true,
      ));
    }
  }
  if (raw['limits'] is Map) {
    (raw['limits'] as Map).forEach((k, v) {
      if (k is! String || v is! Map) return;
      m.limits[k] = {
        for (final e in v.entries)
          if (e.key is String && _n(e.value) != null) e.key as String: _n(e.value)!.round().abs(),
      };
    });
  }
  if (raw['sections'] is List) {
    final seen = <String>{};
    final list = <MoneySection>[
      for (final s in raw['sections'])
        if (s is Map && kMoneySections.containsKey(s['id']) && seen.add(s['id'])) MoneySection(s['id'], s['on'] != false),
    ];
    // Sections added in a later version join at their default spot.
    for (final id in kMoneySections.keys) {
      if (seen.contains(id)) continue;
      final after = kMoneySections.keys.takeWhile((k) => k != id).lastWhere((k) => seen.contains(k), orElse: () => '');
      final at = after.isEmpty ? 0 : list.indexWhere((s) => s.id == after) + 1;
      list.insert(at, MoneySection(id, true));
      seen.add(id);
    }
    m.sections = list;
  }

  if (raw['txns'] is List) {
    for (final t in raw['txns']) {
      final x = txnFromJson(t, m);
      if (x != null) m.txns.add(x);
    }
  }
  return m;
}

/// One saved transaction, checked against [m]'s categories and accounts.
Txn? txnFromJson(dynamic t, Money m) {
  if (t is! Map) return null;
  final at = _n(t['at']), amt = _n(t['amount']);
  if (at == null || amt == null) return null;
  final ids = m.cats.map((c) => c.id).toSet();
  final acctIds = m.accounts.map((a) => a.id).toSet();
  final type = t['income'] == true ? 'income' : (kTxnTypes.contains(t['type']) ? t['type'] as String : 'spend');
  final cat = t['cat'];
  return Txn(
        id: t['id']?.toString() ?? uid(),
        title: _s(t['title']),
        cat: ids.contains(cat) ? cat : (type == 'income' ? m.fallbackIncome : m.fallbackCat),
        note: _s(t['note']),
        at: at.round(),
        amount: type == 'adjust' ? amt.round() : amt.round().abs(),
        type: type,
        acct: acctIds.contains(t['acct']) ? t['acct'] : '',
        to: acctIds.contains(t['to']) ? t['to'] : '',
        tags: _strs(t['tags']),
        review: t['review'] == true,
        excluded: t['excluded'] == true,
        goal: _s(t['goal']),
        plan: _s(t['plan']),
        task: t['task'] is String ? t['task'] : null,
        src: _s(t['src']),
      );
}

// ---------------------------------------------------------------------------
// Formatting

/// "₹1,23,456" (Indian grouping for ₹), "$123,456.50". Paise only when not whole.
String fmtMoney(int minor, String cur, {bool sign = false, bool compact = false}) {
  final neg = minor < 0;
  final a = minor.abs();
  final whole = a ~/ 100, frac = a % 100;
  String s;
  if (compact && whole >= 100000) {
    s = cur == '₹' && whole < 10000000
        ? '${_trim(whole / 100000)}L'
        : cur == '₹'
            ? '${_trim(whole / 10000000)}Cr'
            : whole >= 1000000
                ? '${_trim(whole / 1000000)}M'
                : '${_trim(whole / 1000)}k';
  } else if (compact && whole >= 10000) {
    s = '${_trim(whole / 1000)}k';
  } else {
    s = _group(whole.toString(), indian: cur == '₹');
    if (frac != 0 && !compact) s = '$s.${frac.toString().padLeft(2, '0')}';
  }
  final p = neg ? '−' : (sign ? '+' : '');
  return '$p$cur$s';
}

String _trim(double v) => v >= 100 ? v.round().toString() : v.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');

String _group(String d, {required bool indian}) {
  if (d.length <= 3) return d;
  final last3 = d.substring(d.length - 3);
  var rest = d.substring(0, d.length - 3);
  final size = indian ? 2 : 3;
  final parts = <String>[];
  while (rest.length > size) {
    parts.insert(0, rest.substring(rest.length - size));
    rest = rest.substring(0, rest.length - size);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '${parts.join(',')},$last3';
}

/// Parses "1,200", "1200.5", "1.5k" into minor units; null if it isn't a number.
int? parseAmount(String s) {
  var t = s.trim().toLowerCase().replaceAll(',', '').replaceAll(RegExp(r'^(rs\.?|inr|₹|\$|€|£)\s*'), '');
  var mul = 1.0;
  if (t.endsWith('k')) {
    mul = 1000;
    t = t.substring(0, t.length - 1);
  } else if (t.endsWith('l') || t.endsWith('lakh')) {
    mul = 100000;
    t = t.replaceAll(RegExp(r'(lakh|l)$'), '');
  }
  final v = double.tryParse(t.trim());
  if (v == null || v < 0 || !v.isFinite) return null;
  return (v * mul * 100).round();
}

/// Minor units as the plain number you'd type ("1200", "45.50").
String plainAmount(int minor) => minor % 100 == 0 ? '${minor ~/ 100}' : (minor / 100).toStringAsFixed(2);

// ---------------------------------------------------------------------------
// Months

/// Local midnight on the 1st of the month containing [ms].
int monthStart(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return DateTime(d.year, d.month).millisecondsSinceEpoch;
}

int monthEnd(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return DateTime(d.year, d.month + 1).millisecondsSinceEpoch;
}

int addMonths(int ms, int n) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return DateTime(d.year, d.month + n).millisecondsSinceEpoch;
}

/// 'YYYY-MM' of the month containing [ms].
String monthKey(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.year}-${pad(d.month)}';
}

int daysInMonth(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return DateTime(d.year, d.month + 1, 0).day;
}

String monthLong(int ms) => const ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'][DateTime.fromMillisecondsSinceEpoch(ms).month - 1];

// ---------------------------------------------------------------------------
// The month

/// How much a transaction adds to its category's spending (refunds take away).
/// Zero for income, moves, and anything excluded.
int spendOf(Txn t, Money m) {
  if (!t.isSpend || t.excluded) return 0;
  final c = m.catOf(t.cat);
  if (c.excluded) return 0;
  return t.type == 'refund' ? -t.amount : t.amount;
}

class MonthStats {
  final int spent, income, budget, today, upcoming;

  /// Spent before today (current month), so today's allowance doesn't shrink as you spend.
  final int before;

  /// Per-category spending this month (refunds already taken off).
  final Map<String, int> byCat;

  /// Per-category limit this month, rollover included.
  final Map<String, int> limit;

  /// Days left including today (current month only; 0 otherwise).
  final int daysLeft;
  const MonthStats({
    required this.spent,
    required this.income,
    required this.budget,
    required this.today,
    required this.upcoming,
    required this.byCat,
    required this.limit,
    required this.daysLeft,
    this.before = 0,
  });

  int get left => budget - spent;

  /// What can go out each remaining day, after bills still to pay this month.
  int get perDay => daysLeft <= 0 ? 0 : math.max(0, (budget - spent - upcoming) ~/ daysLeft);

  /// Today's share, worked out from the morning's position.
  int get todayAllowance => daysLeft <= 0 ? 0 : math.max(0, (budget - before - upcoming) ~/ daysLeft);

  /// What's left of today's share.
  int get leftToday => todayAllowance - today;

  double get used => budget <= 0 ? 0 : spent / budget;
}

/// Spending per category in [from, to).
Map<String, int> spendByCat(Money m, int from, int to) {
  final out = <String, int>{};
  for (final t in m.txns) {
    if (t.at < from || t.at >= to) continue;
    final v = spendOf(t, m);
    if (v != 0) out[t.cat] = (out[t.cat] ?? 0) + v;
  }
  return out;
}

/// A category's limit in [month0] plus what rolled over from earlier months
/// (only for rollover categories; looks back at most a year).
int limitWithRollover(Money m, MCat c, int month0, {Map<int, Map<String, int>>? cache}) {
  final base = m.limitIn(c, month0);
  if (!c.rollover) return base;
  var carry = 0;
  for (var i = 12; i >= 1; i--) {
    final mm = addMonths(month0, -i);
    final lim = m.limitIn(c, mm);
    if (lim <= 0 && carry == 0) continue;
    final byCat = cache == null ? spendByCat(m, mm, monthEnd(mm)) : (cache[mm] ??= spendByCat(m, mm, monthEnd(mm)));
    final spent = byCat[c.id] ?? 0;
    carry += lim - spent;
  }
  return math.max(0, base + carry);
}

MonthStats monthStats(Money m, List<Task> tasks, int month0, int now) {
  final from = monthStart(month0), to = monthEnd(month0);
  final t0 = sod(now), t1 = addDays(t0, 1);
  var spent = 0, income = 0, today = 0, before = 0;
  final byCat = <String, int>{};
  for (final t in m.txns) {
    if (t.at < from || t.at >= to) continue;
    if (t.income) {
      if (!t.excluded) income += t.amount;
      continue;
    }
    final v = spendOf(t, m);
    if (v == 0) continue;
    spent += v;
    byCat[t.cat] = (byCat[t.cat] ?? 0) + v;
    if (t.at >= t0 && t.at < t1) {
      today += v;
    } else if (t.at < t0) {
      before += v;
    }
  }
  final current = now >= from && now < to;
  // Unpaid bills due from today to the end of the month (overdue ones included).
  var upcoming = 0;
  if (current) {
    final end = dstr(to - 1);
    for (final k in tasks) {
      if (!k.done && k.isBill && k.due.isNotEmpty && k.due.compareTo(end) <= 0) upcoming += k.amount;
    }
  }
  final cache = <int, Map<String, int>>{};
  final limit = <String, int>{
    for (final c in m.spendCats)
      if (!c.excluded) c.id: limitWithRollover(m, c, from, cache: cache),
  };
  final catSum = limit.values.fold(0, (a, b) => a + b);
  final daysLeft = current ? ((to - t0) / kDay).round() : 0;
  return MonthStats(
    spent: spent,
    income: income,
    budget: m.budget > 0 ? m.budget : catSum,
    today: today,
    before: before,
    upcoming: upcoming,
    byCat: byCat,
    limit: limit,
    daysLeft: daysLeft,
  );
}

final _reEsc = RegExp(r'[.*+?^${}()|[\]\\]');

/// Category whose keyword (or name) appears in [title] as a whole word; longest wins.
/// [income] picks from income categories instead of spending ones.
String? matchMCat(Money m, String title, {bool income = false}) {
  final text = ' ${title.toLowerCase()} ';
  String? best;
  var score = 0;
  for (final c in m.cats) {
    if (c.income != income || c.archived) continue;
    final words = [c.name, ...c.kw.split(',')].map((w) => w.trim().toLowerCase()).where((w) => w.isNotEmpty);
    for (final w in words) {
      if (w.length > score && RegExp('(^|[^a-z0-9])${w.replaceAllMapped(_reEsc, (x) => '\\${x[0]}')}(\$|[^a-z0-9])').hasMatch(text)) {
        best = c.id;
        score = w.length;
      }
    }
  }
  return best;
}
