// One search across everything: events (next or latest date), tasks, money
// entries, and accounts, goals, loans and trip budgets by name. Opened from
// the magnifier in the top bar.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/store.dart';
import '../core/logic.dart';
import '../core/model.dart';
import '../core/money.dart';
import '../core/tasks.dart';
import '../core/util.dart';
import 'money.dart';
import 'money_pages.dart';
import 'money_sections.dart';
import 'tasks.dart';
import 'theme.dart';
import 'widgets.dart';

void openSearch(BuildContext context) {
  final app = context.read<AppState>();
  final pal = Pal.of(context);
  Navigator.of(context).push(PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 380),
    reverseTransitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (_, _, _) => ChangeNotifierProvider.value(value: app, child: PalScope(pal: pal, child: const SearchPage())),
    transitionsBuilder: (_, anim, _, child) => FadeTransition(
      opacity: anim,
      child: SlideTransition(position: Tween(begin: const Offset(0, .03), end: Offset.zero).animate(CurvedAnimation(parent: anim, curve: kEase)), child: child),
    ),
  ));
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

/// An event hit: the master event and the occurrence to open.
class _EvHit {
  final Event ev;
  final int at;
  const _EvHit(this.ev, this.at);
}

class _SearchPageState extends State<SearchPage> {
  final _q = TextEditingController();

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

