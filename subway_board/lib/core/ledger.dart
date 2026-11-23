// Numbers worked out from the money log: account balances and net worth,
// goal and loan progress, trip/event budget windows, and the series the
// Money tab's charts draw (cash flow, daily spending, pace, net worth).
import 'dart:math' as math;

import 'money.dart';
import 'tasks.dart';
import 'util.dart';

// ---------------------------------------------------------------------------
// Accounts

/// Adds what [t] does to each account into [bal].
void applyToAccounts(Txn t, Map<String, int> bal, Money m) {
  void add(String id, int v) {
    if (id.isNotEmpty) bal[id] = (bal[id] ?? 0) + v;
  }

  switch (t.type) {
    case 'spend' || 'save' || 'lent':
      add(t.acct, -t.amount);
    case 'income' || 'refund' || 'unsave' || 'borrowed':
      add(t.acct, t.amount);
    case 'transfer':
      add(t.acct, -t.amount);
      add(t.to, t.amount);
    case 'adjust':
      add(t.acct, t.amount);
    case 'repay':
      // Getting a loan back brings money in; paying one back sends it out.
      add(t.acct, m.goalOf(t.goal)?.kind == 'borrowed' ? -t.amount : t.amount);
  }
}

/// Every account's balance (opening balance included) as of [until] (ms, exclusive).
Map<String, int> balances(Money m, {int? until}) {
  final bal = <String, int>{for (final a in m.accounts) a.id: a.opening};
  for (final t in m.txns) {
    if (until != null && t.at >= until) continue;
    applyToAccounts(t, bal, m);
  }
  return bal;
}

/// Assets minus debts across live accounts, plus what others owe you minus what you owe.
int netWorth(Money m, Map<String, int> bal, {int? until}) {
  var n = 0;
  for (final a in m.liveAccounts) {
    n += bal[a.id] ?? 0;
  }
  for (final g in m.goals) {
    final v = goalAmount(m, g, until: until);
    if (g.isLoan) {
      if (!g.archived) n += g.kind == 'lent' ? v : -v;
    } else {
      // Money moved into a goal left its account but is still yours. (The
      // starting amount was already sitting in an account somewhere.)
      n += v - g.offset;
    }
  }
  return n;
}

/// Net worth at the end of each of the last [months] months (oldest first).
/// The current month's point is today's figure.
List<(int, int)> netWorthSeries(Money m, int months, int now) {
  final out = <(int, int)>[];
  final cur = monthStart(now);
  for (var i = months - 1; i >= 0; i--) {
    final m0 = addMonths(cur, -i);
    final until = i == 0 ? now + 1 : monthEnd(m0);
    out.add((m0, netWorth(m, balances(m, until: until), until: until)));
  }
  return out;
}

/// What one transaction does to net worth (live accounts, open loans, savings goals).
int netDelta(Txn t, Money m, Set<String> liveIds) {
  final bal = <String, int>{};
  applyToAccounts(t, bal, m);
  var d = 0;
  bal.forEach((k, v) {
    if (liveIds.contains(k)) d += v;
  });
  final g = m.goalOf(t.goal);
  if (g != null) {
    final dir = switch (t.type) {
      'save' || 'lent' || 'borrowed' => 1,
      'unsave' || 'repay' => -1,
      _ => 0,
    };
    if (!g.isLoan) {
      d += dir * t.amount;
    } else if (!g.archived) {
      d += (g.kind == 'lent' ? 1 : -1) * dir * t.amount;
    }
  }
  return d;
}

/// Net worth at the end of every day from [from] (a local midnight) to today, oldest first.
List<(int, int)> netWorthDaily(Money m, int from, int now) {
  final liveIds = {for (final a in m.liveAccounts) a.id};
  var v = netWorth(m, balances(m, until: from), until: from);
  final txs = m.txns.where((t) => t.at >= from && t.at <= now).toList()..sort((a, b) => a.at.compareTo(b.at));
  final out = <(int, int)>[];
  var i = 0;
  final last = sod(now);
  for (var day = sod(from); day <= last; day = addDays(day, 1)) {
    final end = addDays(day, 1);
    while (i < txs.length && txs[i].at < end) {
      v += netDelta(txs[i], m, liveIds);
      i++;
    }
    out.add((day, v));
  }
  return out;
}

