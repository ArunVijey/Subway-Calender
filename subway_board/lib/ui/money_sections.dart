// The Money tab's sections. Each builder returns its rows (header first) for
// the month on screen, or nothing when it has nothing to say. Order and
// visibility come from Settings → Money tab.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/store.dart';
import '../core/ledger.dart';
import '../core/money.dart';
import '../core/tasks.dart';
import '../core/util.dart';
import 'haptics.dart';
import 'money.dart';
import 'money_charts.dart';
import 'money_pages.dart';
import 'motion.dart';
import 'tasks.dart';
import 'theme.dart';

/// Everything the sections need, worked out once per build.
class MoneyCtx {
  final AppState app;
  final Money m;
  final int month, now;
  final bool current;
  final MonthStats st;
  final Map<String, int> bal;
  /// [month] defaults to the month the Money tab is showing.
  MoneyCtx(this.app, {int? month})
      : m = app.s.money,
        month = month ?? app.moneyMonth,
        now = nowMs(),
        current = monthStart(nowMs()) == (month ?? app.moneyMonth),
        st = app.stats(month ?? app.moneyMonth),
        bal = app.balancesNow();

  String cash(int v, {bool sign = false, bool compact = false}) => app.cash(v, sign: sign, compact: compact);
  int get to => monthEnd(month);
  int get todayIndex => current ? DateTime.fromMillisecondsSinceEpoch(now).day - 1 : -1;
}

typedef SectionBuilder = List<Widget> Function(BuildContext context, MoneyCtx c, bool first);

final Map<String, SectionBuilder> kSectionBuilders = {
  'review': _review,
  'bills': _bills,
  'budgets': _budgets,
  'pace': _pace,
  'accounts': _accounts,
  'plans': _plans,
  'goals': _goals,
  'loans': _loans,
  'cashflow': _cashflow,
  'breakdown': _breakdown,
  'moons': _moons,
  'networth': _networth,
  'activity': _activity,
};

// ---------------------------------------------------------------------------
// Shared bits

class MoneyHint extends StatelessWidget {
  final String text;
  final String? action;
  final VoidCallback? onAction;
  const MoneyHint(this.text, {super.key, this.action, this.onAction});
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
      child: Row(children: [
        Expanded(child: Text(text, style: inter(14, FontWeight.w500, height: 1.45, color: pal.sub))),
        if (action != null) ...[const SizedBox(width: 12), HeadAction(action!, onAction ?? () {})],
      ]),
    );
  }
}

class HeadAction extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const HeadAction(this.label, this.onTap, {super.key});
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: Pressable(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            child: Text(label, style: cond(14, FontWeight.w800, ls: .08, color: Pal.of(context).light ? const Color(0xFF111111) : kYellow)),
          ),
        ),
      );
}

class HeadSum extends StatelessWidget {
  final String text;
  final Color? color;
  const HeadSum(this.text, {super.key, this.color});
  @override
  Widget build(BuildContext context) => Text(text, style: cond(15, FontWeight.w800, ls: .06, color: color ?? Pal.of(context).sub));
}

/// Emoji in a soft circle of [color].
class EmojiBadge extends StatelessWidget {
  final String emoji, color;
  final double size;
  const EmojiBadge(this.emoji, this.color, {super.key, this.size = 40});
  @override
  Widget build(BuildContext context) {
    final c = hexColor(color);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: c.withValues(alpha: Pal.of(context).light ? .2 : .26), border: Border.all(color: c, width: 2)),
      child: Text(emoji, style: TextStyle(fontSize: size * .44, height: 1.1, color: c)),
    );
  }
}

const kAcctEmoji = {
  'checking': '🏦',
  'savings': '🐷',
  'credit': '💳',
  'cash': '💵',
  'wallet': '👛',
  'investment': '📈',
  'loan': '🧾',
  'property': '🏠',
  'other': '•',
};

