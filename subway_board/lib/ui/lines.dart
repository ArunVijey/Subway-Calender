// Lines tab and the line editor sheet.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/store.dart';
import '../core/logic.dart';
import '../core/model.dart';
import '../core/util.dart';
import 'board.dart';
import 'haptics.dart';
import 'theme.dart';
import 'widgets.dart';

/// Opens Lines as a page (from Settings).
void openLinesPage(BuildContext context) {
  final app = context.read<AppState>();
  final pal = Pal.of(context);
  Navigator.of(context).push(PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 520),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (_, _, _) => ChangeNotifierProvider.value(
      value: app,
      child: PalScope(
        pal: pal,
        child: Builder(builder: (context) {
          final pad = MediaQuery.paddingOf(context);
          return Scaffold(
            backgroundColor: kBlack,
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Padding(padding: EdgeInsets.fromLTRB(18, 10 + pad.top, 18, pad.bottom), child: const LinesView(asPage: true)),
              ),
            ),
          );
        }),
      ),
    ),
    transitionsBuilder: (_, anim, _, child) => SlideTransition(
      position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(CurvedAnimation(parent: anim, curve: kEase, reverseCurve: Curves.easeInCubic)),
      child: child,
    ),
  ));
}

class LinesView extends StatelessWidget {
  /// Shown as a page from Settings: a close button instead of the gear, and
  /// picking a line closes it and shows that line on the board.
  final bool asPage;
  const LinesView({super.key, this.asPage = false});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d0 = dms(app.sel), isToday = app.sel == todayStr();
    final occ = occurrences(app.s, d0, addDays(d0, 1));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PageHead(
        title: 'Lines',
        sub: '${weekdayShort(d0)}, ${monthDay(d0)}'.toUpperCase(),
        trailing: asPage
            ? CircleBtn(label: 'Close', onTap: () => Navigator.pop(context), child: const Text('✕', style: TextStyle(fontSize: 16, color: Colors.white)))
            : const GearButton(),
      ),
      Expanded(
        // Long-press a row (or drag its handle) to reorder; the top line is the default.
        child: ReorderableListView.builder(
          padding: const EdgeInsets.only(bottom: 24),
          buildDefaultDragHandles: false,
          itemCount: app.s.lines.length,
          onReorderStart: (_) => buzz(),
          onReorderItem: app.moveLine,
          proxyDecorator: (child, _, anim) => AnimatedBuilder(
            animation: anim,
            builder: (_, child) {
              final t = Curves.easeOutCubic.transform(anim.value);
              return Transform.scale(
                scale: 1 + .03 * t,
                child: Material(
                  color: Color.lerp(kBlack, const Color(0xFF18181C), t),
                  elevation: 0,
                  borderRadius: BorderRadius.circular(12),
                  shadowColor: Colors.transparent,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .6 * t), blurRadius: 24, offset: const Offset(0, 8))],
                    ),
                    child: child,
                  ),
                ),
              );
            },
            child: child,
          ),
          itemBuilder: (context, i) {
            final l = app.s.lines[i];
            return ReorderableDelayedDragStartListener(
              key: ValueKey(l.id),
              index: i,
              child: InkWell(
                onTap: tapped(() {
                  if (asPage) Navigator.of(context).popUntil((r) => r.isFirst);
                  app.showLine(l.id);
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 2),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFF26262B)))),
                  child: Row(children: [
                    ReorderableDragStartListener(
                      index: i,
                      child: Semantics(
                        label: 'Drag to reorder ${l.name}',
                        child: const Padding(
                          padding: EdgeInsets.fromLTRB(0, 8, 10, 8),
                          child: Icon(Icons.drag_indicator, size: 22, color: Color(0xFF52525B)),
                        ),
                      ),
                    ),
                    LineBadge(l),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Row(children: [
                        Flexible(
                          child: Text(l.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: cond(26, FontWeight.w700, color: Colors.white)),
                        ),
                        if (i == 0) ...[
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 7),
                            decoration: BoxDecoration(color: kYellow, borderRadius: BorderRadius.circular(3)),
                            child: Text('DEFAULT', style: cond(12, FontWeight.w800, ls: .1, color: Colors.black)),
                          ),
                        ],
                      ]),
                    ),
                    const SizedBox(width: 14),
                    Text('${occ.where((e) => e.cat == l.id).length} ${isToday ? 'today' : 'that day'}',
                        style: inter(13, FontWeight.w600, color: kDim)),
                    const SizedBox(width: 6),
                    Semantics(
                      button: true,
                      label: 'Edit line ${l.name}',
                      child: GestureDetector(
                        onTap: tapped(() => openLineSheet(context, l.id)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                          child: Text('•••', style: inter(18, FontWeight.w500, ls: .05, color: kDim)),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            );
          },
          footer: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('Hold and drag to reorder. The top line is the default for new events.',
                  style: inter(12, FontWeight.w500, height: 1.45, color: const Color(0xFF71717A))),
            ),
            if (app.s.lines.length < kLetters.length)
              Padding(
                padding: const EdgeInsets.only(top: 18),
                child: OutlinedButton(
                  onPressed: tapped(() => openLineSheet(context, null)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                    side: const BorderSide(color: Colors.white, width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('ADD LINE', style: cond(14, FontWeight.w800, ls: .08, color: Colors.white)),
                ),
              ),
          ]),
        ),
      ),
    ]);
  }
}

