import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class CrashLog {
  static const int _maxEntries = 50;
  static const String _fileName = 'crash_log.txt';
  static File? _file;
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/crash');
      if (!await dir.exists()) await dir.create(recursive: true);
      _file = File('${dir.path}/$_fileName');

      if (await _file!.exists()) {
        final lines = await _file!.readAsLines();
        if (lines.length > _maxEntries * 2) {
          await _file!.writeAsString(lines.sublist(lines.length - _maxEntries).join('\n'));
        }
      }

      final prev = FlutterError.onError;
      FlutterError.onError = (details) {
        prev?.call(details);
        _write('[FlutterError] ${details.exception}\n${details.stack}');
      };

      if (kReleaseMode) {
        PlatformDispatcher.instance.onError = (error, stack) {
          _write('[PlatformError] $error\n$stack');
          return true;
        };
      }
    } catch (_) {
      // crash logging unavailable — app continues normally
    }
  }

  static Future<void> _write(String text) async {
    try {
      final timestamp = DateTime.now().toIso8601String();
      final entry = '--- $timestamp ---\n$text\n\n';
      await _file?.writeAsString(entry, mode: FileMode.append);
    } catch (_) {}
  }

  static Future<String> read() async {
    try {
      if (!_initialized || _file == null || !await _file!.exists()) return '';
      return await _file!.readAsString();
    } catch (_) {
      return '';
    }
  }

  static Future<void> clear() async {
    try {
      await _file?.writeAsString('');
    } catch (_) {}
  }
}