/// A plain row on the panel: badge, two lines of text, and something on the right.
class PanelRow extends StatelessWidget {
  final Widget lead;
  final String title;
  final String? sub;
  final Widget? trailing;
  final Widget? below;
  final VoidCallback? onTap;
  final String? semantics;
  const PanelRow({super.key, required this.lead, required this.title, this.sub, this.trailing, this.below, this.onTap, this.semantics});
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Semantics(
      button: onTap != null,
      label: semantics,
      excludeSemantics: semantics != null,
      child: Pressable(
        scale: .985,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          decoration: BoxDecoration(color: pal.row, border: Border(bottom: BorderSide(color: pal.rule))),
          child: Row(children: [
            lead,
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: cond(21, FontWeight.w700, height: 1.1, color: pal.text))),
                  if (trailing != null) ...[const SizedBox(width: 10), trailing!],
                ]),
                if (sub != null) ...[
                  const SizedBox(height: 2),
                  Text(sub!, maxLines: 1, overflow: TextOverflow.ellipsis, style: inter(13, FontWeight.w600, color: pal.sub)),
                ],
                if (below != null) ...[const SizedBox(height: 8), below!],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

TextStyle _num(double size, Color color) => cond(size, FontWeight.w800, color: color).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

Widget _pad(Widget child, {double top = 4, double bottom = 10}) => Padding(padding: EdgeInsets.fromLTRB(20, top, 20, bottom), child: child);

// ---------------------------------------------------------------------------
// To review

List<Widget> _review(BuildContext context, MoneyCtx c, bool first) {
  final q = reviewQueue(c.m);
  if (q.isEmpty) return const [];
  return [
    GroupHead('TO REVIEW', count: q.length, first: first, color: Pal.of(context).light ? kAccentInk : kYellow, trailing: HeadAction('ALL GOOD', c.app.markAllReviewed)),
    for (final t in q.take(4)) TxnRow(key: ValueKey('rv-${t.id}'), txn: t, showDate: true),
    if (q.length > 4) _SeeAll('SEE ALL ${q.length}', () => openTxnList(context, review: true)),
  ];
}

class _SeeAll extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _SeeAll(this.label, this.onTap);
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Pressable(
      scale: .98,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 20),
        decoration: BoxDecoration(color: pal.row, border: Border(bottom: BorderSide(color: pal.rule))),
        child: Row(children: [
          Text(label, style: cond(15, FontWeight.w800, ls: .08, color: pal.light ? pal.text : kYellow)),
          const Spacer(),
          Text('›', style: TextStyle(fontSize: 24, height: .8, color: pal.placeholder)),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Upcoming bills

List<Widget> _bills(BuildContext context, MoneyCtx c, bool first) {
  if (!c.current) return const [];
  final bills = upcomingBills(c.app.s.tasks, c.now);
  if (bills.isEmpty) return const [];
  return [
    GroupHead('UPCOMING BILLS', count: bills.length, first: first, trailing: HeadSum(c.cash(bills.fold(0, (a, t) => a + t.amount)))),
    for (final t in bills) TaskRow(key: ValueKey('bill-${t.id}|${t.due}'), task: t),
  ];
}

// ---------------------------------------------------------------------------
// Category budgets

List<Widget> _budgets(BuildContext context, MoneyCtx c, bool first) {
  final st = c.st;
  final cats = c.m.cats.where((x) => !x.income && ((st.byCat[x.id] ?? 0) != 0 || (st.limit[x.id] ?? 0) > 0)).toList()
    ..sort((a, b) {
      final la = st.limit[a.id] ?? 0, lb = st.limit[b.id] ?? 0;
      if ((la > 0) != (lb > 0)) return la > 0 ? -1 : 1;
      return (st.byCat[b.id] ?? 0).compareTo(st.byCat[a.id] ?? 0);
    });
  final out = <Widget>[GroupHead('BUDGETS', first: first, trailing: HeadAction('EDIT', () => openCategories(context)))];
  if (cats.isEmpty) {
    out.add(const MoneyHint('Spending shows up here by category. Give categories a monthly limit under EDIT.'));
    return out;
  }
  final top = st.byCat.values.fold(0, math.max);
  for (final x in cats) {
    out.add(CatRow(key: ValueKey('cat-${x.id}'), cat: x, spent: st.byCat[x.id] ?? 0, limit: st.limit[x.id] ?? 0, top: top));
  }
  // Spending in categories with no limit (counted in the total, not in any bar's limit).
  final loose = cats.where((x) => (st.limit[x.id] ?? 0) == 0 && !x.excluded).fold(0, (a, x) => a + (st.byCat[x.id] ?? 0));
  if (loose > 0 && cats.any((x) => (st.limit[x.id] ?? 0) > 0)) {
    out.add(MoneyHint('${c.cash(loose)} in categories without a limit.'));
  }
  return out;
}

class CatRow extends StatelessWidget {
  final MCat cat;
  final int spent, limit;

  /// The biggest category's spend: without a limit, bars compare against it.
  final int top;
  const CatRow({super.key, required this.cat, required this.spent, required this.limit, required this.top});
  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final pal = Pal.of(context);
    final col = hexColor(cat.color);
    final over = limit > 0 && spent > limit;
    final rolled = cat.rollover && limit != app.s.money.limitIn(cat, app.moneyMonth);
    final sub = [
      if (limit > 0) over ? '${app.cash(spent - limit)} over' : '${app.cash(limit - spent)} left',
      if (rolled) 'incl. rollover',
      if (cat.excluded) 'not in budget',
    ].join(' · ');
    return PanelRow(
      onTap: () => openCatSheet(context, cat),
      semantics: '${cat.name}, ${app.cash(spent)} spent${limit > 0 ? ' of ${app.cash(limit)}' : ''}',
      lead: CatBadge(cat, size: 36),
      title: cat.name,
      sub: sub.isEmpty ? null : sub,
      trailing: Text.rich(
        TextSpan(children: [
          TextSpan(text: app.cash(spent), style: TextStyle(color: over ? kRed : pal.text)),
          if (limit > 0) TextSpan(text: ' / ${app.cash(limit)}', style: TextStyle(color: pal.sub)),
        ]),
        style: _num(18, pal.text),
      ),
      below: MoneyBar(frac: limit > 0 ? spent / limit : (top <= 0 ? 0 : spent / top), color: over ? kRed : col, height: 5),
    );
  }
}

// ---------------------------------------------------------------------------
// Spending pace

List<Widget> _pace(BuildContext context, MoneyCtx c, bool first) {
  final daily = dailySpend(c.m, c.month);
  final cum = cumulative(daily);
  if (cum.isEmpty || (cum.last == 0 && c.st.budget == 0)) return const [];
  final last = cumulative(dailySpend(c.m, addMonths(c.month, -1)));
  final i = c.todayIndex;
  String? status;
  if (c.st.budget > 0) {
    final n = cum.length;
    final at = i >= 0 ? i : n - 1;
    final even = (c.st.budget * (at + 1) / n).round();
    final diff = cum[at] - even;
    status = diff.abs() < c.st.budget * .02 ? 'ON PACE' : (diff > 0 ? '${c.cash(diff, compact: true)} AHEAD OF PACE' : '${c.cash(-diff, compact: true)} UNDER PACE');
  }
  return [
    GroupHead('SPENDING PACE', first: first, trailing: status == null ? null : HeadSum(status, color: status.contains('AHEAD') ? const Color(0xFFFF8A00) : null)),
    _pad(PaceChart(cum: cum, lastCum: last, budget: c.st.budget, today: i, money: (v) => c.cash(v, compact: true))),
    _pad(
      Row(children: [
        _Key(color: kYellow, label: monthLong(c.month).substring(0, 3).toUpperCase()),
        const SizedBox(width: 16),
        _Key(color: Pal.of(context).sub.withValues(alpha: .5), label: monthLong(addMonths(c.month, -1)).substring(0, 3).toUpperCase()),
        if (c.st.budget > 0) ...[const SizedBox(width: 16), _Key(color: Pal.of(context).sub, label: 'EVEN PACE', dashed: true)],
      ]),
      top: 0,
      bottom: 6,
    ),
  ];
}

class _Key extends StatelessWidget {
  final Color color;
  final String label;
  final bool dashed;
  const _Key({required this.color, required this.label, this.dashed = false});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 14,
          height: 3,
          decoration: BoxDecoration(
            color: dashed ? null : color,
            borderRadius: BorderRadius.circular(2),
            gradient: dashed ? LinearGradient(colors: [color, color, Colors.transparent, Colors.transparent, color, color], stops: const [0, .35, .35, .65, .65, 1]) : null,
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: cond(12, FontWeight.w800, ls: .08, color: Pal.of(context).sub)),
      ]);
}

