// App frame: top bar, the current tab, bottom tabs and the toast.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/store.dart';
import '../core/util.dart';
import 'board.dart';
import 'form.dart';
import 'money.dart';
import 'quick_add.dart';
import 'search.dart';
import 'tasks.dart';
import 'today.dart';
import 'settings.dart';
import 'haptics.dart';
import 'motion.dart';
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
    final app = context.read<AppState>();
    if (state == AppLifecycleState.resumed) {
      app.resumed();
    } else if (state == AppLifecycleState.hidden || state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      app.paused();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final mq = MediaQuery.of(context);
    app.use24h = mq.alwaysUse24HourFormat;
    hapticsOn = app.s.settings.haptics;
    final keyboard = mq.viewInsets.bottom > 0;

    final view = switch (app.tab) {
      'tasks' => const TasksView(),
      'money' => const MoneyView(),
      'today' => const TodayView(),
      'add' => EventForm(key: ValueKey(app.formSeq)),
      _ => const BoardView(),
    };
    final reduce = mq.disableAnimations || app.instantTab;

    return PopScope(
      canPop: app.tab == 'today',
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) app.switchTab('today');
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
                  Expanded(
                    // Tabs cross-fade with a slight rise and settle, like a UIKit tab switch.
                    child: AnimatedSwitcher(
                      duration: reduce ? Duration.zero : const Duration(milliseconds: 420),
                      reverseDuration: reduce ? Duration.zero : const Duration(milliseconds: 160),
                      switchInCurve: Motion.smooth,
                      switchOutCurve: Curves.easeOut,
                      layoutBuilder: (cur, prev) => Stack(fit: StackFit.expand, children: [...prev, ?cur]),
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim.drive(CurveTween(curve: const Interval(0, .6))),
                        child: SlideTransition(
                          position: anim.drive(Tween(begin: const Offset(0, .025), end: Offset.zero)),
                          child: ScaleTransition(scale: anim.drive(Tween(begin: .985, end: 1)), child: child),
                        ),
                      ),
                      child: KeyedSubtree(key: ValueKey(app.tab == 'add' ? 'add${app.formSeq}' : app.tab), child: view),
                    ),
                  ),
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
        Semantics(
          button: true,
          label: 'Search',
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: tapped(() => openSearch(context)),
            child: const Padding(padding: EdgeInsets.fromLTRB(14, 0, 14, 0), child: Icon(Icons.search, size: 22, color: Colors.white)),
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
          RollingText(fmtT(nowMs(), use24h: app.use24h).toUpperCase(),
              style: cond(12, FontWeight.w800, ls: .06, color: Colors.white).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
              animate: !MediaQuery.disableAnimationsOf(context)),
      ]),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs();
  static const _slots = ['today', 'board', 'tasks', 'money', '+'];

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final bottom = MediaQuery.paddingOf(context).bottom;
    final idx = _slots.indexOf(app.tab);
    final today = todayStr();
    // Open tasks due today or overdue, shown as a count on TASKS.
    final due = app.s.tasks.where((t) => !t.done && t.due.isNotEmpty && t.due.compareTo(today) <= 0).length;

    Widget tab(String id, String icon, String label, {int badge = 0}) {
      final on = app.tab == id;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          label: badge > 0 ? '$label, $badge due' : label,
          excludeSemantics: true,
          child: Pressable(
            scale: .9,
            onTap: () => app.switchTab(id),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
              child: TweenAnimationBuilder<Color?>(
                tween: ColorTween(end: on ? kYellow : kTabIdle),
                duration: const Duration(milliseconds: 250),
                builder: (_, color, _) => Column(mainAxisSize: MainAxisSize.min, children: [
                  Stack(clipBehavior: Clip.none, children: [
                    AnimatedScale(
                      duration: Motion.bouncyDur,
                      curve: Motion.bouncy,
                      scale: on ? 1.08 : 1,
                      child: SvgIcon(icon, size: 26, color: color!),
                    ),
                    Positioned(
                      right: -11,
                      top: -5,
                      child: AnimatedScale(
                        duration: Motion.bouncyDur,
                        curve: Motion.bouncy,
                        scale: badge > 0 ? 1 : 0,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 18),
                          height: 18,
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: kYellow, borderRadius: BorderRadius.circular(9), border: Border.all(color: kBlack, width: 2)),
                          child: Text(badge > 99 ? '99+' : '$badge', style: cond(11, FontWeight.w800, color: Colors.black, height: 1)),
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 5),
                  Text(label, style: cond(14, FontWeight.w800, ls: .08, color: color)),
                ]),
              ),
            ),
          ),
        ),
      );
    }

    final plus = Expanded(
      child: Semantics(
        button: true,
        label: 'Add a task, event or spend',
        excludeSemantics: true,
        child: Pressable(
          scale: .88,
          onTap: () => openQuickAdd(context),
          child: Center(
            heightFactor: 1,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: kYellow,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: kYellow.withValues(alpha: .28), blurRadius: 18, offset: const Offset(0, 4))],
              ),
              child: const Center(child: SvgIcon('plus', size: 28, color: Colors.black)),
            ),
          ),
        ),
      ),
    );

    return Container(
      decoration: const BoxDecoration(color: kBlack, border: Border(top: BorderSide(color: Color(0xFF1C1C20)))),
      padding: EdgeInsets.fromLTRB(0, 8, 0, 8 + bottom),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Stack(clipBehavior: Clip.none, children: [
            Row(children: [
              tab('today', 'today', 'TODAY'),
              tab('board', 'grid', 'BOARD'),
              tab('tasks', 'tasks', 'TASKS', badge: due),
              tab('money', 'money', 'MONEY'),
              plus,
            ]),
            // The yellow bar glides to the active tab on a spring.
            if (idx >= 0)
              Positioned(
                left: 0,
                right: 0,
                top: -1,
                child: AnimatedAlign(
                  duration: Motion.snappyDur,
                  curve: Motion.snappy,
                  alignment: Alignment(-1 + 2 * idx / (_slots.length - 1), 0),
                  child: FractionallySizedBox(
                    widthFactor: 1 / _slots.length,
                    child: Center(
                      child: Container(width: 28, height: 3, decoration: BoxDecoration(color: kYellow, borderRadius: BorderRadius.circular(2))),
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
        // Springs up with a little overshoot; drops away on an ease-in.
        child: AnimatedSlide(
          duration: on ? Motion.bouncyDur : const Duration(milliseconds: 260),
          curve: on ? Motion.bouncy : Curves.easeInCubic,
          offset: on ? Offset.zero : const Offset(0, .6),
          child: AnimatedOpacity(
            duration: Duration(milliseconds: on ? 200 : 240),
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
