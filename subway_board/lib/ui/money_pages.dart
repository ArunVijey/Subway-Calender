// Money sheets and pages: accounts, savings goals, loans, trip/event budgets,
// the searchable transaction list, and the page that orders the Money tab.
import 'dart:convert';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/store.dart';
import '../core/csv_import.dart';
import '../core/ledger.dart';
import '../core/money.dart';
import '../core/tasks.dart';
import '../core/util.dart';
import 'haptics.dart';
import 'lines.dart';
import 'money.dart';
import 'money_charts.dart';
import 'money_sections.dart';
import 'motion.dart';
import 'tasks.dart';
import 'theme.dart';
import 'widgets.dart';

// ---------------------------------------------------------------------------
// Shared pieces

Future<void> _sheet(BuildContext context, Widget child) {
  final app = context.read<AppState>();
  return showSheet<void>(context, (_) => ChangeNotifierProvider.value(value: app, child: child));
}

void _page(BuildContext context, Widget child) {
  final app = context.read<AppState>();
  final pal = Pal.of(context);
  Navigator.of(context).push(PageRouteBuilder<void>(
    transitionDuration: Motion.smoothDur,
    reverseTransitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (_, _, _) => ChangeNotifierProvider.value(value: app, child: PalScope(pal: pal, child: child)),
    transitionsBuilder: (_, anim, _, child) => SlideTransition(
      position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(CurvedAnimation(parent: anim, curve: Motion.smooth, reverseCurve: Curves.easeInCubic)),
      child: child,
    ),
  ));
}

Widget _label(Pal pal, String t) => Padding(padding: const EdgeInsets.only(top: 14, bottom: 6), child: Text(t, style: inter(13, FontWeight.w600, color: pal.label)));

Widget _fr(Pal pal, String label, Widget control, {String? hint}) => Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.panelRule))),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: inter(16, FontWeight.w500, color: pal.rowLabel)),
            if (hint != null) Text(hint, style: inter(12, FontWeight.w500, height: 1.4, color: pal.label)),
          ]),
        ),
        const SizedBox(width: 12),
        control,
      ]),
    );

class _Chip extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  const _Chip(this.text, this.onTap, {this.onClear});
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Pressable(
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .5),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          decoration: BoxDecoration(color: pal.field, borderRadius: BorderRadius.circular(8)),
          child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: inter(15, FontWeight.w500, color: pal.ink)),
        ),
      ),
      if (onClear != null)
        Semantics(
          button: true,
          label: 'Clear',
          child: Pressable(onTap: onClear, child: Padding(padding: const EdgeInsets.only(left: 6), child: Text('✕', style: TextStyle(fontSize: 14, color: pal.label)))),
        ),
    ]);
  }
}

class _Colors extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _Colors(this.value, this.onChanged);
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Wrap(spacing: 10, runSpacing: 10, children: [
      for (final x in kPaletteMoney)
        Semantics(
          button: true,
          selected: x == value,
          label: 'Color $x',
          child: Pressable(
            onTap: () => onChanged(x),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: hexColor(x),
                shape: BoxShape.circle,
                border: Border.all(color: x == value ? (pal.light ? Colors.black : Colors.white) : Colors.transparent, width: 3),
              ),
            ),
          ),
        ),
    ]);
  }
}

/// Name + emoji fields side by side.
Widget _nameEmoji(Pal pal, TextEditingController name, TextEditingController emoji, {String nameLabel = 'Name', String? hint}) => Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_label(pal, nameLabel), SheetField(controller: name, hint: hint, maxLength: 32)])),
      const SizedBox(width: 12),
      SizedBox(width: 76, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_label(pal, 'Emoji'), SheetField(controller: emoji, maxLength: 8, center: true)])),
    ]);

/// Big amount field with the currency in front.
class _AmountField extends StatelessWidget {
  final TextEditingController ctl;
  final bool autofocus;
  const _AmountField(this.ctl, {this.autofocus = false});
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final app = context.read<AppState>();
    return Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
      Text(app.s.money.currency.trim(), style: cond(40, FontWeight.w800, color: pal.label)),
      const SizedBox(width: 6),
      Expanded(
        child: TextField(
          controller: ctl,
          autofocus: autofocus,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          style: cond(46, FontWeight.w800, color: pal.ink).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          cursorColor: kYellow,
          decoration: InputDecoration(hintText: '0', hintStyle: cond(46, FontWeight.w800, color: pal.placeholder), border: InputBorder.none, isDense: true),
        ),
      ),
    ]);
  }
}

/// "−1,200" / "1200" → signed minor units.
int? _signed(String s) {
  final t = s.trim();
  final neg = t.startsWith('-') || t.startsWith('−');
  final v = parseAmount(neg ? t.substring(1) : t);
  return v == null ? null : (neg ? -v : v);
}

Future<String?> _pickAcct(BuildContext context, String title, String current, {String none = 'No account'}) {
  final m = context.read<AppState>().s.money;
  return pickOption<String>(context, title, [
    for (final a in m.accounts)
      if (!a.archived || a.id == current) (a.id, '${kAcctEmoji[a.type]}  ${a.name}'),
    ('', none),
  ], current);
}

String _acctLabel(Money m, String id, {String none = 'No account'}) {
  final a = m.acctOf(id);
  return a == null ? none : '${kAcctEmoji[a.type]}  ${a.name}';
}

/// One line per entry inside a sheet.
class _MiniTxn extends StatelessWidget {
  final Txn t;
  const _MiniTxn(this.t);
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final pal = Pal.of(context);
    final m = app.s.money;
    final cat = m.catOf(t.cat);
    final plus = t.type == 'income' || t.type == 'refund' || t.type == 'unsave' || t.type == 'borrowed' || (t.type == 'repay' && m.goalOf(t.goal)?.kind == 'lent');
    final label = t.title.isNotEmpty
        ? t.title
        : switch (t.type) {
            'save' => 'Added',
            'unsave' => 'Taken out',
            'lent' => 'Lent',
            'borrowed' => 'Borrowed',
            'repay' => 'Repayment',
            'transfer' => 'Transfer',
            'adjust' => 'Balance update',
            _ => cat.name,
          };
    return Pressable(
      scale: .98,
      onTap: () => openTxnSheet(context, t),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.panelRule))),
        child: Row(children: [
          SizedBox(width: 28, child: Text(t.isSpend || t.income ? cat.emoji : (t.type == 'transfer' ? '⇄' : '•'), style: const TextStyle(fontSize: 16))),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: inter(15, FontWeight.w600, color: pal.ink)),
              Text('${monthDay(t.at)} ${DateTime.fromMillisecondsSinceEpoch(t.at).year != DateTime.now().year ? DateTime.fromMillisecondsSinceEpoch(t.at).year : ''}'.trim(),
                  style: inter(12, FontWeight.w500, color: pal.label)),
            ]),
          ),
          Text(t.type == 'adjust' ? app.cash(t.amount, sign: true) : '${plus ? '+' : ''}${app.cash(t.amount)}',
              style: cond(19, FontWeight.w800, color: plus ? kIncomeGreen : pal.ink).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
      ),
    );
  }
}

/// Amount (+ account, date, note) for goal and loan moves. Null on cancel.
Future<(int, String, int, String)?> _askAmount(BuildContext context, {required String title, required String cta, String acct = '', String acctLabel = 'Account', String hint = 'Note'}) {
  final app = context.read<AppState>();
  return showSheet<(int, String, int, String)>(
      context, (_) => ChangeNotifierProvider.value(value: app, child: _AmountSheet(title: title, cta: cta, acct: acct, acctLabel: acctLabel, hint: hint)));
}