// ---------------------------------------------------------------------------
// Accounts

List<Widget> _accounts(BuildContext context, MoneyCtx c, bool first) {
  final live = c.m.liveAccounts.toList();
  if (live.isEmpty) {
    return [
      GroupHead('ACCOUNTS', first: first),
      MoneyHint('Add your bank accounts, cards and cash to see balances and net worth.', action: 'ADD', onAction: () => openAccountSheet(context, null)),
    ];
  }
  return [
    GroupHead('ACCOUNTS', count: live.length, first: first, trailing: HeadAction('ALL', () => openAccountsList(context))),
    _AccountCards(c: c, accounts: live),
  ];
}

class _AccountCards extends StatefulWidget {
  final MoneyCtx c;
  final List<Account> accounts;
  const _AccountCards({required this.c, required this.accounts});
  @override
  State<_AccountCards> createState() => _AccountCardsState();
}

class _AccountCardsState extends State<_AccountCards> {
  // keepPage off: the strip sits inside the Money list, and restoring would pick up the
  // list's scroll offset (far past the strip's end) and jump to the last card.
  final _ctl = PageController(viewportFraction: .78, keepPage: false);

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final net = netWorth(c.m, c.bal);
    final from = c.month, to = c.current ? c.now + 1 : c.to;
    final count = widget.accounts.length + 1;
    return Column(children: [
      SizedBox(
        height: 138,
        child: PageView.builder(
          key: const PageStorageKey('account-cards'),
          controller: _ctl,
          padEnds: false,
          itemCount: count,
          onPageChanged: (_) => tick(),
          itemBuilder: (context, i) {
            final left = i == 0 ? 20.0 : 6.0, right = i == count - 1 ? 20.0 : 6.0;
            if (i == 0) {
              final change = widget.accounts.fold(0, (a, x) => a + acctChange(c.m, x.id, from, to));
              return Padding(
                padding: EdgeInsets.fromLTRB(left, 4, right, 8),
                child: _Card(
                  color: kYellow,
                  label: 'NET WORTH',
                  title: c.app.netCash(net),
                  sub: '${widget.accounts.length} account${widget.accounts.length == 1 ? '' : 's'}',
                  change: change,
                  money: c.cash,
                  onTap: () => openAccountsList(context),
                  hero: true,
                ),
              );
            }
            final a = widget.accounts[i - 1];
            return Padding(
              padding: EdgeInsets.fromLTRB(left, 4, right, 8),
              child: _Card(
                color: hexColor(a.color),
                label: '${kAcctEmoji[a.type]}  ${kAcctTypes[a.type]!.toUpperCase()}${c.m.defaultAcct == a.id ? ' · DEFAULT' : ''}',
                title: c.cash(c.bal[a.id] ?? 0),
                sub: a.name,
                change: acctChange(c.m, a.id, from, to),
                money: c.cash,
                onTap: () => openAccountSheet(context, a),
              ),
            );
          },
        ),
      ),
      if (count > 1)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          // Follows the scroll itself, so a restored position shows the right dot.
          child: AnimatedBuilder(
            animation: _ctl,
            builder: (context, _) {
              final page = _ctl.hasClients && _ctl.position.hasContentDimensions
                  ? (_ctl.position.pixels >= _ctl.position.maxScrollExtent - 1 ? count - 1 : (_ctl.page ?? 0).round())
                  : 0;
              return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 0; i < count; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == page ? 16 : 6,
                    height: 6,
                    decoration: BoxDecoration(color: i == page ? kYellow : Pal.of(context).rule, borderRadius: BorderRadius.circular(3)),
                  ),
              ]);
            },
          ),
        ),
    ]);
  }
}