/// Page title block shared by Lines, Add/Edit and Settings.
class PageHead extends StatelessWidget {
  final String title;
  final String? sub;
  final Widget trailing;
  const PageHead({super.key, required this.title, this.sub, required this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 20, 0, 18),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title.toUpperCase(), style: cond(50, FontWeight.w800, ls: -.01, height: .95, color: Colors.white)),
              if (sub != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(sub!, style: inter(12, FontWeight.w800, ls: .08, color: kDim)),
                ),
            ]),
          ),
          trailing,
        ]),
      );
}

void openLineSheet(BuildContext context, String? id) {
  final app = context.read<AppState>();
  showSheet<void>(context, (_) => ChangeNotifierProvider.value(value: app, child: _LineSheet(id)));
}

class _LineSheet extends StatefulWidget {
  final String? id;
  const _LineSheet(this.id);
  @override
  State<_LineSheet> createState() => _LineSheetState();
}

class _LineSheetState extends State<_LineSheet> {
  late final AppState app = context.read<AppState>();
  late final Line? line = widget.id == null ? null : app.lineOf(widget.id!);
  late final _name = TextEditingController(text: line?.name ?? '');
  late final _kw = TextEditingController(text: line?.kw ?? '');
  late final _badge = TextEditingController(text: line?.label ?? app.nextLineId)..addListener(() => setState(() {}));
  late String _color = line?.color ?? kPalette.firstWhere((c) => !app.s.lines.any((l) => l.color == c), orElse: () => kPalette.first);

  @override
  void dispose() {
    _name.dispose();
    _kw.dispose();
    _badge.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    final l = line!;
    final others = app.s.lines.where((x) => x.id != l.id).toList();
    final n = app.s.events.where((e) => e.cat == l.id).length;
    final ok = await ask<bool>(context, 'Delete ${l.name}?', n > 0 ? 'Its $n event${n > 1 ? 's' : ''} will move to ${others.first.name}.' : '',
        [const AskBtn('Delete line', true, BtnKind.red)]);
    if (ok != true || !mounted) return;
    Navigator.pop(context);
    app.deleteLine(l.id);
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 5),
          child: Text(t, style: inter(13, FontWeight.w600, color: pal.label)),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SheetHead(line != null ? 'Edit line' : 'New line'),
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            label('Name'),
            SheetField(controller: _name, maxLength: 24),
          ]),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 76,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            label('Badge'),
            SheetField(controller: _badge, maxLength: 2, caps: true, center: true),
          ]),
        ),
        const SizedBox(width: 12),
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: LineBadge(
            Line(id: widget.id ?? app.nextLineId, name: '', color: _color, kw: '', label: _badge.text),
            size: 40,
            fontSize: 17,
          ),
        ),
      ]),
      label('Color'),
      Wrap(spacing: 10, runSpacing: 10, children: [
        for (final c in kPalette)
          Semantics(
            button: true,
            selected: c == _color,
            label: 'Color $c',
            child: GestureDetector(
              onTap: tapped(() => setState(() => _color = c)),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: hexColor(c),
                  shape: BoxShape.circle,
                  border: Border.all(color: c == _color ? (pal.light ? Colors.black : Colors.white) : Colors.transparent, width: 3),
                ),
              ),
            ),
          ),
      ]),
      label('Keywords (sorts imported events onto this line)'),
      SheetField(controller: _kw, hint: 'meeting, sync, standup'),
      SheetBtn('Save line', kind: BtnKind.yellow, onTap: () {
        final name = _name.text.trim();
        if (name.isEmpty) {
          app.showToast('Give the line a name');
          return;
        }
        Navigator.pop(context);
        app.saveLine(widget.id, name, _color, _kw.text.trim(), _badge.text);
      }),
      if (line != null && app.s.lines.length > 1) SheetBtn('Delete line', kind: BtnKind.red, onTap: _delete),
    ]);
  }
}

/// Boxed text field used in sheets.
class SheetField extends StatelessWidget {
  final TextEditingController controller;
  final String? hint;
  final int? maxLength;
  final int maxLines;
  final TextInputType? keyboard;
  final bool caps, center;
  const SheetField({super.key, required this.controller, this.hint, this.maxLength, this.maxLines = 1, this.keyboard, this.caps = false, this.center = false});
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return TextField(
      controller: controller,
      maxLength: maxLength,
      maxLines: maxLines,
      minLines: 1,
      keyboardType: keyboard,
      autocorrect: false,
      textAlign: center ? TextAlign.center : TextAlign.start,
      textCapitalization: caps ? TextCapitalization.characters : TextCapitalization.none,
      style: inter(15, FontWeight.w500, color: pal.ink),
      cursorColor: kYellow,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: inter(15, FontWeight.w500, color: pal.placeholder),
        counterText: '',
        isDense: true,
        filled: true,
        fillColor: pal.field,
        contentPadding: const EdgeInsets.all(12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      ),
    );
  }
}
