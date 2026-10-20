# Subway Board — Flutter Port Spec & Parity Checklist

Source of truth: `index.html` (single file: ~170 lines CSS, ~1,050 lines JS), `sw.js`, `manifest.webmanifest`, `icon.svg`, `icon-maskable.svg`.
Target: Android first (Flutter 3.47.7, device A142 / Android 16). iOS later (needs a Mac or cloud CI).

---

## 1. What the app is

A calendar that looks like a subway departure board. Events are "departures", categories are "lines" (lettered A–H, colored circles). The Board shows the selected day's events with live countdowns; the current event glows yellow with a progress bar. Events can be local, imported from `.ics`, pulled from Google iCal links (read-only), or two-way synced with Google Calendar.

---

## 2. Data model (port 1:1 so backups stay compatible)

Stored as one JSON blob, key `subway3` (with a legacy `subway2` migration path, `fromV2`).

```
State {
  v: 3
  lines: Line[]                 // 1..8, ids from "ABCDEFGH"
  events: Event[]
  hidden: { [eventKey]: 1 }     // synced events the user hid/deleted
  pendingDeletes: { cal, gid }[]// Google deletes not yet sent
  seriesProps: { [googleId]: { cat, catManual, remind } }
  settings: Settings
}
Line     { id: 'A'..'H', name (≤24 chars), color '#rrggbb', kw: 'comma, separated, keywords' }
Event    { id, title, loc, notes (≤2000), start ms, end ms, allDay, cat (line id),
           source: 'local'|'legacy'|'file'|'ical'|'gapi', key?, feed?, gid?, calId?, link?,
           repeat?: { freq: daily|weekdays|weekly|monthly|yearly, until: 'YYYY-MM-DD' },
           exdates?: minuteKeys[], remind?: ''|-1|0|5|10|15|30|60,
           catManual?, dirty?, dirtyNotes?, sample? }
Settings { mode: 'none'|'ical'|'api', feeds: {id,url}[], proxy, clientId,
           calendars: {id,name,primary,writable,enabled}[], defaultCalId,
           sound, notify, remindDefault, lastSync, lastSyncMsg, lastSyncError }
```

Defaults: 6 lines (Work, Focus, Deadlines, Personal, Health, Social) with preset colors/keywords; 8-color palette; `remindDefault` 10; sound on; notify off.

`normalize()` must be ported exactly: it repairs bad data (missing ids, invalid colors, end < start, all-day snapping to midnight, unknown line → first line).

**Migration path for your existing data:** web app → Settings → *Back up* → copy the JSON to the phone → Flutter app → *Restore backup*. Same format, so it works both ways.

---

## 3. Screens & behavior (parity checklist)

### 3.1 Shell
- [ ] Black background, max content width 560, safe-area padding top/bottom
- [ ] Top bar (condensed font, 2px white underline): left label, right clock
  - Left text priority: `TAP TO RECONNECT GOOGLE` (api mode, not connected) → `SUBWAY BOARD · SYNC ⚠` (sync error) → `SAMPLE DAY` → `LINE X · NAME` (filter active) → `SUBWAY BOARD`
  - Tap left: reconnect Google, or open Settings if there's a sync error
  - Right: current time; shows `✕` (clear sample events, with confirm) when sample events exist
- [ ] Bottom tabs: BOARD / LINES / ADD with icons; active = yellow + yellow bar above
- [ ] Toast (bottom, white pill): 2.6 s normally; 5 s with an **UNDO** button after any change
- [ ] Undo restores events, lines, hidden, pendingDeletes (not settings)
- [ ] Confirm dialog ("ask") = bottom sheet with title, text, action buttons + Cancel

### 3.2 Board tab
- [ ] Header: `Weekday,` ⌄ / `Mon D`, 50px condensed uppercase; tap → date picker
- [ ] `TODAY` yellow pill when not viewing today; gear button → Settings
- [ ] Line filter chips (A–H circles). Tap = filter to that line (others dim to 30%, selected scales + white ring); tap again = clear
- [ ] `◆ N ALL-DAY` toggle (disabled when none); switches list between timed departures and all-day events; column label `DEPARTURES` / `ALL-DAY`
- [ ] Rows: line badge · title (ellipsis) · location (ellipsis) · `↻` if repeating + time + green **JOIN** link if a Zoom/Meet/Teams/Webex/Whereby/Jitsi URL is found in link/loc/notes
- [ ] Right side number + unit:
  - Today, upcoming: minutes `MIN`, or `H:MM` `HR` when ≥ 60
  - Today, live: minutes remaining, `MIN LEFT`
  - Other day: `HH:MM` `SCHED`; multi-day started earlier: end time `UNTIL`
  - All-day: `ALL DAY`, or `2/3 DAYS` for multi-day
