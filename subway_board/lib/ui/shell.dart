// App frame: top bar, the current tab, bottom tabs and the toast.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/store.dart';
import '../core/util.dart';
import 'board.dart';
import 'form.dart';
import 'lines.dart';
import 'settings.dart';
import 'haptics.dart';
import 'theme.dart';
import 'widgets.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) context.read<AppState>().resumed();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final mq = MediaQuery.of(context);
    app.use24h = mq.alwaysUse24HourFormat;
    hapticsOn = app.s.settings.haptics;
    final keyboard = mq.viewInsets.bottom > 0;

    final view = switch (app.tab) {
      'lines' => const LinesView(),
      'add' => EventForm(key: ValueKey(app.formSeq)),
      _ => const BoardView(),
    };

    return PopScope(
      canPop: app.tab == 'board',
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) app.switchTab('board');
      },
      child: Scaffold(
        backgroundColor: kBlack,
        bottomNavigationBar: keyboard ? null : const _Tabs(),
        body: Stack(children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: EdgeInsets.fromLTRB(18, 10 + mq.padding.top, 18, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const _TopBar(),
                  Expanded(child: view),
                ]),
              ),
            ),
          ),
          const _Toast(),
        ]),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final st = app.s.settings;
    final sample = app.s.events.any((e) => e.sample);
    final syncError = st.mode != 'none' && st.lastSyncError.isNotEmpty;
    final reconnect = st.mode == 'api' && !app.gConnected;
    final left = reconnect
        ? 'TAP TO RECONNECT GOOGLE'
        : syncError
        ? 'SUBWAY BOARD · SYNC ⚠'
        : sample
            ? 'SAMPLE DAY'
            : app.activeCat != null
                ? 'LINE ${app.lineOf(app.activeCat!).label} · ${app.lineOf(app.activeCat!).name.toUpperCase()}'
                : 'SUBWAY BOARD';
    return Container(
      padding: const EdgeInsets.fromLTRB(0, 6, 0, 10),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white, width: 2))),
      child: Row(children: [
        Expanded(
          child: GestureDetector(
            onTap: tapped(reconnect
                ? () async {
                    try {
                      await app.connectGoogle();
                      app.showToast('Reconnected');
                    } catch (e) {
                      app.showToast('$e');
                    }
                  }
                : syncError
                ? () => openSettings(context)
                : null),
            child: Text(left, maxLines: 1, overflow: TextOverflow.ellipsis, style: cond(15, FontWeight.w800, ls: .08, color: Colors.white)),
          ),
        ),
        if (sample)
          GestureDetector(
            onTap: tapped(() async {
              final ok = await ask<bool>(context, 'Clear the sample day?', 'Removes the example events so you start with your own.',
                  const [AskBtn('Clear samples', true)]);
              if (ok == true) app.clearSamples();
            }),
            child: Text('✕', style: cond(20, FontWeight.w800, color: Colors.white)),
          )
        else
          Text(fmtT(nowMs(), use24h: app.use24h).toUpperCase(), style: cond(12, FontWeight.w800, ls: .06, color: Colors.white)),
      ]),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs();
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final bottom = MediaQuery.paddingOf(context).bottom;
    Widget tab(String id, String icon, String label) {
      final on = app.tab == id;
      final color = on ? kYellow : kTabIdle;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          label: label,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: tapped(() => app.switchTab(id)),
            child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  SvgIcon(icon, size: 26, color: color),
                  const SizedBox(height: 5),
                  Text(label, style: cond(14, FontWeight.w800, ls: .08, color: color)),
                ]),
              ),
              if (on)
                Positioned(
                  top: -9,
                  child: Container(width: 28, height: 3, decoration: BoxDecoration(color: kYellow, borderRadius: BorderRadius.circular(2))),
                ),
            ]),
          ),
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(color: kBlack, border: Border(top: BorderSide(color: Color(0xFF1C1C20)))),
      padding: EdgeInsets.fromLTRB(0, 8, 0, 8 + bottom),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Row(children: [
            tab('board', 'grid', 'BOARD'),
            tab('lines', 'lines', 'LINES'),
            tab('add', 'plus', 'ADD'),
          ]),
        ),
      ),
    );
  }
}

class _Toast extends StatefulWidget {
  const _Toast();
  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> {
  ToastMsg? _last; // kept while fading out

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final t = app.toast;
    if (t != null) _last = t;
    final shown = _last;
    final on = t != null;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 16,
      child: IgnorePointer(
        ignoring: !on || t.action == null,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 250),
          offset: on ? Offset.zero : const Offset(0, .4),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 250),
            opacity: on ? 1 : 0,
            child: Center(
              child: shown == null
                  ? const SizedBox.shrink()
                  : Container(
                      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .9),
                      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 15),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 30, offset: Offset(0, 10))],
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Flexible(child: Text(shown.text, style: inter(14, FontWeight.w700, color: Colors.black))),
                        if (shown.action != null) ...[
                          const SizedBox(width: 12),
                          GestureDetector(
                            onTap: tapped(app.runToastAction),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                              decoration: BoxDecoration(color: const Color(0xFF111111), borderRadius: BorderRadius.circular(8)),
                              child: Text(shown.action!.label, style: inter(12, FontWeight.w900, color: kYellow)),
                            ),
                          ),
                        ],
                      ]),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
