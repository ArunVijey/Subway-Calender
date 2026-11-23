import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:subwayboard/core/ics.dart' as nu;
import 'package:subwayboard/core/util.dart';
import '_old_ics.dart' as old;

void main() {
  test('fast-forwarded RRULE expansion matches the original', () {
    tzdata.initializeTimeZones();
    final r = Random(7);
    final rules = [
      'FREQ=DAILY', 'FREQ=DAILY;INTERVAL=3', 'FREQ=DAILY;BYDAY=MO,WE,FR', 'FREQ=DAILY;BYMONTH=1,6',
      'FREQ=WEEKLY', 'FREQ=WEEKLY;INTERVAL=2', 'FREQ=WEEKLY;BYDAY=TU,TH,SU', 'FREQ=WEEKLY;INTERVAL=3;BYDAY=MO,SA',
      'FREQ=MONTHLY', 'FREQ=MONTHLY;INTERVAL=2', 'FREQ=MONTHLY;BYMONTHDAY=31', 'FREQ=MONTHLY;BYMONTHDAY=-1',
      'FREQ=MONTHLY;BYDAY=2TU', 'FREQ=MONTHLY;BYDAY=-1FR', 'FREQ=MONTHLY;INTERVAL=5;BYMONTH=3,9', 'FREQ=YEARLY',
      'FREQ=DAILY;COUNT=40', 'FREQ=WEEKLY;UNTIL=20261001', 'FREQ=MONTHLY;UNTIL=20270115T120000Z',
    ];
    var cases = 0, occ = 0;
    for (final rule in rules) {
      for (var i = 0; i < 300; i++) {
        final start = DateTime(2018 + r.nextInt(9), 1 + r.nextInt(12), 1 + r.nextInt(28), r.nextInt(24), [0, 15, 30, 45][r.nextInt(4)]);
        final allDay = r.nextInt(5) == 0;
        final dur = allDay ? kDay * (1 + r.nextInt(3)) : kMin * (15 + r.nextInt(600)) + (r.nextInt(8) == 0 ? kDay * r.nextInt(20) : 0);
        final w0 = DateTime(2019 + r.nextInt(9), 1 + r.nextInt(12), 1 + r.nextInt(28)).millisecondsSinceEpoch;
        final span = [kDay, 7 * kDay, 42 * kDay, 366 * kDay][r.nextInt(4)];
        final tz = [null, 'Asia/Kolkata', 'America/New_York', 'UTC'][r.nextInt(4)];
        final w = nu.wallL(start.millisecondsSinceEpoch);
        final a = old.expand(rule, old.IcsDate(allDay, old.Wall(w.y, w.mo, w.d, w.h, w.mi, w.s), tz), dur, old.Window(w0, w0 + span));
        final b = nu.expand(rule, nu.IcsDate(allDay, w, tz), dur, nu.Window(w0, w0 + span));
        expect(b, a, reason: '$rule start=$start dur=$dur win=${DateTime.fromMillisecondsSinceEpoch(w0)} tz=$tz');
        cases++;
        occ += a.length;
      }
    }
    // ignore: avoid_print
    print('$cases cases, $occ occurrences identical');
  });
}
