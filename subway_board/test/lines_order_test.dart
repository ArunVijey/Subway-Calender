// Line order is saved, and the first line is what new events and imports default to.
import 'package:flutter_test/flutter_test.dart';
import 'package:subwayboard/core/logic.dart';
import 'package:subwayboard/core/model.dart';

void main() {
  test('reordered lines survive save and restore', () {
    final d = AppData();
    final moved = d.lines.removeAt(3);
    d.lines.insert(0, moved);
    final back = normalize(d.toJson());
    expect(back.lines.map((l) => l.id).toList(), d.lines.map((l) => l.id).toList());
  });

  test('unmatched imports land on the first line', () {
    final d = AppData();
    d.lines.insert(0, d.lines.removeAt(4));
    expect(autoCat(d, 'zzz no keyword here', ''), d.lines.first.id);
  });
}
