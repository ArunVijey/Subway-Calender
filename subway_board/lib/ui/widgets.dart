// Small shared widgets: icons, line badges, switch, sheets, pickers.
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/model.dart';
import '../core/util.dart';
import 'haptics.dart';
import 'theme.dart';

const _icons = {
  'gear':
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09a1.65 1.65 0 0 0-1-1.51 1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09a1.65 1.65 0 0 0 1.51-1 1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/></svg>',
  'grid':
      '<svg viewBox="0 0 24 24" fill="currentColor"><rect x="3" y="3" width="8" height="8" rx="2"/><rect x="13" y="3" width="8" height="8" rx="2"/><rect x="3" y="13" width="8" height="8" rx="2"/><rect x="13" y="13" width="8" height="8" rx="2"/></svg>',
  'lines':
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><circle cx="6" cy="5" r="2.2"/><circle cx="18" cy="5" r="2.2"/><circle cx="12" cy="19" r="2.2"/><path d="M6 7.2c0 5 6 4 6 9.6M18 7.2c0 5-6 4-6 9.6"/></svg>',
  'plus': '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round"><path d="M12 5v14M5 12h14"/></svg>',
  'reset':
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12a9 9 0 1 0 3-6.7"/><path d="M3 4v5h5"/></svg>',
  'chev': '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M6 9l6 6 6-6"/></svg>',
};

class SvgIcon extends StatelessWidget {
  final String name;
  final double size;
  final Color color;
  const SvgIcon(this.name, {super.key, this.size = 22, this.color = Colors.white});
  @override
  Widget build(BuildContext context) =>
      SvgPicture.string(_icons[name]!, width: size, height: size, theme: SvgTheme(currentColor: color));
}

/// Colored circle with the line letter.
class LineBadge extends StatelessWidget {
  final Line line;
  final double size, fontSize;
  final bool outline; // live row: transparent with a black ring
  const LineBadge(this.line, {super.key, this.size = 40, this.fontSize = 17, this.outline = false});
  @override
  Widget build(BuildContext context) {
    final bg = hexColor(line.color);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: outline ? Colors.transparent : bg,
        border: outline ? Border.all(color: Colors.black, width: 2.5) : null,
      ),
      child: Text(line.label,
          style: cond(fontSize, FontWeight.w800, color: outline ? Colors.black : (darkTextOn(line.color) ? Colors.black : Colors.white))),
    );
  }
}

/// iOS-style 50×30 switch, yellow when on.
class PillSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  const PillSwitch({super.key, required this.value, this.onChanged});
  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      child: GestureDetector(
        onTap: tapped(onChanged == null ? null : () => onChanged!(!value)),
        child: Opacity(
          opacity: onChanged == null ? .5 : 1,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 50,
            height: 30,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: value ? kYellow : const Color(0xFF3F3F46), borderRadius: BorderRadius.circular(15)),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 200),
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Color(0x40000000), blurRadius: 3, offset: Offset(0, 1))],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 46px round button (settings gear, form reset/close).
class CircleBtn extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  final String label;
  const CircleBtn({super.key, required this.child, required this.onTap, required this.label});
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          onTap: tapped(onTap),
          child: Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF141416),
              border: Border.all(color: const Color(0xFF3A3A40), width: 1.5),
            ),
            child: child,
          ),
        ),
      );
}

/// Opens a bottom sheet with the web app's look.
Future<T?> showSheet<T>(BuildContext context, WidgetBuilder builder) {
  final pal = Pal.of(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0xB3000000),
    builder: (ctx) => PalScope(
      pal: pal,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * .9),
          child: Container(
            decoration: BoxDecoration(color: pal.panel, borderRadius: const BorderRadius.vertical(top: Radius.circular(22))),
            padding: EdgeInsets.fromLTRB(18, 20, 18, 20 + MediaQuery.paddingOf(ctx).bottom),
            child: SingleChildScrollView(child: builder(ctx)),
          ),
        ),
      ),
    ),
  );
}

