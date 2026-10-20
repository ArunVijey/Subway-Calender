// Replays the inputs in fixtures/parity.json (produced by running the web
// app's JavaScript, see tool/parity/gen_fixtures.js) and expects identical
// results from the Dart port.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:subwayboard/core/google.dart';
import 'package:subwayboard/core/ics.dart';
import 'package:subwayboard/core/logic.dart';
import 'package:subwayboard/core/model.dart';
import 'package:subwayboard/core/util.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

void main() {
  final f = jsonDecode(File('test/fixtures/parity.json').readAsStringSync()) as Map<String, dynamic>;

  setUpAll(() {
    tzdata.initializeTimeZones();
    nowMs = () => f['now'] as int;
  });

  test('fixtures were generated in this time zone', () {
    final offset = DateTime.fromMillisecondsSinceEpoch(f['now'] as int).timeZoneOffset.inMinutes;
    expect(offset, f['tzOffsetMin'], reason: 'regenerate fixtures: node tool/parity/gen_fixtures.js');
  });

  group('parseIcs', () {
    for (final c in f['ics'] as List) {
      test(c['name'], () {
        final got = parseIcs(c['text'] as String).map((i) => i.toJson()).toList();
        final want = (c['items'] as List).map((i) => Map<String, dynamic>.from(i)).toList();
        expect(got.length, want.length);
        for (var i = 0; i < want.length; i++) {
          expect(got[i], want[i], reason: 'item $i (${want[i]['key']})');
        }
      });
    }
  });

  test('occurrences of local repeats', () {
    final s = normalize(Map<String, dynamic>.from(f['occState']));
    for (final w in f['occ'] as List) {
      final got = occurrences(s, w['from'], w['to']).map((e) => {'id': e.id, 'start': e.start, 'end': e.end}).toList();
      expect(got, w['result'], reason: 'window ${DateTime.fromMillisecondsSinceEpoch(w['from'])}');
    }
  });

  test('fromGoogle', () {
    for (final c in f['fromG'] as List) {
      final it = fromGoogle(Map<String, dynamic>.from(c['ge']), 'me@example.com');
      final got = it == null ? null : {...it.toJson(), 'gid': it.gid, 'calId': it.calId};
      expect(got, c['result'], reason: c['ge']['id']);
    }
  });

  test('toGoogle', () {
    for (final c in f['toG'] as List) {
      final ev = normalize({'events': [c['ev']]}).events.single;
      expect(jsonDecode(jsonEncode(toGoogle(ev, f['tzName'] as String))), c['result'], reason: c['ev']['id']);
    }
  });

  test('matchLine', () {
    final s = normalize(null);
    for (final m in f['match'] as List) {
      expect(matchLine(s, m['title'], m['loc']), m['result'], reason: m['title']);
    }
  });

  test('merge', () {
    final m = f['merge'] as Map<String, dynamic>;
    final s = normalize(Map<String, dynamic>.from(m['base']));
    final basic = (f['ics'] as List).firstWhere((c) => c['name'] == 'basic')['text'] as String;
    final items1 = parseIcs(basic).map((it) => it.withKey('file:${it.key}')).toList();

    Map<String, dynamic> rj(MergeResult r) => {'a': r.added, 'u': r.updated, 'r': r.removed};
    List<Map<String, dynamic>> ev() => s.events
        .map((e) => {
              'id': e.id == 'mine' ? 'mine' : '*',
              'key': e.key,
              'title': e.title,
              'cat': e.cat,
              'start': e.start,
              'end': e.end,
              'source': e.source,
              'feed': e.feed,
            })
        .toList();
    List<Map<String, dynamic>> want(List l) => l.map((e) => Map<String, dynamic>.from(e)).toList();

    expect(rj(merge(s, items1, 'file', 'file', false)), m['r1']);
    expect(ev(), want(m['after1']));

    final items2 = [
      for (final it in items1)
        if (!it.key.contains('allday-2'))
          it.key == 'file:basic-1'
              ? IcsItem(key: it.key, title: 'Renamed', loc: it.loc, notes: it.notes, link: it.link, start: it.start, end: it.end, allDay: it.allDay)
              : it
    ];
    expect(rj(merge(s, items2, 'file', 'file', true)), m['r2']);
    expect(ev(), want(m['after2']));
  });

  test('backup round trip keeps Google fields', () {
    final s = normalize({
      'events': [
        {'id': 'x', 'title': 'Synced', 'cat': 'A', 'start': 1000, 'end': 2000, 'source': 'gapi', 'gid': 'g123', 'calId': 'me@example.com', 'remind': ''},
      ],
      'settings': {'mode': 'api', 'clientId': 'abc.apps.googleusercontent.com', 'remindDefault': 15},
    });
    final j = jsonDecode(jsonEncode(s.toJson()));
    expect(j['events'][0]['gid'], 'g123');
    expect(j['events'][0]['remind'], '');
    expect(j['settings']['clientId'], 'abc.apps.googleusercontent.com');
    expect(j['settings']['remindDefault'], 15);
    expect(j['settings']['mode'], 'api');
    final back = normalize(j);
    expect(back.events.single.calId, 'me@example.com');
    expect(back.events.single.gid, 'g123');
    expect(back.settings.clientId, 'abc.apps.googleusercontent.com');
  });
}
