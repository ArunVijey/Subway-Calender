// Money tab: the month at the top (what's left, per day), then the sections
// in the order set under Settings → Money tab. Plus the transaction editor and
// the budget / category sheets.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/store.dart';
import '../core/ledger.dart';
import '../core/money.dart';
import '../core/tasks.dart';
import '../core/util.dart';
import 'board.dart';
import 'haptics.dart';
import 'lines.dart';
import 'money_charts.dart';
import 'money_pages.dart';
import 'money_sections.dart';
import 'motion.dart';
import 'tasks.dart';
import 'theme.dart';
import 'widgets.dart';

class MoneyView extends StatefulWidget {
  const MoneyView({super.key});
  @override
  State<MoneyView> createState() => _MoneyViewState();
}

class _MoneyViewState extends State<MoneyView> with SingleTickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(vsync: this, duration: Entrance.total);
  int? _epoch;
  Offset? _s0, _s1;

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (_epoch != app.boardEpoch) {
      _epoch = app.boardEpoch;
      if (MediaQuery.disableAnimationsOf(context)) {
        _intro.value = 1;
      } else {
        _intro.forward(from: 0);
      }
    }
    final c = MoneyCtx(app);

    final items = <Widget>[];
    var k = 0;
    Widget enter(Widget w) => Entrance(intro: _intro, index: k++, child: w);
    for (final s in c.m.sections) {
      if (!s.on) continue;
      for (final row in kSectionBuilders[s.id]!(context, c, items.isEmpty)) {
        items.add(enter(row));
      }
    }
    items.add(enter(const _Customise()));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MonthHead(month: c.month, current: c.current),
        MoneyHero(c: c),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (d) => _s0 = _s1 = d.globalPosition,
            onHorizontalDragUpdate: (d) => _s1 = d.globalPosition,
            onHorizontalDragEnd: (_) {
              final a = _s0, b = _s1;
              _s0 = _s1 = null;
              if (a == null || b == null) return;
              final dx = b.dx - a.dx, dy = b.dy - a.dy;
              if (dx.abs() > 60 && dx.abs() > dy.abs() * 1.5) {
                buzz();
                app.shiftMonth(dx < 0 ? 1 : -1);
              }
            },
            child: EdgePanel(
              child: ListView(key: PageStorageKey('money-${c.month}'), padding: const EdgeInsets.only(bottom: 120), children: items),
            ),
          ),
        ),
      ],
    );
  }
}

