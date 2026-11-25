// Pickers shared by quick add and the full editors: money categories (a strip
// and a searchable grid, after Cashew's), accounts, task reminders, custom
// repeats, priority flags and one-tap due days.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/store.dart';
import '../core/money.dart';
import '../core/tasks.dart';
import '../core/util.dart';
import 'haptics.dart';
import 'money.dart';
import 'money_sections.dart' show kAcctEmoji;
import 'motion.dart';
import 'theme.dart';
import 'widgets.dart';

// ---------------------------------------------------------------------------
// Money categories

/// A round category tile: emoji on its colour, the name underneath. Selected
/// tiles fill with the colour and get a ring; [tag] sits on top ("LAST TIME").
class CatTile extends StatelessWidget {
  final MCat c;
  final bool selected;
  final String? tag;
  final double size;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  const CatTile(this.c, {super.key, required this.selected, required this.onTap, this.onLongPress, this.tag, this.size = 50});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final col = hexColor(c.color);
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: true,
      selected: selected,
      label: c.name,
      excludeSemantics: true,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Pressable(
          scale: .9,
          onTap: onTap,
          child: SizedBox(
            width: size + 14,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
                Padding(
                  padding: const EdgeInsets.all(3),
                  child: AnimatedContainer(
                    duration: reduce ? Duration.zero : Motion.snappyDur,
                    curve: Motion.snappy,
                    width: size,
                    height: size,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? col : Color.alphaBlend(col.withValues(alpha: pal.light ? .28 : .24), pal.field),
                      boxShadow: selected ? [BoxShadow(color: pal.panel, spreadRadius: 2.5), BoxShadow(color: col, spreadRadius: 4.5)] : null,
                    ),
                    child: Text(c.emoji, style: TextStyle(fontSize: size * .44)),
                  ),
                ),
                if (tag != null)
                  Positioned(
                    top: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(color: kYellow, borderRadius: BorderRadius.circular(4)),
                      child: Text(tag!, style: cond(10, FontWeight.w800, ls: .08, color: Colors.black)),
                    ),
                  ),
              ]),
              const SizedBox(height: 3),
              Text(
                c.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: inter(11.5, selected ? FontWeight.w800 : FontWeight.w600, color: selected ? pal.ink : pal.rowLabel),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The dashed "More / New" tile at the end of a strip or grid.
class _MoreTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _MoreTile(this.label, this.icon, {required this.onTap});
  static const double size = 50;
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Pressable(
        scale: .9,
        onTap: onTap,
        child: SizedBox(
          width: size + 14,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.all(3),
              child: Container(
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: pal.label.withValues(alpha: .7), width: 1.5)),
                child: Icon(icon, size: size * .42, color: pal.label),
              ),
            ),
            const SizedBox(height: 3),
            Text(label, maxLines: 1, style: inter(11.5, FontWeight.w600, color: pal.label)),
          ]),
        ),
      ),
    );
  }
}

/// The categories in the order a strip shows them: recent ones, then the rest
/// as arranged in settings. The order stays put while you tap around; the
/// pick only moves to the front when it would otherwise be off-screen.
List<MCat> stripOrder(Money m, {required bool income, required String selected, List<String> recent = const []}) {
  final live = [for (final c in m.cats) if (c.income == income && (!c.archived || c.id == selected)) c];
  final byId = {for (final c in live) c.id: c};
  final out = <MCat>[];
  void add(String id) {
    final c = byId[id];
    if (c != null && !out.contains(c)) out.add(c);
  }

  for (final id in recent) {
    add(id);
  }
  for (final c in live) {
    add(c.id);
  }
  final i = out.indexWhere((c) => c.id == selected);
  if (i >= 4) out.insert(0, out.removeAt(i));
  return out;
}

