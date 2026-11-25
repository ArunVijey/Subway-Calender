// Tasks tab, the task row (also used on the board), and the task editor.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app/store.dart';
import '../core/money.dart';
import '../core/tasks.dart';
import '../core/util.dart';
import 'board.dart';
import 'haptics.dart';
import 'lines.dart';
import 'motion.dart';
import 'pickers.dart';
import 'theme.dart';
import 'widgets.dart';


class TasksView extends StatefulWidget {
  const TasksView({super.key});
  @override
  State<TasksView> createState() => _TasksViewState();
}

class _TasksViewState extends State<TasksView> with SingleTickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(vsync: this, duration: Entrance.total);
  int? _epoch;

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
    final now = nowMs(), today = dstr(now), tomorrow = dstr(addDays(sod(now), 1));
    bool keep(Task t) => (app.activeCat == null || t.cat == app.activeCat) && (!app.starOnly || t.star);
    final byPrio = app.taskSort == 'prio';
    final open = app.s.tasks.where((t) => !t.done && keep(t)).toList()..sort(byPrio ? compareTasksByPrio : compareTasks);
    final done = app.s.tasks.where((t) => t.done && keep(t)).toList()..sort((a, b) => b.doneAt.compareTo(a.doneAt));

    final groups = <(String, List<Task>, bool)>[
      ('OVERDUE', open.where((t) => t.due.isNotEmpty && t.due.compareTo(today) < 0).toList(), true),
      ('TODAY', open.where((t) => t.due == today).toList(), false),
      ('TOMORROW', open.where((t) => t.due == tomorrow).toList(), false),
      ('UPCOMING', open.where((t) => t.due.compareTo(tomorrow) > 0).toList(), false),
      ('SOMEDAY', open.where((t) => t.due.isEmpty).toList(), false),
    ];
    final overdue = groups.first.$2.length;
    final sub = open.isEmpty
        ? (done.isEmpty ? 'NOTHING ON THE LIST' : 'ALL CLEAR')
        : '${open.length} OPEN${overdue > 0 ? ' · $overdue OVERDUE' : ''}${groups[1].$2.isNotEmpty ? ' · ${groups[1].$2.length} TODAY' : ''}';

    final items = <Widget>[];
    var k = 0;
    Widget enter(Widget w) => Entrance(intro: _intro, index: k++, child: w);
    for (final (label, list, red) in groups) {
      if (list.isEmpty) continue;
      items.add(enter(GroupHead(label, count: list.length, color: red ? kRed : null, first: items.isEmpty)));
      for (final t in list) {
        items.add(enter(TaskRow(key: ValueKey('${t.id}|${t.due}'), task: t, swipe: true, showDue: label != 'TODAY' && label != 'TOMORROW')));
      }
    }
    if (open.isEmpty) items.add(enter(_Empty(anyDone: done.isNotEmpty, filtered: app.activeCat != null || app.starOnly)));
    if (done.isNotEmpty) {
      items.add(enter(_CompletedHead(count: done.length, open: app.showCompleted)));
      items.add(_FoldList(
        open: app.showCompleted,
        children: [for (final t in done.take(60)) TaskRow(key: ValueKey('done-${t.id}'), task: t, showDue: true)],
      ));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PageHead(title: 'Tasks', sub: sub, trailing: const GearButton()),
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(children: [
          Expanded(child: LineChips(lines: app.s.lines, active: app.activeCat, onTap: app.toggleCat)),
          const SizedBox(width: 10),
          FilterPill(
            label: '★ STARRED',
            on: app.starOnly,
            onTap: app.toggleStarOnly,
          ),
          const SizedBox(width: 8),
          // Sort: by due day (off) or priority first (on).
          Semantics(
            button: true,
            toggled: byPrio,
            label: byPrio ? 'Sorted by priority. Tap to sort by due day' : 'Sort by priority',
            excludeSemantics: true,
            child: Pressable(
              scale: .88,
              onTap: () {
                tick();
                app.taskSort = byPrio ? 'due' : 'prio';
                app.showToast(byPrio ? 'Sorted by due day' : 'Priority first');
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: byPrio ? Colors.white : const Color(0xFF1C1C20), shape: BoxShape.circle),
                child: Icon(byPrio ? Icons.flag_rounded : Icons.outlined_flag_rounded, size: 20, color: byPrio ? const Color(0xFFF87171) : const Color(0xFFE4E4E7)),
              ),
            ),
          ),
        ]),
      ),
      Expanded(
        child: EdgePanel(
          child: ListView(
            key: const PageStorageKey('tasks'),
            padding: const EdgeInsets.only(bottom: 120),
            children: items,
          ),
        ),
      ),
    ]);
  }
}