/// Sheet title row: big condensed title + ✕.
class SheetHead extends StatelessWidget {
  final String title;
  const SheetHead(this.title, {super.key});
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(children: [
        Expanded(child: Text(title.toUpperCase(), style: cond(28, FontWeight.w800, color: pal.ink))),
        GestureDetector(
          onTap: tapped(() => Navigator.pop(context)),
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: pal.btn, shape: BoxShape.circle),
            child: Text('✕', style: TextStyle(fontSize: 14, color: pal.ink)),
          ),
        ),
      ]),
    );
  }
}

enum BtnKind { plain, yellow, red }

/// Full-width uppercase button used in sheets.
class SheetBtn extends StatelessWidget {
  final String label;
  final BtnKind kind;
  final VoidCallback? onTap;
  const SheetBtn(this.label, {super.key, this.kind = BtnKind.plain, this.onTap});
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final (bg, fg) = switch (kind) {
      BtnKind.yellow => (kYellow, Colors.black),
      BtnKind.red => (const Color(0xFFDC2626), Colors.white),
      BtnKind.plain => (pal.btn, pal.ink),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: tapped(onTap),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            alignment: Alignment.center,
            child: Text(label.toUpperCase(), style: cond(16, FontWeight.w800, ls: .06, color: fg)),
          ),
        ),
      ),
    );
  }
}

class AskBtn<T> {
  final String label;
  final T value;
  final BtnKind kind;
  const AskBtn(this.label, this.value, [this.kind = BtnKind.plain]);
}

/// Confirmation sheet; resolves to the tapped button's value, or null on cancel.
Future<T?> ask<T>(BuildContext context, String title, String text, List<AskBtn<T>> btns) {
  return showSheet<T>(context, (ctx) {
    final pal = Pal.of(ctx);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Text(title.toUpperCase(), style: cond(28, FontWeight.w800, color: pal.ink)),
      ),
      if (text.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(text, style: inter(14, FontWeight.w500, color: pal.label, height: 1.45)),
        ),
      for (final b in btns) SheetBtn(b.label, kind: b.kind, onTap: () => Navigator.pop(ctx, b.value)),
      SheetBtn('Cancel', onTap: () => Navigator.pop(ctx)),
    ]);
  });
}

/// Option list sheet (stands in for the web app's <select>).
Future<T?> pickOption<T>(BuildContext context, String title, List<(T, String)> options, T current) {
  return showSheet<T>(context, (ctx) {
    final pal = Pal.of(ctx);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SheetHead(title),
      for (final (v, label) in options)
        InkWell(
          onTap: tapped(() => Navigator.pop(ctx, v)),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 4),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.panelRule))),
            child: Row(children: [
              Expanded(child: Text(label, style: inter(16, FontWeight.w500, color: pal.ink))),
              if (v == current) const Icon(Icons.check, color: kYellow, size: 20),
            ]),
          ),
        ),
    ]);
  });
}

/// Date picker themed to match.
Future<DateTime?> pickDate(BuildContext context, DateTime initial) {
  final pal = Pal.of(context);
  return showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
    builder: (ctx, child) => Theme(data: pickerTheme(pal), child: child!),
  );
}

Future<TimeOfDay?> pickTime(BuildContext context, TimeOfDay initial) {
  final pal = Pal.of(context);
  return showTimePicker(
    context: context,
    initialTime: initial,
    builder: (ctx, child) => Theme(data: pickerTheme(pal), child: child!),
  );
}

ThemeData pickerTheme(Pal pal) {
  final scheme = pal.light
      ? const ColorScheme.light(primary: Color(0xFF111111), onPrimary: kYellow, surface: Color(0xFFF6F3EC), onSurface: Color(0xFF111111))
      : const ColorScheme.dark(primary: kYellow, onPrimary: Colors.black, surface: Color(0xFF141416), onSurface: Colors.white);
  return ThemeData(colorScheme: scheme, useMaterial3: true, fontFamily: 'Inter');
}
