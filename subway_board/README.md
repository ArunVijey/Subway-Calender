# Subway Board (Flutter)

Native Android version of the Subway Board web app (`../index.html`); the overview and install steps are in `../README.md`. See `../FLUTTER_PORT_SPEC.md` for the feature checklist, decisions and status.

Flutter lives in `C:\src\flutter\bin` (add it to PATH if a shell doesn't find `flutter`).

## Run on the phone

```powershell
flutter run -d 000693428000055      # debug, with hot reload
flutter run --release -d 000693428000055
```

## Build an APK to install

```powershell
flutter build apk --release --target-platform android-arm64 --obfuscate --split-debug-info=build/symbols   # the phone's APK (arm64 only)
```

The release build is signed with the key in `android/key.properties` (never committed); without that file it falls back to the debug key. A Play Store upload would use `flutter build appbundle`.

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
| `lib/services/platform.dart`, `android/.../AppChannels.kt` | App folders and the in-app chime (in place of path_provider and audioplayers) |
| `lib/ui/icons.dart` | The line icons, drawn from SVG path data (no SVG library) |
| `lib/services/google_auth.dart`, `lib/core/google.dart` | Google sign-in, Calendar API calls, event mapping (setup: `GOOGLE_SETUP.md`) |
| `lib/ui/` | Screens: `board.dart`, `lines.dart`, `form.dart`, `settings.dart`, frame in `shell.dart` |
| `assets/` | Fonts (Barlow Condensed, Inter; OFL, subset: see below), icon sources |
| `android/app/src/main/res/raw/` | Chimes (OGG) for the notifications and the in-app chime; WAV masters in `tool/sounds/` |

Icons: the SVGs in `assets/icon/` are the sources; render them to the PNGs next to them (1024×1024), then `dart run flutter_launcher_icons`.

## 2.0: Tasks and Money

The board now carries three things: **events** (departures), **tasks** and **spending**.

| Tab | What |
|---|---|
| BOARD | Departures for the day (or week), with today's and overdue tasks under **TO DO** |
| TASKS | Overdue / Today / Tomorrow / Upcoming / Someday, ★ filter, completed fold. Swipe right = done, left = tomorrow |
| **+** | Quick add. One line of text becomes a task, event or spend: `Pay rent ₹15000 1st monthly`, `Gym tomorrow 6pm for 1h`, `Lunch 180` |
| MONEY | What's left this month, a per-day allowance (after bills still due), bills, categories with limits, the spending log |
| LINES | Unchanged |

A task with an amount is a **bill**: ticking it off logs the payment in Money; a repeating bill rolls on to its next date.
Quick add's **ALSO** row makes more than one thing from a line: `Laptop service 3pm 3700` in Task mode is a task, a 15:00
slot on the board and a ₹3,700 bill logged when it's ticked off. The task and event stay linked (`Event.task`): edits move
both, the tick shows on the board row, deleting asks whether to delete both. Tests: `test/linked_add_test.dart`.
Settings → Money → *Import from Budget app* reads the Budget app's `budget-backup.json` (transactions, categories,
latest limits, recurring payments) and skips anything already imported.

Code: `lib/core/tasks.dart`, `money.dart`, `quick.dart` (parser), `budget_import.dart`; screens in `lib/ui/tasks.dart`,
`money.dart`, `quick_add.dart`. Tests: `test/plan_test.dart`; `test/real_budget_test.dart` runs against a real backup when
`BUDGET_FILE` is set. Saved data gains `tasks` and `money`; older data and web backups still load, and the first launch after
upgrading keeps the old file as `subway3.pre-v2.json`.

Google two-way sync is parked: it's hidden in Settings unless the phone already uses it.

### Preview build (installs next to the real app)

```powershell
flutter build apk --release --target-platform android-arm64 --android-project-arg=preview=true --dart-define=DEMO=true
```

App id `com.arunvijey.subwayboard.preview`, named "Board β", with a sample day (✕ in the top bar clears it).

### Home-screen widget (v2.2.0)

DAY / WEEK, and each day shows its departures, its TO DO tasks and the money logged. Ticks work on the widget itself
(a bill logs its spend), and **+** opens the quick-add sheet over the home screen. Tapping a row opens the app on it.

- Rows: `android/.../widget/WidgetRows.kt`. Android 12+ gets the whole list in one atomic update (RemoteCollectionItems),
  which fixes the stale-header bug from Android 17's async remote adapter conversion. Older Android uses `BoardWidgetService`.
- Ticks and adds wait in a queue (`WidgetActions.kt`) until a copy of the app applies them: the open app, or a headless
  engine running Dart `widgetWorker` when it's closed. Applying is idempotent, and actions are acked only after the save.
- **+** is `QuickAddActivity` (Dart `quickAddMain`). It only reads the data, and what it adds goes into the same queue.
- Tests: `test/widget_actions_test.dart`.

### TODAY tab (v2.3.0)

The widget's view inside the app. Up top is the Money hero (net worth, spent this month) and the net-worth graph. Then
**DAY**: the day's departures (with ticks for linked tasks), its to-dos (and the ones done that day), and the money logged.
**WEEK** shows the same for seven days under day headings. It shares the selected day with BOARD; swipe or use ‹ › to
move, and tap the title for a date. Code: `lib/ui/today.dart`, test: `test/today_test.dart`.

**v2.3.3:** TODAY is the start tab, and Back from any other tab returns to it.

**v2.3.1:** MONEY tab has an eye by NET WORTH that turns it into dots. TODAY has its own arrow there that folds the net-worth
numbers and graph away, separate from the Money tab. TODAY and the widget fold today's ended departures behind "N ENDED ⌄"
by DEPARTURES, like the board.

## Size and battery notes (2.3.2)

- Fonts in `assets/fonts/` are subsets of the full files in `tool/fonts-full/` (Latin, Greek, punctuation, currency, arrows,
  symbols; default shaping features + `tnum`; Inter keeps its `wght`/`opsz` axes). To redo them:
  `pyftsubset tool/fonts-full/Inter.ttf --unicodes=<ranges> --layout-features+=tnum --glyph-names --notdef-outline --output-file=assets/fonts/Inter.ttf`
  (the ranges are in the 2.3.2 notes in `../dist`). A character outside them falls back to the system font.
- Release builds are obfuscated; keep `build/symbols` (copied to `../dist/symbols-v<version>`) to read crash stack traces:
  `flutter symbolize -i <trace> -d ../dist/symbols-v2.3.2+9/app.android-arm64.symbols`.
- The clock redraws on the minute, and only while the app is in front; saves are batched (350 ms) and flushed when the app goes
  to the background; reminders and the widget are only re-sent when what they show has changed.
- `test/expand_ff_test.dart` checks the fast-forwarded repeat expansion against the original (`test/_old_ics.dart`).