/// The board-colored panel that runs edge to edge, past the page's side padding.
class EdgePanel extends StatelessWidget {
  final Widget child;
  const EdgePanel({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return LayoutBuilder(
      builder: (context, box) => OverflowBox(
        minWidth: box.maxWidth + 36,
        maxWidth: box.maxWidth + 36,
        child: DecoratedBox(
          decoration: BoxDecoration(color: pal.board, border: Border(top: BorderSide(color: pal.rule, width: 2))),
          child: child,
        ),
      ),
    );
  }
}

/// Rounded toggle pill next to the line chips (★ STARRED).
class FilterPill extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback? onTap;
  const FilterPill({super.key, required this.label, required this.on, this.onTap});
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: on,
        label: label,
        excludeSemantics: true,
        child: Pressable(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            decoration: BoxDecoration(color: on ? Colors.white : const Color(0xFF1C1C20), borderRadius: BorderRadius.circular(20)),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 260),
              style: cond(15, FontWeight.w800, ls: .04, color: on ? Colors.black : const Color(0xFFE4E4E7)),
              child: Text(label),
            ),
          ),
        ),
      );
}

/// Section label on the panel: "TODAY · 3".
class GroupHead extends StatelessWidget {
  final String label;
  final int? count;
  final Color? color;
  final bool first;
  final Widget? trailing;
  const GroupHead(this.label, {super.key, this.count, this.color, this.first = false, this.trailing});
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final c = color ?? pal.sub;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, first ? 16 : 26, 20, 8),
      child: Row(children: [
        Text(label, style: cond(15, FontWeight.w800, ls: .08, color: c)),
        if (count != null) ...[
          const SizedBox(width: 8),
          Text('$count', style: cond(15, FontWeight.w800, ls: .08, color: c.withValues(alpha: .6))),
        ],
        const Spacer(),
        ?trailing,
      ]),
    );
  }
}

