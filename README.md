# Subway Board

A calendar that looks like a subway departure board. Your events are **departures**, your categories are colour-coded
**lines** (A–H), and the one happening now glows with a live countdown. Version 2 adds **tasks** and **money** to the
same board, so one app covers your day: where you're going, what you need to do and what you've spent.
Android only, works offline, no account, no ads, no tracking. Your data stays on your phone.

## Features

- **TODAY.** Your whole day on one screen: departures (with ticks for linked tasks), to-dos and the money you logged,
  under your net worth and this month's spending. Switch to **WEEK** to see the same for seven days.
- **BOARD.** The departure board itself: live countdowns, the current event glowing with a progress bar, ended departures
  folded away behind "N ENDED".
- **Type it like you say it.** One line in quick add (**+**) becomes a task, an event or a spend:
  `Gym tomorrow 6pm for 1h`, `Lunch 180`, `Pay rent ₹15000 1st monthly`.
  `Laptop service 3pm 3700` can be a task, a 15:00 slot on the board *and* a ₹3,700 bill, all linked.
- **TASKS.** Overdue / Today / Tomorrow / Upcoming / Someday, starred filter, swipe right for done, left for tomorrow.
  A task with an amount is a **bill**: ticking it off logs the payment, and a repeating bill rolls on to its next date.
- **MONEY.** What's left this month and what you can spend per day (after bills still due), category limits, net-worth
  graph, cash flow and pace charts, a searchable spending log. Hide your net worth behind dots with one tap.
- **Home-screen widget.** DAY / WEEK with departures, tasks and money. Tick tasks and add things right from the
  home screen; it works even when the app is closed.
- **Lines.** Up to 8 colour-coded lines with keywords, so new events land on the right line by themselves.
- **Reminders** with boarding / departing chimes.
- **Import** `.ics` files and Google Calendar iCal links (read-only), CSV spending, or a Budget app backup.
  Export and back up everything to a file.

## Install (for friends)

1. Open the **[Releases](../../releases)** page on your Android phone and download the latest `SubwayBoard-x.y.z.apk`.
2. Open the downloaded file. If Android asks, allow your browser / Files app to **install unknown apps**.
3. Tap **Install**. Needs Android 7.0 or newer on a 64-bit phone (almost every phone from the last several years).

Play Protect may show a warning because the app isn't from the Play Store. Choose **Install anyway**.
To update later, install the newer APK from Releases over the old one; your data is kept.

## Build from source

Requirements: Flutter 3.47 (stable) and the Android SDK. The app lives in [`subway_board/`](subway_board).

```sh
cd subway_board
flutter test
flutter build apk --release --target-platform android-arm64 --obfuscate --split-debug-info=build/symbols
```

Release builds are signed with the key in `subway_board/android/key.properties` if that file exists
(keys are never committed); otherwise they fall back to the debug key. More detail, including the code layout and the
home-screen widget, is in [`subway_board/README.md`](subway_board/README.md).

## The web app

The original Subway Board is a single-file web app ([`index.html`](index.html), installable as a PWA with
`manifest.webmanifest` and `sw.js`). The Flutter app is a port of it ([`FLUTTER_PORT_SPEC.md`](FLUTTER_PORT_SPEC.md)),
and its backups still load in the app.

## Credits

Fonts: Barlow Condensed and Inter, both under the SIL Open Font License.
