// Settings: calendar links, alerts, appearance, import/export/backup.
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
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

void openSettings(BuildContext context) {
  final pal = Pal.of(context);
  Navigator.of(context).push(PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 350),
    reverseTransitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (_, _, _) => PalScope(pal: pal, child: const SettingsPage()),
    transitionsBuilder: (_, anim, _, child) => SlideTransition(
      position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(CurvedAnimation(parent: anim, curve: kEase)),
      child: child,
    ),
  ));
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final AppState app = context.read<AppState>();
  late String mode = app.s.settings.mode;
  late final _feeds = TextEditingController(text: app.s.settings.feeds.map((f) => f.url).join('\n'));
  late final _client = TextEditingController(text: app.s.settings.clientId);
  bool _connecting = false;
  bool _notifyOn = false;

  @override
  void initState() {
    super.initState();
    _refreshNotify();
  }

  Future<void> _refreshNotify() async {
    final ok = app.s.settings.notify && await app.alerts.enabled();
    if (mounted) setState(() => _notifyOn = ok);
  }

  @override
  void dispose() {
    _feeds.dispose();
    _client.dispose();
    super.dispose();
  }

  List<String> get _urls => _feeds.text.split(RegExp(r'\s+')).map((u) => u.trim()).where((u) => u.isNotEmpty).toList();

  Future<void> _saveSync() async {
    var removeOld = false;
    final n = app.pendingModeSwitchCount(mode);
    if (n > 0) {
      removeOld = await ask<bool>(context, 'Switch sync method?', 'Remove the $n events from your previous sync? They stay in Google Calendar.',
              const [AskBtn('Remove them', true)]) ==
          true;
      if (!mounted) return;
    }
    app.applySync(mode, _urls, _client.text, removeOld: removeOld);
    final st = app.s.settings;
    if (st.mode == 'none') {
      Navigator.pop(context);
      app.boardEpoch++;
      app.showToast('Saved');
      return;
    }
    if (st.mode == 'ical' && st.feeds.isEmpty) {
      app.showToast('Add an iCal link first');
      return;
    }
    if (st.mode == 'api' && st.clientId.isEmpty) {
      app.showToast('Paste your OAuth Client ID first');
      return;
    }
    await app.runSync(manual: true);
    if (!mounted) return;
    if (st.lastSyncError.isEmpty) {
      Navigator.pop(context);
      app.boardEpoch++;
      app.showToast('Synced · ${st.lastSyncMsg}');
    }
  }

  Future<void> _connect() async {
    if (_client.text.trim().isEmpty) {
      app.showToast('Paste your OAuth Client ID first');
      return;
    }
    app.applySync(mode, _urls, _client.text);
    setState(() => _connecting = true);
    try {
      await app.connectGoogle();
      app.showToast('Connected to Google');
    } catch (e) {
      app.showToast('$e');
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _disconnect() async {
    await app.disconnectGoogle();
    app.showToast('Disconnected');
  }

  Future<String?> _pickText() async {
    final files = await FilePicker.pickFiles();
    if (files.isEmpty) return null;
    return utf8.decode(await files.first.readAsBytes(), allowMalformed: true);
  }

  Future<void> _importIcs() async {
    final text = await _pickText();
    if (text == null || !mounted) return;
    if (!RegExp('BEGIN:VCALENDAR', caseSensitive: false).hasMatch(text)) {
      app.showToast("That isn't an .ics calendar file");
      return;
    }
    final r = app.importIcs(text);
    Navigator.pop(context);
    app.showToast('Imported ${r.added} new, ${r.updated} updated');
  }

  Future<void> _save(String name, String text, String mime, String done) async {
    try {
      final uri = await FilePicker.saveFile(fileName: name, bytes: utf8.encode(text), mimeType: mime);
      if (uri != null) app.showToast(done);
    } catch (e) {
      app.showToast('Could not save the file');
    }
  }

  Future<void> _restore() async {
    final text = await _pickText();
    if (text == null || !mounted) return;
    final b = app.readBackup(text);
    if (b == null) {
      app.showToast("That isn't a Subway Board backup");
      return;
    }
    final (state, at) = b;
    final when = at == null ? '' : DateTime.tryParse(at)?.toLocal();
    final ok = await ask<bool>(
      context,
      'Restore backup?',
      'This replaces everything on this device with the backup${when is DateTime ? ' from ${monthDay(when.millisecondsSinceEpoch)} ${when.year}, ${fmtT(when.millisecondsSinceEpoch, use24h: app.use24h)}' : ''}.',
      const [AskBtn('Replace with backup', true, BtnKind.red)],
    );
    if (ok != true || !mounted) return;
    Navigator.pop(context);
    app.restoreBackup(state);
  }

  Future<void> _googleImport() async {
    final r = await showSheet<MergeResult>(context, (_) => const _GoogleImportSheet());
    if (r == null || !mounted) return;
    Navigator.pop(context);
    app.switchTab('board');
    app.showToast('Imported ${r.added} new, ${r.updated} updated');
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    context.watch<AppState>();
    final st = app.s.settings;
    final pad = MediaQuery.paddingOf(context);

    Widget sec(String t) => Padding(
          padding: const EdgeInsets.only(top: 26),
          child: Text(t.toUpperCase(), style: cond(15, FontWeight.w800, ls: .08, color: pal.label)),
        );
    Widget fr(String label, Widget control) => Container(
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.panelRule))),
          child: Row(children: [Expanded(child: Text(label, style: inter(16, FontWeight.w500, color: pal.rowLabel))), control]),
        );
    Widget chip(String text, VoidCallback onTap) => GestureDetector(
          onTap: tapped(onTap),
          child: Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .55),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
            decoration: BoxDecoration(color: pal.field, borderRadius: BorderRadius.circular(8)),
            child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: inter(15, FontWeight.w500, color: pal.ink)),
          ),
        );
    Widget go(String label, VoidCallback onTap) => InkWell(
          onTap: tapped(onTap),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 15),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.panelRule))),
            child: Row(children: [
              Expanded(child: Text(label, style: inter(16, FontWeight.w500, color: pal.rowLabel))),
              Text('›', style: TextStyle(fontSize: 24, height: .8, color: pal.placeholder)),
            ]),
          ),
        );

    String? status;
    Color statusColor = pal.label;
    if (mode == st.mode && mode != 'none') {
      if (app.syncing) {
        status = 'Syncing…';
      } else if (st.lastSyncError.isNotEmpty) {
        status = '⚠ ${st.lastSyncError}';
        statusColor = kRed;
      } else if (st.lastSync > 0) {
        status = '✓ Synced ${fmtT(st.lastSync, use24h: app.use24h)} · ${st.lastSyncMsg}';
        statusColor = const Color(0xFF4ADE80);
      }
    }
    if (mode == 'api') {
      final who = app.google.email;
      final c = app.gConnected ? '● Connected${who != null ? ' as $who' : ''}' : '○ Not connected';
      status = status == null ? c : '$c · $status';
    }

    const modes = [('none', 'Off: this device only'), ('ical', 'Google iCal links (read-only)'), ('api', 'Google Calendar (two-way)')];
    const themes = [('system', 'Match phone'), ('dark', 'Dark'), ('light', 'Light')];
    final hidden = app.hiddenCount;

    return Scaffold(
      backgroundColor: kBlack,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: EdgeInsets.fromLTRB(18, 10 + pad.top, 18, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              PageHead(
                title: 'Settings',
                trailing: CircleBtn(label: 'Close', onTap: () => Navigator.pop(context), child: const Text('✕', style: TextStyle(fontSize: 16, color: Colors.white))),
              ),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(color: pal.panel, borderRadius: const BorderRadius.vertical(top: Radius.circular(16))),
                  child: ListView(padding: EdgeInsets.fromLTRB(18, 0, 18, 28 + pad.bottom), children: [
                    Padding(padding: const EdgeInsets.only(top: 16), child: Text('CALENDAR SYNC', style: cond(15, FontWeight.w800, ls: .08, color: pal.label))),
                    fr(
                      'Sync',
                      chip(modes.firstWhere((m) => m.$1 == mode).$2, () async {
                        final x = await pickOption<String>(context, 'Sync', modes, mode);
                        if (x != null) setState(() => mode = x);
                      }),
                    ),
                    if (mode == 'ical')
                      Container(
                        padding: const EdgeInsets.fromLTRB(0, 16, 0, 12),
                        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.panelRule))),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Text('ICAL LINKS, ONE PER LINE', style: inter(11, FontWeight.w800, ls: .1, color: pal.label)),
                          const SizedBox(height: 8),
                          SheetField(controller: _feeds, hint: 'https://calendar.google.com/calendar/ical/…/basic.ics', maxLines: 5, keyboard: TextInputType.url),
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text('Checked every 10 minutes while the app is open. Events from these links are read-only here.',
                                style: inter(12, FontWeight.w500, height: 1.45, color: pal.label)),
                          ),
                        ]),
                      ),
                    if (mode == 'api') ...[
                      Container(
                        padding: const EdgeInsets.fromLTRB(0, 16, 0, 12),
                        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.panelRule))),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Text('OAUTH CLIENT ID (WEB)', style: inter(11, FontWeight.w800, ls: .1, color: pal.label)),
                          const SizedBox(height: 8),
                          SheetField(controller: _client, hint: '…apps.googleusercontent.com'),
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                                'The same Web client ID the web app uses. Google Cloud also needs an Android client for this app; see GOOGLE_SETUP.md.',
                                style: inter(12, FontWeight.w500, height: 1.45, color: pal.label)),
                          ),
                        ]),
                      ),
                      go(_connecting ? 'Connecting…' : (app.gConnected ? 'Reconnect' : 'Connect Google'), _connecting ? () {} : _connect),
                      if (app.gConnected) go('Disconnect', _disconnect),
                      if (st.calendars.isNotEmpty) ...[
                        sec('Show calendars'),
                        for (final c in st.calendars)
                          InkWell(
                            onTap: tapped(c.id == st.defaultCalId ? null : () => app.setCalendarEnabled(c.id, !c.enabled)),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(children: [
                                Icon(c.enabled || c.id == st.defaultCalId ? Icons.check_box : Icons.check_box_outline_blank,
                                    size: 22, color: c.id == st.defaultCalId ? pal.placeholder : kYellow),
                                const SizedBox(width: 10),
                                Expanded(child: Text(c.name, style: inter(15, FontWeight.w500, color: pal.ink))),
                              ]),
                            ),
                          ),
                      ],
                    ],
                    if (status != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(status, style: inter(13, FontWeight.w600, height: 1.4, color: statusColor)),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: Material(
                        color: kYellow,
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: tapped(app.syncing ? null : _saveSync),
                          child: Container(
                            padding: const EdgeInsets.all(18),
                            alignment: Alignment.center,
                            child: Text(mode == 'none' ? 'SAVE' : (app.syncing ? 'SYNCING…' : 'SAVE & SYNC'),
                                style: cond(15, FontWeight.w800, ls: .06, color: Colors.black)),
                          ),
                        ),
                      ),
                    ),
                    sec('Alerts'),
                    fr('Chime', PillSwitch(value: st.sound, onChanged: app.setSound)),
                    fr(
                      'Notifications',
                      PillSwitch(
                        value: _notifyOn,
                        onChanged: (v) async {
                          final ok = await app.setNotify(v);
                          if (v && !ok) app.showToast('Notifications are blocked in phone settings');
                          await _refreshNotify();
                        },
                      ),
                    ),
                    fr(
                      'Default reminder',
                      chip(kRemind[st.remindDefault]!, () async {
                        final x = await pickOption<int>(context, 'Default reminder', kRemind.entries.map((e) => (e.key, e.value)).toList(), st.remindDefault);
                        if (x != null) app.setRemindDefault(x);
                      }),
                    ),
                    sec('Display'),
                    fr(
                      'Appearance',
                      chip(themes.firstWhere((t) => t.$1 == st.theme).$2, () async {
                        final x = await pickOption<String>(context, 'Appearance', themes, st.theme);
                        if (x != null) app.setTheme(x);
                      }),
                    ),
                    fr(
                      'Vibration',
                      PillSwitch(
                        value: st.haptics,
                        onChanged: (v) {
                          hapticsOn = v;
                          app.setHaptics(v);
                        },
                      ),
                    ),
                    sec('Data'),
                    go('Import from Google Calendar', _googleImport),
                    go('Import .ics file', _importIcs),
                    go('Export .ics file', () => _save('subway-board.ics', app.exportIcsText(), 'text/calendar', 'Calendar exported')),
                    go('Back up', () => _save('subway-board-backup-${todayStr()}.json', app.backupJson(), 'application/json', 'Backup saved')),
                    go('Restore backup', _restore),
                    if (hidden > 0)
                      go('Restore $hidden hidden event${hidden > 1 ? 's' : ''}', () {
                        app.restoreHidden();
                        app.showToast(st.mode == 'none' ? 'Hidden events return when you import again' : 'Hidden events return on next sync');
                      }),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// One-time copy of a Google Calendar using its secret iCal address.