  bool _has(String hay, List<String> words) {
    final h = hay.toLowerCase();
    return words.every(h.contains);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final pal = Pal.of(context);
    final pad = MediaQuery.paddingOf(context);
    final s = app.s;
    final m = s.money;
    final words = _q.text.trim().toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final now = nowMs();

    final events = <_EvHit>[];
    final tasks = <Task>[];
    final txns = <Txn>[];
    final things = <(String, String, String, VoidCallback)>[]; // emoji, title, sub, open
    if (words.isNotEmpty) {
      // Events: the next time each matching one happens (or the last, if it's over).
      final upcoming = occurrences(s, sod(now), addDays(sod(now), 366));
      for (final e in s.events) {
        if (!_has('${e.title} ${e.loc} ${e.notes} ${s.lineOf(e.cat).name}', words)) continue;
        final next = upcoming.where((o) => (o.seriesId ?? o.id) == e.id && o.end >= now).firstOrNull;
        events.add(_EvHit(next ?? e, (next ?? e).start));
      }
      events.sort((a, b) {
        final fa = a.at >= sod(now), fb = b.at >= sod(now);
        if (fa != fb) return fa ? -1 : 1;
        return fa ? a.at.compareTo(b.at) : b.at.compareTo(a.at);
      });
      for (final t in s.tasks) {
        if (_has('${t.title} ${t.notes} ${t.subs.map((x) => x.title).join(' ')} ${s.lineOf(t.cat).name}', words)) tasks.add(t);
      }
      tasks.sort((a, b) => a.done != b.done ? (a.done ? 1 : -1) : compareTasks(a, b));
      for (final t in m.txns) {
        final hay = '${t.title} ${t.note} ${t.tags.join(' ')} ${m.catOf(t.cat).name} ${m.acctOf(t.acct)?.name ?? ''} ${plainAmount(t.amount.abs())}';
        if (_has(hay, words)) txns.add(t);
      }
      txns.sort((a, b) => b.at.compareTo(a.at));
      final bal = app.balancesNow();
      for (final a in m.accounts) {
        if (_has(a.name, words)) things.add((kAcctEmoji[a.type]!, a.name, 'Account · ${app.cash(bal[a.id] ?? 0)}', () => openAccountSheet(context, a)));
      }
      for (final g in m.goals) {
        if (_has(g.name, words)) things.add((g.emoji, g.name, g.isLoan ? 'Loan' : 'Goal', () => g.isLoan ? openLoanSheet(context, g) : openGoalSheet(context, g)));
      }
      for (final p in m.plans) {
        if (_has(p.name, words)) things.add((p.emoji, p.name, 'Trip / event budget', () => openPlanSheet(context, p)));
      }
      for (final l in s.lines) {
        if (_has(l.name, words)) {
          things.add(('🚇', 'Line ${l.label} · ${l.name}', 'Show on the board', () {
            Navigator.pop(context);
            app.showLine(l.id);
          }));
        }
      }
    }
    final total = events.length + tasks.length + txns.length + things.length;

    Widget head(String label, int n) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
          child: Text('$label · $n', style: cond(15, FontWeight.w800, ls: .08, color: pal.sub)),
        );
    Widget more(int n) => n <= 0
        ? const SizedBox.shrink()
        : Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 0), child: Text('+ $n more · type more to narrow it down', style: inter(13, FontWeight.w600, color: pal.label)));

    final items = <Widget>[
      if (things.isNotEmpty) ...[
        head('MONEY & LINES', things.length),
        for (final (emoji, title, sub, open) in things)
          PanelRow(lead: EmojiBadge(emoji, '#71717a', size: 36), title: title, sub: sub, onTap: open, semantics: '$title, $sub'),
      ],
      if (events.isNotEmpty) ...[
        head('EVENTS', events.length),
        for (final h in events.take(30)) _EventHit(hit: h),
        more(events.length - 30),
      ],
      if (tasks.isNotEmpty) ...[
        head('TASKS', tasks.length),
        for (final t in tasks.take(30)) TaskRow(key: ValueKey('s-${t.id}'), task: t, showDue: true),
        more(tasks.length - 30),
      ],
      if (txns.isNotEmpty) ...[
        head('TRANSACTIONS', txns.length),
        for (final t in txns.take(50)) TxnRow(key: ValueKey('s-${t.id}'), txn: t, showDate: true),
        more(txns.length - 50),
      ],
    ];

    return Scaffold(
      backgroundColor: kBlack,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: EdgeInsets.fromLTRB(18, 10 + pad.top, 18, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 14),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _q,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      style: inter(18, FontWeight.w500, color: Colors.white),
                      cursorColor: kYellow,
                      decoration: InputDecoration(
                        hintText: 'Search events, tasks, money…',
                        hintStyle: inter(18, FontWeight.w500, color: const Color(0xFF71717A)),
                        prefixIcon: const Icon(Icons.search, color: Color(0xFFA1A1AA)),
                        suffixIcon: _q.text.isEmpty ? null : IconButton(onPressed: _q.clear, icon: const Icon(Icons.close, color: Color(0xFFA1A1AA))),
                        filled: true,
                        fillColor: const Color(0xFF141416),
                        isDense: true,
                        contentPadding: const EdgeInsets.all(14),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  CircleBtn(label: 'Close', onTap: () => Navigator.pop(context), child: const Text('✕', style: TextStyle(fontSize: 16, color: Colors.white))),
                ]),
              ),
              Expanded(
                child: EdgePanel(
                  child: words.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text('Find anything: an event, a task, a shop you paid, a tag, an amount, an account.',
                              style: inter(15, FontWeight.w500, height: 1.45, color: pal.sub)),
                        )
                      : total == 0
                          ? Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text('Nothing matches “${_q.text.trim()}”.', style: inter(15, FontWeight.w500, color: pal.sub)),
                            )
                          : ListView(padding: EdgeInsets.only(bottom: 40 + pad.bottom), keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, children: items),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _EventHit extends StatelessWidget {
  final _EvHit hit;
  const _EventHit({required this.hit});
  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final ev = hit.ev;
    final line = app.lineOf(ev.cat);
    final when = ev.allDay ? dueLabel(dstr(hit.at), nowMs()) : '${dueLabel(dstr(hit.at), nowMs())}, ${fmtT(hit.at, use24h: app.use24h)}';
    return PanelRow(
      onTap: () {
        Navigator.pop(context);
        app.setSel(dstr(hit.at));
        app.openForm(ev);
      },
      semantics: '${ev.title}, $when',
      lead: LineBadge(line, size: 36, fontSize: 15),
      title: ev.title,
      sub: [when, if (ev.loc.isNotEmpty) ev.loc, if (ev.repeat != null || ev.seriesId != null) '↻'].join('  ·  '),
    );
  }
}