class _Card extends StatelessWidget {
  final Color color;
  final String label, title, sub;
  final int change;
  final String Function(int, {bool sign, bool compact}) money;
  final VoidCallback onTap;
  final bool hero;
  const _Card({required this.color, required this.label, required this.title, required this.sub, required this.change, required this.money, required this.onTap, this.hero = false});
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final fg = hero ? Colors.black : pal.text;
    final dim = hero ? Colors.black.withValues(alpha: .6) : pal.sub;
    return Semantics(
      button: true,
      label: '$label $sub $title',
      excludeSemantics: true,
      child: Pressable(
        scale: .97,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          decoration: BoxDecoration(
            color: hero ? kYellow : pal.rowNext,
            borderRadius: BorderRadius.circular(16),
            border: hero ? null : Border.all(color: color, width: 2),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: cond(12, FontWeight.w800, ls: .1, color: dim)),
            const Spacer(),
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(title, style: _num(34, fg).copyWith(height: 1))),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(child: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: inter(13, FontWeight.w700, color: dim))),
              if (change != 0)
                Text('${money(change, sign: true, compact: true)} THIS MO',
                    style: cond(12, FontWeight.w800, ls: .04, color: hero ? Colors.black.withValues(alpha: .7) : (change > 0 ? kIncomeGreen : kRed))),
            ]),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Trip & event budgets

