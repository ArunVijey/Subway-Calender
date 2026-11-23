// The welcome shows on a fresh install only, never for existing data or backups.
import 'package:flutter_test/flutter_test.dart';
import 'package:subwayboard/core/model.dart';

void main() {
  test('fresh install has not seen the welcome', () {
    expect(AppData().settings.welcomed, isFalse);
  });

  test('saved data and backups from before the welcome count as welcomed', () {
    expect(normalize({}).settings.welcomed, isTrue);
    expect(normalize({'settings': {'mode': 'api'}}).settings.welcomed, isTrue);
  });

  test('the answer round-trips through save and backup', () {
    final d = AppData()..settings.welcomed = false;
    expect(normalize(d.toJson()).settings.welcomed, isFalse);
    d.settings.welcomed = true;
    expect(normalize(d.toJson()).settings.welcomed, isTrue);
  });
}