class _Customise extends StatelessWidget {
  const _Customise();
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
      child: Pressable(
        scale: .97,
        onTap: () => openSectionsPage(context),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: pal.rule, width: 1.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.tune, size: 18, color: pal.sub),
              const SizedBox(width: 8),
              Text('ARRANGE THIS PAGE', style: cond(15, FontWeight.w800, ls: .08, color: pal.sub)),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthHead extends StatelessWidget {
  final int month;
  final bool current;
  const _MonthHead({required this.month, required this.current});
  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final year = DateTime.fromMillisecondsSinceEpoch(month).year;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 20, 0, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Semantics(
              button: true,
              label: 'Pick a month',
              child: Pressable(
                scale: .98,
                onTap: () async {
                  final first = app.s.money.txns.fold<int>(nowMs(), (a, t) => t.at < a ? t.at : a);
                  final back = ((monthStart(nowMs()) - monthStart(first)) / (30.44 * kDay)).round().clamp(12, 120);
                  final opts = [for (var i = -back; i <= 1; i++) addMonths(monthStart(nowMs()), i)].reversed.toList();
                  final x = await pickOption<int>(context, 'Month', [
                    for (final o in opts) (o, '${monthLong(o)} ${DateTime.fromMillisecondsSinceEpoch(o).year}'),
                  ], month);
                  if (x != null) app.setMoneyMonth(x);
                },
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  layoutBuilder: (cur, prev) => Stack(alignment: Alignment.topLeft, children: [...prev, ?cur]),
                  child: FittedBox(
                    key: ValueKey(month),
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text.rich(
                      TextSpan(
                        style: cond(50, FontWeight.w800, ls: -.01, height: .95, color: Colors.white),
                        children: [
                          TextSpan(text: monthLong(month).toUpperCase()),
                          TextSpan(
                            text: ' $year',
                            style: const TextStyle(color: Color(0xFF52525B)),
                          ),
                          const WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Padding(
                              padding: EdgeInsets.only(left: 8),
                              child: Opacity(opacity: .8, child: SvgIcon('chev', size: 22)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Row(
            children: [
              AnimatedSwitcher(
                duration: Motion.bouncyDur,
                reverseDuration: const Duration(milliseconds: 180),
                switchInCurve: Motion.bouncy,
                transitionBuilder: (c, a) => FadeTransition(
                  opacity: a,
                  child: ScaleTransition(scale: a.drive(Tween(begin: .6, end: 1)), child: c),
                ),
                child: current
                    ? const SizedBox.shrink(key: ValueKey('now'))
                    : Pressable(
                        key: const ValueKey('back'),
                        onTap: () => app.setMoneyMonth(nowMs()),
                        child: Container(
                          height: 40,
                          margin: const EdgeInsets.only(right: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: kYellow, borderRadius: BorderRadius.circular(20)),
                          child: Text('NOW', style: cond(15, FontWeight.w800, ls: .06, color: Colors.black)),
                        ),
                      ),
              ),
              const GearButton(),
            ],
          ),
        ],
      ),
    );
  }
}

/// Net worth at the top: today's (or the month-end figure for a past month),
/// how it moved this month, and the month's spending beside it.
class MoneyHero extends StatelessWidget {
  final MoneyCtx c;

  /// On the Today tab: an arrow by NET WORTH folds the numbers away (its own
  /// switch), instead of the Money tab's eye that turns them to dots.
  final bool today;
  const MoneyHero({super.key, required this.c, this.today = false});
  @override
  Widget build(BuildContext context) {
    final app = c.app;
    final m = c.m;
    final st = c.st;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final small = cond(15, FontWeight.w800, ls: .06, color: kDim);
    final num = const [FontFeature.tabularFigures()];

    // No accounts yet: spending is the headline, with a way to add one.
    if (m.accounts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SPENT', style: small),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: RollingText(
                      app.cash(st.spent),
                      style: cond(54, FontWeight.w800, ls: -.01, height: .95, color: Colors.white).copyWith(fontFeatures: num),
                      animate: !reduce,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(st.income > 0 ? 'IN ${app.cash(st.income)}' : 'ADD AN ACCOUNT TO SEE NET WORTH', style: small),
                ],
              ),
            ),
            Pressable(
              onTap: () => openAccountSheet(context, null),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                decoration: BoxDecoration(color: kYellow, borderRadius: BorderRadius.circular(20)),
                child: Text('ADD ACCOUNT', style: cond(15, FontWeight.w800, ls: .06, color: Colors.black)),
              ),
            ),
          ],
        ),
      );
    }

    final until = c.current ? null : c.to;
    final bal = until == null ? c.bal : balances(m, until: until);
    final net = netWorth(m, bal, until: until);
    final start = balances(m, until: c.month);
    final change = net - netWorth(m, start, until: c.month);
    final live = m.liveAccounts;
    final assets = live.fold(0, (a, x) => a + math.max(0, bal[x.id] ?? 0));
    final debts = live.fold(0, (a, x) => a + math.min(0, bal[x.id] ?? 0));
    final hasBudget = st.budget > 0;
    final over = hasBudget && st.left < 0;
    final hidden = !today && app.s.settings.hideNet;

    // Today tab, folded: one slim line, the arrow to open it and the month's spending.
    if (today && app.s.settings.foldTodayNet) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          const TodayNetFold(),
          const Spacer(),
          ExcludeSemantics(child: Text('SPENT ', style: small)),
          RollingText(app.cash(st.spent ~/ 100 * 100), style: cond(15, FontWeight.w800, ls: .06, color: over ? kRed : kYellow).copyWith(fontFeatures: num), animate: !reduce),
        ]),
      );
    }

    return Semantics(
      button: true,
      label: hidden
          ? 'Net worth hidden. Spent ${app.cash(st.spent)}.'
          : 'Net worth ${app.cash(net)}, ${app.cash(change, sign: true)} this month. Spent ${app.cash(st.spent)}.',
      // Its texts are summed up in the label; only the eye inside stays a button of its own.
      child: Pressable(
        scale: .99,
        onTap: () => openAccountsList(context),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ExcludeSemantics(child: Text(c.current ? 'NET WORTH' : 'NET WORTH · ${monthShort(c.month).toUpperCase()} END', style: small)),
                            if (today) const TodayNetFold(compact: true) else NetEye(hidden: hidden),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ExcludeSemantics(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: RollingText(
                              hidden ? app.netCash(net) : app.cash(net),
                              style: cond(
                                54,
                                FontWeight.w800,
                                ls: -.01,
                                height: .95,
                                color: net < 0 && !hidden ? kRed : Colors.white,
                              ).copyWith(fontFeatures: num),
                              animate: !reduce,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  ExcludeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('SPENT', style: small),
                        const SizedBox(height: 4),
                        RollingText(
                          app.cash(st.spent ~/ 100 * 100),
                          style: cond(30, FontWeight.w800, color: over ? kRed : kYellow).copyWith(fontFeatures: num),
                          animate: !reduce,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ExcludeSemantics(
                child: Row(
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            if (hidden)
                              const TextSpan(text: '••••')
                            else
                              TextSpan(
                                text: change == 0 ? 'NO CHANGE' : app.cash(change, sign: true, compact: true),
                                style: TextStyle(color: change > 0 ? kIncomeGreen : (change < 0 ? kRed : kDim)),
                              ),
                            TextSpan(text: c.current ? ' THIS MONTH' : ' IN ${monthShort(c.month).toUpperCase()}'),
                            if (debts < 0) TextSpan(text: '  ·  DEBTS ${hidden ? '••••' : app.cash(-debts, compact: true)}'),
                            if (debts == 0 && assets > 0) TextSpan(text: '  ·  ${live.length} ACCOUNT${live.length == 1 ? '' : 'S'}'),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: small,
                      ),
                    ),
                    Text(
                      hasBudget
                          ? (over ? '${app.cash(-st.left)} OVER' : '${app.cash(st.left)} LEFT')
                          : (st.income > 0 ? 'IN ${app.cash(st.income, compact: true)}' : ''),
                      style: small.copyWith(color: over ? kRed : kDim),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Today tab: the arrow by NET WORTH. Folded, it reads "NET WORTH ⌄" and
/// opens the numbers and graph again; open ([compact]), just the arrow.
class TodayNetFold extends StatelessWidget {
  final bool compact;
  const TodayNetFold({super.key, this.compact = false});
  @override
  Widget build(BuildContext context) {
    final open = !context.watch<AppState>().s.settings.foldTodayNet;
    final small = cond(15, FontWeight.w800, ls: .06, color: kDim);
    return Semantics(
      button: true,
      expanded: open,
      label: open ? 'Fold away net worth' : 'Show net worth',
      excludeSemantics: true,
      child: Pressable(
        scale: .9,
        onTap: () {
          tick();
          context.read<AppState>().toggleTodayNet();
        },
        // A bigger tap target than the arrow, without moving the label.
        child: Padding(
          padding: EdgeInsets.fromLTRB(compact ? 8 : 0, 6, 8, 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (!compact) ...[Text('NET WORTH', style: small), const SizedBox(width: 8)],
            AnimatedRotation(
              turns: open ? .5 : 0,
              duration: Motion.snappyDur,
              curve: Motion.snappy,
              child: const SvgIcon('chev', size: 14, color: kDim),
            ),
          ]),
        ),
      ),
    );
  }
}

/// The eye by NET WORTH: hides the amount (dots) or shows it again.
class NetEye extends StatelessWidget {
  final bool hidden;
  final Color color;
  const NetEye({super.key, required this.hidden, this.color = kDim});
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: hidden ? 'Show net worth' : 'Hide net worth',
    excludeSemantics: true,
    child: Pressable(
      scale: .8,
      onTap: () {
        tick();
        context.read<AppState>().toggleHideNet();
      },
      // A bigger tap target than the icon, without moving the label.
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: AnimatedSwitcher(
          duration: Motion.snappyDur,
          transitionBuilder: (c, a) => FadeTransition(
            opacity: a,
            child: ScaleTransition(scale: a.drive(Tween(begin: .7, end: 1)), child: c),
          ),
          child: Icon(hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined, key: ValueKey(hidden), size: 17, color: color),
        ),
      ),
    ),
  );
}

/// Emoji in a soft circle of the category color.
class CatBadge extends StatelessWidget {
  final MCat cat;
  final double size;
  const CatBadge(this.cat, {super.key, this.size = 40});
  @override
  Widget build(BuildContext context) => EmojiBadge(cat.emoji, cat.color, size: size);
}

// ---------------------------------------------------------------------------
// A transaction on the panel.

class TxnRow extends StatelessWidget {
  final Txn txn;

  /// Show the date instead of just the time (lists that span days).
  final bool showDate;
  const TxnRow({super.key, required this.txn, this.showDate = false});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final pal = Pal.of(context);
    final m = app.s.money;
    final t = txn;
    final cat = m.catOf(t.cat);
    final acct = m.acctOf(t.acct), to = m.acctOf(t.to);
    final goal = m.goalOf(t.goal);
    final plan = m.planOf(t.plan);

    final Widget lead = switch (t.type) {
      'transfer' => const EmojiBadge('⇄', '#71717a', size: 38),
      'adjust' => const EmojiBadge('⚖️', '#71717a', size: 38),
      'save' || 'unsave' || 'lent' || 'borrowed' || 'repay' => EmojiBadge(goal?.emoji ?? '🎯', goal?.color ?? '#71717a', size: 38),
      _ => CatBadge(cat, size: 38),
    };
    final kind = switch (t.type) {
      'transfer' => '${acct?.name ?? 'Outside'} → ${to?.name ?? 'Outside'}',
      'adjust' => 'Balance update',
      'save' => 'Into ${goal?.name ?? 'goal'}',
      'unsave' => 'Out of ${goal?.name ?? 'goal'}',
      'lent' => 'Lent · ${goal?.name ?? ''}',
      'borrowed' => 'Borrowed · ${goal?.name ?? ''}',
      'repay' => goal?.kind == 'borrowed' ? 'Repaid · ${goal?.name ?? ''}' : 'Paid back · ${goal?.name ?? ''}',
      'refund' => 'Refund · ${cat.name}',
      _ => cat.name,
    };
    final meta = [
      kind,
      if (acct != null && t.type != 'transfer') acct.name,
      showDate ? '${monthDay(t.at)}, ${fmtT(t.at, use24h: app.use24h)}' : fmtT(t.at, use24h: app.use24h),
      if (plan != null) '${plan.emoji} ${plan.name}',
      if (t.task != null) 'bill',
      for (final g in t.tags) '#$g',
      if (t.note.isNotEmpty) t.note,
    ].join('  ·  ');
    final title = t.title.isNotEmpty
        ? t.title
        : switch (t.type) {
            'transfer' => 'Transfer',
            'adjust' => 'Balance update',
            'save' || 'unsave' || 'lent' || 'borrowed' || 'repay' => goal?.name ?? 'Goal',
            _ => cat.name,
          };

    final plus = t.type == 'income' || t.type == 'refund';
    final neutral = t.isMove;
    // Moves show which way the money went for the account: back in gets a +.
    final back = t.type == 'unsave' || t.type == 'borrowed' || (t.type == 'repay' && goal?.kind != 'borrowed');
    final amountText = t.type == 'adjust' || plus || back ? app.cash(t.amount, sign: true) : app.cash(t.amount);
    final amountColor = plus ? kIncomeGreen : (neutral ? pal.sub : pal.text);

    return Semantics(
      button: true,
      label: '$title, $amountText${t.review ? ', to review' : ''}',
      excludeSemantics: true,
      child: Pressable(
        scale: .985,
        onTap: () => openTxnSheet(context, t),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          decoration: BoxDecoration(
            color: pal.row,
            border: Border(bottom: BorderSide(color: pal.rule)),
          ),
          child: Row(
            children: [
              lead,
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (t.review)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(right: 7),
                            decoration: BoxDecoration(color: pal.light ? const Color(0xFFD97706) : kYellow, shape: BoxShape.circle),
                          ),
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: cond(
                              22,
                              FontWeight.w700,
                              height: 1.1,
                              color: t.excluded ? pal.sub : pal.text,
                            ).copyWith(decoration: t.excluded ? TextDecoration.lineThrough : null, decorationColor: pal.sub),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: inter(13, FontWeight.w600, color: pal.sub),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                amountText,
                style: cond(25, FontWeight.w800, color: amountColor).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Transaction editor.

void openTxnSheet(
  BuildContext context,
  Txn? txn, {
  String? title,
  int? amount,
  String? cat,
  bool income = false,
  int? at,
  String? type,
  String? acct,
  String? plan,
}) {
  final app = context.read<AppState>();
  final m = app.s.money;
  final ty = type ?? (income ? 'income' : 'spend');
  final t =
      txn?.copy() ??
      Txn(
        id: uid(),
        title: title ?? '',
        cat: cat ?? (ty == 'income' ? (matchMCat(m, title ?? '', income: true) ?? m.fallbackIncome) : m.fallbackCat),
        at: at ?? nowMs(),
        amount: amount ?? 0,
        type: ty,
        acct: acct ?? m.newAcct,
        plan: plan ?? '',
      );
  showSheet<void>(
    context,
    (_) => ChangeNotifierProvider.value(
      value: app,
      child: _TxnSheet(t, isNew: txn == null),
    ),
  );
}

class _TxnSheet extends StatefulWidget {
  final Txn t;
  final bool isNew;
  const _TxnSheet(this.t, {required this.isNew});
  @override
  State<_TxnSheet> createState() => _TxnSheetState();
}

class _TxnSheetState extends State<_TxnSheet> {
  late final AppState app = context.read<AppState>();
  late Txn t = widget.t;
  late bool isNew = widget.isNew;
  late final _amount = TextEditingController(text: t.amount != 0 ? plainAmount(t.amount.abs()) : '');
  late final _title = TextEditingController(text: t.title);
  late final _note = TextEditingController(text: t.note);
  late final _tags = TextEditingController(text: t.tags.join(', '));
  late bool _neg = t.type == 'adjust' && t.amount < 0;
  bool _catTouched = false;
  int _added = 0;

  static const _main = {'spend', 'refund', 'income', 'transfer'};

  @override
  void initState() {
    super.initState();
    _catTouched = !isNew;
    _title.addListener(() {
      if (_catTouched || !(t.isSpend || t.income)) return;
      final c = matchMCat(app.s.money, _title.text, income: t.income);
      if (c != null && c != t.cat) setState(() => t.cat = c);
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    _title.dispose();
    _note.dispose();
    _tags.dispose();
    super.dispose();
  }

  void _setType(String ty) {
    final m = app.s.money;
    setState(() {
      t.type = ty;
      if (ty == 'income' && !m.catOf(t.cat).income) t.cat = matchMCat(m, _title.text, income: true) ?? m.fallbackIncome;
      if ((ty == 'spend' || ty == 'refund') && m.catOf(t.cat).income) t.cat = matchMCat(m, _title.text) ?? m.fallbackCat;
      if (ty == 'transfer') {
        final live = m.liveAccounts.toList();
        if (t.acct.isEmpty && live.isNotEmpty) t.acct = live.first.id;
        if (t.to.isEmpty || t.to == t.acct) t.to = live.where((a) => a.id != t.acct).firstOrNull?.id ?? '';
      }
    });
  }

  /// Reads the form into [t]; null with a toast when something's missing.
  Txn? _read() {
    final a = parseAmount(_amount.text);
    if (a == null || a <= 0) {
      app.showToast('Enter an amount');
      return null;
    }
    if (t.type == 'transfer') {
      if (t.acct.isEmpty && t.to.isEmpty) {
        app.showToast('Pick the accounts');
        return null;
      }
      if (t.acct == t.to) {
        app.showToast('Pick two different accounts');
        return null;
      }
    }
    return t
      ..amount = t.type == 'adjust' && _neg ? -a : a
      ..title = _title.text.trim()
      ..note = _note.text.trim()
      ..tags = {
        for (final g in _tags.text.split(RegExp(r'[,\s]+')))
          if (g.trim().isNotEmpty) g.trim().replaceFirst(RegExp('^#'), '').toLowerCase(),
      }.toList();
  }

  void _save({bool reviewed = false}) {
    final x = _read();
    if (x == null) return;
    if (reviewed) x.review = false;
    Navigator.pop(context);
    app.saveTxn(x);
  }

  /// Saves and starts a fresh entry with the same kind, account and day.
  void _saveAndNew() {
    final x = _read();
    if (x == null) return;
    app.saveTxn(x);
    setState(() {
      _added++;
      t = Txn(
        id: uid(),
        title: '',
        cat: x.isSpend ? app.s.money.fallbackCat : x.cat,
        at: x.at,
        amount: 0,
        type: x.type,
        acct: x.acct,
        to: x.to,
        plan: x.plan,
        tags: List.of(x.tags),
      );
      isNew = true;
      _catTouched = false;
      _amount.clear();
      _title.clear();
      _note.clear();
    });
  }

  Future<void> _pickAcct({required bool dest}) async {
    final m = app.s.money;
    final cur = dest ? t.to : t.acct;
    final opts = <(String, String)>[
      for (final a in m.accounts)
        if (!a.archived || a.id == cur) (a.id, '${kAcctEmoji[a.type]}  ${a.name}'),
      ('', t.type == 'transfer' ? 'Outside (not tracked)' : 'No account'),
    ];
    final x = await pickOption<String>(context, dest ? 'To' : (t.type == 'transfer' ? 'From' : 'Account'), opts, cur);
    if (x == null) return;
    setState(() => dest ? t.to = x : t.acct = x);
  }

  Future<void> _pickPlan() async {
    final m = app.s.money;
    final opts = <(String, String)>[
      for (final p in m.plans)
        if ((!p.archived && p.mode == 'added') || p.id == t.plan) (p.id, '${p.emoji}  ${p.name}'),
      ('', 'None'),
    ];
    final x = await pickOption<String>(context, 'Trip or event', opts, t.plan);
    if (x != null) setState(() => t.plan = x);
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final m = app.s.money;
    final dt = DateTime.fromMillisecondsSinceEpoch(t.at);
    final main = _main.contains(t.type);
    final hasAccts = m.accounts.isNotEmpty;
    final canTransfer = m.liveAccounts.length >= 2 || t.type == 'transfer';
    final green = t.type == 'income' || t.type == 'refund';

    Widget chip(String text, VoidCallback onTap) => Pressable(
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .55),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(color: pal.field, borderRadius: BorderRadius.circular(8)),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: inter(15, FontWeight.w500, color: pal.ink),
        ),
      ),
    );
    Widget fr(String label, Widget control) => Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: pal.panelRule)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: inter(16, FontWeight.w500, color: pal.rowLabel)),
          ),
          control,
        ],
      ),
    );
    String acctName(String id, {String none = 'None'}) {
      final a = m.acctOf(id);
      return a == null ? none : '${kAcctEmoji[a.type]}  ${a.name}';
    }

    final head = switch (t.type) {
      'adjust' => 'Balance update',
      'save' => 'Into goal',
      'unsave' => 'Out of goal',
      'lent' => 'Money lent',
      'borrowed' => 'Money borrowed',
      'repay' => 'Repayment',
      'transfer' => isNew ? 'Log transfer' : 'Transfer',
      'income' => isNew ? 'Log income' : 'Income',
      'refund' => isNew ? 'Log refund' : 'Refund',
      _ => isNew ? 'Log spend' : 'Spend',
    };
    final cats = t.income ? m.cats.where((c) => c.income && (!c.archived || c.id == t.cat)) : m.cats.where((c) => !c.income && (!c.archived || c.id == t.cat));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHead(_added > 0 ? '$head · ${_added + 1}' : head),
        if (main)
          Center(
            child: Segmented<String>(
              options: [('spend', 'SPEND'), ('income', 'INCOME'), if (canTransfer) ('transfer', 'TRANSFER')],
              value: t.type == 'refund' ? 'spend' : t.type,
              onChanged: _setType,
              track: pal.field,
              thumb: pal.light ? const Color(0xFF111111) : Colors.white,
              on: pal.light ? Colors.white : Colors.black,
              off: pal.label,
              style: cond(14, FontWeight.w800, ls: .08),
              segWidth: canTransfer ? 92 : 104,
            ),
          ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            if (t.type == 'adjust')
              Pressable(
                onTap: () => setState(() => _neg = !_neg),
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(_neg ? '−' : '+', style: cond(44, FontWeight.w800, color: _neg ? kRed : kIncomeGreen)),
                ),
              ),
            Text(m.currency.trim(), style: cond(44, FontWeight.w800, color: pal.label)),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: _amount,
                autofocus: isNew && t.amount == 0,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: cond(52, FontWeight.w800, color: green ? kIncomeGreen : pal.ink).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                cursorColor: kYellow,
                decoration: InputDecoration(
                  hintText: '0',
                  hintStyle: cond(52, FontWeight.w800, color: pal.placeholder),
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
            if (t.type == 'spend' || t.type == 'refund')
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Semantics(
                  toggled: t.type == 'refund',
                  label: 'Refund',
                  child: Pressable(
                    onTap: () => setState(() => t.type = t.type == 'refund' ? 'spend' : 'refund'),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 11),
                      decoration: BoxDecoration(color: t.type == 'refund' ? kIncomeGreen : pal.field, borderRadius: BorderRadius.circular(16)),
                      child: Text('REFUND', style: cond(13, FontWeight.w800, ls: .08, color: t.type == 'refund' ? Colors.black : pal.label)),
                    ),
                  ),
                ),
              ),
          ],
        ),
        SheetField(
          controller: _title,
          hint: switch (t.type) {
            'income' => 'From (salary, refund…)',
            'refund' => 'What came back? (Amazon return…)',
            'transfer' => 'What for? (card bill, savings…)',
            _ => 'What for? (lunch, metro…)',
          },
        ),
        if (t.isSpend || t.income) ...[
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: Text('CATEGORY', style: inter(11, FontWeight.w800, ls: .1, color: pal.label)),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in cats)
                Semantics(
                  button: true,
                  selected: c.id == t.cat,
                  label: c.name,
                  excludeSemantics: true,
                  child: Pressable(
                    onTap: () {
                      tick();
                      setState(() {
                        t.cat = c.id;
                        _catTouched = true;
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      decoration: BoxDecoration(color: c.id == t.cat ? hexColor(c.color) : pal.field, borderRadius: BorderRadius.circular(20)),
                      child: Text(
                        '${c.emoji}  ${c.name}',
                        style: inter(14, FontWeight.w700, color: c.id == t.cat ? (darkTextOn(c.color) ? Colors.black : Colors.white) : pal.ink),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        if (t.type == 'transfer') ...[
          fr('From', chip(acctName(t.acct, none: 'Outside'), () => _pickAcct(dest: false))),
          fr('To', chip(acctName(t.to, none: 'Outside'), () => _pickAcct(dest: true))),
        ] else if (hasAccts)
          fr(t.income || t.type == 'refund' ? 'Into' : 'Account', chip(acctName(t.acct), () => _pickAcct(dest: false))),
        fr(
          'When',
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              chip(dueLabel(dstr(t.at), nowMs()), () async {
                final d = await pickDate(context, dt);
                if (d != null) setState(() => t.at = DateTime(d.year, d.month, d.day, dt.hour, dt.minute).millisecondsSinceEpoch);
              }),
              const SizedBox(width: 8),
              chip(fmtT(t.at, use24h: app.use24h), () async {
                final x = await pickTime(context, TimeOfDay(hour: dt.hour, minute: dt.minute));
                if (x != null) setState(() => t.at = DateTime(dt.year, dt.month, dt.day, x.hour, x.minute).millisecondsSinceEpoch);
              }),
            ],
          ),
        ),
        if (t.isSpend && m.plans.any((p) => (!p.archived && p.mode == 'added') || p.id == t.plan))
          fr('Trip or event', chip(m.planOf(t.plan) == null ? 'None' : '${m.planOf(t.plan)!.emoji}  ${m.planOf(t.plan)!.name}', _pickPlan)),
        if (t.isSpend || t.income) fr('Leave out of budgets', PillSwitch(value: t.excluded, onChanged: (v) => setState(() => t.excluded = v))),
        const SizedBox(height: 10),
        SheetField(controller: _tags, hint: 'Tags (trip, work…)'),
        const SizedBox(height: 10),
        SheetField(controller: _note, hint: 'Note'),
        if (t.review) ...[
          SheetBtn('Mark reviewed', kind: BtnKind.yellow, onTap: () => _save(reviewed: true)),
          SheetBtn('Save, keep in review', onTap: _save),
        ] else
          SheetBtn(isNew ? head : 'Save', kind: BtnKind.yellow, onTap: _save),
        if (isNew && main) SheetBtn('Save & new', onTap: _saveAndNew),
        if (!isNew)
          SheetBtn(
            'Delete',
            kind: BtnKind.red,
            onTap: () {
              Navigator.pop(context);
              app.deleteTxn(t.id);
            },
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Budget and categories.

void openBudgetSheet(BuildContext context) {
  final app = context.read<AppState>();
  showSheet<void>(context, (_) => ChangeNotifierProvider.value(value: app, child: const _BudgetSheet()));
}

class _BudgetSheet extends StatefulWidget {
  const _BudgetSheet();
  @override
  State<_BudgetSheet> createState() => _BudgetSheetState();
}

class _BudgetSheetState extends State<_BudgetSheet> {
  late final AppState app = context.read<AppState>();
  late final _ctl = TextEditingController(text: app.s.money.budget > 0 ? '${app.s.money.budget ~/ 100}' : '');

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _save() {
    final v = _ctl.text.trim().isEmpty ? 0 : parseAmount(_ctl.text);
    if (v == null) {
      app.showToast('Enter an amount');
      return;
    }
    Navigator.pop(context);
    app.setMonthBudget(v);
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final m = app.s.money;
    final st = app.stats(monthStart(nowMs()));
    final catSum = st.limit.values.fold(0, (a, b) => a + b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SheetHead('Monthly budget'),
        Text(
          'How much you plan to spend in a month. The Money tab counts down from it and works out what you can spend today.',
          style: inter(14, FontWeight.w500, height: 1.5, color: pal.label),
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(m.currency.trim(), style: cond(40, FontWeight.w800, color: pal.label)),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: _ctl,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onSubmitted: (_) => _save(),
                style: cond(48, FontWeight.w800, color: pal.ink),
                cursorColor: kYellow,
                decoration: InputDecoration(
                  hintText: catSum > 0 ? '${catSum ~/ 100}' : '0',
                  hintStyle: cond(48, FontWeight.w800, color: pal.placeholder),
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        if (catSum > 0)
          Text(
            'Leave it empty to use your category limits (${app.cash(catSum)} this month).',
            style: inter(13, FontWeight.w500, height: 1.45, color: pal.label),
          ),
        SheetBtn('Save budget', kind: BtnKind.yellow, onTap: _save),
        if (m.budget > 0)
          SheetBtn(
            'Turn off',
            onTap: () {
              Navigator.pop(context);
              app.setMonthBudget(0);
            },
          ),
      ],
    );
  }
}

void openCategories(BuildContext context) {
  final app = context.read<AppState>();
  showSheet<void>(context, (_) => ChangeNotifierProvider.value(value: app, child: const _CatList()));
}

class _CatList extends StatelessWidget {
  const _CatList();
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final pal = Pal.of(context);
    final m = app.s.money;
    final month = monthStart(nowMs());
    Widget row(MCat c) {
      final lim = m.limitIn(c, month);
      final flags = [if (c.rollover) '↻', if (c.excluded) 'not in budget', if (c.archived) 'hidden'].join(' · ');
      return Pressable(
        scale: .98,
        onTap: () => openCatSheet(context, c),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: pal.panelRule)),
          ),
          child: Row(
            children: [
              Opacity(opacity: c.archived ? .45 : 1, child: CatBadge(c, size: 34)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.name, style: inter(16, FontWeight.w600, color: c.archived ? pal.label : pal.ink)),
                    if (flags.isNotEmpty) Text(flags, style: inter(12, FontWeight.w600, color: pal.label)),
                  ],
                ),
              ),
              if (!c.income) Text(lim > 0 ? '${app.cash(lim)} / mo' : 'No limit', style: inter(14, FontWeight.w600, color: pal.label)),
              const SizedBox(width: 6),
              Text('›', style: TextStyle(fontSize: 24, height: .8, color: pal.placeholder)),
            ],
          ),
        ),
      );
    }

    Widget label(String t) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 4),
      child: Text(t, style: inter(11, FontWeight.w800, ls: .1, color: pal.label)),
    );

    final total = app.stats(month).budget;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SheetHead('Categories'),
        Pressable(
          scale: .98,
          onTap: () => openBudgetSheet(context),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: pal.panelRule)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text('Monthly budget', style: inter(16, FontWeight.w600, color: pal.ink)),
                ),
                Text(m.budget > 0 ? app.cash(m.budget) : (total > 0 ? 'Sum · ${app.cash(total)}' : 'Off'), style: inter(15, FontWeight.w600, color: pal.label)),
                const SizedBox(width: 6),
                Text('›', style: TextStyle(fontSize: 24, height: .8, color: pal.placeholder)),
              ],
            ),
          ),
        ),
        label('SPENDING'),
        for (final c in m.cats.where((c) => !c.income)) row(c),
        label('INCOME'),
        for (final c in m.cats.where((c) => c.income)) row(c),
        SheetBtn('Add category', onTap: () => openCatSheet(context, null)),
      ],
    );
  }
}