class _CompletedHead extends StatelessWidget {
  final int count;
  final bool open;
  const _CompletedHead({required this.count, required this.open});
  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final pal = Pal.of(context);
    return Semantics(
      button: true,
      expanded: open,
      label: '${open ? 'Hide' : 'Show'} $count completed',
      excludeSemantics: true,
      child: Pressable(
        scale: .98,
        onTap: () {
          tick();
          app.toggleCompleted();
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 26, 12, 4),
          child: Row(children: [
            Text('COMPLETED', style: cond(15, FontWeight.w800, ls: .08, color: pal.sub)),
            const SizedBox(width: 8),
            Text('$count', style: cond(15, FontWeight.w800, ls: .08, color: pal.sub.withValues(alpha: .6))),
            const SizedBox(width: 6),
            AnimatedRotation(
              turns: open ? .5 : 0,
              duration: Motion.snappyDur,
              curve: Motion.snappy,
              child: SvgIcon('chev', size: 14, color: pal.sub),
            ),
            const Spacer(),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: open ? 1 : 0,
              child: IgnorePointer(
                ignoring: !open,
                child: Pressable(
                  onTap: () async {
                    final ok = await ask<bool>(context, 'Clear completed?', 'Removes $count finished task${count == 1 ? '' : 's'}. Logged payments stay in Money.',
                        const [AskBtn('Clear them', true, BtnKind.red)]);
                    if (ok == true) app.clearCompleted();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                    child: Text('CLEAR', style: cond(14, FontWeight.w800, ls: .08, color: kRed)),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// A folding list (height + fade from the top edge); closed, it builds nothing.
class _FoldList extends StatefulWidget {
  final bool open;
  final List<Widget> children;
  const _FoldList({required this.open, required this.children});
  @override
  State<_FoldList> createState() => _FoldListState();
}

class _FoldListState extends State<_FoldList> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Motion.smoothDur, value: widget.open ? 1 : 0);

  @override
  void didUpdateWidget(_FoldList old) {
    super.didUpdateWidget(old);
    if (widget.open == old.open) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = widget.open ? 1 : 0;
    } else if (widget.open) {
      _c.animateTo(1, curve: Motion.smooth);
    } else {
      _c.animateBack(0, duration: const Duration(milliseconds: 340), curve: Curves.easeOutCubic);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          if (_c.value == 0 && !widget.open) return const SizedBox(width: double.infinity);
          final v = _c.value.clamp(0.0, 1.0);
          return ClipRect(child: Align(alignment: Alignment.topCenter, heightFactor: v, child: Opacity(opacity: Curves.easeOut.transform(v), child: child)));
        },
        child: Column(children: widget.children),
      );
}

class _Empty extends StatelessWidget {
  final bool anyDone, filtered;
  const _Empty({required this.anyDone, required this.filtered});
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 56, 28, 24),
      child: Column(children: [
        Text(filtered ? 'NOTHING HERE' : (anyDone ? 'ALL CLEAR' : 'NO TASKS YET'), style: cond(30, FontWeight.w800, ls: .02, color: pal.text)),
        const SizedBox(height: 8),
        Text(
          filtered
              ? 'No open tasks match this filter.'
              : 'Tap + and type it the way you’d say it:\n“Submit HW fri 5pm” or “Pay rent ₹15000 1st monthly”.',
          textAlign: TextAlign.center,
          style: inter(14, FontWeight.w500, height: 1.5, color: pal.sub),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// One task.

/// Line colors as ink: very light ones (the yellow line) are deepened on the cream board so rings stay visible.
Color inkFor(Color c, Pal pal) => pal.light && c.computeLuminance() > .5 ? Color.lerp(c, Colors.black, .28)! : c;

/// "Today · Fri, Nov 20" / "Mon, Nov 23" for the editor.
String dueLong(String due, int now) {
  final d = dms(due);
  final s = '${weekdayShort(d)}, ${monthDay(d)}';
  final short = dueLabel(due, now);
  final y = DateTime.fromMillisecondsSinceEpoch(d).year;
  final full = y == DateTime.fromMillisecondsSinceEpoch(now).year ? s : '$s, $y';
  return short == 'Today' || short == 'Tomorrow' || short == 'Yesterday' ? '$short · $full' : full;
}

/// Round checkbox in the line's color. Fills and ticks when done.
class TaskCheck extends StatelessWidget {
  final bool done;
  final Color color;
  final double size;
  final VoidCallback? onTap;
  final String label;
  const TaskCheck({super.key, required this.done, required this.color, this.size = 26, this.onTap, this.label = 'Done'});
  @override
  Widget build(BuildContext context) {
    final onC = color.computeLuminance() > .45 ? Colors.black : Colors.white;
    return Semantics(
      checked: done,
      button: true,
      label: label,
      excludeSemantics: true,
      child: Pressable(
        scale: .8,
        onTap: onTap,
        // A bigger tap target than the circle.
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? color : Colors.transparent,
              border: Border.all(color: color, width: size > 22 ? 2.4 : 2),
            ),
            child: AnimatedScale(
              duration: Motion.bouncyDur,
              curve: Motion.bouncy,
              scale: done ? 1 : 0,
              child: Center(child: SvgIcon('check', size: size * .62, color: onC)),
            ),
          ),
        ),
      ),
    );
  }
}

/// A task on a board-colored panel: check · title / due, line, repeat · amount, star.
class TaskRow extends StatefulWidget {
  final Task task;

  /// Swipe right = done, swipe left = tomorrow.
  final bool swipe;

  /// Show the due day in the meta line (off when the group already says it).
  final bool showDue;
  const TaskRow({super.key, required this.task, this.swipe = false, this.showDue = true});
  @override
  State<TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends State<TaskRow> {
  /// Ticked, waiting a beat so the check is seen before the row moves away.
  bool _ticking = false;

  void _toggle() {
    final app = context.read<AppState>();
    final t = widget.task;
    if (t.done) return app.setTaskDone(t.id, false);
    if (MediaQuery.disableAnimationsOf(context)) return app.setTaskDone(t.id, true);
    setState(() => _ticking = true);
    Future.delayed(const Duration(milliseconds: 420), () {
      if (mounted) app.setTaskDone(t.id, true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final pal = Pal.of(context);
    final t = widget.task;
    final line = app.lineOf(t.cat);
    final color = inkFor(hexColor(line.color), Pal.of(context));
    final now = nowMs();
    final done = t.done || _ticking;
    final overdue = t.overdue(now);

    final meta = <InlineSpan>[];
    void add(String s, {Color? c}) {
      if (meta.isNotEmpty) meta.add(TextSpan(text: '  ·  ', style: TextStyle(color: pal.sub.withValues(alpha: .6))));
      meta.add(TextSpan(text: s, style: c == null ? null : TextStyle(color: c)));
    }

    if (t.done && t.doneAt > 0) {
      add('Done ${dueLabel(dstr(t.doneAt), now).toLowerCase()}');
    } else {
      final due = widget.showDue || overdue ? dueLabel(t.due, now) : '';
      final time = t.time != null ? minLabel(t.time!, use24h: app.use24h) : '';
      final when = [due, time].where((x) => x.isNotEmpty).join(' ');
      if (when.isNotEmpty) add(when, c: overdue ? kRed : null);
    }
    add(line.name);
    if (!t.done && app.s.events.any((e) => e.task == t.id)) add('On board');
    if (t.repeat.isNotEmpty) add('↻ ${repeatLabel(t.repeat).toLowerCase()}');
    if (!t.done && t.due.isNotEmpty && t.remind != null && t.remind!.isNotEmpty) add('🔔');
    if (t.subs.isNotEmpty) add('${t.subs.where((x) => x.done).length}/${t.subs.length} steps');
    if (t.notes.isNotEmpty && t.subs.isEmpty) add('Note');

    final title = AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 260),
      style: cond(23, FontWeight.w700, height: 1.12, color: done ? pal.sub : pal.text).copyWith(
        decoration: done ? TextDecoration.lineThrough : TextDecoration.none,
        decorationColor: pal.sub,
        decorationThickness: 2,
      ),
      child: Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis),
    );

    Widget row = Container(
      decoration: BoxDecoration(color: pal.row, border: Border(bottom: BorderSide(color: pal.rule))),
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        TaskCheck(done: done, color: color, onTap: _toggle, label: done ? 'Mark ${t.title} not done' : 'Complete ${t.title}'),
        const SizedBox(width: 4),
        if (t.prio > 0 && !t.done) Padding(padding: const EdgeInsets.only(right: 4), child: PrioFlag(t.prio, size: 17)),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              title,
              if (meta.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text.rich(TextSpan(children: meta),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: inter(13.5, FontWeight.w600, color: pal.sub)),
                ),
            ]),
          ),
        ),
        if (t.isBill) ...[
          const SizedBox(width: 10),
          Text(app.cash(t.amount), style: cond(22, FontWeight.w800, color: done ? pal.sub : pal.text).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
        ],
        if (!t.done)
          Semantics(
            button: true,
            toggled: t.star,
            label: t.star ? 'Unstar' : 'Star',
            excludeSemantics: true,
            child: Pressable(
              scale: .75,
              onTap: () {
                tick();
                app.toggleStar(t.id);
              },
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: AnimatedSwitcher(
                  duration: Motion.bouncyDur,
                  switchInCurve: Motion.bouncy,
                  transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                  child: SvgIcon(t.star ? 'star-on' : 'star', key: ValueKey(t.star), size: 22, color: t.star ? kYellow : pal.sub.withValues(alpha: .55)),
                ),
              ),
            ),
          )
        else
          const SizedBox(width: 12),
      ]),
    );

    row = Semantics(
      button: true,
      label: t.title,
      child: Pressable(scale: .985, onTap: () => openTaskSheet(context, t), child: row),
    );

    if (!widget.swipe || t.done) return row;
    return Dismissible(
      key: ValueKey('swipe-${t.id}|${t.due}'),
      background: _SwipeBg(left: true, label: 'DONE', color: kGreen),
      secondaryBackground: _SwipeBg(left: false, label: 'TOMORROW', color: const Color(0xFF1D6CF2)),
      dismissThresholds: const {DismissDirection.startToEnd: .3, DismissDirection.endToStart: .3},
      confirmDismiss: (dir) async {
        HapticFeedback.mediumImpact();
        if (dir == DismissDirection.startToEnd) {
          app.setTaskDone(t.id, true);
        } else {
          app.postponeTask(t.id);
        }
        return true;
      },
      child: row,
    );
  }
}

