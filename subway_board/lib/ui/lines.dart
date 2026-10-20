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

class LinesView extends StatelessWidget {
  const LinesView({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d0 = dms(app.sel), isToday = app.sel == todayStr();
    final occ = occurrences(app.s, d0, addDays(d0, 1));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PageHead(
        title: 'Lines',
        sub: '${weekdayShort(d0)}, ${monthDay(d0)}'.toUpperCase(),
        trailing: const GearButton(),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
          for (final l in app.s.lines)
            InkWell(
              onTap: tapped(() => app.showLine(l.id)),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 2),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFF26262B)))),
                child: Row(children: [
                  LineBadge(l),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(l.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: cond(26, FontWeight.w700, color: Colors.white)),
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