class _AmountSheet extends StatefulWidget {
  final String title, cta, acct, acctLabel, hint;
  const _AmountSheet({required this.title, required this.cta, required this.acct, required this.acctLabel, required this.hint});
  @override
  State<_AmountSheet> createState() => _AmountSheetState();
}

class _AmountSheetState extends State<_AmountSheet> {
  late final AppState app = context.read<AppState>();
  final _amt = TextEditingController(), _note = TextEditingController();
  late String _acct = widget.acct;
  int _at = nowMs();

  @override
  void dispose() {
    _amt.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final m = app.s.money;
    final dt = DateTime.fromMillisecondsSinceEpoch(_at);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SheetHead(widget.title),
      _AmountField(_amt, autofocus: true),
      if (m.accounts.isNotEmpty)
        _fr(pal, widget.acctLabel, _Chip(_acctLabel(m, _acct), () async {
          final x = await _pickAcct(context, widget.acctLabel, _acct);
          if (x != null) setState(() => _acct = x);
        })),
      _fr(pal, 'When', _Chip(dueLabel(dstr(_at), nowMs()), () async {
        final d = await pickDate(context, dt);
        if (d != null) setState(() => _at = DateTime(d.year, d.month, d.day, dt.hour, dt.minute).millisecondsSinceEpoch);
      })),
      const SizedBox(height: 10),
      SheetField(controller: _note, hint: widget.hint),
      SheetBtn(widget.cta, kind: BtnKind.yellow, onTap: () {
        final v = parseAmount(_amt.text);
        if (v == null || v <= 0) {
          app.showToast('Enter an amount');
          return;
        }
        Navigator.pop(context, (v, _acct, _at, _note.text.trim()));
      }),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Accounts

void openAccountsList(BuildContext context) => _sheet(context, const _AccountsList());

class _AccountsList extends StatelessWidget {
  const _AccountsList();
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final pal = Pal.of(context);
    final m = app.s.money;
    final bal = app.balancesNow();
    final net = netWorth(m, bal);
    final assets = m.liveAccounts.fold(0, (a, x) => a + math.max(0, bal[x.id] ?? 0));
    final debts = m.liveAccounts.fold(0, (a, x) => a + math.min(0, bal[x.id] ?? 0));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SheetHead('Accounts'),
      Row(children: [
        Expanded(child: _BigStat('NET WORTH', app.cash(net), pal.ink)),
        Expanded(child: _BigStat('ASSETS', app.cash(assets), kIncomeGreen)),
        Expanded(child: _BigStat('DEBTS', app.cash(-debts), debts < 0 ? kRed : pal.label)),
      ]),
      const SizedBox(height: 10),
      if (m.accounts.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text('No accounts yet. Add your bank accounts, cards and cash to track balances.', style: inter(14, FontWeight.w500, height: 1.45, color: pal.label)),
        ),
      ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        itemCount: m.accounts.length,
        onReorderStart: (_) => buzz(),
        onReorderItem: app.moveAccount,
        proxyDecorator: (child, _, _) => Material(color: pal.panel, elevation: 6, borderRadius: BorderRadius.circular(10), child: child),
        itemBuilder: (context, i) {
          final a = m.accounts[i];
          final b = bal[a.id] ?? 0;
          return Container(
            key: ValueKey(a.id),
            decoration: BoxDecoration(color: pal.panel, border: Border(bottom: BorderSide(color: pal.panelRule))),
            child: Row(children: [
              ReorderableDragStartListener(
                index: i,
                child: Semantics(label: 'Drag to reorder ${a.name}', child: Padding(padding: const EdgeInsets.fromLTRB(0, 14, 10, 14), child: Icon(Icons.drag_indicator, size: 22, color: pal.placeholder))),
              ),
              Expanded(
                child: Pressable(
                  scale: .98,
                  onTap: () => openAccountSheet(context, a),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(children: [
                      Opacity(opacity: a.archived ? .45 : 1, child: EmojiBadge(kAcctEmoji[a.type]!, a.color, size: 34)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: inter(16, FontWeight.w600, color: a.archived ? pal.label : pal.ink)),
                          Text([kAcctTypes[a.type]!, if (m.defaultAcct == a.id) 'default', if (a.archived) 'hidden'].join(' · '), style: inter(12, FontWeight.w600, color: pal.label)),
                        ]),
                      ),
                      Text(app.cash(b), style: cond(20, FontWeight.w800, color: b < 0 ? kRed : pal.ink).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                    ]),
                  ),
                ),
              ),
            ]),
          );
        },
      ),
      if (m.accounts.length > 1)
        Padding(padding: const EdgeInsets.only(top: 8), child: Text('Drag the handle to reorder.', style: inter(12, FontWeight.w500, color: pal.label))),
      SheetBtn('Add account', kind: BtnKind.yellow, onTap: () => openAccountSheet(context, null)),
    ]);
  }
}

class _BigStat extends StatelessWidget {
  final String label, value;
  final Color color;
  const _BigStat(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: cond(12, FontWeight.w800, ls: .1, color: pal.label)),
      FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: cond(24, FontWeight.w800, color: color).copyWith(fontFeatures: const [FontFeature.tabularFigures()]))),
    ]);
  }
}

void openAccountSheet(BuildContext context, Account? a) => _sheet(context, _AccountSheet(a));

