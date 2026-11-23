// First launch: what the app is, a live preview of the board, and the choice
// between Google two-way sync and staying on this phone.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/store.dart';
import '../core/model.dart';
import '../core/util.dart';
import 'board.dart';
import 'motion.dart';
import 'shell.dart';
import 'theme.dart';

/// Build with --dart-define=FORCE_WELCOME=true to preview the welcome on a device that has data.
const _forceWelcome = bool.fromEnvironment('FORCE_WELCOME');

/// Shows the welcome until it's answered, then the app.
class AppRoot extends StatefulWidget {
  const AppRoot({super.key});
  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  bool _forced = _forceWelcome;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    // A forced preview ends at the first answer, like a real first launch.
    if (_forced && app.s.settings.welcomed && app.welcomeAnswered) _forced = false;
    final welcomed = app.s.settings.welcomed && !_forced;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 520),
      switchInCurve: Motion.smooth,
      switchOutCurve: Curves.easeOut,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(scale: anim.drive(Tween(begin: .97, end: 1)), child: child),
      ),
      child: welcomed ? const Shell(key: ValueKey('app')) : const WelcomePage(key: ValueKey('welcome')),
    );
  }
}

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});
  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> with SingleTickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(vsync: this, duration: Entrance.total);

  /// Preview times are set once, so the countdowns tick down like the real board.
  final int _t0 = nowMs();

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted) _intro.forward();
    });
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  /// Three departures around now: one live, one next, one later.
  List<Event> _preview(AppData s) {
    String cat(int i) => s.lines[i % s.lines.length].id;
    int at(int min) => _t0 + min * kMin;
    return [
      Event(id: 'w1', title: 'Team standup', loc: 'Room 4B', cat: cat(0), start: at(-12), end: at(18)),
      Event(id: 'w2', title: 'Gym', loc: 'Powerpac Gym', cat: cat(4), start: at(47), end: at(107)),
      Event(id: 'w3', title: 'Dinner with Sam', cat: cat(5), start: at(312), end: at(402)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final pal = Pal.of(context);
    final mq = MediaQuery.of(context);
    app.use24h = mq.alwaysUse24HourFormat; // the shell isn't built yet to set it
    final evs = _preview(app.s);
    final day0 = sod(nowMs());

    Widget enter(int i, Widget child) => Entrance(intro: _intro, index: i, child: child);

    return Scaffold(
      backgroundColor: kBlack,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: EdgeInsets.fromLTRB(18, 10 + mq.padding.top, 18, 16 + mq.padding.bottom),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                padding: const EdgeInsets.fromLTRB(0, 6, 0, 10),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white, width: 2))),
                child: Row(children: [
                  Expanded(child: Text('SUBWAY BOARD', style: cond(15, FontWeight.w800, ls: .08, color: Colors.white))),
                  Text(fmtT(nowMs(), use24h: app.use24h).toUpperCase(), style: cond(12, FontWeight.w800, ls: .06, color: Colors.white)),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 24, 0, 10),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text('YOUR DAY,\nON THE BOARD.', style: cond(50, FontWeight.w800, ls: -.01, height: .95, color: Colors.white)),
                ),
              ),
              Text('Events become departures with live countdowns. Tasks and spending ride along: one board for your day.',
                  style: inter(15, FontWeight.w500, height: 1.45, color: kDim)),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('DEPARTURES', style: cond(15, FontWeight.w800, ls: .08, color: kDim)),
                  Text('TIME', style: cond(15, FontWeight.w800, ls: .08, color: kDim)),
                ]),
              ),
              // A live preview of the board, edge to edge like the real one.
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) => OverflowBox(
                    minWidth: box.maxWidth + 36,
                    maxWidth: box.maxWidth + 36,
                    alignment: Alignment.topCenter,
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(color: pal.board, border: Border(top: BorderSide(color: pal.rule, width: 2))),
                        child: ClipRect(
                          child: SingleChildScrollView(
                            physics: const NeverScrollableScrollPhysics(),
                            child: Column(children: [
                              for (var i = 0; i < evs.length; i++)
                                enter(
                                  i,
                                  BoardRow(
                                    key: ValueKey(evs[i].id),
                                    ev: evs[i],
                                    day0: day0,
                                    isToday: true,
                                    primaryLive: i == 0,
                                    next: i == 1,
                                    onTap: () {},
                                  ),
                                ),
                            ]),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              enter(
                4,
                Pressable(
                  scale: .97,
                  onTap: app.finishWelcome,
                  child: Container(
                    height: 54,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: kYellow, borderRadius: BorderRadius.circular(27)),
                    child: Text('GET STARTED', style: cond(17, FontWeight.w800, ls: .08, color: Colors.black)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Everything stays on this phone. Back it up any time in Settings.',
                textAlign: TextAlign.center,
                style: inter(12, FontWeight.w500, height: 1.45, color: const Color(0xFF71717A)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