List<Widget> _plans(BuildContext context, MoneyCtx c, bool first) {
  final list = shownPlans(c.m, c.now);
  final out = <Widget>[GroupHead('TRIPS & EVENTS', first: first, trailing: HeadAction('ADD', () => openPlanSheet(context, null)))];
  if (list.isEmpty) {
    out.add(MoneyHint(c.m.plans.isEmpty ? 'Set a budget for a trip, a festival or a project, separate from the month.' : 'No pinned budgets. Pin one to keep it here.'));
    return out;
  }
  for (final p in list) {
    out.add(PlanRow(key: ValueKey('plan-${p.id}'), plan: p, c: c));
  }
  return out;
}

class PlanRow extends StatelessWidget {
  final Plan plan;
  final MoneyCtx c;
  const PlanRow({super.key, required this.plan, required this.c});
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final p = plan;
    final spent = planSpent(c.m, p, c.now);
    final (from, to) = planWindow(p, c.now);
    final state = planState(p, c.now);
    final over = p.amount > 0 && spent > p.amount;
    String when;
    if (p.period == 'custom') {
      when = to == 0 ? 'From ${monthDay(from)}' : rangeLabel(from, to - 1);
    } else {
      when = '${const {'daily': 'Today', 'weekly': 'This week', 'monthly': 'This month', 'yearly': 'This year'}[p.period]} · ${rangeLabel(from, to - 1)}';
    }
    final daysLeft = to == 0 ? 0 : ((to - sod(c.now)) / kDay).round();
    final sub = [
      when,
      if (state == 'upcoming') 'starts ${dueLabel(dstr(from), c.now).toLowerCase()}',
      if (state == 'ended') 'ended',
      if (state == 'live' && p.amount > 0 && !over && daysLeft > 0) '${c.cash((p.amount - spent) ~/ daysLeft)}/day left',
    ].join(' · ');
    return PanelRow(
      onTap: () => openPlanSheet(context, p),
      semantics: '${p.name}, ${c.cash(spent)} of ${c.cash(p.amount)}',
      lead: EmojiBadge(p.emoji, p.color, size: 36),
      title: p.name,
      sub: sub,
      trailing: Text.rich(
        TextSpan(children: [
          TextSpan(text: c.cash(spent), style: TextStyle(color: over ? kRed : pal.text)),
          if (p.amount > 0) TextSpan(text: ' / ${c.cash(p.amount)}', style: TextStyle(color: pal.sub)),
        ]),
        style: _num(18, pal.text),
      ),
      below: MoneyBar(
        frac: p.amount > 0 ? spent / p.amount : 0,
        color: over ? kRed : hexColor(p.color),
        height: 5,
        mark: state == 'live' && to != 0 ? (c.now - from) / (to - from) : null,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Savings goals

List<Widget> _goals(BuildContext context, MoneyCtx c, bool first) {
  final list = c.m.goals.where((g) => g.kind == 'save' && !g.archived).toList();
  final out = <Widget>[GroupHead('GOALS', count: list.isEmpty ? null : list.length, first: first, trailing: HeadAction('ADD', () => openGoalSheet(context, null)))];
  if (list.isEmpty) {
    out.add(const MoneyHint('Save toward a trip, a laptop or an emergency fund, and see how much to put aside each month.'));
    return out;
  }
  for (final g in list) {
    out.add(GoalRow(key: ValueKey('goal-${g.id}'), goal: g, c: c));
  }
  return out;
}

class GoalRow extends StatelessWidget {
  final Goal goal;
  final MoneyCtx c;
  const GoalRow({super.key, required this.goal, required this.c});
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final g = goal;
    final saved = goalAmount(c.m, g);
    final done = g.target > 0 && saved >= g.target;
    final per = perMonthToGoal(c.m, g, c.now);
    final sub = done
        ? 'Goal reached 🎉'
        : [
            if (g.target > 0) '${c.cash(g.target - saved)} to go',
            if (per > 0) '${c.cash(per)}/month to reach it by ${monthDay(g.end)}',
            if (g.end > 0 && g.end <= c.now) 'target date passed',
          ].join(' · ');
    return PanelRow(
      onTap: () => openGoalSheet(context, g),
      semantics: '${g.name}, ${c.cash(saved)} saved${g.target > 0 ? ' of ${c.cash(g.target)}' : ''}',
      lead: EmojiBadge(g.emoji, g.color, size: 36),
      title: g.name,
      sub: sub.isEmpty ? null : sub,
      trailing: Text.rich(
        TextSpan(children: [
          TextSpan(text: c.cash(saved), style: TextStyle(color: done ? kIncomeGreen : pal.text)),
          if (g.target > 0) TextSpan(text: ' / ${c.cash(g.target)}', style: TextStyle(color: pal.sub)),
        ]),
        style: _num(18, pal.text),
      ),
      below: g.target > 0 ? MoneyBar(frac: saved / g.target, color: done ? kIncomeGreen : hexColor(g.color), height: 5) : null,
    );
  }
}

// ---------------------------------------------------------------------------
// Loans

List<Widget> _loans(BuildContext context, MoneyCtx c, bool first) {
  final open = c.m.goals.where((g) => g.isLoan && !g.archived).toList();
  final owed = open.where((g) => g.kind == 'lent').fold(0, (a, g) => a + goalAmount(c.m, g));
  final owe = open.where((g) => g.kind == 'borrowed').fold(0, (a, g) => a + goalAmount(c.m, g));
  final out = <Widget>[GroupHead('LOANS', count: open.isEmpty ? null : open.length, first: first, trailing: HeadAction('ADD', () => openLoanSheet(context, null)))];
  if (open.isEmpty) {
    out.add(const MoneyHint('Keep track of money you lent or borrowed, and long-term loans like an EMI.'));
    return out;
  }
  out.add(_pad(
    Row(children: [
      Expanded(child: _Stat(label: 'YOU’RE OWED', value: c.cash(owed), color: owed > 0 ? kIncomeGreen : null)),
      Expanded(child: _Stat(label: 'YOU OWE', value: c.cash(owe), color: owe > 0 ? kRed : null)),
    ]),
    top: 0,
  ));
  final short = open.where((g) => !g.longTerm).toList(), long = open.where((g) => g.longTerm).toList();
  for (final g in short) {
    out.add(LoanRow(key: ValueKey('loan-${g.id}'), loan: g, c: c));
  }
  if (long.isNotEmpty) {
    out.add(const GroupHead('LONG-TERM'));
    for (final g in long) {
      out.add(LoanRow(key: ValueKey('loan-${g.id}'), loan: g, c: c));
    }
  }
  return out;
}

class _Stat extends StatelessWidget {
  final String label, value;
  final Color? color;
  const _Stat({required this.label, required this.value, this.color});
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: cond(12, FontWeight.w800, ls: .1, color: pal.sub)),
      const SizedBox(height: 2),
      Text(value, style: _num(26, color ?? pal.text)),
    ]);
  }
}

