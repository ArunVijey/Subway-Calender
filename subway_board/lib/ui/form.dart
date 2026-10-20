// Add / Edit tab.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/store.dart';
import '../core/logic.dart';
import '../core/model.dart';
import '../core/util.dart';
import 'lines.dart';
import 'haptics.dart';
import 'theme.dart';
import 'widgets.dart';

const _durs = [15, 30, 45, 60, 90, 120, 180, 240];
String durLabel(int m) => m < 60 ? '$m min' : (m % 60 != 0 ? '${m ~/ 60} hr ${m % 60} min' : '${m ~/ 60} hr');

class EventForm extends StatefulWidget {
  const EventForm({super.key});
  @override
  State<EventForm> createState() => _EventFormState();
}

class _EventFormState extends State<EventForm> {
  late final AppState app = context.read<AppState>();
  late final Event? view = app.editing;
  late final Event? master = view == null ? null : app.masterOf(view!);
  late final bool ro = view != null && app.readOnly(view!);

  final _name = TextEditingController();
  final _loc = TextEditingController();
  final _notes = TextEditingController();
  final _nameFocus = FocusNode();
  final _scroll = ScrollController();

  late bool allDay;
  late DateTime date; // local midnight
  late TimeOfDay time;
  late int dur; // minutes, or days when all-day
  late String cat;
  String repeat = '', until = '';
  int? remind;
  String calId = ''; // Google calendar to save to; '' = this device only
  bool locOpen = false, moreOpen = false, lineTouched = false;

  @override
  void initState() {
    super.initState();
    int start, end;
    allDay = false;
    final v = view;
    if (v != null) {
      start = v.start;
      end = v.end;
      allDay = v.allDay;
    } else if (app.sel == todayStr()) {
      start = (nowMs() / 900000).ceil() * 900000;
      end = start + 30 * kMin;
    } else {
      final d = DateTime.fromMillisecondsSinceEpoch(dms(app.sel));
      start = DateTime(d.year, d.month, d.day, 9).millisecondsSinceEpoch;
      end = start + 30 * kMin;
    }
    final sd = DateTime.fromMillisecondsSinceEpoch(start);
    date = DateTime(sd.year, sd.month, sd.day);
    time = TimeOfDay(hour: sd.hour, minute: sd.minute);
    dur = allDay ? math.max(1, ((end - start) / kDay).round()) : ((end - start) / kMin).round();
    cat = v?.cat ?? app.activeCat ?? app.s.lines.first.id;
    _name.text = v?.title ?? '';
    _loc.text = v?.loc ?? '';
    _notes.text = v?.notes ?? '';
    final m = master;
    repeat = m?.repeat?.freq ?? '';
    until = m?.repeat?.until ?? '';
    remind = v?.remind;
    locOpen = v != null && (v.loc.isNotEmpty || v.notes.isNotEmpty);
    moreOpen = (m?.repeat != null) || remind != null;
    if (app.s.settings.mode == 'api') calId = v == null ? app.s.settings.defaultCalId : (v.source == 'gapi' ? v.calId ?? '' : '');
    _name.addListener(_autoLine);
  }