/// A sideways strip of category tiles with "All" at the end.
class CatStrip extends StatelessWidget {
  final List<MCat> cats;
  final String selected;
  final String? tag;
  final ValueChanged<String> onPick;
  final VoidCallback onAll;
  const CatStrip({super.key, required this.cats, required this.selected, required this.onPick, required this.onAll, this.tag});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 86,
      child: ListView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: const EdgeInsets.only(top: 7),
        children: [
          for (final c in cats) ...[
            CatTile(c, key: ValueKey(c.id), selected: c.id == selected, tag: c.id == selected ? tag : null, onTap: () => onPick(c.id)),
            const SizedBox(width: 4),
          ],
          _MoreTile('All', Icons.grid_view_rounded, onTap: onAll),
        ],
      ),
    );
  }
}

/// The full category picker: search, recent, then everything in a grid.
/// Hold a tile to edit it (keywords too); "+ New" makes one. Returns the id.
Future<String?> pickMoneyCat(BuildContext context, {required bool income, required String current, List<String> recent = const []}) {
  final app = context.read<AppState>();
  return showSheet<String>(context, (_) => ChangeNotifierProvider.value(value: app, child: _CatPicker(income: income, current: current, recent: recent)));
}

class _CatPicker extends StatefulWidget {
  final bool income;
  final String current;
  final List<String> recent;
  const _CatPicker({required this.income, required this.current, required this.recent});
  @override
  State<_CatPicker> createState() => _CatPickerState();
}

class _CatPickerState extends State<_CatPicker> {
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

  Widget _grid(List<Widget> tiles) => LayoutBuilder(builder: (context, box) {
        const cols = 4;
        final w = box.maxWidth / cols;
        return Wrap(runSpacing: 12, children: [for (final t in tiles) SizedBox(width: w, child: Center(child: t))]);
      });

