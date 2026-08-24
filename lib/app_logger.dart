import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

// Timestamped request/response log written to the app's external files dir
// so it's pullable via `adb pull` or shareable through the download button.
// adb path: /storage/emulated/0/Android/data/<applicationId>/files/smartpoc_log.txt
class AppLogger {
  static File? _logFile;
  // The 5-way ecom fan-out (buy/recommend GET+POST/analyze/lifebalance) logs
  // concurrently every tick - each writeAsString(append) independently opens,
  // seeks to end, writes, closes, so overlapping calls can race and clobber
  // each other's line entirely (confirmed: a lifebalance line appearing twice
  // in one batch while the concurrent buy line vanished). Chaining writes
  // through this queue serializes them so no entry is ever lost.
  static Future<void> _writeQueue = Future.value();

  static Future<void> init() async {
    if (kIsWeb) return;
    final directory = await getExternalStorageDirectory();
    if (directory == null) return;
    final logFile = File('${directory.path}/smartpoc_log.txt');
    if (!await logFile.exists()) {
      await logFile.create(recursive: true);
    }
    _logFile = logFile;
  }

  static Future<void> log(String tag, String message) async {
    final line = '[${DateTime.now().toIso8601String()}] $tag: $message';
    debugPrint(line);
    final logFile = _logFile;
    if (logFile == null) return;
    _writeQueue = _writeQueue.then((_) => logFile.writeAsString('$line\n', mode: FileMode.append));
    await _writeQueue;
  }

  static File? get logFile => _logFile;
}