class _AccountSheet extends StatefulWidget {
  final Account? a;
  const _AccountSheet(this.a);
  @override
  State<_AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<_AccountSheet> {
  late final AppState app = context.read<AppState>();
  late final Account a = widget.a?.copy() ??
      Account(id: 'a${uid()}', name: '', color: kPaletteMoney.firstWhere((x) => !app.s.money.accounts.any((y) => y.color == x), orElse: () => kPaletteMoney[1]));
  late final _name = TextEditingController(text: a.name);
  // New accounts: today's balance. Existing ones: the opening balance (before any entries).
  late final _bal = TextEditingController(text: widget.a == null ? '' : (a.opening == 0 ? '' : (a.opening < 0 ? '-' : '') + plainAmount(a.opening.abs())));
  late bool _default = app.s.money.defaultAcct == a.id || (widget.a == null && app.s.money.newAcct.isEmpty);

  @override
  void dispose() {
    _name.dispose();
    _bal.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      app.showToast('Give it a name');
      return;
    }
    final v = _bal.text.trim().isEmpty ? 0 : _signed(_bal.text);
    if (v == null) {
      app.showToast('Enter the balance as a number');
      return;
    }
    // A card's balance is what you owe: typing 5,000 means −5,000.
    final opening = widget.a == null && a.debt ? -v.abs() : v;
    Navigator.pop(context);
    app.saveAccount(a
      ..name = name
      ..opening = opening);
    if (_default) {
      app.setDefaultAcct(a.id);
    } else if (app.s.money.defaultAcct == a.id) {
      app.setDefaultAcct('');
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final m = app.s.money;
    final existing = widget.a != null;
    final bal = existing ? (app.balancesNow()[a.id] ?? 0) : 0;
    final recent = existing ? (m.txns.where((t) => t.acct == a.id || t.to == a.id).toList()..sort((x, y) => y.at.compareTo(x.at))) : <Txn>[];
    final monthChange = existing ? acctChange(m, a.id, monthStart(nowMs()), nowMs() + 1) : 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SheetHead(existing ? a.name : 'New account'),
      if (existing) ...[
        Text(a.debt && bal < 0 ? 'OWED' : 'BALANCE', style: cond(13, FontWeight.w800, ls: .1, color: pal.label)),
        Text(app.cash(a.debt && bal < 0 ? -bal : bal), style: cond(48, FontWeight.w800, height: 1, color: bal < 0 && !a.debt ? kRed : pal.ink).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
        if (monthChange != 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('${app.cash(monthChange, sign: true)} this month', style: inter(13, FontWeight.w600, color: monthChange > 0 ? kIncomeGreen : kRed)),
          ),
        Row(children: [
          Expanded(
            child: SheetBtn('Update balance', onTap: () async {
              final ctl = TextEditingController(text: (bal < 0 ? '-' : '') + plainAmount(bal.abs()));
              final v = await showSheet<int>(context, (ctx) {
                final p = Pal.of(ctx);
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const SheetHead('Update balance'),
                  Text('What does ${a.name} show right now? The difference is logged as a balance update${a.debt ? ' (use − for money owed)' : ''}.',
                      style: inter(14, FontWeight.w500, height: 1.5, color: p.label)),
                  const SizedBox(height: 10),
                  ChangeNotifierProvider.value(value: app, child: _AmountField(ctl, autofocus: true)),
                  SheetBtn('Update', kind: BtnKind.yellow, onTap: () {
                    final x = _signed(ctl.text);
                    if (x == null) return;
                    Navigator.pop(ctx, x);
                  }),
                ]);
              });
              ctl.dispose();
              if (v != null) app.updateBalance(a.id, v);
              if (mounted) setState(() {});
            }),
          ),
          const SizedBox(width: 10),
          if (m.liveAccounts.length >= 2)
            Expanded(
              child: SheetBtn('Transfer', onTap: () {
                Navigator.pop(context);
                openTxnSheet(context, null, type: 'transfer', acct: a.id);
              }),
            ),
        ]),
        if (recent.isNotEmpty) ...[
          _label(pal, 'RECENT'),
          for (final t in recent.take(6)) _MiniTxn(t),
          if (recent.length > 6)
            Pressable(
              onTap: () => openTxnList(context, acct: a.id),
              child: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text('SEE ALL ${recent.length}', style: cond(15, FontWeight.w800, ls: .08, color: pal.light ? pal.ink : kYellow))),
            ),
        ],
        _label(pal, 'DETAILS'),
      ],
      SheetField(controller: _name, hint: 'Name (HDFC, Cash, Amex…)', maxLength: 28),
      _label(pal, 'Type'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final e in kAcctTypes.entries)
          Pressable(
            onTap: () => setState(() => a.type = e.key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(color: a.type == e.key ? (pal.light ? const Color(0xFF111111) : Colors.white) : pal.field, borderRadius: BorderRadius.circular(20)),
              child: Text('${kAcctEmoji[e.key]}  ${e.value}', style: inter(14, FontWeight.w700, color: a.type == e.key ? (pal.light ? Colors.white : Colors.black) : pal.ink)),
            ),
          ),
      ]),
      _label(pal, 'Color'),
      _Colors(a.color, (x) => setState(() => a.color = x)),
      _label(pal, existing ? 'Opening balance (before the first entry)' : (a.debt ? 'Amount owed now' : 'Balance now')),
      SheetField(controller: _bal, hint: '0', keyboard: const TextInputType.numberWithOptions(decimal: true, signed: true)),
      _fr(pal, 'Default for new entries', PillSwitch(value: _default, onChanged: (v) => setState(() => _default = v))),
      if (existing) _fr(pal, 'Hide', PillSwitch(value: a.archived, onChanged: (v) => setState(() => a.archived = v)), hint: 'Keeps its history; leaves net worth'),
      SheetBtn(existing ? 'Save' : 'Add account', kind: BtnKind.yellow, onTap: _save),
      if (existing)
        SheetBtn('Delete account', kind: BtnKind.red, onTap: () async {
          final n = m.txns.where((t) => t.acct == a.id || t.to == a.id).length;
          final ok = await ask<bool>(context, 'Delete ${a.name}?', n > 0 ? 'Its $n entries stay in your spending but won’t belong to any account. Hiding it keeps everything instead.' : '',
              const [AskBtn('Delete', true, BtnKind.red)]);
          if (ok != true || !context.mounted) return;
          Navigator.pop(context);
          app.deleteAccount(a.id);
        }),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Savings goals

void openGoalSheet(BuildContext context, Goal? g) => _sheet(context, _GoalSheet(g));

class _GoalSheet extends StatefulWidget {
  final Goal? g;
  const _GoalSheet(this.g);
  @override
  State<_GoalSheet> createState() => _GoalSheetState();
}

class _GoalSheetState extends State<_GoalSheet> {
  late final AppState app = context.read<AppState>();
  late final Goal g = widget.g?.copy() ?? Goal(id: 'g${uid()}', name: '', color: kPaletteMoney[5]);
  late final _name = TextEditingController(text: g.name);
  late final _emoji = TextEditingController(text: g.emoji);
  late final _target = TextEditingController(text: g.target > 0 ? plainAmount(g.target) : '');
  late final _offset = TextEditingController(text: g.offset > 0 ? plainAmount(g.offset) : '');

  @override
  void dispose() {
    _name.dispose();
    _emoji.dispose();
    _target.dispose();
    _offset.dispose();
    super.dispose();
  }

  bool _apply() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      app.showToast('Give it a name');
      return false;
    }
    g
      ..name = name
      ..emoji = _emoji.text.trim().isEmpty ? '🎯' : _emoji.text.trim()
      ..target = parseAmount(_target.text) ?? 0
      ..offset = parseAmount(_offset.text) ?? 0;
    return true;
  }

  Future<void> _move(bool into) async {
    final r = await _askAmount(context,
        title: into ? 'Add to ${g.name}' : 'Take from ${g.name}', cta: into ? 'Add' : 'Take out', acct: app.s.money.newAcct, acctLabel: into ? 'From account' : 'Back into');
    if (r == null || !mounted) return;
    final (v, acct, at, note) = r;
    app.saveTxn(Txn(id: uid(), title: '', note: note, cat: app.s.money.fallbackCat, at: at, amount: v, type: into ? 'save' : 'unsave', acct: acct, goal: g.id));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final existing = widget.g != null;
    final m = app.s.money;
    final saved = existing ? goalAmount(m, g) : 0;
    final per = existing ? perMonthToGoal(m, g, nowMs()) : 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SheetHead(existing ? g.name : 'New goal'),
      if (existing) ...[
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(app.cash(saved), style: cond(48, FontWeight.w800, height: 1, color: pal.ink).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
          if (g.target > 0) Padding(padding: const EdgeInsets.only(left: 8, bottom: 4), child: Text('of ${app.cash(g.target)}', style: cond(22, FontWeight.w700, color: pal.label))),
        ]),
        if (g.target > 0) Padding(padding: const EdgeInsets.only(top: 10), child: MoneyBar(frac: saved / g.target, color: hexColor(g.color), height: 8)),
        if (per > 0) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Put aside ${app.cash(per)} a month to reach it by ${monthDay(g.end)}.', style: inter(14, FontWeight.w600, color: pal.label))),
        Row(children: [
          Expanded(child: SheetBtn('Add money', kind: BtnKind.yellow, onTap: () => _move(true))),
          const SizedBox(width: 10),
          Expanded(child: SheetBtn('Take out', onTap: saved > 0 ? () => _move(false) : null)),
        ]),
        if (goalTxns(m, g).isNotEmpty) ...[_label(pal, 'HISTORY'), for (final t in goalTxns(m, g).take(8)) _MiniTxn(t)],
        _label(pal, 'DETAILS'),
      ],
      _nameEmoji(pal, _name, _emoji, hint: 'Laptop, trip, emergency fund…'),
      _label(pal, 'Color'),
      _Colors(g.color, (x) => setState(() => g.color = x)),
      _label(pal, 'Target (${m.currency.trim()})'),
      SheetField(controller: _target, hint: 'How much you need', keyboard: const TextInputType.numberWithOptions(decimal: true)),
      _fr(
        pal,
        'Target date',
        _Chip(g.end == 0 ? 'None' : '${monthDay(g.end)}, ${DateTime.fromMillisecondsSinceEpoch(g.end).year}', () async {
          final d = await pickDate(context, DateTime.fromMillisecondsSinceEpoch(g.end == 0 ? addMonths(nowMs(), 6) : g.end));
          if (d != null) setState(() => g.end = d.millisecondsSinceEpoch);
        }, onClear: g.end == 0 ? null : () => setState(() => g.end = 0)),
      ),
      _label(pal, 'Already saved before tracking here'),
      SheetField(controller: _offset, hint: '0', keyboard: const TextInputType.numberWithOptions(decimal: true)),
      SheetBtn(existing ? 'Save' : 'Create goal', kind: existing ? BtnKind.plain : BtnKind.yellow, onTap: () {
        if (!_apply()) return;
        Navigator.pop(context);
        app.saveGoal(g);
      }),
      if (existing)
        SheetBtn(g.archived ? 'Bring back' : 'Mark done', onTap: () {
          if (!_apply()) return;
          Navigator.pop(context);
          app.saveGoal(g..archived = !g.archived);
        }),
      if (existing)
        SheetBtn('Delete goal', kind: BtnKind.red, onTap: () async {
          final ok = await ask<bool>(context, 'Delete ${g.name}?', 'Its history goes too. Money put into it counts as back in its account.', const [AskBtn('Delete', true, BtnKind.red)]);
          if (ok != true || !context.mounted) return;
          Navigator.pop(context);
          app.deleteGoal(g.id);
        }),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Loans