void openCatSheet(BuildContext context, MCat? cat, {bool income = false}) {
  final app = context.read<AppState>();
  showSheet<void>(
    context,
    (_) => ChangeNotifierProvider.value(
      value: app,
      child: _CatSheet(cat, income: income),
    ),
  );
}

class _CatSheet extends StatefulWidget {
  final MCat? cat;
  final bool income;
  const _CatSheet(this.cat, {this.income = false});
  @override
  State<_CatSheet> createState() => _CatSheetState();
}

class _CatSheetState extends State<_CatSheet> {
  late final AppState app = context.read<AppState>();
  late final MCat c =
      widget.cat?.copy() ??
      MCat(
        id: 'c${uid()}',
        name: '',
        emoji: '✨',
        income: widget.income,
        color: kPaletteMoney.firstWhere((x) => !app.s.money.cats.any((c) => c.color == x), orElse: () => kPaletteMoney.first),
      );
  late final _name = TextEditingController(text: c.name);
  late final _emoji = TextEditingController(text: c.emoji);
  late final int _lim = widget.cat == null ? 0 : app.s.money.limitIn(widget.cat!, monthStart(nowMs()));
  late final _limit = TextEditingController(text: _lim > 0 ? plainAmount(_lim) : '');
  late final _kw = TextEditingController(text: c.kw);

