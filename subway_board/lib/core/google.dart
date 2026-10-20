// Google Calendar event <-> board event mapping (port of fromGoogle/toGoogle).
import 'ics.dart';
import 'model.dart';
import 'util.dart';

final _tags = RegExp(r'<[^>]+>');
final _br = RegExp(r'<br\s*/?>', caseSensitive: false);

/// Converts a Calendar API event to an import item; null for cancelled ones.
IcsItem? fromGoogle(Map<String, dynamic> ge, String calId) {
  final st = ge['start'];
  if (ge['status'] == 'cancelled' || st is! Map) return null;
  final en = ge['end'] is Map ? ge['end'] as Map : const {};
  final allDay = st['date'] != null;
  int parse(dynamic dateTime) => DateTime.parse(dateTime as String).millisecondsSinceEpoch;
  final start = allDay ? dms(st['date']) : parse(st['dateTime']);
  var end = allDay ? dms((en['date'] ?? st['date']) as String) : parse(en['dateTime'] ?? st['dateTime']);
  if (end <= start) end = allDay ? addDays(start, 1) : start + kHour;
  final entry = ((ge['conferenceData'] is Map ? ge['conferenceData']['entryPoints'] : null) as List? ?? const [])
      .whereType<Map>()
      .where((p) => p['entryPointType'] == 'video')
      .firstOrNull;
  final id = ge['id'] as String;
  final summary = ge['summary'] as String?;
  return IcsItem(
    key: 'g:$calId|$id',
    gid: id,
    calId: calId,
    title: summary == null || summary.isEmpty ? '(No title)' : summary,
    loc: (ge['location'] as String?) ?? '',
    notes: clip(((ge['description'] as String?) ?? '').replaceAll(_br, '\n').replaceAll(_tags, ''), 2000),
    link: (ge['hangoutLink'] as String?) ?? (entry?['uri'] as String?) ?? '',
    start: start,
    end: end,
    allDay: allDay,
  );
}

/// Request body for creating/updating [ev] in Google Calendar. [tzName] is the
/// device's IANA zone (Google needs it for repeating timed events).
Map<String, dynamic> toGoogle(Event ev, String tzName) {
  Map<String, dynamic> t(int ms) => ev.allDay
      ? {'date': dstr(ms)}
      : {'dateTime': DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String(), 'timeZone': tzName};
  return {
    'summary': ev.title,
    'location': ev.loc,
    'start': t(ev.start),
    'end': t(ev.end),
    // Notes pulled from Google may have lost HTML formatting; only send them when edited here.
    if (ev.gid == null || ev.dirtyNotes) 'description': ev.notes,
    if (ev.repeat != null && kRepeat.containsKey(ev.repeat!.freq)) 'recurrence': ['RRULE:${ruleFor(ev, forExport: true)}'],
  };
}
