// Date/time helpers ported from the web app. All times are epoch milliseconds;
// "local" helpers use the device time zone, like JavaScript's Date.
import 'dart:math';

const int kDay = 86400000;
const int kHour = 3600000;
const int kMin = 60000;

/// Injectable clock so tests can pin "now".
int Function() nowMs = () => DateTime.now().millisecondsSinceEpoch;

String pad(int n) => n.toString().padLeft(2, '0');

DateTime _local(int ms) => DateTime.fromMillisecondsSinceEpoch(ms);

/// YYYY-MM-DD in local time.
String dstr(int ms) {
  final d = _local(ms);
  return '${d.year}-${pad(d.month)}-${pad(d.day)}';
}

String todayStr() => dstr(nowMs());

/// Local midnight of a YYYY-MM-DD string.
int dms(String s) {
  final p = s.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]).millisecondsSinceEpoch;
}

/// Start of the local day containing [ms].
int sod(int ms) {
  final d = _local(ms);
  return DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;
}

/// Same local wall time, [n] days later (DST-safe, like JS setDate).
int addDays(int ms, int n) {
  final d = _local(ms);
  return DateTime(d.year, d.month, d.day + n, d.hour, d.minute, d.second, d.millisecond).millisecondsSinceEpoch;
}

/// HH:MM, 24-hour.
String hm(int ms) {
  final d = _local(ms);
  return '${pad(d.hour)}:${pad(d.minute)}';
}

/// Minute key, used to identify repeat occurrences and exdates.
int mkey(int ms) => (ms / kMin).round();

const _wd = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _mo = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

String weekdayLong(int ms) => _wd[_local(ms).weekday - 1];
String weekdayShort(int ms) => _wd[_local(ms).weekday - 1].substring(0, 3);
String monthShort(int ms) => _mo[_local(ms).month - 1].substring(0, 3);

/// "Oct 20"
String monthDay(int ms) => '${monthShort(ms)} ${_local(ms).day}';

/// Time of day in the phone's preferred format.
String fmtT(int ms, {bool use24h = false}) {
  final d = _local(ms);
  if (use24h) return '${pad(d.hour)}:${pad(d.minute)}';
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${pad(d.minute)} ${d.hour < 12 ? 'AM' : 'PM'}';
}

final _rnd = Random();
String uid() => nowMs().toRadixString(36) + _rnd.nextInt(1 << 30).toRadixString(36).padLeft(6, '0').substring(0, 5);

/// Black or white text for a #rrggbb background (same threshold as the web app).
bool darkTextOn(String hex) {
  final n = int.parse(hex.substring(1), radix: 16);
  return 0.299 * (n >> 16) + 0.587 * (n >> 8 & 255) + 0.114 * (n & 255) > 165;
}

String clip(String s, int max) => s.length > max ? s.substring(0, max) : s;