  @override
  void dispose() {
    _name.dispose();
    _emoji.dispose();
    _limit.dispose();
    _kw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final m = app.s.money;
    Widget label(String t) => Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 5),
      child: Text(t, style: inter(13, FontWeight.w600, color: pal.label)),
    );
    Widget fr(String label, String hint, Widget control) => Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: pal.panelRule)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: inter(16, FontWeight.w500, color: pal.rowLabel)),
                Text(hint, style: inter(12, FontWeight.w500, height: 1.4, color: pal.label)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          control,
        ],
      ),
    );
    final canDelete = widget.cat != null && m.cats.where((x) => x.income == c.income).length > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHead(widget.cat == null ? 'New category' : 'Category'),
        if (widget.cat == null)
          Center(
            child: Segmented<bool>(
              options: const [(false, 'SPENDING'), (true, 'INCOME')],
              value: c.income,
              onChanged: (v) => setState(() => c.income = v),
              track: pal.field,
              thumb: pal.light ? const Color(0xFF111111) : Colors.white,
              on: pal.light ? Colors.white : Colors.black,
              off: pal.label,
              style: cond(14, FontWeight.w800, ls: .08),
              segWidth: 104,
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  label('Name'),
                  SheetField(controller: _name, maxLength: 24),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 76,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  label('Emoji'),
                  SheetField(controller: _emoji, maxLength: 8, center: true),
                ],
              ),
            ),
          ],
        ),
        label('Color'),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final x in kPaletteMoney)
              Pressable(
                onTap: () => setState(() => c.color = x),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: hexColor(x),
                    shape: BoxShape.circle,
                    border: Border.all(color: x == c.color ? (pal.light ? Colors.black : Colors.white) : Colors.transparent, width: 3),
                  ),
                ),
              ),
          ],
        ),
        if (!c.income) ...[
          label('Monthly limit (${m.currency.trim()})'),
          SheetField(controller: _limit, hint: 'No limit', keyboard: const TextInputType.numberWithOptions(decimal: true)),
          const SizedBox(height: 4),
          fr(
            'Roll over',
            'What’s left (or overspent) carries into next month',
            PillSwitch(value: c.rollover, onChanged: (v) => setState(() => c.rollover = v)),
          ),
          fr(
            'Leave out of budget',
            'Spending here doesn’t count toward the month',
            PillSwitch(value: c.excluded, onChanged: (v) => setState(() => c.excluded = v)),
          ),
        ],
        if (widget.cat != null)
          fr('Hide', 'Keeps its history but drops it from pickers', PillSwitch(value: c.archived, onChanged: (v) => setState(() => c.archived = v))),
        label('Keywords (sorts new ${c.income ? 'income' : 'spends'} into this category)'),
        SheetField(controller: _kw, hint: c.income ? 'salary, stipend' : 'lunch, swiggy, coffee'),
        SheetBtn(
          'Save',
          kind: BtnKind.yellow,
          onTap: () {
            final name = _name.text.trim();
            if (name.isEmpty) {
              app.showToast('Give it a name');
              return;
            }
            Navigator.pop(context);
            app.saveMCat(
              c
                ..name = name
                ..emoji = _emoji.text.trim().isEmpty ? '•' : _emoji.text.trim()
                ..budget = c.income ? 0 : (parseAmount(_limit.text) ?? 0)
                ..kw = _kw.text.trim(),
            );
          },
        ),
        if (canDelete)
          SheetBtn(
            'Delete category',
            kind: BtnKind.red,
            onTap: () async {
              final to = m.catOf(c.income ? m.fallbackIncome : m.fallbackCat).name;
              final ok = await ask<bool>(context, 'Delete ${c.name}?', 'Its entries move to $to.', const [AskBtn('Delete', true, BtnKind.red)]);
              if (ok != true || !context.mounted) return;
              Navigator.pop(context);
              app.deleteMCat(c.id);
            },
          ),
      ],
    );
  }
}

/// Kept for older call sites.
const kPaletteCats = kPaletteMoney;

/// Shorthand used by sheets that list a task's bill details.
String billLine(AppState app, Task t) => '${app.cash(t.amount)} · ${dueLabel(t.due, nowMs())}';