class LoanRow extends StatelessWidget {
  final Goal loan;
  final MoneyCtx c;
  const LoanRow({super.key, required this.loan, required this.c});
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final g = loan;
    final left = goalAmount(c.m, g), total = loanTotal(c.m, g);
    final paid = math.max(0, total - left);
    final lent = g.kind == 'lent';
    final sub = [
      lent ? 'You lent' : 'You borrowed',
      if (total > 0) '${c.cash(paid)} of ${c.cash(total)} back',
      if (g.end > 0) (g.end < c.now ? 'was due ${monthDay(g.end)}' : 'due ${monthDay(g.end)}'),
    ].join(' · ');
    return PanelRow(
      onTap: () => openLoanSheet(context, g),
      semantics: '${g.name}, ${lent ? 'owes you' : 'you owe'} ${c.cash(left)}',
      lead: EmojiBadge(g.emoji, g.color, size: 36),
      title: g.name,
      sub: sub,
      trailing: Text(left <= 0 ? 'SETTLED' : c.cash(left), style: _num(left <= 0 ? 15 : 20, left <= 0 ? kIncomeGreen : (lent ? kIncomeGreen : pal.text))),
      below: total > 0 ? MoneyBar(frac: paid / total, color: hexColor(g.color), height: 5) : null,
    );
  }
}

