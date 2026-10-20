// Runs the web app's own logic (extracted from ../../../index.html) over a set
// of inputs and writes the results to test/fixtures/parity.json. The Dart
// tests replay the same inputs and must produce identical output.
//
//   node tool/parity/gen_fixtures.js [extra.ics ...]
//
// Extra .ics files (e.g. a real calendar export) are added as more parseIcs cases.
const fs = require('fs');
const path = require('path');
const { loadWebApp } = require('./web_app');

const NOW = new Date(2026, 9, 20, 12, 0, 0).getTime(); // Oct 20 2026, 12:00 local
const api = loadWebApp(NOW);

const ICS = {};
const wrap = body => `BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Test//EN\r\n${body}\r\nEND:VCALENDAR\r\n`;

ICS.basic = wrap(`BEGIN:VEVENT
UID:basic-1
DTSTART:20261020T150000Z
DTEND:20261020T160000Z
SUMMARY:Team standup\\, daily
LOCATION:Room 4\\; floor 2
DESCRIPTION:Line one\\nLine two https://meet.google.com/abc-defg-hij
END:VEVENT
BEGIN:VEVENT
UID:floating-1
DTSTART:20261021T093000
DURATION:PT45M
SUMMARY:Floating local time
END:VEVENT
BEGIN:VEVENT
UID:allday-1
DTSTART;VALUE=DATE:20261022
DTEND;VALUE=DATE:20261025
SUMMARY:Conference
END:VEVENT
BEGIN:VEVENT
UID:allday-2
DTSTART;VALUE=DATE:20261101
SUMMARY:One day no end
END:VEVENT
BEGIN:VEVENT
UID:cancel-1
DTSTART:20261020T150000Z
STATUS:CANCELLED
SUMMARY:Cancelled thing
END:VEVENT
BEGIN:VEVENT
DTSTART:20261023T100000Z
SUMMARY:No uid
BEGIN:VALARM
TRIGGER:-PT10M
ACTION:DISPLAY
DESCRIPTION:Reminder
END:VALARM
END:VEVENT
BEGIN:VEVENT
UID:old-1
DTSTART:20250101T100000Z
SUMMARY:Outside the window
END:VEVENT
BEGIN:VEVENT
UID:fold-1
DTSTART:20261024T080000Z
DTEND:20261024T083000Z
SUMMARY:A very long title that is folded across
  two lines in the file
ATTENDEE;CN="Doe: John";ROLE=REQ-PARTICIPANT:mailto:john@example.com
URL:https://zoom.us/j/123456
END:VEVENT`.replace(/\n/g, '\r\n'));

ICS.tz = wrap(`BEGIN:VEVENT
UID:ny-weekly
DTSTART;TZID=America/New_York:20260302T090000
DTEND;TZID=America/New_York:20260302T100000
RRULE:FREQ=WEEKLY;BYDAY=MO,WE;UNTIL=20261231T235959Z
EXDATE;TZID=America/New_York:20261021T090000
SUMMARY:NY weekly across DST
END:VEVENT
BEGIN:VEVENT
UID:ny-weekly
RECURRENCE-ID;TZID=America/New_York:20261026T090000
DTSTART;TZID=America/New_York:20261026T130000
DTEND;TZID=America/New_York:20261026T140000
SUMMARY:NY weekly (moved)
END:VEVENT
BEGIN:VEVENT
UID:berlin-1
DTSTART;TZID=Europe/Berlin:20261025T020000
DTEND;TZID=Europe/Berlin:20261025T040000
SUMMARY:Berlin over the DST change
END:VEVENT
BEGIN:VEVENT
UID:win-tz
DTSTART;TZID=Eastern Standard Time:20261027T110000
DTEND;TZID=Eastern Standard Time:20261027T120000
SUMMARY:Windows zone name
END:VEVENT
BEGIN:VEVENT
UID:tokyo-daily
DTSTART;TZID=Asia/Tokyo:20261018T070000
DURATION:PT30M
RRULE:FREQ=DAILY;INTERVAL=2;COUNT=6
SUMMARY:Tokyo every other day
END:VEVENT`.replace(/\n/g, '\r\n'));