  @override
  void dispose() {
    _name.dispose();
    _loc.dispose();
    _notes.dispose();
    _nameFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _autoLine() {
    if (view != null || lineTouched) return;
    final c = matchLine(app.s, _name.text, _loc.text);
    if (c != null && c != cat) setState(() => cat = c);
  }

  List<(int, String)> get _durOptions {
    final opts = allDay ? [for (var n = 1; n <= 7; n++) (n, n == 1 ? '1 day' : '$n days')] : [for (final m in _durs) (m, durLabel(m))];
    if (!opts.any((o) => o.$1 == dur)) {
      opts
        ..add((dur, allDay ? '$dur days' : durLabel(dur)))
        ..sort((a, b) => a.$1.compareTo(b.$1));
    }
    return opts;
  }

  FormValues _read() {
    final start = allDay ? date.millisecondsSinceEpoch : DateTime(date.year, date.month, date.day, time.hour, time.minute).millisecondsSinceEpoch;
    return FormValues(
      title: _name.text.trim(),
      cat: cat,
      loc: _loc.text.trim(),
      notes: clip(_notes.text.trim(), 2000),
      start: start,
      end: allDay ? addDays(start, dur) : start + dur * kMin,
      allDay: allDay,
      repeat: repeat,
      until: repeat.isNotEmpty ? until : '',
      remind: remind,
      calId: app.s.settings.mode == 'api' ? calId : '',
    );
  }

  void _save() {
    final err = app.saveEvent(_read());
    if (err != null) {
      _nameFocus.requestFocus();
      app.showToast(err);
    }
  }

  Future<void> _delete() async {
    final v = view, m = master;
    if (v == null || m == null) return;
    if (!ro && v.seriesId != null) {
      final c = await ask<String>(context, 'Delete repeating event', '"${m.title}" repeats.', const [
        AskBtn('Only this one', 'one'),
        AskBtn('Every occurrence', 'all', BtnKind.red),
      ]);
      if (c == null) return;
      app.deleteEvent(choice: c);
    } else if (app.isGoogleEvent(m)) {
      final c = await ask<String>(context, 'Delete event', "It's also in your Google Calendar.", const [
        AskBtn('Delete everywhere', 'all', BtnKind.red),
        AskBtn('Hide on this board', 'hide'),
      ]);
      if (c == null) return;
      app.deleteEvent(choice: c);
    } else {
      app.deleteEvent();
    }
  }

  /// "Save to" row: which Google calendar a new/local event goes to.
  Widget _saveTo(Widget Function(String, Widget) fr, Widget Function(String, VoidCallback?) chip) {
    final st = app.s.settings;
    final writable = st.calendars.where((c) => c.writable).toList();
    final opts = <(String, String)>[
      if (writable.isEmpty) (st.defaultCalId, 'Google Calendar') else for (final c in writable) (c.id, c.name),
      ('', 'This device only'),
    ];
    final label = opts.where((o) => o.$1 == calId).firstOrNull?.$2 ?? (calId.isEmpty ? 'This device only' : 'Google Calendar');
    final locked = view?.source == 'gapi'; // already in Google; moving between calendars isn't supported
    return fr(
      'Save to',
      chip(label, locked
          ? null
          : () async {
              final x = await pickOption<String>(context, 'Save to', opts, calId);
              if (x != null) setState(() => calId = x);
            }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final v = view;
    final remDefault = kRemind[app.s.settings.remindDefault] ?? kRemind[0]!;
    final note = ro
        ? 'From your read-only iCal link. You can change its line and reminder here; edit everything else in Google Calendar.'
        : v?.seriesId != null
            ? 'Repeating event. Changes apply to every occurrence.'
            : v?.source == 'gapi' && app.s.settings.mode == 'api'
                ? 'Synced with Google Calendar. Changes are sent back.'
                : '';
    final line = app.lineOf(cat);
    final rowLabel = inter(16, FontWeight.w500, color: pal.rowLabel);

    Widget fr(String label, Widget control) => Container(
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.panelRule))),
          child: Row(children: [Expanded(child: Text(label, style: rowLabel)), control]),
        );

    Widget chip(String text, VoidCallback? onTap) => GestureDetector(
          onTap: tapped(onTap),
          child: Opacity(
            opacity: onTap == null ? .5 : 1,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
              decoration: BoxDecoration(color: pal.field, borderRadius: BorderRadius.circular(8)),
              child: Text(text, style: inter(15, FontWeight.w500, color: pal.ink)),
            ),
          ),
        );