/// Midnight of the first day there's any money history (null with none).
int? historyStart(Money m) {
  int? first;
  for (final t in m.txns) {
    if (first == null || t.at < first) first = t.at;
  }
  return first == null ? null : sod(first);
}

/// Change in an account's balance over [from, to).
int acctChange(Money m, String id, int from, int to) {
  final bal = <String, int>{};
  for (final t in m.txns) {
    if (t.at < from || t.at >= to) continue;
    if (t.acct != id && t.to != id) continue;
    applyToAccounts(t, bal, m);
  }
  return bal[id] ?? 0;
}

// ---------------------------------------------------------------------------
// Goals and loans

/// Saved so far (savings goal), or still owed (loan).
int goalAmount(Money m, Goal g, {int? until}) {
  var v = g.offset;
  for (final t in m.txns) {
    if (t.goal != g.id || (until != null && t.at >= until)) continue;
    switch (t.type) {
      case 'save' || 'lent' || 'borrowed':
        v += t.amount;
      case 'unsave' || 'repay':
        v -= t.amount;
    }
  }
  return v;
}

/// A loan's full size: what was owed at the start plus every amount lent/borrowed since.
int loanTotal(Money m, Goal g) {
  var v = g.offset;
  for (final t in m.txns) {
    if (t.goal == g.id && (t.type == 'lent' || t.type == 'borrowed')) v += t.amount;
  }
  return math.max(v, g.target);
}

/// What needs to go in each month to reach a savings goal by its date (0 when done or undated).
int perMonthToGoal(Money m, Goal g, int now) {
  if (g.end <= now || g.target <= 0) return 0;
  final left = g.target - goalAmount(m, g);
  if (left <= 0) return 0;
  final a = DateTime.fromMillisecondsSinceEpoch(now), b = DateTime.fromMillisecondsSinceEpoch(g.end);
  // Whole months between now and the target date (at least one).
  final months = math.max(1, (b.year - a.year) * 12 + b.month - a.month - (b.day < a.day ? 1 : 0));
  return (left / months).ceil();
}

List<Txn> goalTxns(Money m, Goal g) => m.txns.where((t) => t.goal == g.id).toList()..sort((a, b) => b.at.compareTo(a.at));

// ---------------------------------------------------------------------------
// Trip and event budgets

/// The window a plan is counting now: its dates for a one-off, or the current
/// week/month/year of a repeating one. End is exclusive; 0 = open-ended.
(int, int) planWindow(Plan p, int now) {
  final s = sod(p.start);
  if (p.period == 'custom') return (s, p.end == 0 ? 0 : addDays(sod(p.end), 1));
  final d = DateTime.fromMillisecondsSinceEpoch(s);
  if (p.period == 'daily' || p.period == 'weekly') {
    final n = p.period == 'daily' ? 1 : 7;
    final k = now < s ? 0 : ((sod(now) - s) / kDay).round() ~/ n;
    final from = addDays(s, n * k);
    return (from, addDays(from, n));
  }
  final step = p.period == 'yearly' ? 12 : 1;
  var k = 0;
  while (k < 1200 && _monthsFrom(d, step * (k + 1)).millisecondsSinceEpoch <= now) {
    k++;
  }
  return (_monthsFrom(d, step * k).millisecondsSinceEpoch, _monthsFrom(d, step * (k + 1)).millisecondsSinceEpoch);
}

DateTime _monthsFrom(DateTime d, int n) {
  final last = DateTime(d.year, d.month + n + 1, 0).day;
  return DateTime(d.year, d.month + n, math.min(d.day, last));
}

