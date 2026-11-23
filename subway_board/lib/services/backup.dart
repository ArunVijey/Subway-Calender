// Automatic backups. Two places:
//  • a file the user picks once (any folder, or Google Drive through Android's
//    picker), overwritten once a day; and
//  • a rolling copy of the last 7 days in the app's own folder on the phone
//    (Android/data/…/files/backups), which needs no setup.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'platform.dart';

abstract final class BackupFile {
  static const _ch = MethodChannel('subwayboard/backup');
  static bool get supported => !kIsWeb && Platform.isAndroid;

  /// Asks where to keep the backup. Returns (uri, display name), or null if cancelled.
  static Future<(String, String)?> pick(String suggestedName) async {
    if (!supported) return null;
    final m = await _ch.invokeMethod<Map>('pick', {'name': suggestedName});
    if (m == null) return null;
    return (m['uri'] as String, (m['name'] as String?) ?? 'backup');
  }

  /// Overwrites the picked file. Throws a readable message on failure.
  static Future<void> write(String uri, String text) async {
    try {
      await _ch.invokeMethod('write', {'uri': uri, 'text': text});
    } on PlatformException catch (e) {
      throw e.message ?? 'could not write the backup';
    }
  }

  /// Whether the app can still write to [uri] (the file or its permission may be gone).
  static Future<bool> usable(String uri) async {
    if (!supported || uri.isEmpty) return false;
    try {
      return await _ch.invokeMethod<bool>('check', {'uri': uri}) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Writes today's copy to the app's folder and keeps the newest [keep].
  static Future<String?> writeLocal(String text, String day, {int keep = 7}) async {
    try {
      final base = (supported ? await AppPlatform.externalDir() : null) ?? await AppPlatform.docsDir();
      final dir = Directory('${base.path}/backups');
      await dir.create(recursive: true);
      final f = File('${dir.path}/subway-board-$day.json');
      await f.writeAsString(text, flush: true);
      final old = dir.listSync().whereType<File>().where((x) => x.path.endsWith('.json')).toList()..sort((a, b) => b.path.compareTo(a.path));
      for (final x in old.skip(keep)) {
        await x.delete();
      }
      return dir.path;
    } catch (e) {
      debugPrint('local backup: $e');
      return null;
    }
  }
}