ICS.rules = wrap(`BEGIN:VEVENT
UID:last-fri
DTSTART:20260130T170000Z
DTEND:20260130T180000Z
RRULE:FREQ=MONTHLY;BYDAY=-1FR
SUMMARY:Last Friday
END:VEVENT
BEGIN:VEVENT
UID:second-tue
DTSTART:20260113T120000Z
DTEND:20260113T123000Z
RRULE:FREQ=MONTHLY;BYDAY=2TU;COUNT=14
SUMMARY:Second Tuesday
END:VEVENT
BEGIN:VEVENT
UID:month-end
DTSTART;VALUE=DATE:20260131
DTEND;VALUE=DATE:20260201
RRULE:FREQ=MONTHLY;BYMONTHDAY=-1
SUMMARY:Month end
END:VEVENT
BEGIN:VEVENT
UID:the-31st
DTSTART:20260131T090000Z
DTEND:20260131T100000Z
RRULE:FREQ=MONTHLY
SUMMARY:Only months with 31 days
END:VEVENT
BEGIN:VEVENT
UID:leap
DTSTART;VALUE=DATE:20240229
RRULE:FREQ=YEARLY
SUMMARY:Leap day
END:VEVENT
BEGIN:VEVENT
UID:yearly-bymonth
DTSTART:20250310T080000Z
DTEND:20250310T090000Z
RRULE:FREQ=YEARLY;BYMONTH=3,11;BYDAY=1MO
SUMMARY:First Monday of March and November
END:VEVENT
BEGIN:VEVENT
UID:daily-until-date
DTSTART;VALUE=DATE:20261015
RRULE:FREQ=DAILY;UNTIL=20261025
EXDATE;VALUE=DATE:20261020,20261021
SUMMARY:Daily until a date
END:VEVENT
BEGIN:VEVENT
UID:weekday-daily
DTSTART:20261019T060000Z
DTEND:20261019T063000Z
RRULE:FREQ=DAILY;BYDAY=MO,TU,WE,TH,FR;COUNT=20
SUMMARY:Weekdays via DAILY
END:VEVENT
BEGIN:VEVENT
UID:biweekly
DTSTART:20261007T140000Z
DTEND:20261007T150000Z
RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=WE,FR
SUMMARY:Every other week
END:VEVENT`.replace(/\n/g, '\r\n'));

for (const f of process.argv.slice(2)) ICS[path.basename(f)] = fs.readFileSync(f, 'utf8');

const ics = Object.entries(ICS).map(([name, text]) => ({ name, text, items: api.parseIcs(text) }));