// ---------------------------------------------------------------------------
// Income vs spending

List<Widget> _cashflow(BuildContext context, MoneyCtx c, bool first) {
  final months = cashflow(c.m, c.month, 6);
  if (months.every((x) => x.income == 0 && x.spent == 0)) return const [];
  final net = months.last.net;
  return [
    GroupHead('INCOME VS SPENDING', first: first, trailing: HeadSum('${monthLong(c.month).substring(0, 3).toUpperCase()} ${c.cash(net, sign: true, compact: true)}', color: net >= 0 ? kIncomeGreen : kRed)),
    _pad(FlowChart(months: months, selected: c.month, money: (v) => c.cash(v, sign: true, compact: true), onTap: (m0) {
      tick();
      c.app.setMoneyMonth(m0);
    })),
    _pad(
      Row(children: [
        const _Key(color: kIncomeGreen, label: 'IN'),
        const SizedBox(width: 16),
        _Key(color: Pal.of(context).text.withValues(alpha: .82), label: 'OUT'),
        const Spacer(),
        Text('TAP A MONTH TO OPEN IT', style: cond(12, FontWeight.w800, ls: .08, color: Pal.of(context).placeholder)),
      ]),
      top: 0,
      bottom: 6,
    ),
  ];
}

// ---------------------------------------------------------------------------
// Spending by category

List<Widget> _breakdown(BuildContext context, MoneyCtx c, bool first) {
  final byCat = c.st.byCat.entries.where((e) => e.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));
  if (byCat.isEmpty) return const [];
  final total = byCat.fold(0, (a, e) => a + e.value);
  const top = 6;
  final shown = byCat.take(top).toList();
  final rest = byCat.skip(top).fold(0, (a, e) => a + e.value);
  final pal = Pal.of(context);
  return [
    GroupHead('WHERE IT WENT', first: first, trailing: HeadSum(c.cash(total))),
    _pad(ShareBar(parts: [for (final e in shown) (hexColor(c.m.catOf(e.key).color), e.value), if (rest > 0) (pal.placeholder, rest)]), top: 2, bottom: 8),
    for (final e in shown) _ShareRow(cat: c.m.catOf(e.key), amount: e.value, total: total, c: c),
    if (rest > 0) _ShareRow(cat: MCat(id: '_rest', name: '${byCat.length - top} more', emoji: '…', color: '#71717a'), amount: rest, total: total, c: c),
  ];
}

class _ShareRow extends StatelessWidget {
  final MCat cat;
  final int amount, total;
  final MoneyCtx c;
  const _ShareRow({required this.cat, required this.amount, required this.total, required this.c});
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final pct = total <= 0 ? 0 : (amount * 100 / total).round();
    return Pressable(
      scale: .985,
      onTap: cat.id == '_rest' ? null : () => openTxnList(context, cat: cat.id, month: c.month),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 7, 20, 7),
        child: Row(children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: hexColor(cat.color), shape: BoxShape.circle)),
          const SizedBox(width: 12),
          Text(cat.emoji, style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 8),
          Expanded(child: Text(cat.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: inter(15, FontWeight.w600, color: pal.text))),
          SizedBox(width: 44, child: Text('$pct%', textAlign: TextAlign.right, style: cond(16, FontWeight.w800, color: pal.sub))),
          SizedBox(width: 96, child: Text(c.cash(amount), textAlign: TextAlign.right, style: _num(18, pal.text))),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Daily moons

