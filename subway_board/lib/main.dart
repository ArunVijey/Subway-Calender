import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'app/store.dart';
import 'core/quick.dart';
import 'services/alerts.dart';
import 'services/google_auth.dart';
import 'services/widget_bridge.dart';
import 'ui/quick_add.dart';
import 'ui/theme.dart';
import 'ui/welcome.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Orientation, notifications and the saved data load side by side.
  final orient = SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: kBlack,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  final alerts = Alerts();
  final ready = alerts.init();
  final app = AppState(alerts, GoogleAuth());
  await app.load();
  await ready;
  await orient;
  runApp(ChangeNotifierProvider.value(value: app, child: const SubwayApp()));
}

/// Started by the home-screen widget when the app isn't open: applies the
/// ticks and adds queued on the widget, saves, refreshes the widget, and waits
/// for more until the widget lets it go.
@pragma('vm:entry-point')
Future<void> widgetWorker() async {
  WidgetsFlutterBinding.ensureInitialized();
  final app = AppState(Alerts(), GoogleAuth());
  await app.load(headless: true);
  Future<void> run() async {
    await app.drainWidget();
    await WidgetBridge.idle();
  }

  WidgetBridge.listen(onKick: run);
  await run();
}

/// The widget's + : just the quick-add sheet, over the home screen. It reads
/// the data but never writes it: what's added goes to the widget's queue.
@pragma('vm:entry-point')
Future<void> quickAddMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  final app = AppState(Alerts(), GoogleAuth());
  await app.load(readOnly: true);
  app.relay = WidgetBridge.enqueue;
  final mode = switch (await WidgetBridge.quickMode()) {
    'task' => QMode.task,
    'spend' => QMode.spend,
    _ => QMode.event,
  };
  runApp(ChangeNotifierProvider.value(value: app, child: QuickAddApp(mode)));
}

class QuickAddApp extends StatelessWidget {
  final QMode mode;
  const QuickAddApp(this.mode, {super.key});
  @override
  Widget build(BuildContext context) {
    final theme = context.select<AppState, String>((a) => a.s.settings.theme);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: appTheme(),
      color: Colors.transparent,
      builder: (context, child) => PalScope(pal: palFor(theme, context), child: child!),
      home: _QuickHost(mode),
    );
  }
}

class _QuickHost extends StatefulWidget {
  final QMode mode;
  const _QuickHost(this.mode);
  @override
  State<_QuickHost> createState() => _QuickHostState();
}

class _QuickHostState extends State<_QuickHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final app = context.read<AppState>();
      await openQuickAdd(context, mode: widget.mode);
      await app.relayed;
      SystemNavigator.pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    // The shell normally sets this; here there's no shell.
    context.read<AppState>().use24h = MediaQuery.alwaysUse24HourFormatOf(context);
    return const Scaffold(backgroundColor: Colors.transparent);
  }
}

ThemeData appTheme() => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBlack,
        fontFamily: 'Inter',
        colorScheme: const ColorScheme.dark(primary: kYellow, onPrimary: Colors.black, surface: Color(0xFF141416)),
        textSelectionTheme: TextSelectionThemeData(cursorColor: kYellow, selectionColor: kYellow.withValues(alpha: .35), selectionHandleColor: kYellow),
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.white10,
      );

Pal palFor(String theme, BuildContext context) {
  final light = theme == 'light' || (theme == 'system' && MediaQuery.platformBrightnessOf(context) == Brightness.light);
  return light ? Pal.lightPal : Pal.dark;
}

class SubwayApp extends StatelessWidget {
  const SubwayApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.select<AppState, String>((a) => a.s.settings.theme);
    return MaterialApp(
      title: 'Subway Board',
      debugShowCheckedModeBanner: false,
      theme: appTheme(),
      builder: (context, child) => PalScope(pal: palFor(theme, context), child: child!),
      home: const AppRoot(),
    );
  }
}