/// Spends a plan counts in its current window, newest first.
List<Txn> planTxns(Money m, Plan p, int now) {
  final (from, to) = planWindow(p, now);
  final out = <Txn>[];
  for (final t in m.txns) {
    if (!t.isSpend || t.excluded) continue;
    if (p.mode == 'added') {
      if (t.plan != p.id) continue;
      // A one-off counts everything put in it; a repeating one only this window.
      if (p.period != 'custom' && (t.at < from || (to != 0 && t.at >= to))) continue;
    } else {
      if (t.at < from || (to != 0 && t.at >= to)) continue;
      if (p.cats.isNotEmpty && !p.cats.contains(t.cat)) continue;
      if (p.accts.isNotEmpty && !p.accts.contains(t.acct)) continue;
    }
    out.add(t);
  }
  return out..sort((a, b) => b.at.compareTo(a.at));
}

int planSpent(Money m, Plan p, int now) => planTxns(m, p, now).fold(0, (a, t) => a + (t.type == 'refund' ? -t.amount : t.amount));

/// 'upcoming' (not started), 'live', or 'ended'.
String planState(Plan p, int now) {
  final (from, to) = planWindow(p, now);
  if (now < from) return 'upcoming';
  if (to != 0 && now >= to) return 'ended';
  return 'live';
}

/// Plans to show on the Money tab: pinned, not archived; live ones first.
List<Plan> shownPlans(Money m, int now) {
  final list = m.plans.where((p) => p.pinned && !p.archived).toList();
  int rank(Plan p) => switch (planState(p, now)) { 'live' => 0, 'upcoming' => 1, _ => 2 };
  list.sort((a, b) => rank(a) != rank(b) ? rank(a).compareTo(rank(b)) : a.start.compareTo(b.start));
  return list;
}

// ---------------------------------------------------------------------------
// Reports

class FlowMonth {
  final int month0, income, spent;
  const FlowMonth(this.month0, this.income, this.spent);
  int get net => income - spent;
}

/// Income and spending for the last [months] months ending with [lastMonth0], oldest first.
List<FlowMonth> cashflow(Money m, int lastMonth0, int months) {
  final first = addMonths(lastMonth0, -(months - 1));
  final inc = List.filled(months, 0), out = List.filled(months, 0);
  final end = monthEnd(lastMonth0);
  final starts = [for (var i = 0; i < months; i++) addMonths(first, i)];
  for (final t in m.txns) {
    if (t.at < first || t.at >= end) continue;
    var i = months - 1;
    while (i > 0 && t.at < starts[i]) {
      i--;
    }
    if (t.income) {
      if (!t.excluded) inc[i] += t.amount;
    } else {
      out[i] += spendOf(t, m);
    }
  }
  return [for (var i = 0; i < months; i++) FlowMonth(starts[i], inc[i], math.max(0, out[i]))];
}

/// Spending on each day of the month (index 0 = the 1st).
List<int> dailySpend(Money m, int month0) {
  final from = monthStart(month0), to = monthEnd(month0);
  final days = List.filled(daysInMonth(month0), 0);
  for (final t in m.txns) {
    if (t.at < from || t.at >= to) continue;
    final v = spendOf(t, m);
    if (v == 0) continue;
    final d = DateTime.fromMillisecondsSinceEpoch(t.at).day - 1;
    days[d] += v;
  }
  return days;
}

/// Running total of [daily].
List<int> cumulative(List<int> daily) {
  var s = 0;
  return [for (final d in daily) s += d];
}

/// Entries waiting in To Review, newest first.
List<Txn> reviewQueue(Money m) => m.txns.where((t) => t.review).toList()..sort((a, b) => b.at.compareTo(a.at));

/// Unpaid bills due within [days] days (overdue ones included), soonest first.
List<Task> upcomingBills(List<Task> tasks, int now, {int days = 30}) {
  final end = dstr(addDays(sod(now), days));
  return tasks.where((t) => !t.done && t.isBill && t.due.isNotEmpty && t.due.compareTo(end) <= 0).toList()..sort(compareTasks);
}

/// All the tags used, most used first.
List<String> allTags(Money m) {
  final n = <String, int>{};
  for (final t in m.txns) {
    for (final g in t.tags) {
      n[g] = (n[g] ?? 0) + 1;
    }
  }
  return n.keys.toList()..sort((a, b) => n[b]!.compareTo(n[a]!));
}
