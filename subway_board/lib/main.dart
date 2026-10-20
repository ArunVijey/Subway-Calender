import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

import 'app/store.dart';
import 'services/alerts.dart';
import 'services/google_auth.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: kBlack,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  final alerts = Alerts();
  await alerts.init();
  final app = AppState(alerts, GoogleAuth());
  await app.load();
  runApp(ChangeNotifierProvider.value(value: app, child: const SubwayApp()));
}

class SubwayApp extends StatelessWidget {
  const SubwayApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.select<AppState, String>((a) => a.s.settings.theme);
    return MaterialApp(
      title: 'Subway Board',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBlack,
        fontFamily: 'Inter',
        colorScheme: const ColorScheme.dark(primary: kYellow, onPrimary: Colors.black, surface: Color(0xFF141416)),
        textSelectionTheme: TextSelectionThemeData(cursorColor: kYellow, selectionColor: kYellow.withValues(alpha: .35), selectionHandleColor: kYellow),
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.white10,
      ),
      builder: (context, child) {
        final light = theme == 'light' || (theme == 'system' && MediaQuery.platformBrightnessOf(context) == Brightness.light);
        return PalScope(pal: light ? Pal.lightPal : Pal.dark, child: child!);
      },
      home: const Shell(),
    );
  }
}