- [ ] Today hides events that already ended
- [ ] **Live** row (first event in progress): yellow background breathing between `#f7c400`↔`#ffdc3d` (3 s), black outline badge, pulsing `LIVE` tag, progress bar at bottom
- [ ] Other in-progress rows: yellow `LIVE` tag + yellow progress bar
- [ ] **Next** row (first upcoming after live, or first row if none live): highlighted, yellow number
- [ ] Animations: rows flip in (rotateX −80° → 0, staggered 50 ms, max 10) on navigation; digits that change flip individually on the 10 s refresh; respect reduced-motion
- [ ] Swipe left/right on the board = next/previous day
- [ ] Tap row → edit form
- [ ] Empty states: `NO MORE DEPARTURES TODAY` / `NO SCHEDULED DEPARTURES` / `NO ALL-DAY EVENTS`
- [ ] Refresh every 10 s; roll over to the new day at midnight if viewing "today"

### 3.3 Lines tab
- [ ] Title `Lines` + selected date (`TUE, OCT 20`), gear button
- [ ] Row per line: badge, name, `N today` / `N that day`, `•••` edit button
- [ ] Tap row → Board filtered to that line
- [ ] `ADD LINE` outline button (hidden at 8 lines)
- [ ] Line sheet: name (max 24), 8 color swatches, keywords; Save; Delete (hidden if only one line) with confirm → its events move to the first remaining line

### 3.4 Add / Edit tab
- [ ] Title `Add Event` / `Edit Event` / `Synced Event`; top-right button = reset (add) or ✕ (edit)
- [ ] Fields: name (Enter = save), All-day switch, date + time (time hidden for all-day), Duration (15m…4h) / Lasts (1–7 days), Line picker (badge + name), Save-to calendar (api mode only; locked for existing Google events)
- [ ] New-event defaults: today → next 15-min slot; other day → 09:00; 30 min; line = active filter or first
- [ ] **Auto-line:** typing the name picks a line by keyword match (longest whole-word match wins) until the user picks a line manually
- [ ] Collapsible "Location & notes" (auto-open if filled) and "Repeat & reminder" (repeat: never/daily/weekdays/weekly/monthly/yearly + Until date; reminder: default/none/at departure/5/10/15/30/60 min)
- [ ] Repeat hidden for Google events
- [ ] Read-only iCal events: only line and reminder editable; note explains why; delete becomes "Hide from board"
- [ ] Info notes: repeating ("changes apply to every occurrence"), Google-synced ("changes are sent back")
- [ ] Editing one occurrence of a repeat shifts the whole series by the day/time delta (and shifts exdates)
- [ ] Delete: repeating → "Only this one / Every occurrence"; Google → "Delete everywhere / Hide on this board"; others delete directly; all undoable
- [ ] After save: jump to Board on the event's date

### 3.5 Settings (full-screen page)
- [ ] **Calendar sync** mode: Off / Google iCal links (read-only) / Google Calendar (two-way)
  - iCal: feed URLs (one per line, `webcal:` accepted); ~~CORS proxy~~ (see decision D2)
  - API: connect / reconnect / disconnect, list of calendars with "show" checkboxes
  - Status line: `● Connected`, `✓ Synced 12:09 · 3 new, 1 updated, 0 removed`, or `⚠ error`
  - `SAVE & SYNC`; switching mode offers to remove events from the previous source
- [ ] **Alerts:** Chime switch (plays a sample when turned on), Notifications switch (asks permission), Default reminder
- [ ] **Data:** Import .ics · Export .ics · Back up (JSON) · Restore backup (confirm) · Restore N hidden events (only if any)

---

## 4. Logic to port (the hard part — pure Dart, fully unit-tested)

| Piece | JS source | Notes |
|---|---|---|
| Date helpers | `dstr`, `dms`, `sod`, `addDays`, `hm`, `mkey` | Local-time math; `mkey` = minute key used for exdates/overrides |
| `normalize`, `fromV2` | lines 334–372 | Must accept every backup the web app produced |
| `matchLine` | 383–391 | Whole-word keyword match, longest wins |
| `meetLink` | 392–393 | Regex over link/loc/notes |
| RRULE expansion `expand` | 513–579 | DAILY/WEEKLY/MONTHLY/YEARLY, INTERVAL, COUNT, UNTIL, BYDAY (incl. `2TU`, `-1FR`), BYMONTHDAY (incl. negative), BYMONTH |
| Time zones `toReal`/`tzOff` | 481–496 | Needs the `timezone` package (IANA DB) instead of `Intl` |
| `.ics` parser `parseIcs` | 581–622 | Line unfolding, params with quotes, VALARM stripping, CANCELLED, DTEND vs DURATION, EXDATE, RECURRENCE-ID overrides, sync window (−30 d … +365 d) |
| `occurrences(from,to)` | 631–646 | Expands local repeats, applies exdates |
| `merge` | 649–674 | Dedupe by key, adopt matching local events, respect `hidden`/`dirty`, reconcile removals |
| Google mapping `fromGoogle`/`toGoogle`/`flushPending` | 730–793 | Push dirty edits (PATCH/POST), pending deletes, then pull per calendar |
| Sync engine `runSync` | 797–833 | Runs on start, every 10 min, on resume (>2 min since last), on reconnect; 6 s debounce after edits |
| Reminders `checkAlerts` | 462–478 | "Now boarding" at T−reminder, "Now departing" at start |
| `.ics` export | 1230–1250 | RFC 5545 escaping + 75-octet folding, RRULE/EXDATE, CATEGORIES = line name |