void openLoanSheet(BuildContext context, Goal? g) => _sheet(context, _LoanSheet(g));

class _LoanSheet extends StatefulWidget {
  final Goal? g;
  const _LoanSheet(this.g);
  @override
  State<_LoanSheet> createState() => _LoanSheetState();
}

class _LoanSheetState extends State<_LoanSheet> {
  late final AppState app = context.read<AppState>();
  late final Goal g = widget.g?.copy() ?? Goal(id: 'l${uid()}', name: '', emoji: '🤝', color: kPaletteMoney[0], kind: 'lent');
  late final _name = TextEditingController(text: g.name);
  late final _emoji = TextEditingController(text: g.emoji);
  final _amount = TextEditingController();
  late String _acct = app.s.money.newAcct;
  int _at = nowMs();

  @override
  void dispose() {
    _name.dispose();
    _emoji.dispose();
    _amount.dispose();
    super.dispose();
  }

  bool get _lent => g.kind == 'lent';

  Future<void> _move(bool repay) async {
    final r = await _askAmount(
      context,
      title: repay ? (_lent ? '${g.name} paid back' : 'You paid back') : (_lent ? 'Lend more' : 'Borrow more'),
      cta: repay ? 'Record repayment' : (_lent ? 'Record' : 'Record'),
      acct: app.s.money.newAcct,
      acctLabel: (repay == _lent) ? 'Into' : 'From',
    );
    if (r == null || !mounted) return;
    final (v, acct, at, note) = r;
    app.saveTxn(Txn(id: uid(), title: '', note: note, cat: app.s.money.fallbackCat, at: at, amount: v, type: repay ? 'repay' : g.kind, acct: acct, goal: g.id));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final m = app.s.money;
    final existing = widget.g != null;
    final left = existing ? goalAmount(m, g) : 0, total = existing ? loanTotal(m, g) : 0;
    final dt = DateTime.fromMillisecondsSinceEpoch(_at);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SheetHead(existing ? g.name : 'New loan'),
      if (!existing)
        Center(
          child: Segmented<String>(
            options: const [('lent', 'I LENT'), ('borrowed', 'I BORROWED')],
            value: g.kind,
            onChanged: (v) => setState(() {
              g.kind = v;
              if (_emoji.text == '🤝' || _emoji.text == '🏦') _emoji.text = v == 'lent' ? '🤝' : '🏦';
            }),
            track: pal.field,
            thumb: pal.light ? const Color(0xFF111111) : Colors.white,
            on: pal.light ? Colors.white : Colors.black,
            off: pal.label,
            style: cond(14, FontWeight.w800, ls: .08),
            segWidth: 120,
          ),
        ),
      if (existing) ...[
        Text(left <= 0 ? 'SETTLED' : (_lent ? '${g.name.toUpperCase()} OWES YOU' : 'YOU OWE'), style: cond(13, FontWeight.w800, ls: .1, color: pal.label)),
        Text(app.cash(math.max(0, left)), style: cond(48, FontWeight.w800, height: 1, color: left <= 0 ? kIncomeGreen : pal.ink).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
        if (total > 0) ...[
          Padding(padding: const EdgeInsets.only(top: 10), child: MoneyBar(frac: (total - left) / total, color: hexColor(g.color), height: 8)),
          Padding(padding: const EdgeInsets.only(top: 6), child: Text('${app.cash(math.max(0, total - left))} of ${app.cash(total)} back', style: inter(13, FontWeight.w600, color: pal.label))),
        ],
        Row(children: [
          Expanded(child: SheetBtn('Repayment', kind: BtnKind.yellow, onTap: left > 0 ? () => _move(true) : null)),
          const SizedBox(width: 10),
          Expanded(child: SheetBtn(_lent ? 'Lend more' : 'Borrow more', onTap: () => _move(false))),
        ]),
        if (goalTxns(m, g).isNotEmpty) ...[_label(pal, 'HISTORY'), for (final t in goalTxns(m, g).take(10)) _MiniTxn(t)],
        _label(pal, 'DETAILS'),
      ],
      _nameEmoji(pal, _name, _emoji, nameLabel: _lent ? 'Who has it' : 'Who from (or what for)', hint: _lent ? 'Sam' : 'Bike loan, Dad…'),
      if (!existing) ...[
        _label(pal, 'Amount'),
        _AmountField(_amount),
        if (m.accounts.isNotEmpty)
          _fr(pal, _lent ? 'From account' : 'Into account', _Chip(_acctLabel(m, _acct), () async {
            final x = await _pickAcct(context, 'Account', _acct);
            if (x != null) setState(() => _acct = x);
          })),
        _fr(pal, 'When', _Chip(dueLabel(dstr(_at), nowMs()), () async {
          final d = await pickDate(context, dt);
          if (d != null) setState(() => _at = DateTime(d.year, d.month, d.day, dt.hour, dt.minute).millisecondsSinceEpoch);
        })),
      ],
      _label(pal, 'Color'),
      _Colors(g.color, (x) => setState(() => g.color = x)),
      _fr(
        pal,
        'Due',
        _Chip(g.end == 0 ? 'No date' : '${monthDay(g.end)}, ${DateTime.fromMillisecondsSinceEpoch(g.end).year}', () async {
          final d = await pickDate(context, DateTime.fromMillisecondsSinceEpoch(g.end == 0 ? addMonths(nowMs(), 1) : g.end));
          if (d != null) setState(() => g.end = d.millisecondsSinceEpoch);
        }, onClear: g.end == 0 ? null : () => setState(() => g.end = 0)),
      ),
      _fr(pal, 'Long-term', PillSwitch(value: g.longTerm, onChanged: (v) => setState(() => g.longTerm = v)), hint: 'An EMI or loan that runs for months'),
      SheetBtn(existing ? 'Save' : 'Add loan', kind: existing ? BtnKind.plain : BtnKind.yellow, onTap: () {
        final name = _name.text.trim();
        if (name.isEmpty) {
          app.showToast(_lent ? 'Who did you lend it to?' : 'Who did you borrow from?');
          return;
        }
        g
          ..name = name
          ..emoji = _emoji.text.trim().isEmpty ? (_lent ? '🤝' : '🏦') : _emoji.text.trim();
        if (existing) {
          Navigator.pop(context);
          app.saveGoal(g);
          return;
        }
        final v = parseAmount(_amount.text);
        if (v == null || v <= 0) {
          app.showToast('Enter an amount');
          return;
        }
        Navigator.pop(context);
        g.start = _at;
        app.saveGoal(g, first: Txn(id: uid(), title: '', cat: m.fallbackCat, at: _at, amount: v, type: g.kind, acct: _acct, goal: g.id));
      }),
      if (existing)
        SheetBtn(g.archived ? 'Reopen' : 'Mark settled', onTap: () {
          Navigator.pop(context);
          app.saveGoal(g..archived = !g.archived);
        }),
      if (existing)
        SheetBtn('Delete loan', kind: BtnKind.red, onTap: () async {
          final ok = await ask<bool>(context, 'Delete ${g.name}?', 'Its history goes too, and account balances change back.', const [AskBtn('Delete', true, BtnKind.red)]);
          if (ok != true || !context.mounted) return;
          Navigator.pop(context);
          app.deleteGoal(g.id);
        }),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Trip & event budgets

void openPlanSheet(BuildContext context, Plan? p) => _sheet(context, _PlanSheet(p));

const _periods = [('custom', 'One-off dates'), ('daily', 'Every day'), ('weekly', 'Every week'), ('monthly', 'Every month'), ('yearly', 'Every year')];

class _PlanSheet extends StatefulWidget {
  final Plan? p;
  const _PlanSheet(this.p);
  @override
  State<_PlanSheet> createState() => _PlanSheetState();
}

class _PlanSheetState extends State<_PlanSheet> {
  late final AppState app = context.read<AppState>();
  late final Plan p = widget.p?.copy() ?? Plan(id: 'p${uid()}', name: '', color: kPaletteMoney[6], start: sod(nowMs()), end: addDays(sod(nowMs()), 6));
  late final _name = TextEditingController(text: p.name);
  late final _emoji = TextEditingController(text: p.emoji);
  late final _amount = TextEditingController(text: p.amount > 0 ? plainAmount(p.amount) : '');

  @override
  void dispose() {
    _name.dispose();
    _emoji.dispose();
    _amount.dispose();
    super.dispose();
  }

  bool _apply() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      app.showToast('Give it a name');
      return false;
    }
    final v = parseAmount(_amount.text);
    if (v == null || v <= 0) {
      app.showToast('Enter the budget amount');
      return false;
    }
    if (p.period == 'custom' && p.end != 0 && p.end < p.start) {
      app.showToast('The end is before the start');
      return false;
    }
    p
      ..name = name
      ..emoji = _emoji.text.trim().isEmpty ? '🧳' : _emoji.text.trim()
      ..amount = v;
    return true;
  }

  Widget _toggles<T>(Pal pal, List<(T, String, String)> items, List<T> chosen) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (final (id, label, color) in items)
          Pressable(
            onTap: () => setState(() => chosen.contains(id) ? chosen.remove(id) : chosen.add(id)),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(color: chosen.contains(id) ? hexColor(color) : pal.field, borderRadius: BorderRadius.circular(20)),
              child: Text(label, style: inter(14, FontWeight.w700, color: chosen.contains(id) ? (darkTextOn(color) ? Colors.black : Colors.white) : pal.ink)),
            ),
          ),
      ]);

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final m = app.s.money;
    final existing = widget.p != null;
    final now = nowMs();
    final spent = existing ? planSpent(m, p, now) : 0;
    final txns = existing ? planTxns(m, p, now) : <Txn>[];
    final (from, to) = planWindow(p, now);
    final daysLeft = to == 0 ? 0 : ((to - sod(now)) / kDay).round();
    String date(int ms) => ms == 0 ? 'Open' : '${monthDay(ms)}${DateTime.fromMillisecondsSinceEpoch(ms).year != DateTime.now().year ? ', ${DateTime.fromMillisecondsSinceEpoch(ms).year}' : ''}';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SheetHead(existing ? p.name : 'New budget'),
      if (existing) ...[
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(app.cash(spent), style: cond(48, FontWeight.w800, height: 1, color: spent > p.amount ? kRed : pal.ink).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
          Padding(padding: const EdgeInsets.only(left: 8, bottom: 4), child: Text('of ${app.cash(p.amount)}', style: cond(22, FontWeight.w700, color: pal.label))),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: MoneyBar(frac: p.amount > 0 ? spent / p.amount : 0, color: spent > p.amount ? kRed : hexColor(p.color), height: 8, mark: to != 0 && now >= from && now < to ? (now - from) / (to - from) : null),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            [
              rangeLabel(from, to == 0 ? now : to - 1),
              if (planState(p, now) == 'live' && daysLeft > 0 && spent < p.amount) '${app.cash((p.amount - spent) ~/ daysLeft)} a day for $daysLeft more day${daysLeft == 1 ? '' : 's'}',
              if (spent > p.amount) '${app.cash(spent - p.amount)} over',
            ].join(' · '),
            style: inter(14, FontWeight.w600, color: pal.label),
          ),
        ),
        if (p.mode == 'added' && planState(p, now) != 'ended')
          SheetBtn('Add a spend to it', kind: BtnKind.yellow, onTap: () {
            Navigator.pop(context);
            openTxnSheet(context, null, plan: p.id);
          }),
        if (txns.isNotEmpty) ...[
          _label(pal, 'COUNTED · ${txns.length}'),
          for (final t in txns.take(8)) _MiniTxn(t),
          if (txns.length > 8)
            Pressable(
              onTap: () => openTxnList(context, plan: p.id),
              child: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text('SEE ALL ${txns.length}', style: cond(15, FontWeight.w800, ls: .08, color: pal.light ? pal.ink : kYellow))),
            ),
        ],
        _label(pal, 'DETAILS'),
      ],
      _nameEmoji(pal, _name, _emoji, hint: 'Goa trip, Diwali, wedding…'),
      _label(pal, 'Budget (${m.currency.trim()})'),
      SheetField(controller: _amount, hint: 'How much for it', keyboard: const TextInputType.numberWithOptions(decimal: true)),
      _label(pal, 'Color'),
      _Colors(p.color, (x) => setState(() => p.color = x)),
      _fr(pal, 'Runs', _Chip(_periods.firstWhere((x) => x.$1 == p.period).$2, () async {
        final x = await pickOption<String>(context, 'Runs', _periods, p.period);
        if (x != null) setState(() => p.period = x);
      })),
      _fr(pal, p.period == 'custom' ? 'Starts' : 'From', _Chip(date(p.start), () async {
        final d = await pickDate(context, DateTime.fromMillisecondsSinceEpoch(p.start));
        if (d != null) setState(() => p.start = d.millisecondsSinceEpoch);
      })),
      if (p.period == 'custom')
        _fr(pal, 'Ends', _Chip(date(p.end), () async {
          final d = await pickDate(context, DateTime.fromMillisecondsSinceEpoch(p.end == 0 ? addDays(p.start, 6) : p.end));
          if (d != null) setState(() => p.end = d.millisecondsSinceEpoch);
        }, onClear: p.end == 0 ? null : () => setState(() => p.end = 0))),
      _label(pal, 'What counts'),
      Center(
        child: Segmented<String>(
          options: const [('added', 'ONLY ONES I ADD'), ('all', 'ALL MATCHING')],
          value: p.mode,
          onChanged: (v) => setState(() => p.mode = v),
          track: pal.field,
          thumb: pal.light ? const Color(0xFF111111) : Colors.white,
          on: pal.light ? Colors.white : Colors.black,
          off: pal.label,
          style: cond(13, FontWeight.w800, ls: .06),
          segWidth: 140,
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          p.mode == 'added'
              ? 'Pick this budget under “Trip or event” when you log a spend.'
              : 'Every spend in its dates counts, narrowed to the categories and accounts below (none picked = all).',
          style: inter(13, FontWeight.w500, height: 1.45, color: pal.label),
        ),
      ),
      if (p.mode == 'all') ...[
        _label(pal, 'Categories'),
        _toggles<String>(pal, [for (final c in m.spendCats) (c.id, '${c.emoji}  ${c.name}', c.color)], p.cats),
        if (m.accounts.isNotEmpty) ...[
          _label(pal, 'Accounts'),
          _toggles<String>(pal, [for (final a in m.liveAccounts) (a.id, '${kAcctEmoji[a.type]}  ${a.name}', a.color)], p.accts),
        ],
      ],
      const SizedBox(height: 6),
      _fr(pal, 'Pin to Money tab', PillSwitch(value: p.pinned, onChanged: (v) => setState(() => p.pinned = v))),
      SheetBtn(existing ? 'Save' : 'Create budget', kind: existing ? BtnKind.plain : BtnKind.yellow, onTap: () {
        if (!_apply()) return;
        Navigator.pop(context);
        app.savePlan(p);
      }),
      if (existing)
        SheetBtn(p.archived ? 'Bring back' : 'Archive', onTap: () {
          if (!_apply()) return;
          Navigator.pop(context);
          app.savePlan(p..archived = !p.archived);
        }),
      if (existing)
        SheetBtn('Delete budget', kind: BtnKind.red, onTap: () async {
          final ok = await ask<bool>(context, 'Delete ${p.name}?', 'Spends in it stay in your log.', const [AskBtn('Delete', true, BtnKind.red)]);
          if (ok != true || !context.mounted) return;
          Navigator.pop(context);
          app.deletePlan(p.id);
        }),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Transaction list with search and filters