class _GoogleImportSheet extends StatefulWidget {
  const _GoogleImportSheet();
  @override
  State<_GoogleImportSheet> createState() => _GoogleImportSheetState();
}

class _GoogleImportSheetState extends State<_GoogleImportSheet> {
  final _url = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final app = context.read<AppState>();
    final url = _url.text.trim();
    if (url.isEmpty) {
      setState(() => _error = 'Paste the secret address first');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await app.importFromUrl(url);
      if (mounted) Navigator.pop(context, r);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not import: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final hint = inter(14, FontWeight.w500, height: 1.5, color: pal.label);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SheetHead('Import Google'),
      Text('Copies your Google Calendar events onto the board once. Later changes in Google won’t show up here until you import again.', style: hint),
      const SizedBox(height: 12),
      Text('1. Open calendar.google.com on a computer\n'
          '2. Settings → pick your calendar under “Settings for my calendars”\n'
          '3. Integrate calendar → copy “Secret address in iCal format”\n'
          '4. Paste it below', style: hint),
      const SizedBox(height: 14),
      SheetField(controller: _url, hint: 'https://calendar.google.com/calendar/ical/…/basic.ics', maxLines: 3, keyboard: TextInputType.url),
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text('Keep this address private: anyone with it can read the calendar. It is used once and not stored.',
            style: inter(12, FontWeight.w500, height: 1.45, color: pal.label)),
      ),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: inter(13, FontWeight.w600, color: kRed))),
      SheetBtn(_busy ? 'Importing…' : 'Import', kind: BtnKind.yellow, onTap: _busy ? null : _go),
    ]);
  }
}