class _SwipeBg extends StatelessWidget {
  final bool left;
  final String label;
  final Color color;
  const _SwipeBg({required this.left, required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
        color: color,
        alignment: left ? Alignment.centerLeft : Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (left) const SvgIcon('check', size: 22),
          if (left) const SizedBox(width: 8),
          Text(label, style: cond(17, FontWeight.w800, ls: .08, color: Colors.white)),
          if (!left) const SizedBox(width: 8),
          if (!left) const SvgIcon('arrow', size: 20),
        ]),
      );
}

// ---------------------------------------------------------------------------
// Task editor.

/// Opens the task editor: [task] to edit, or a new one ([draft] fills it in,
/// e.g. from quick add's "More"; [onBoard] starts its board switch on).
void openTaskSheet(BuildContext context, Task? task, {String? due, Task? draft, bool onBoard = false}) {
  final app = context.read<AppState>();
  final t = task?.copy() ?? draft ?? Task(id: uid(), title: '', cat: app.activeCat ?? app.s.lines.first.id, due: due ?? '');
  showSheet<void>(context, (_) => ChangeNotifierProvider.value(value: app, child: _TaskSheet(t, isNew: task == null, startOnBoard: onBoard)));
}

class _TaskSheet extends StatefulWidget {
  final Task t;
  final bool isNew, startOnBoard;
  const _TaskSheet(this.t, {required this.isNew, this.startOnBoard = false});
  @override
  State<_TaskSheet> createState() => _TaskSheetState();
}