void openTxnList(BuildContext context, {int? month, String? cat, String? acct, bool review = false, String? plan}) =>
    _page(context, TxnListPage(month: month, cat: cat, acct: acct, review: review, plan: plan));

class TxnListPage extends StatefulWidget {
  final int? month;
  final String? cat, acct, plan;
  final bool review;
  const TxnListPage({super.key, this.month, this.cat, this.acct, this.review = false, this.plan});
  @override
  State<TxnListPage> createState() => _TxnListPageState();
}

class _TxnListPageState extends State<TxnListPage> {
  final _q = TextEditingController();

  /// `month:MS` | `30` | `90` | `year` | `all`
  late String _period = widget.month != null ? 'month:${widget.month}' : (widget.review || widget.acct != null || widget.plan != null ? 'all' : 'month:${monthStart(nowMs())}');
  String _type = 'all';
  late String? _cat = widget.cat, _acct = widget.acct;
  String? _tag;
  late bool _review = widget.review;
  late final String? _plan = widget.plan;

  @override
  void initState() {
    super.initState();
    _q.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  (int, int) _range() {
    final now = nowMs();
    if (_period.startsWith('month:')) {
      final m0 = int.parse(_period.substring(6));
      return (m0, monthEnd(m0));
    }
    return switch (_period) {
      '30' => (addDays(sod(now), -29), addDays(sod(now), 1)),
      '90' => (addDays(sod(now), -89), addDays(sod(now), 1)),
      'year' => (DateTime(DateTime.now().year).millisecondsSinceEpoch, DateTime(DateTime.now().year + 1).millisecondsSinceEpoch),
      _ => (0, 1 << 52),
    };
  }

  String _periodLabel() {
    if (_period.startsWith('month:')) {
      final m0 = int.parse(_period.substring(6));
      return '${monthLong(m0)} ${DateTime.fromMillisecondsSinceEpoch(m0).year}';
    }
    return const {'30': 'Last 30 days', '90': 'Last 90 days', 'year': 'This year', 'all': 'All time'}[_period]!;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final pal = Pal.of(context);
    final m = app.s.money;
    final pad = MediaQuery.paddingOf(context);
    final (from, to) = _range();
    final q = _q.text.trim().toLowerCase();
    final plan = m.planOf(_plan ?? '');
    final base = plan != null ? planTxns(m, plan, nowMs()) : m.txns;
    final list = base.where((t) {
      if (t.at < from || t.at >= to) return false;
      if (_review && !t.review) return false;
      if (_cat != null && t.cat != _cat) return false;
      if (_acct != null && t.acct != _acct && t.to != _acct) return false;
      if (_tag != null && !t.tags.contains(_tag)) return false;
      switch (_type) {
        case 'spend':
          if (!t.isSpend) return false;
        case 'income':
          if (!t.income) return false;
        case 'moves':
          if (!t.isMove) return false;
      }
      if (q.isNotEmpty) {
        final hay = '${t.title} ${t.note} ${m.catOf(t.cat).name} ${t.tags.join(' ')} ${m.acctOf(t.acct)?.name ?? ''}'.toLowerCase();
        if (!hay.contains(q) && !plainAmount(t.amount.abs()).contains(q)) return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => b.at.compareTo(a.at));
    final out = list.fold(0, (a, t) => a + spendOf(t, m));
    final inc = list.where((t) => t.income && !t.excluded).fold(0, (a, t) => a + t.amount);

    // Flatten into day headers and rows.
    final rows = <Object>[];
    String? last;
    for (final t in list) {
      final d = dstr(t.at);
      if (d != last) {
        last = d;
        rows.add(d);
      }
      rows.add(t);
    }

    Widget filter(String label, bool on, VoidCallback onTap, {VoidCallback? onClear}) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Pressable(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              padding: EdgeInsets.fromLTRB(14, 9, onClear != null ? 10 : 14, 9),
              decoration: BoxDecoration(color: on ? Colors.white : const Color(0xFF1C1C20), borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(label, style: cond(15, FontWeight.w800, ls: .04, color: on ? Colors.black : const Color(0xFFE4E4E7))),
                if (onClear != null) ...[
                  const SizedBox(width: 6),
                  GestureDetector(onTap: onClear, child: Icon(Icons.close, size: 16, color: on ? Colors.black : const Color(0xFFE4E4E7))),
                ],
              ]),
            ),
          ),
        );
    final tags = allTags(m);
    final title = plan != null ? plan.name : (widget.review ? 'To review' : 'Transactions');

    return Scaffold(
      backgroundColor: kBlack,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: EdgeInsets.fromLTRB(18, 10 + pad.top, 18, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              PageHead(
                title: title,
                sub: '${list.length} · OUT ${app.cash(out)}${inc > 0 ? ' · IN ${app.cash(inc)}' : ''}',
                trailing: CircleBtn(label: 'Close', onTap: () => Navigator.pop(context), child: const Text('✕', style: TextStyle(fontSize: 16, color: Colors.white))),
              ),
              TextField(
                controller: _q,
                style: inter(16, FontWeight.w500, color: Colors.white),
                cursorColor: kYellow,
                decoration: InputDecoration(
                  hintText: 'Search title, note, tag, amount…',
                  hintStyle: inter(16, FontWeight.w500, color: const Color(0xFF71717A)),
                  prefixIcon: const Icon(Icons.search, color: Color(0xFF71717A)),
                  suffixIcon: q.isEmpty ? null : IconButton(onPressed: _q.clear, icon: const Icon(Icons.close, color: Color(0xFF71717A))),
                  filled: true,
                  fillColor: const Color(0xFF141416),
                  isDense: true,
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 40,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  if (plan == null)
                    filter(_periodLabel().toUpperCase(), true, () async {
                      final cur = monthStart(nowMs());
                      final x = await pickOption<String>(context, 'Period', [
                        ('month:$cur', 'This month'),
                        ('month:${addMonths(cur, -1)}', 'Last month'),
                        ('30', 'Last 30 days'),
                        ('90', 'Last 90 days'),
                        ('year', 'This year'),
                        ('all', 'All time'),
                      ], _period);
                      if (x != null) setState(() => _period = x);
                    }),
                  filter(const {'all': 'ALL TYPES', 'spend': 'SPENDING', 'income': 'INCOME', 'moves': 'TRANSFERS & MOVES'}[_type]!, _type != 'all', () async {
                    final x = await pickOption<String>(context, 'Type', const [('all', 'Everything'), ('spend', 'Spending & refunds'), ('income', 'Income'), ('moves', 'Transfers, goals & loans')], _type);
                    if (x != null) setState(() => _type = x);
                  }, onClear: _type == 'all' ? null : () => setState(() => _type = 'all')),
                  filter(_cat == null ? 'CATEGORY' : m.catOf(_cat!).name.toUpperCase(), _cat != null, () async {
                    final x = await pickOption<String>(context, 'Category', [for (final c in m.cats) (c.id, '${c.emoji}  ${c.name}${c.income ? '  (income)' : ''}')], _cat ?? '');
                    if (x != null) setState(() => _cat = x);
                  }, onClear: _cat == null ? null : () => setState(() => _cat = null)),
                  if (m.accounts.isNotEmpty)
                    filter(_acct == null ? 'ACCOUNT' : (m.acctOf(_acct!)?.name ?? 'ACCOUNT').toUpperCase(), _acct != null, () async {
                      final x = await pickOption<String>(context, 'Account', [for (final a in m.accounts) (a.id, '${kAcctEmoji[a.type]}  ${a.name}')], _acct ?? '');
                      if (x != null) setState(() => _acct = x);
                    }, onClear: _acct == null ? null : () => setState(() => _acct = null)),
                  if (tags.isNotEmpty)
                    filter(_tag == null ? 'TAG' : '#${_tag!.toUpperCase()}', _tag != null, () async {
                      final x = await pickOption<String>(context, 'Tag', [for (final g in tags) (g, '#$g')], _tag ?? '');
                      if (x != null) setState(() => _tag = x);
                    }, onClear: _tag == null ? null : () => setState(() => _tag = null)),
                  filter('TO REVIEW', _review, () => setState(() => _review = !_review)),
                ]),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: EdgePanel(
                  child: rows.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(q.isNotEmpty ? 'Nothing matches “${_q.text.trim()}”.' : 'Nothing here.', style: inter(15, FontWeight.w500, color: pal.sub)),
                        )
                      : ListView.builder(
                          padding: EdgeInsets.only(bottom: 40 + pad.bottom),
                          itemCount: rows.length,
                          itemBuilder: (context, i) {
                            final r = rows[i];
                            if (r is String) {
                              final sum = list.where((t) => dstr(t.at) == r).fold(0, (a, t) => a + spendOf(t, m));
                              final d = dms(r);
                              final y = DateTime.fromMillisecondsSinceEpoch(d).year;
                              return DayLine(
                                label: '${dueLabel(r, nowMs())}${y != DateTime.now().year && !dueLabel(r, nowMs()).contains('$y') ? ', $y' : ''}'.toUpperCase(),
                                total: sum > 0 ? app.cash(sum) : '',
                              );
                            }
                            return TxnRow(key: ValueKey((r as Txn).id), txn: r);
                          },
                        ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Money tab sections: order and visibility

void openSectionsPage(BuildContext context) => _page(context, const SectionsPage());

class SectionsPage extends StatelessWidget {
  const SectionsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final pal = Pal.of(context);
    final pad = MediaQuery.paddingOf(context);
    final list = app.s.money.sections;
    final on = list.where((s) => s.on).length;
    return Scaffold(
      backgroundColor: kBlack,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: EdgeInsets.fromLTRB(18, 10 + pad.top, 18, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              PageHead(
                title: 'Money tab',
                sub: '$on OF ${list.length} SECTIONS SHOWN',
                trailing: CircleBtn(label: 'Close', onTap: () => Navigator.pop(context), child: const Text('✕', style: TextStyle(fontSize: 16, color: Colors.white))),
              ),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(color: pal.panel, borderRadius: const BorderRadius.vertical(top: Radius.circular(16))),
                  child: ReorderableListView.builder(
                    padding: EdgeInsets.fromLTRB(14, 8, 14, 28 + pad.bottom),
                    buildDefaultDragHandles: false,
                    itemCount: list.length,
                    onReorderStart: (_) => buzz(),
                    onReorderItem: app.moveSection,
                    header: Padding(
                      padding: const EdgeInsets.fromLTRB(4, 10, 4, 10),
                      child: Text('Turn sections on or off, and drag the handle to change the order. The month and what’s left stay at the top.',
                          style: inter(13, FontWeight.w500, height: 1.45, color: pal.label)),
                    ),
                    proxyDecorator: (child, _, anim) => AnimatedBuilder(
                      animation: anim,
                      builder: (_, child) {
                        final t = Curves.easeOutCubic.transform(anim.value);
                        return Transform.scale(
                          scale: 1 + .03 * t,
                          child: Material(
                            color: Color.lerp(pal.panel, pal.field, t),
                            borderRadius: BorderRadius.circular(12),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .5 * t), blurRadius: 24, offset: const Offset(0, 8))],
                              ),
                              child: child,
                            ),
                          ),
                        );
                      },
                      child: child,
                    ),
                    itemBuilder: (context, i) {
                      final s = list[i];
                      return ReorderableDelayedDragStartListener(
                        key: ValueKey(s.id),
                        index: i,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.panelRule))),
                          child: Row(children: [
                            ReorderableDragStartListener(
                              index: i,
                              child: Semantics(
                                label: 'Drag to reorder ${kMoneySections[s.id]}',
                                child: Padding(padding: const EdgeInsets.fromLTRB(4, 8, 12, 8), child: Icon(Icons.drag_indicator, size: 24, color: pal.placeholder)),
                              ),
                            ),
                            Expanded(
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 200),
                                opacity: s.on ? 1 : .45,
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(kMoneySections[s.id]!.toUpperCase(), style: cond(21, FontWeight.w800, color: pal.ink)),
                                  Text(kMoneySectionHints[s.id]!, style: inter(13, FontWeight.w500, color: pal.label)),
                                ]),
                              ),
                            ),
                            const SizedBox(width: 10),
                            PillSwitch(value: s.on, onChanged: (v) => app.setSection(s.id, v)),
                          ]),
                        ),
                      );
                    },
                    footer: Padding(
                      padding: const EdgeInsets.only(top: 18),
                      child: SheetBtn('Reset to default', onTap: () async {
                        final ok = await ask<bool>(context, 'Reset the Money tab?', 'Shows every section in the original order.', const [AskBtn('Reset', true)]);
                        if (ok == true) app.resetSections();
                      }),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// CSV export

String _csv(String s) => s.contains(RegExp('[",\n]')) ? '"${s.replaceAll('"', '""')}"' : s;

/// Every transaction as CSV (spreadsheets, or another money app).
String moneyCsv(Money m) {
  final b = StringBuffer('Date,Time,Type,Title,Category,Account,To account,Amount,Currency,Tags,Note,Goal/loan,Trip/event\n');
  final list = List.of(m.txns)..sort((a, b) => a.at.compareTo(b.at));
  for (final t in list) {
    final d = DateTime.fromMillisecondsSinceEpoch(t.at);
    final signed = switch (t.type) {
      'spend' || 'save' || 'lent' => -t.amount,
      'repay' => m.goalOf(t.goal)?.kind == 'borrowed' ? -t.amount : t.amount,
      _ => t.amount,
    };
    b.writeln([
      dstr(t.at),
      '${pad(d.hour)}:${pad(d.minute)}',
      t.type,
      _csv(t.title),
      _csv(t.isSpend || t.income ? m.catOf(t.cat).name : ''),
      _csv(m.acctOf(t.acct)?.name ?? ''),
      _csv(m.acctOf(t.to)?.name ?? ''),
      (signed / 100).toStringAsFixed(2),
      _csv(m.currency.trim()),
      _csv(t.tags.join(' ')),
      _csv(t.note),
      _csv(m.goalOf(t.goal)?.name ?? ''),
      _csv(m.planOf(t.plan)?.name ?? ''),
    ].join(','));
  }
  return b.toString();
}

// ---------------------------------------------------------------------------
// CSV import

/// Picks a CSV file and opens the column-matching sheet.
Future<void> openCsvImport(BuildContext context) async {
  final app = context.read<AppState>();
  final files = await FilePicker.pickFiles();
  if (files.isEmpty || !context.mounted) return;
  final f = files.first;
  final text = utf8.decode(await f.readAsBytes(), allowMalformed: true);
  final rows = parseCsv(text);
  if (rows.length < 2) {
    app.showToast("That file doesn't have any rows to import");
    return;
  }
  if (!context.mounted) return;
  await _sheet(context, _CsvSheet(name: f.name, rows: rows));
}

class _CsvSheet extends StatefulWidget {
  final String name;
  final List<List<String>> rows;
  const _CsvSheet({required this.name, required this.rows});
  @override
  State<_CsvSheet> createState() => _CsvSheetState();
}

class _CsvSheetState extends State<_CsvSheet> {
  late final AppState app = context.read<AppState>();
  late final List<String> header = widget.rows.first;
  late final List<List<String>> body = widget.rows.skip(1).toList();
  late final CsvMap map = guessMap(header);
  String _fmt = 'auto';
  bool _positive = false, _reviewed = false, _createCats = true;
  late String _acct = app.s.money.newAcct;

  @override
  void initState() {
    super.initState();
    // Most of the file's amounts positive and no debit/credit split: spending is probably positive.
    if (map.amount >= 0 && map.debit < 0 && map.credit < 0 && map.type < 0) {
      final vals = [for (final r in body.take(200)) if (map.amount < r.length) parseSigned(r[map.amount])].whereType<int>();
      _positive = vals.isNotEmpty && vals.where((v) => v > 0).length > vals.length * .8;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final m = app.s.money;
    final r = map.usable
        ? buildCsvImport(body, map, m, dateFormat: _fmt, expensesPositive: _positive, acct: _acct, reviewed: _reviewed, createCats: _createCats)
        : null;
    String col(int i) => i < 0 ? 'None' : (header[i].isEmpty ? 'Column ${i + 1}' : header[i]);
    final sample = r == null ? <Txn>[] : r.txns.take(3).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SheetHead('Import CSV'),
      Text('${widget.name} · ${body.length} rows', style: inter(14, FontWeight.w600, color: pal.label)),
      _label(pal, 'MATCH COLUMNS'),
      for (final e in CsvMap.fields.entries)
        if (e.key != 'time' || map.time >= 0 || header.length > 4)
          _fr(pal, e.value, _Chip(col(map[e.key]), () async {
            final x = await pickOption<int>(context, e.value, [(-1, 'None'), for (var i = 0; i < header.length; i++) (i, col(i))], map[e.key]);
            if (x != null) setState(() => map[e.key] = x);
          })),
      _fr(pal, 'Date format', _Chip(_fmt == 'auto' ? 'Detect' : _fmt, () async {
        final x = await pickOption<String>(context, 'Date format', [for (final f in kDateFormats) (f, f == 'auto' ? 'Detect automatically' : f)], _fmt);
        if (x != null) setState(() => _fmt = x);
      })),
      _label(pal, 'OPTIONS'),
      if (m.accounts.isNotEmpty)
        _fr(pal, 'Import into', _Chip(_acctLabel(m, _acct), () async {
          final x = await _pickAcct(context, 'Import into', _acct);
          if (x != null) setState(() => _acct = x);
        }), hint: 'Rows that name one of your accounts go there instead'),
      _fr(pal, 'Spending is positive', PillSwitch(value: _positive, onChanged: (v) => setState(() => _positive = v)), hint: 'Turn on if purchases show as 45.00 instead of −45.00'),
      _fr(pal, 'Create missing categories', PillSwitch(value: _createCats, onChanged: (v) => setState(() => _createCats = v)), hint: 'Otherwise they’re sorted by keyword'),
      _fr(pal, 'Mark as reviewed', PillSwitch(value: _reviewed, onChanged: (v) => setState(() => _reviewed = v)), hint: 'Off: they wait in To Review'),
      const SizedBox(height: 14),
      if (r == null)
        Text('Pick at least a date column and an amount (or money in / out) column.', style: inter(14, FontWeight.w600, height: 1.45, color: kRed))
      else ...[
        Text(
          [
            '${r.txns.length} ready to import',
            if (r.dupes > 0) '${r.dupes} already here (skipped)',
            if (r.skipped > 0) "${r.skipped} couldn't be read",
            if (r.newCats.isNotEmpty) '${r.newCats.length} new categor${r.newCats.length == 1 ? 'y' : 'ies'}',
          ].join(' · '),
          style: inter(14, FontWeight.w700, height: 1.45, color: pal.ink),
        ),
        for (final t in sample)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${monthDay(t.at)} ${DateTime.fromMillisecondsSinceEpoch(t.at).year} · ${t.title.isEmpty ? '(no title)' : t.title} · ${t.type == 'income' || t.type == 'refund' ? '+' : ''}${app.cash(t.amount)} · ${m.catOf(t.cat).name == 'Other' ? ([...m.cats, ...r.newCats].where((c) => c.id == t.cat).firstOrNull?.name ?? 'Other') : m.catOf(t.cat).name}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: inter(13, FontWeight.w500, color: pal.label),
            ),
          ),
      ],
      SheetBtn(r == null || r.txns.isEmpty ? 'Nothing to import' : 'Import ${r.txns.length}', kind: BtnKind.yellow, onTap: r == null || r.txns.isEmpty
          ? null
          : () {
              Navigator.pop(context);
              app.importCsv(r.txns, r.newCats);
            }),
    ]);
  }
}