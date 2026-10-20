# Subway Board (Flutter)

Native Android/iOS version of the Subway Board web app (`../index.html`). See `../FLUTTER_PORT_SPEC.md` for the feature checklist, decisions and status.

Flutter lives in `C:\src\flutter\bin` (add it to PATH if a shell doesn't find `flutter`).

## Run on the phone

```powershell
flutter run -d 000693428000055      # debug, with hot reload
flutter run --release -d 000693428000055
```

## Build an APK to install

```powershell
flutter build apk --release --split-per-abi   # one APK per CPU type; the A142 needs app-arm64-v8a-release.apk
```

The release build is signed with the debug key for now. A Play Store upload needs a real signing key (`android/key.properties`) and `flutter build appbundle`.

## Tests

```powershell
flutter test
```

`test/parity_test.dart` replays `test/fixtures/parity.json`, which is produced by running the web app's own JavaScript. After changing the logic in `index.html` (or to add a real calendar as a test case), regenerate it with Node:

```powershell
node tool/parity/gen_fixtures.js [extra.ics ...]
```

## Layout

| Path | What |
|---|---|
| `lib/core/` | Pure logic ported from the web app: data model and repair (`model.dart`), iCal parse/export, RRULE and time zones (`ics.dart`), occurrences, line matching, merge (`logic.dart`) |
| `lib/app/store.dart` | App state, saving, undo, iCal sync, import/export, reminder scheduling |
| `lib/services/alerts.dart` | Scheduled notifications and the chime |
| `lib/services/google_auth.dart`, `lib/core/google.dart` | Google sign-in, Calendar API calls, event mapping (setup: `GOOGLE_SETUP.md`) |
| `lib/ui/` | Screens: `board.dart`, `lines.dart`, `form.dart`, `settings.dart`, frame in `shell.dart` |
| `assets/` | Fonts (Barlow Condensed, Inter; OFL), chime WAVs, icon sources |
| `android/app/src/main/res/raw/` | Chimes used as notification sounds |

Icons: the SVGs in `assets/icon/` are the sources; render them to the PNGs next to them (1024×1024), then `dart run flutter_launcher_icons`.