// Local repeating events → occurrences over several windows.
const d = (y, m, dd, h = 0, mi = 0) => new Date(y, m - 1, dd, h, mi).getTime();
const occState = {
  lines: [{ id: 'A', name: 'Work', color: '#1d6cf2', kw: '' }, { id: 'B', name: 'Focus', color: '#ff8a00', kw: '' }],
  events: [
    { id: 'daily', title: 'Daily', cat: 'A', start: d(2026, 10, 1, 9), end: d(2026, 10, 1, 9, 30), repeat: { freq: 'daily', until: '2026-10-25' }, exdates: [Math.round(d(2026, 10, 21, 9) / 6e4)] },
    { id: 'wkdays', title: 'Weekdays', cat: 'B', start: d(2026, 10, 2, 8), end: d(2026, 10, 2, 8, 15), repeat: { freq: 'weekdays', until: '' } },
    { id: 'weekly', title: 'Weekly', cat: 'A', start: d(2026, 9, 29, 18), end: d(2026, 9, 29, 19), repeat: { freq: 'weekly', until: '' } },
    { id: 'monthly31', title: 'Monthly 31', cat: 'A', start: d(2026, 8, 31, 12), end: d(2026, 8, 31, 13), repeat: { freq: 'monthly', until: '' } },
    { id: 'yearly', title: 'Birthday', cat: 'B', allDay: true, start: d(2020, 10, 22), end: d(2020, 10, 23), repeat: { freq: 'yearly', until: '' } },
    { id: 'alldayrep', title: 'Two-day weekly', cat: 'B', allDay: true, start: d(2026, 10, 3), end: d(2026, 10, 5), repeat: { freq: 'weekly', until: '2026-11-30' } },
    { id: 'plain', title: 'Plain', cat: 'A', start: d(2026, 10, 20, 14), end: d(2026, 10, 20, 15) },
    { id: 'overnight', title: 'Overnight', cat: 'A', start: d(2026, 10, 19, 22), end: d(2026, 10, 20, 2) },
    { id: 'zero', title: 'Zero length', cat: 'A', start: d(2026, 10, 21, 0), end: d(2026, 10, 21, 0) },
    { id: 'multiday', title: 'Multi-day', cat: 'B', allDay: true, start: d(2026, 10, 19), end: d(2026, 10, 23) },
  ],
};
const windows = [[d(2026, 10, 20), d(2026, 10, 21)], [d(2026, 10, 21), d(2026, 10, 22)], [d(2026, 10, 22), d(2026, 10, 23)], [d(2026, 10, 31), d(2026, 11, 1)], [d(2026, 10, 1), d(2026, 12, 31)]];
api.setS(api.normalize(occState));
const occ = windows.map(([from, to]) => ({ from, to, result: api.occurrences(from, to).map(e => ({ id: e.id, start: e.start, end: e.end })) }));

// Line matching with the default lines.
api.setS(api.normalize({}));
const titles = [['Weekly standup', ''], ['Gym session', 'Downtown'], ['Coffee with Sam', ''], ['Deep work: coding', ''], ['Submit report — deadline', ''], ['Running errands', ''], ['Run club', ''], ['1:1 with manager', ''], ['Lunch meeting', ''], ['Dentist', ''], ['Something else', 'home office'], ['Interviewing', '']];
const match = titles.map(([t, l]) => ({ title: t, loc: l, result: api.matchLine(t, l) }));

// Merge: import basic.ics into a store with one matching local event, then re-import with changes.
const base = api.normalize({ events: [{ id: 'mine', title: 'Team standup, daily', cat: 'A', source: 'local', start: Date.UTC(2026, 9, 20, 15, 0, 20), end: Date.UTC(2026, 9, 20, 15, 30) }], hidden: { 'file:fold-1': 1 } });
api.setS(base);
const items1 = api.parseIcs(ICS.basic).map(it => ({ ...it, key: 'file:' + it.key }));
const r1 = api.merge(items1, 'file', 'file', false);
const after1 = api.getS().events.map(e => ({ id: e.id.startsWith('u') ? '*' : e.id, key: e.key, title: e.title, cat: e.cat, start: e.start, end: e.end, source: e.source, feed: e.feed }));
const items2 = items1.filter(it => !it.key.includes('allday-2')).map(it => it.key === 'file:basic-1' ? { ...it, title: 'Renamed' } : it);
const r2 = api.merge(items2, 'file', 'file', true);
const after2 = api.getS().events.map(e => ({ id: e.id.startsWith('u') ? '*' : e.id, key: e.key, title: e.title, cat: e.cat, start: e.start, end: e.end, source: e.source, feed: e.feed }));