    Widget expander(String label, bool open, VoidCallback onTap) => InkWell(
          onTap: tapped(onTap),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 15),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.panelRule))),
            child: Row(children: [
              Text(open ? '⊖' : '⊕', style: inter(15, FontWeight.w500, color: pal.label)),
              const SizedBox(width: 8),
              Text(label, style: inter(15, FontWeight.w500, color: pal.label)),
            ]),
          ),
        );

    final dateLabel = '${weekdayShort(date.millisecondsSinceEpoch)}, ${monthDay(date.millisecondsSinceEpoch)} ${date.year}';
    final timeMs = DateTime(2000, 1, 1, time.hour, time.minute).millisecondsSinceEpoch;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PageHead(
        title: v == null ? 'Add Event' : (ro ? 'Synced Event' : 'Edit Event'),
        trailing: CircleBtn(
          label: v == null ? 'Reset' : 'Close',
          onTap: () => v == null ? app.openForm(null) : app.switchTab('board'),
          child: v == null ? const SvgIcon('reset', size: 22) : const Text('✕', style: TextStyle(fontSize: 16, color: Colors.white)),
        ),
      ),
      Expanded(
        child: Container(
          decoration: BoxDecoration(color: pal.panel, borderRadius: const BorderRadius.vertical(top: Radius.circular(16))),
          child: ListView(controller: _scroll, padding: const EdgeInsets.fromLTRB(18, 4, 18, 28), children: [
            Container(
              padding: const EdgeInsets.fromLTRB(0, 16, 0, 12),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.panelRule))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('EVENT NAME', style: inter(11, FontWeight.w800, ls: .1, color: pal.label)),
                TextField(
                  controller: _name,
                  focusNode: _nameFocus,
                  enabled: !ro,
                  textInputAction: TextInputAction.done,
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: (_) => _save(),
                  cursorColor: kYellow,
                  style: inter(24, FontWeight.w700, color: pal.ink),
                  decoration: InputDecoration(
                    hintText: "What's happening?",
                    hintStyle: inter(24, FontWeight.w700, color: pal.placeholder),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.fromLTRB(0, 6, 0, 2),
                  ),
                ),
              ]),
            ),
            fr('All day', PillSwitch(value: allDay, onChanged: ro ? null : (x) => setState(() {
                  allDay = x;
                  dur = x ? 1 : 30;
                }))),
            fr(
              'Starts',
              Row(children: [
                chip(dateLabel, ro
                    ? null
                    : () async {
                        final d = await pickDate(context, date);
                        if (d != null) setState(() => date = DateTime(d.year, d.month, d.day));
                      }),
                if (!allDay) ...[
                  const SizedBox(width: 8),
                  chip(fmtT(timeMs, use24h: app.use24h), ro
                      ? null
                      : () async {
                          final t = await pickTime(context, time);
                          if (t != null) setState(() => time = t);
                        }),
                ],
              ]),
            ),
            fr(
              allDay ? 'Lasts' : 'Duration',
              chip(_durOptions.firstWhere((o) => o.$1 == dur).$2, ro
                  ? null
                  : () async {
                      final x = await pickOption<int>(context, allDay ? 'Lasts' : 'Duration', _durOptions, dur);
                      if (x != null) setState(() => dur = x);
                    }),
            ),
            fr(
              'Line',
              GestureDetector(
                onTap: tapped(() async {
                  final x = await pickOption<String>(context, 'Line', [for (final l in app.s.lines) (l.id, '${l.label} · ${l.name}')], cat);
                  if (x != null) {
                    setState(() {
                      cat = x;
                      lineTouched = true;
                    });
                  }
                }),
                child: Row(children: [
                  LineBadge(line, size: 26, fontSize: 12),
                  const SizedBox(width: 8),
                  Text(line.name, style: inter(16, FontWeight.w600, color: pal.ink)),
                  const SizedBox(width: 8),
                  const SvgIcon('chev', size: 14, color: kDim),
                ]),
              ),
            ),
            if (app.s.settings.mode == 'api') _saveTo(fr, chip),
            expander('Location & notes', locOpen, () => setState(() => locOpen = !locOpen)),
            if (locOpen)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Column(children: [
                  IgnorePointer(ignoring: ro, child: Opacity(opacity: ro ? .5 : 1, child: SheetField(controller: _loc, hint: 'Location or meeting link'))),
                  const SizedBox(height: 10),
                  IgnorePointer(ignoring: ro, child: Opacity(opacity: ro ? .5 : 1, child: SheetField(controller: _notes, hint: 'Notes', maxLines: 6))),
                  const SizedBox(height: 10),
                ]),
              ),
            expander('Repeat & reminder', moreOpen, () => setState(() => moreOpen = !moreOpen)),
            if (moreOpen) ...[
              if (v?.source != 'gapi') ...[
                fr(
                  'Repeat',
                  chip(kRepeatLabels[repeat]!, ro
                      ? null
                      : () async {
                          final x = await pickOption<String>(context, 'Repeat', kRepeatLabels.entries.map((e) => (e.key, e.value)).toList(), repeat);
                          if (x != null) setState(() => repeat = x);
                        }),
                ),
                if (repeat.isNotEmpty)
                  fr(
                    'Until',
                    Row(children: [
                      chip(until.isEmpty ? 'Forever' : '${monthDay(dms(until))} ${until.substring(0, 4)}', ro
                          ? null
                          : () async {
                              final d = await pickDate(context, until.isEmpty ? date : DateTime.fromMillisecondsSinceEpoch(dms(until)));
                              if (d != null) setState(() => until = dstr(d.millisecondsSinceEpoch));
                            }),
                      if (until.isNotEmpty && !ro)
                        IconButton(
                          tooltip: 'Repeat forever',
                          onPressed: tapped(() => setState(() => until = '')),
                          icon: Icon(Icons.close, size: 18, color: pal.label),
                        ),
                    ]),
                  ),
              ],
              fr(
                'Reminder',
                chip(remind == null ? 'Default (${remDefault.toLowerCase()})' : kRemind[remind]!, () async {
                  final x = await pickOption<int>(
                    context,
                    'Reminder',
                    [(-999, 'Default (${remDefault.toLowerCase()})'), ...kRemind.entries.map((e) => (e.key, e.value))],
                    remind ?? -999,
                  );
                  if (x != null) setState(() => remind = x == -999 ? null : x);
                }),
              ),
            ],
            if (note.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 14),
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                decoration: BoxDecoration(color: pal.light ? const Color(0xFFF3E7B8) : const Color(0xFF2A2108), borderRadius: BorderRadius.circular(10)),
                child: Text(note, style: inter(13, FontWeight.w500, height: 1.4, color: pal.light ? const Color(0xFF713F12) : const Color(0xFFFCD34D))),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: Material(
                color: kYellow,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: tapped(_save),
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    alignment: Alignment.center,
                    child: Text(v == null ? 'ADD TO BOARD' : 'SAVE CHANGES', style: cond(15, FontWeight.w800, ls: .06, color: Colors.black)),
                  ),
                ),
              ),
            ),
            if (v != null)
              TextButton(
                onPressed: tapped(_delete),
                style: TextButton.styleFrom(padding: const EdgeInsets.all(14)),
                child: Text(ro ? 'Hide from board' : 'Delete event', style: inter(15, FontWeight.w700, color: kRed)),
              ),
          ]),
        ),
      ),
    ]);
  }
}