class _TaskSheetState extends State<_TaskSheet> {
  late final AppState app = context.read<AppState>();
  late final Task t = widget.t;
  late final _title = TextEditingController(text: t.title);
  late final _notes = TextEditingController(text: t.notes);
  late final _amount = TextEditingController(text: t.amount > 0 ? _plain(t.amount) : '');
  final _subCtl = <String, TextEditingController>{};
  final _newSub = TextEditingController();
  final _newSubFocus = FocusNode();
  late final TitleMemory _mem = TitleMemory(app.s.money);

  /// Has a linked event on the board (quick add's "Also: calendar").
  late final bool _wasOnBoard = app.s.events.any((e) => e.task == t.id);
  late bool _onBoard = _wasOnBoard || widget.startOnBoard;

  static String _plain(int minor) => minor % 100 == 0 ? '${minor ~/ 100}' : (minor / 100).toStringAsFixed(2);

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _amount.dispose();
    _newSub.dispose();
    _newSubFocus.dispose();
    for (final c in _subCtl.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _ctl(SubTask s) => _subCtl.putIfAbsent(s.id, () => TextEditingController(text: s.title));

  void _addSub() {
    final v = _newSub.text.trim();
    if (v.isEmpty) return;
    setState(() {
      t.subs.add(SubTask(id: uid(), title: v));
      _newSub.clear();
    });
    _newSubFocus.requestFocus();
  }

  /// The category a bill is logged under: the one set, else your usual one for this name.
  String _billCat() {
    final m = app.s.money;
    if (t.mcat.isNotEmpty && m.cats.any((c) => c.id == t.mcat && !c.income)) return t.mcat;
    final g = _mem.guess(_title.text);
    if (g.why == CatWhy.fallback && m.cats.any((c) => c.id == 'bills' && !c.archived)) return 'bills';
    return g.cat;
  }

  Task _read() {
    final out = t.copy()
      ..title = _title.text.trim()
      ..notes = clip(_notes.text.trim(), 2000)
      ..amount = parseAmount(_amount.text) ?? 0;
    out.subs = [
      for (final s in t.subs)
        if ((_subCtl[s.id]?.text ?? s.title).trim().isNotEmpty) SubTask(id: s.id, title: (_subCtl[s.id]?.text ?? s.title).trim(), done: s.done),
    ];
    if (_newSub.text.trim().isNotEmpty) out.subs.add(SubTask(id: uid(), title: _newSub.text.trim()));
    if (out.due.isEmpty) {
      out
        ..time = null
        ..remind = null;
    }
    // A bill is logged under a set category, so what you see is what you get.
    if (out.amount > 0 && out.mcat.isEmpty) out.mcat = _billCat();
    if (out.amount == 0) {
      out
        ..mcat = ''
        ..acct = '';
    }
    return out;
  }

  void _save() {
    final out = _read();
    if (out.title.isEmpty) {
      app.showToast('Give the task a name');
      return;
    }
    if (out.repeat.isNotEmpty && out.due.isEmpty) out.due = todayStr();
    Navigator.pop(context);
    app.saveTask(out, onBoard: _onBoard == _wasOnBoard ? null : _onBoard);
  }

  Future<void> _delete() async {
    var withEvent = false;
    if (_wasOnBoard) {
      final c = await ask<String>(context, 'Delete task', '"${t.title}" is also on the board.', const [
        AskBtn('Delete task and event', 'both', BtnKind.red),
        AskBtn('Delete task, keep event', 'task'),
      ]);
      if (c == null || !mounted) return;
      withEvent = c == 'both';
    }
    Navigator.pop(context);
    app.deleteTask(t.id, withEvent: withEvent);
  }

  Future<void> _pickDue() async {
    final now = nowMs();
    final d = await pickDate(context, t.due.isEmpty ? DateTime.fromMillisecondsSinceEpoch(sod(now)) : DateTime.fromMillisecondsSinceEpoch(dms(t.due)));
    if (d != null) setState(() => t.due = dstr(d.millisecondsSinceEpoch));
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final m = app.s.money;
    final line = app.lineOf(t.cat);
    final now = nowMs();
    final amount = parseAmount(_amount.text) ?? 0;
    final rowLabel = inter(16, FontWeight.w500, color: pal.rowLabel);
    final timed = t.time != null;

    Widget fr(String label, Widget control) => Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.panelRule))),
          child: Row(children: [Expanded(child: Text(label, style: rowLabel)), const SizedBox(width: 10), Flexible(flex: 3, child: Align(alignment: Alignment.centerRight, child: control))]),
        );
    Widget chip(String text, VoidCallback onTap, {VoidCallback? onClear, Widget? lead, Color? fill}) => Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: Pressable(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                decoration: BoxDecoration(color: fill ?? pal.field, borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (lead != null) ...[lead, const SizedBox(width: 7)],
                  Flexible(
                    child: Text(text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: inter(15, FontWeight.w500, color: fill == null ? pal.ink : (fill.computeLuminance() > .4 ? Colors.black : Colors.white))),
                  ),
                ]),
              ),
            ),
          ),
          if (onClear != null)
            Pressable(
              scale: .8,
              onTap: onClear,
              child: Padding(padding: const EdgeInsets.fromLTRB(8, 8, 0, 8), child: Icon(Icons.close, size: 18, color: pal.label)),
            ),
        ]);
    Widget head(String text) => Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 2),
          child: Text(text, style: inter(11, FontWeight.w800, ls: .1, color: pal.label)),
        );

    final billCat = amount > 0 ? m.catOf(_billCat()) : null;
    final reminders = t.reminders;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SheetHead(widget.isNew ? 'New task' : (t.done ? 'Done' : 'Task')),
      TextField(
        controller: _title,
        autofocus: widget.isNew && t.title.isEmpty,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _save(),
        onChanged: (_) => setState(() {}),
        maxLines: null,
        style: inter(22, FontWeight.w700, color: pal.ink),
        cursorColor: kYellow,
        decoration: InputDecoration(
          hintText: 'What needs doing?',
          hintStyle: inter(22, FontWeight.w700, color: pal.placeholder),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.only(bottom: 8),
        ),
      ),
      SheetField(controller: _notes, hint: 'Add details', maxLines: 4),

      // ---------- when ----------
      head('WHEN'),
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: DatePresets(
          value: t.due.isEmpty ? null : t.due,
          onPick: (d) => setState(() => t.due = d),
          onMore: _pickDue,
        ),
      ),
      fr(
        'Due',
        chip(
          t.due.isEmpty ? 'No date' : dueLong(t.due, now),
          _pickDue,
          lead: SvgIcon('cal', size: 16, color: pal.label),
          onClear: t.due.isEmpty ? null : () => setState(() => t..due = ''..time = null..repeat = ''..remind = null),
        ),
      ),
      if (t.due.isNotEmpty) ...[
        fr(
          'Time',
          chip(
            t.time == null ? 'Any time' : minLabel(t.time!, use24h: app.use24h),
            () async {
              final x = await pickTime(context, TimeOfDay(hour: (t.time ?? 540) ~/ 60, minute: (t.time ?? 540) % 60));
              if (x != null) setState(() => t.time = x.hour * 60 + x.minute);
            },
            lead: SvgIcon('clock', size: 16, color: pal.label),
            onClear: t.time == null ? null : () => setState(() => t.time = null),
          ),
        ),
        fr(
          'Repeat',
          chip(t.repeat.isEmpty ? 'Never' : repeatSentence(t), () async {
            final x = await pickRepeat(context, repeat: t.repeat, fromDone: t.repFromDone, until: t.repUntil, left: t.repLeft, due: t.due);
            if (x == null) return;
            setState(() => t
              ..repeat = x.repeat
              ..repFromDone = x.fromDone
              ..repUntil = x.until
              ..repLeft = x.left);
          }, lead: SvgIcon('repeat', size: 16, color: pal.label)),
        ),
        fr(
          t.time == null && _onBoard ? 'On the board · all day' : 'On the board',
          PillSwitch(value: _onBoard, onChanged: (x) => setState(() => _onBoard = x)),
        ),

        // ---------- reminders ----------
        head('REMIND ME'),
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 10),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final r in reminders)
              Container(
                padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
                decoration: BoxDecoration(color: pal.field, borderRadius: BorderRadius.circular(10)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.notifications_active_rounded, size: 15, color: kYellow),
                  const SizedBox(width: 6),
                  Text(
                    '${remindLabel(r, timed: timed)}${!timed ? ', ${minLabel(kTaskDayBase, use24h: app.use24h)}' : ''}',
                    style: inter(13.5, FontWeight.w600, color: pal.ink),
                  ),
                  Pressable(
                    scale: .8,
                    onTap: () => setState(() => t.remind = [...reminders]..remove(r)),
                    child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.close, size: 15, color: pal.label)),
                  ),
                ]),
              ),
            Pressable(
              scale: .92,
              onTap: () async {
                final x = await pickReminders(context, reminders, timed: timed);
                if (x != null) setState(() => t.remind = x);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: pal.label.withValues(alpha: .6), width: 1.2)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.add, size: 16, color: pal.ink),
                  const SizedBox(width: 4),
                  Text(reminders.isEmpty ? 'Add a reminder' : 'Add', style: inter(13.5, FontWeight.w600, color: pal.ink)),
                ]),
              ),
            ),
          ]),
        ),
        Container(height: 1, color: pal.panelRule),
      ],

      // ---------- organise ----------
      head('ORGANISE'),
      fr(
        'Line',
        Pressable(
          onTap: () async {
            final x = await pickOption<String>(context, 'Line', [for (final l in app.s.lines) (l.id, '${l.label} · ${l.name}')], t.cat);
            if (x != null) setState(() => t.cat = x);
          },
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            LineBadge(line, size: 26, fontSize: 12),
            const SizedBox(width: 8),
            Text(line.name, style: inter(16, FontWeight.w600, color: pal.ink)),
            const SizedBox(width: 8),
            const SvgIcon('chev', size: 14, color: kDim),
          ]),
        ),
      ),
      fr('Priority', PrioPicker(value: t.prio, onChanged: (v) => setState(() => t.prio = v))),
      fr('Starred', PillSwitch(value: t.star, onChanged: (v) => setState(() => t.star = v))),

      // ---------- bill ----------
      head('BILL'),
      fr(
        'Amount',
        SizedBox(
          width: 150,
          child: TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.right,
            onChanged: (_) => setState(() {}),
            style: inter(16, FontWeight.w600, color: pal.ink),
            cursorColor: kYellow,
            decoration: InputDecoration(
              prefixText: m.currency,
              prefixStyle: inter(16, FontWeight.w600, color: pal.label),
              hintText: 'None',
              hintStyle: inter(16, FontWeight.w500, color: pal.placeholder),
              isDense: true,
              filled: true,
              fillColor: pal.field,
              contentPadding: const EdgeInsets.symmetric(vertical: 9, horizontal: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            ),
          ),
        ),
      ),
      if (billCat != null) ...[
        fr(
          'Category',
          chip('${billCat.emoji}  ${billCat.name}', () async {
            final x = await pickMoneyCat(context, income: false, current: billCat.id, recent: _mem.recentCats);
            if (x != null) setState(() => t.mcat = x);
          }, fill: hexColor(billCat.color)),
        ),
        if (m.accounts.isNotEmpty)
          fr(
            'Pay from',
            chip(t.acct.isEmpty ? 'Default · ${acctText(m, m.newAcct, none: 'none')}' : acctText(m, t.acct), () async {
              final x = await pickAccount(context, m, t.acct, title: 'Pay from', noneLabel: 'The default account');
              if (x != null) setState(() => t.acct = x);
            }),
          ),
      ],

      // ---------- steps ----------
      head('STEPS'),
      const SizedBox(height: 4),
      for (final s in t.subs)
        Row(children: [
          TaskCheck(done: s.done, color: inkFor(hexColor(line.color), pal), size: 20, onTap: () => setState(() => s.done = !s.done), label: s.title),
          Expanded(
            child: TextField(
              controller: _ctl(s),
              style: inter(15, FontWeight.w500, color: s.done ? pal.label : pal.ink).copyWith(decoration: s.done ? TextDecoration.lineThrough : null),
              cursorColor: kYellow,
              decoration: const InputDecoration(border: InputBorder.none, isDense: true),
            ),
          ),
          Pressable(
            scale: .8,
            onTap: () => setState(() => t.subs.remove(s)),
            child: Padding(padding: const EdgeInsets.all(8), child: Icon(Icons.close, size: 18, color: pal.label)),
          ),
        ]),
      Row(children: [
        Padding(padding: const EdgeInsets.all(9), child: Icon(Icons.add, size: 20, color: pal.label)),
        Expanded(
          child: TextField(
            controller: _newSub,
            focusNode: _newSubFocus,
            textCapitalization: TextCapitalization.sentences,
            onSubmitted: (_) => _addSub(),
            textInputAction: TextInputAction.next,
            style: inter(15, FontWeight.w500, color: pal.ink),
            cursorColor: kYellow,
            decoration: InputDecoration(
              hintText: 'Add a step',
              hintStyle: inter(15, FontWeight.w500, color: pal.placeholder),
              border: InputBorder.none,
              isDense: true,
            ),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      SheetBtn(widget.isNew ? (amount > 0 ? 'Add bill · ${app.cash(amount)}' : 'Add task') : 'Save', kind: BtnKind.yellow, onTap: _save),
      if (!widget.isNew)
        SheetBtn(t.done ? 'Mark not done' : (t.isBill ? 'Mark paid' : 'Mark done'), onTap: () {
          Navigator.pop(context);
          app.saveTask(_read()..done = t.done);
          app.setTaskDone(t.id, !t.done);
        }),
      if (!widget.isNew) SheetBtn('Delete task', kind: BtnKind.red, onTap: _delete),
    ]);
  }
}