List<Widget> _moons(BuildContext context, MoneyCtx c, bool first) {
  final daily = dailySpend(c.m, c.month);
  final peak = daily.fold(0, math.max);
  if (peak == 0 && !c.current) return const [];
  final big = daily.indexOf(peak);
  return [
    GroupHead('DAILY MOONS', first: first, trailing: peak > 0 ? HeadSum('FULLEST ${monthShort(c.month).toUpperCase()} ${big + 1} · ${c.cash(peak, compact: true)}') : null),
    _pad(
      MoonGrid(
        daily: daily,
        month0: c.month,
        today: c.todayIndex,
        onTap: (d) {
          final day0 = DateTime.fromMillisecondsSinceEpoch(c.month).add(Duration(days: d)).millisecondsSinceEpoch;
          final n = c.m.txns.where((t) => t.isSpend && dstr(t.at) == dstr(day0)).length;
          c.app.showToast('${weekdayShort(day0)}, ${monthDay(day0)} · ${daily[d] == 0 ? 'nothing spent' : '${c.cash(daily[d])} · $n spend${n == 1 ? '' : 's'}'}');
        },
      ),
      top: 2,
    ),
  ];
}

// ---------------------------------------------------------------------------
// Net worth

List<Widget> _networth(BuildContext context, MoneyCtx c, bool first) {
  if (c.m.accounts.isEmpty) return const [];
  return [
    GroupHead('NET WORTH', first: first, trailing: HeadAction('ACCOUNTS', () => openAccountsList(context))),
    _pad(c.app.s.settings.hideNet ? const HiddenNetCard() : NetWorthCard(m: c.m, money: c.cash), top: 0, bottom: 14),
  ];
}

/// Stands in for the net-worth graph while net worth is hidden.
class HiddenNetCard extends StatelessWidget {
  const HiddenNetCard({super.key});
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: pal.rule, width: 1.4)),
      child: Row(children: [
        Expanded(child: Text('Hidden. Tap the eye to show it.', style: inter(14, FontWeight.w500, color: pal.sub))),
        NetEye(hidden: true, color: pal.sub),
      ]),
    );
  }
}
// ---------------------------------------------------------------------------
// This month's transactions

List<Widget> _activity(BuildContext context, MoneyCtx c, bool first) {
  final from = c.month, to = c.to;
  final txns = c.m.txns.where((t) => t.at >= from && t.at < to).toList()..sort((a, b) => b.at.compareTo(a.at));
  final out = <Widget>[
    GroupHead('TRANSACTIONS', count: txns.isEmpty ? null : txns.length, first: first, trailing: HeadAction('SEARCH', () => openTxnList(context, month: c.month))),
  ];
  if (txns.isEmpty) {
    out.add(MoneyHint(c.current ? 'Nothing logged yet. Tap + and type “Lunch 180”.' : 'Nothing logged this month.'));
    return out;
  }
  String? lastDay;
  for (final t in txns.take(120)) {
    final d = dstr(t.at);
    if (d != lastDay) {
      lastDay = d;
      final daySum = txns.where((x) => dstr(x.at) == d).fold(0, (a, x) => a + spendOf(x, c.m));
      out.add(DayLine(label: dueLabel(d, c.now).toUpperCase(), total: daySum > 0 ? c.cash(daySum) : ''));
    }
    out.add(TxnRow(key: ValueKey(t.id), txn: t));
  }
  if (txns.length > 120) out.add(_SeeAll('SEE ALL ${txns.length}', () => openTxnList(context, month: c.month)));
  return out;
}

class DayLine extends StatelessWidget {
  final String label, total;
  const DayLine({super.key, required this.label, required this.total});
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.rule))),
      child: Row(children: [
        Text(label, style: cond(13, FontWeight.w800, ls: .1, color: pal.sub)),
        const Spacer(),
        Text(total, style: cond(13, FontWeight.w800, ls: .1, color: pal.sub)),
      ]),
    );
  }
}