**Parity test strategy:** run the original JS functions in Node over a set of sample `.ics` files and states to produce expected outputs, then assert the Dart port produces identical results. This catches time zone and recurrence bugs that are easy to miss.

---

## 5. Web → native mapping

| Web | Flutter |
|---|---|
| `localStorage` JSON | JSON file in app documents dir (`path_provider`) — atomic write |
| Google Fonts link | Bundle Barlow Condensed (600/700/800) + Inter (500–900) as assets (works offline) |
| CSS animations | `AnimationController` / implicit animations; `Transform` with perspective for flaps |
| `<input type=date/time>` / `<select>` | `showDatePicker`, `showTimePicker`, custom bottom-sheet pickers styled dark |
| Swipe via pointer events | `GestureDetector` horizontal drag (same 60 px / 1.5× rule) |
| Web Audio chime (two oscillator tones) | Two tiny bundled WAVs generated from the same frequencies (880 Hz ×2; 659→523 Hz) via `audioplayers` |
| Notifications while page open | **`flutter_local_notifications` scheduled ahead of time** — fire even when the app is closed (upgrade) |
| `fetch` + CORS proxy for iCal | `http` directly — native apps have no CORS, so no proxy needed |
| Google Identity Services token popup | `google_sign_in` + Calendar API (`googleapis` / `http`) — see D1 |
| `sessionStorage` token | Handled by `google_sign_in` (silent refresh) |
| File input / Blob download | `file_picker` for import/restore; `share_plus` or save dialog for export/backup |
| JOIN link | `url_launcher` |
| Service worker / manifest | Not needed (native app is offline by nature) |
| `icon.svg` / maskable | `flutter_launcher_icons` (adaptive icon from the maskable version) |
| Locale time format | Respect the phone's 24-hour setting (your screenshot shows `17:00`) |

**State management:** one `AppState` `ChangeNotifier` mirroring the web's global `S` + `provider`. The app is small and the web code is already structured around one state object, so this keeps the port close to the original.

---

## 6. Decisions (answered 2026-10-20)

| # | Question | Decision | What was built |
|---|---|---|---|
| D1 | Google two-way sync in v1? | One-time Google import first; two-way sync after v1 | Settings → Data → *Import from Google Calendar*: paste the calendar's secret iCal address, events are copied once (address not stored). iCal-link sync mode (read-only, every 10 min) is also kept. |
| D2 | Drop the CORS proxy? | Drop it | Links are fetched directly. |
| D3 | Background reminders? | Yes | Exact alarms for the next 7 days (max 60), rescheduled on every change, on resume and after reboot. Chime sounds are the notification sounds. |
| D4 | Which look? | Dark = current web CSS; light = beige "next" row | Settings → Display → *Appearance*: Match phone / Dark / Light. Light keeps the black header and tabs, with a cream board, beige next row and cream panels. |
| D5 | Sample day | Keep handling, no generator | `SAMPLE DAY` label and ✕ to clear, for restored backups that contain samples. |
| D6 | Package name | `com.arunvijey.subwayboard` | Set as the Android application id / iOS bundle prefix. |

## 7. Status

Built in `subway_board/` and tested on the A142 (Android 16), debug and release builds:
board rows, countdowns, live/next states, glow and flip animations, swipe between days, date picker, line filters,
add/edit/delete with undo, auto-line from keywords, Lines tab and line editor, Settings, light/dark themes,
and a reminder notification firing at its exact time with the app in the background.

The logic layer is checked against the web app itself: `tool/parity/gen_fixtures.js` runs the original JavaScript
from `index.html` and `test/parity_test.dart` requires identical output (iCal parsing incl. time zones, DST,
RRULE/EXDATE/RECURRENCE-ID, local repeats, line matching, merge). A real Google Calendar feed also matched.

Added 2026-10-20 (round 2):
- Line badges are editable (1–2 characters; the internal A–H id stays so events keep their line).
- New icon in the hand-drawn pastel style of the user's icon pack: a calendar page with a subway map. Adaptive icon has a transparent backdrop and a monochrome layer for themed icons.
- Light vibration on every tap (Settings → Display → Vibration).
- Google Calendar two-way sync, ported from the web app (sign-in via `google_sign_in`, calendar list, pull, push of edits/new events/deletes, "Save to" calendar, "Delete everywhere / Hide on this board"). `fromGoogle`/`toGoogle` are parity-tested against the web app. **Needs the one-time Google Cloud setup in `subway_board/GOOGLE_SETUP.md` before it can sign in.**

Not yet done / not testable here:
- Signing in to Google for real (needs the Android OAuth client from GOOGLE_SETUP.md).
- The Google import with your own secret address (the flow was tested with a public Google feed only).
- iOS build (needs a Mac or cloud CI).
- Play Store release signing (the release build is currently signed with the debug key).

Differences from the web app:
- An event already in Google can't be moved to a different Google calendar (same as the web app).
- Chime plays in-app only when notifications are off; with notifications on, the notification itself plays it.