  Widget _label(String text) {
    final pal = Pal.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 10),
      child: Text(text, style: inter(11, FontWeight.w800, ls: .1, color: pal.label)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final pal = Pal.of(context);
    final m = app.s.money;
    final canEdit = app.relay == null;
    final q = _q.text.trim().toLowerCase();
    final all = [for (final c in m.cats) if (c.income == widget.income && (!c.archived || c.id == widget.current)) c];
    bool hit(MCat c) => q.isEmpty || c.name.toLowerCase().contains(q) || c.kw.toLowerCase().contains(q);
    final shown = all.where(hit).toList();
    final recent = q.isNotEmpty ? <MCat>[] : [for (final id in widget.recent.take(4)) ...all.where((c) => c.id == id)];

    Widget tile(MCat c) => CatTile(
          c,
          selected: c.id == widget.current,
          onTap: () {
            tick();
            Navigator.pop(context, c.id);
          },
          onLongPress: canEdit
              ? () {
                  buzz();
                  openCatSheet(context, c);
                }
              : null,
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SheetHead(widget.income ? 'Income category' : 'Category'),
      TextField(
        controller: _q,
        textInputAction: TextInputAction.search,
        style: inter(15, FontWeight.w500, color: pal.ink),
        cursorColor: kYellow,
        decoration: InputDecoration(
          hintText: 'Search categories',
          hintStyle: inter(15, FontWeight.w500, color: pal.placeholder),
          prefixIcon: Icon(Icons.search, size: 20, color: pal.label),
          isDense: true,
          filled: true,
          fillColor: pal.field,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
      ),
      if (recent.isNotEmpty) ...[_label('RECENT'), _grid([for (final c in recent) tile(c)])],
      _label(q.isNotEmpty ? 'MATCHES' : (canEdit ? 'ALL · HOLD ONE TO EDIT' : 'ALL')),
      if (shown.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text('Nothing called “${_q.text.trim()}”.', style: inter(14, FontWeight.w500, color: pal.label)),
        ),
      _grid([
        for (final c in shown) tile(c),
        if (canEdit)
          _MoreTile('New', Icons.add, onTap: () async {
            final id = await openCatSheet(context, null, income: widget.income, name: _q.text.trim());
            if (id != null && context.mounted) Navigator.pop(context, id);
          }),
      ]),
      const SizedBox(height: 8),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Accounts

/// A sideways row of account chips; the selected one is filled.
class AcctChips extends StatelessWidget {
  final Money m;
  final String selected;
  final ValueChanged<String> onPick;
  const AcctChips({super.key, required this.m, required this.selected, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final list = [for (final a in m.accounts) if (!a.archived || a.id == selected) a];
    final onBg = pal.light ? const Color(0xFF111111) : Colors.white;
    final onFg = pal.light ? Colors.white : Colors.black;
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        children: [
          for (final a in list) ...[
            Semantics(
              button: true,
              selected: a.id == selected,
              label: a.name,
              excludeSemantics: true,
              child: Pressable(
                scale: .92,
                onTap: () {
                  tick();
                  onPick(a.id);
                },
                child: AnimatedContainer(
                  duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : Motion.snappyDur,
                  curve: Motion.snappy,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: a.id == selected ? onBg : pal.field, borderRadius: BorderRadius.circular(12)),
                  child: Text(
                    '${kAcctEmoji[a.type] ?? '•'}  ${a.name}',
                    style: inter(13.5, FontWeight.w700, color: a.id == selected ? onFg : pal.ink),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

String acctText(Money m, String id, {String none = 'No account'}) {
  final a = m.acctOf(id);
  return a == null ? none : '${kAcctEmoji[a.type] ?? '•'}  ${a.name}';
}

/// Picks an account from a list ('' = none / the default, as [noneLabel] says).
Future<String?> pickAccount(BuildContext context, Money m, String current, {String title = 'Account', String noneLabel = 'No account'}) {
  return pickOption<String>(context, title, [
    for (final a in m.accounts)
      if (!a.archived || a.id == current) (a.id, acctText(m, a.id)),
    ('', noneLabel),
  ], current);
}

// ---------------------------------------------------------------------------
// Priority

const kPrioColors = {1: Color(0xFFF87171), 2: Color(0xFFFF9F1A), 3: Color(0xFF60A5FA)};

/// A small flag for a task row (nothing for no priority).
class PrioFlag extends StatelessWidget {
  final int prio;
  final double size;
  const PrioFlag(this.prio, {super.key, this.size = 15});
  @override
  Widget build(BuildContext context) {
    if (prio < 1 || prio > 3) return const SizedBox.shrink();
    return Semantics(label: 'Priority $prio', child: Icon(Icons.flag_rounded, size: size, color: kPrioColors[prio]));
  }
}

/// P1 P2 P3 — as four small buttons.
class PrioPicker extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const PrioPicker({super.key, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    Widget b(int p, String label) {
      final on = value == p;
      final col = p == 0 ? (pal.light ? const Color(0xFF111111) : Colors.white) : kPrioColors[p]!;
      return Padding(
        padding: const EdgeInsets.only(left: 5),
        child: Semantics(
          button: true,
          selected: on,
          label: p == 0 ? 'No priority' : 'Priority $p',
          excludeSemantics: true,
          child: Pressable(
            scale: .88,
            onTap: () {
              tick();
              onChanged(p);
            },
            child: AnimatedContainer(
              duration: Motion.snappyDur,
              width: 38,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: on ? col : pal.field, borderRadius: BorderRadius.circular(9)),
              child: Text(label, style: cond(15, FontWeight.w800, color: on ? (p == 0 && pal.light ? Colors.white : Colors.black) : pal.label)),
            ),
          ),
        ),
      );
    }

    return Row(mainAxisSize: MainAxisSize.min, children: [b(1, 'P1'), b(2, 'P2'), b(3, 'P3'), b(0, '—')]);
  }
}

// ---------------------------------------------------------------------------
// Due-day shortcuts

/// Today · Tomorrow · the weekend · Next week (Monday) · Pick…
class DatePresets extends StatelessWidget {
  final String? value;
  final ValueChanged<String> onPick;
  final VoidCallback onMore;
  const DatePresets({super.key, required this.value, required this.onPick, required this.onMore});

  static List<(String, String)> presets(int now) {
    final t0 = DateTime.fromMillisecondsSinceEpoch(sod(now));
    String d(int add) => dstr(DateTime(t0.year, t0.month, t0.day + add).millisecondsSinceEpoch);
    final toSat = (6 - t0.weekday) % 7;
    final toMon = (8 - t0.weekday) % 7 == 0 ? 7 : (8 - t0.weekday) % 7;
    final out = <(String, String)>[('Today', d(0)), ('Tomorrow', d(1))];
    if (toSat > 1) out.add(('Sat', d(toSat)));
    if (toMon > 1) out.add(('Next week', d(toMon)));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final now = nowMs();
    final list = presets(now);
    final custom = value != null && value!.isNotEmpty && !list.any((p) => p.$2 == value);
    final onBg = pal.light ? const Color(0xFF111111) : Colors.white;
    final onFg = pal.light ? Colors.white : Colors.black;
    Widget chip(String label, bool on, VoidCallback tap, {Widget? lead}) => Pressable(
          scale: .92,
          onTap: () {
            tick();
            tap();
          },
          child: AnimatedContainer(
            duration: Motion.snappyDur,
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            decoration: BoxDecoration(color: on ? onBg : pal.field, borderRadius: BorderRadius.circular(10)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (lead != null) ...[lead, const SizedBox(width: 5)],
              Text(label, style: inter(13, FontWeight.w700, color: on ? onFg : pal.ink)),
            ]),
          ),
        );
    return Wrap(spacing: 6, runSpacing: 6, children: [
      for (final (label, day) in list) chip(label, value == day, () => onPick(day)),
      chip(custom ? dueLabel(value!, now) : 'Pick…', custom, onMore, lead: Icon(Icons.calendar_month_rounded, size: 15, color: custom ? onFg : pal.label)),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Reminders

/// Toggles which reminders a task has. Returns the new list (sorted, largest
/// offset first), or null when dismissed.
Future<List<int>?> pickReminders(BuildContext context, List<int> current, {required bool timed}) {
  return showSheet<List<int>>(context, (_) => _RemindSheet(current: current, timed: timed));
}

class _RemindSheet extends StatefulWidget {
  final List<int> current;
  final bool timed;
  const _RemindSheet({required this.current, required this.timed});
  @override
  State<_RemindSheet> createState() => _RemindSheetState();
}

class _RemindSheetState extends State<_RemindSheet> {
  late final Set<int> on = widget.current.toSet();

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final opts = {...(widget.timed ? kRemindTimed : kRemindDay), ...widget.current}.toList()..sort();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SheetHead('Remind me'),
      if (!widget.timed)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text('No time set, so reminders come at 9:00.', style: inter(13, FontWeight.w500, color: pal.label)),
        ),
      for (final r in opts)
        InkWell(
          onTap: tapped(() => setState(() => on.contains(r) ? on.remove(r) : on.add(r))),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 4),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.panelRule))),
            child: Row(children: [
              Icon(on.contains(r) ? Icons.notifications_active_rounded : Icons.notifications_none_rounded, size: 20, color: on.contains(r) ? kYellow : pal.label),
              const SizedBox(width: 12),
              Expanded(child: Text(remindLabel(r, timed: widget.timed), style: inter(16, FontWeight.w500, color: pal.ink))),
              if (on.contains(r)) Icon(Icons.check, color: kYellow, size: 20),
            ]),
          ),
        ),
      const SizedBox(height: 6),
      SheetBtn(on.isEmpty ? 'No reminders' : 'Done', kind: BtnKind.yellow, onTap: () => Navigator.pop(context, on.toList()..sort((a, b) => b.compareTo(a)))),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Repeat

typedef RepeatPick = ({String repeat, bool fromDone, String until, int? left});

/// The repeat sheet: presets, or every N days/weeks/months/years (weeks on
/// chosen weekdays), counted from the due day or from when it's done, with an
/// optional end. [due] is the task's due day (for the summary).
Future<RepeatPick?> pickRepeat(BuildContext context, {required String repeat, bool fromDone = false, String until = '', int? left, String due = ''}) {
  return showSheet<RepeatPick>(context, (_) => _RepeatSheet(repeat: repeat, fromDone: fromDone, until: until, left: left, due: due));
}

class _RepeatSheet extends StatefulWidget {
  final String repeat, until, due;
  final bool fromDone;
  final int? left;
  const _RepeatSheet({required this.repeat, required this.fromDone, required this.until, required this.left, required this.due});
  @override
  State<_RepeatSheet> createState() => _RepeatSheetState();
}

class _RepeatSheetState extends State<_RepeatSheet> {
  late String preset = widget.repeat.isEmpty ? '' : (kTaskRepeats.contains(widget.repeat) && const ['daily', 'weekdays', 'weekly', 'monthly', 'yearly'].contains(widget.repeat) ? widget.repeat : 'custom');
  late int n = repeatParts(widget.repeat)?.n ?? 1;
  late String unit = repeatParts(widget.repeat)?.unit ?? 'w';
  late Set<int> days = {...?repeatParts(widget.repeat)?.days};
  late bool fromDone = widget.fromDone;
  late String ends = widget.until.isNotEmpty ? 'until' : (widget.left != null ? 'count' : 'never');
  late String until = widget.until;
  late int count = (widget.left ?? 9) + 1;

  String get rule => switch (preset) {
        '' => '',
        'custom' => makeRepeat(n, unit, unit == 'w' ? days.toList() : const []),
        _ => preset,
      };

  String _summary() {
    final r = rule;
    if (r.isEmpty) return 'Doesn’t repeat.';
    final t = Task(id: '', title: '', cat: '', due: widget.due.isEmpty ? todayStr() : widget.due, repeat: r, repFromDone: fromDone, repUntil: ends == 'until' ? until : '', repLeft: ends == 'count' ? count - 1 : null);
    final next = fromDone ? null : nextDue(t.due, r);
    final s = repeatSentence(t).replaceAll(' · last one', '').replaceAll(RegExp(r' · \d+ more$'), '');
    final tail = ends == 'count' ? ' · $count times in all' : '';
    String when(String d) {
      final l = dueLabel(d, nowMs());
      return const ['Today', 'Tomorrow', 'Yesterday'].contains(l) ? l.toLowerCase() : l;
    }

    return '$s$tail${next != null && (until.isEmpty || ends != 'until' || next.compareTo(until) <= 0) ? ' · then ${when(next)}' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final onBg = pal.light ? const Color(0xFF111111) : Colors.white;
    final onFg = pal.light ? Colors.white : Colors.black;
    Widget pill(String label, bool on, VoidCallback tap) => Pressable(
          scale: .92,
          onTap: () {
            tick();
            setState(tap);
          },
          child: AnimatedContainer(
            duration: Motion.snappyDur,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: on ? onBg : pal.field, borderRadius: BorderRadius.circular(10)),
            child: Text(label, style: inter(13.5, FontWeight.w700, color: on ? onFg : pal.ink)),
          ),
        );
    Widget head(String t) => Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 8),
          child: Text(t, style: inter(11, FontWeight.w800, ls: .1, color: pal.label)),
        );
    Widget step(IconData i, VoidCallback f) => Pressable(
          scale: .85,
          onTap: () {
            tick();
            setState(f);
          },
          child: Container(width: 40, height: 38, alignment: Alignment.center, child: Icon(i, size: 18, color: pal.ink)),
        );
    Widget stepper(int v, String suffix, ValueChanged<int> set, {int min = 1, int max = 365}) => Container(
          decoration: BoxDecoration(color: pal.field, borderRadius: BorderRadius.circular(10)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            step(Icons.remove, () => set((v - 1).clamp(min, max))),
            Container(
              constraints: const BoxConstraints(minWidth: 44),
              alignment: Alignment.center,
              child: Text('$v$suffix', style: cond(20, FontWeight.w800, color: pal.ink)),
            ),
            step(Icons.add, () => set((v + 1).clamp(min, max))),
          ]),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SheetHead('Repeat'),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final (k, l) in const [('', 'Never'), ('daily', 'Daily'), ('weekdays', 'Weekdays'), ('weekly', 'Weekly'), ('monthly', 'Monthly'), ('yearly', 'Yearly'), ('custom', 'Custom')])
          pill(l, preset == k, () => preset = k),
      ]),
      AnimatedSize(
        duration: Motion.snappyDur,
        curve: Motion.snappy,
        alignment: Alignment.topCenter,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (preset == 'custom') ...[
            head('EVERY'),
            Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
              stepper(n, '', (v) => n = v, max: 999),
              Segmented<String>(
                options: const [('d', 'DAYS'), ('w', 'WEEKS'), ('m', 'MONTHS'), ('y', 'YEARS')],
                value: unit,
                onChanged: (v) => setState(() => unit = v),
                track: pal.field,
                thumb: onBg,
                on: onFg,
                off: pal.label,
                style: cond(14, FontWeight.w800, ls: .06),
                segWidth: 66,
              ),
            ]),
            if (unit == 'w') ...[
              head('ON (OPTIONAL)'),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                for (var d = 1; d <= 7; d++)
                  Semantics(
                    button: true,
                    selected: days.contains(d),
                    label: const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][d - 1],
                    excludeSemantics: true,
                    child: Pressable(
                      scale: .88,
                      onTap: () {
                        tick();
                        setState(() => days.contains(d) ? days.remove(d) : days.add(d));
                      },
                      child: AnimatedContainer(
                        duration: Motion.snappyDur,
                        width: 38,
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: days.contains(d) ? kYellow : pal.field),
                        child: Text('MTWTFSS'[d - 1], style: cond(15, FontWeight.w800, color: days.contains(d) ? Colors.black : pal.label)),
                      ),
                    ),
                  ),
              ]),
            ],
          ],
          if (preset.isNotEmpty) ...[
            head('NEXT ONE COUNTS FROM'),
            Align(
              alignment: Alignment.centerLeft,
              child: Segmented<bool>(
                options: const [(false, 'DUE DATE'), (true, 'WHEN I FINISH')],
                value: fromDone,
                onChanged: (v) => setState(() => fromDone = v),
                track: pal.field,
                thumb: onBg,
                on: onFg,
                off: pal.label,
                style: cond(14, FontWeight.w800, ls: .06),
                segWidth: 116,
              ),
            ),
            head('ENDS'),
            for (final (k, l) in const [('never', 'Never'), ('until', 'On a date'), ('count', 'After')])
              InkWell(
                onTap: tapped(() async {
                  if (k == 'until' && until.isEmpty) {
                    final d = await pickDate(context, DateTime.now().add(const Duration(days: 90)));
                    if (d == null) return;
                    until = dstr(d.millisecondsSinceEpoch);
                  }
                  setState(() => ends = k);
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.panelRule))),
                  child: Row(children: [
                    Icon(ends == k ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 20, color: ends == k ? kYellow : pal.label),
                    const SizedBox(width: 10),
                    Expanded(child: Text(l, style: inter(15, FontWeight.w500, color: pal.ink))),
                    if (k == 'until' && ends == 'until')
                      Pressable(
                        onTap: () async {
                          final d = await pickDate(context, DateTime.fromMillisecondsSinceEpoch(dms(until)));
                          if (d != null) setState(() => until = dstr(d.millisecondsSinceEpoch));
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(color: pal.field, borderRadius: BorderRadius.circular(8)),
                          child: Text(dueLabel(until, nowMs()), style: inter(14, FontWeight.w600, color: pal.ink)),
                        ),
                      ),
                    if (k == 'count' && ends == 'count') stepper(count, '×', (v) => count = v, min: 2, max: 999),
                  ]),
                ),
              ),
          ],
        ]),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(_summary(), style: inter(13, FontWeight.w500, height: 1.4, color: pal.label)),
      ),
      SheetBtn('Done', kind: BtnKind.yellow, onTap: () {
        final r = rule;
        Navigator.pop<RepeatPick>(context, (
          repeat: r,
          fromDone: r.isNotEmpty && fromDone,
          until: r.isNotEmpty && ends == 'until' ? until : '',
          left: r.isNotEmpty && ends == 'count' ? count - 1 : null,
        ));
      }),
    ]);
  }
}