// Google Calendar API events → board items, and board events → API request bodies.
const gEvents = [
  { id: 'abc123', status: 'confirmed', summary: 'Design review', location: 'Room 2', description: 'Agenda<br>1. Mocks<br/>2. <b>Copy</b>', start: { dateTime: '2026-10-20T15:00:00+05:30' }, end: { dateTime: '2026-10-20T16:00:00+05:30' }, hangoutLink: 'https://meet.google.com/abc-defg-hij' },
  { id: 'ny1', summary: 'NY call', start: { dateTime: '2026-11-02T09:00:00-05:00', timeZone: 'America/New_York' }, end: { dateTime: '2026-11-02T09:30:00-05:00' }, conferenceData: { entryPoints: [{ entryPointType: 'phone', uri: 'tel:+1' }, { entryPointType: 'video', uri: 'https://zoom.us/j/42' }] } },
  { id: 'ad1', summary: 'Offsite', start: { date: '2026-10-22' }, end: { date: '2026-10-24' } },
  { id: 'ad2', start: { date: '2026-10-25' } },
  { id: 'zero', summary: 'Zero length', start: { dateTime: '2026-10-21T10:00:00Z' }, end: { dateTime: '2026-10-21T10:00:00Z' } },
  { id: 'gone', status: 'cancelled', summary: 'Cancelled' },
  { id: 'rec_20261021T043000Z', summary: 'Instance', start: { dateTime: '2026-10-21T10:00:00+05:30' }, end: { dateTime: '2026-10-21T10:15:00+05:30' } },
];
const fromG = gEvents.map(ge => ({ ge, result: api.fromGoogle(ge, 'me@example.com') }));
api.setS(api.normalize({}));
const toEvents = [
  { id: 'n1', title: 'New timed', loc: 'Cafe', notes: 'Bring laptop', cat: 'A', start: d(2026, 10, 20, 15), end: d(2026, 10, 20, 15, 45) },
  { id: 'n2', title: 'New all-day', loc: '', notes: '', cat: 'B', allDay: true, start: d(2026, 10, 22), end: d(2026, 10, 24) },
  { id: 'n3', title: 'Weekly sync', loc: '', notes: '', cat: 'A', start: d(2026, 10, 20, 9), end: d(2026, 10, 20, 9, 30), repeat: { freq: 'weekly', until: '2026-12-31' } },
  { id: 'n4', title: 'Weekday standup', loc: '', notes: '', cat: 'A', start: d(2026, 10, 20, 9), end: d(2026, 10, 20, 9, 15), repeat: { freq: 'weekdays', until: '' } },
  { id: 'e1', title: 'Edited, notes untouched', loc: 'Room 2', notes: 'Agenda', cat: 'A', gid: 'abc123', start: d(2026, 10, 20, 15), end: d(2026, 10, 20, 16) },
  { id: 'e2', title: 'Edited notes', loc: '', notes: 'New notes', cat: 'A', gid: 'abc124', dirtyNotes: true, start: d(2026, 10, 20, 15), end: d(2026, 10, 20, 16) },
];
const tzName = Intl.DateTimeFormat().resolvedOptions().timeZone;
const toG = toEvents.map(ev => ({ ev, result: api.toGoogle(api.normalize({ events: [ev] }).events[0]) }));

const out = { now: NOW, tzOffsetMin: -new Date(NOW).getTimezoneOffset(), tzName, fromG, toG, ics, occState, occ, match, merge: { base: JSON.parse(JSON.stringify({ events: [{ id: 'mine', title: 'Team standup, daily', cat: 'A', source: 'local', start: Date.UTC(2026, 9, 20, 15, 0, 20), end: Date.UTC(2026, 9, 20, 15, 30) }], hidden: { 'file:fold-1': 1 } })), r1, after1, r2, after2 } };
const dest = path.join(__dirname, '../../test/fixtures/parity.json');
fs.mkdirSync(path.dirname(dest), { recursive: true });
fs.writeFileSync(dest, JSON.stringify(out, null, 1));
console.log(`wrote ${dest}: ${ics.map(c => `${c.name}=${c.items.length}`).join(' ')}, occ=${occ.map(o => o.result.length).join('/')}, r1=${JSON.stringify(r1)} r2=${JSON.stringify(r2)}`);
