// Folders and the in-app chime, from the app's own Android code (AppChannels.kt).
// Replaces the path_provider and audioplayers plugins.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract final class AppPlatform {
  static const _ch = MethodChannel('subwayboard/app');
  static bool get _android => !kIsWeb && Platform.isAndroid;

  static String? _docs;

  /// The app's private data folder (where path_provider kept it: app_flutter).
  static Future<Directory> docsDir() async {
    if (_docs == null) {
      if (_android) {
        _docs = await _ch.invokeMethod<String>('docsDir');
      } else {
        // Tests and desktop runs: a folder of their own.
        _docs = '${Directory.systemTemp.path}/subwayboard';
      }
    }
    return Directory(_docs!).create(recursive: true);
  }

  /// The app's folder under Android/data (visible over USB), or null.
  static Future<Directory?> externalDir() async {
    if (!_android) return null;
    try {
      final p = await _ch.invokeMethod<String>('externalDir');
      return p == null ? null : Directory(p);
    } catch (_) {
      return null;
    }
  }

  static Future<void> chime({required bool boarding}) async {
    if (!_android) return;
    try {
      await _ch.invokeMethod('chime', boarding);
    } catch (e) {
      debugPrint('chime failed: $e');
    }
  }
}
