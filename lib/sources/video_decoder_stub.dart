import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

// Native (Android/iOS) video frame extraction powered by MediaMetadataRetriever
// via MethodChannel('com.smartpoc.app/video_decoder').
// Extracts real 640x480 JPEG frames matching the exact live camera pipeline format.
class VideoDecoder {
  static const _channel = MethodChannel('com.smartpoc.app/video_decoder');
  File? _tempFile;

  Future<void> loadVideo(Uint8List bytes, {String? fileName}) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final ext = fileName?.split('.').last.toLowerCase() ?? 'mp4';
      _tempFile = File('${tempDir.path}/upload_stream_video_${DateTime.now().millisecondsSinceEpoch}.$ext');
      await _tempFile!.writeAsBytes(bytes, flush: true);

      await _channel.invokeMethod('loadVideo', {
        'filePath': _tempFile!.path,
      });
    } catch (e) {
      // Graceful fallback
    }
  }

  Future<Uint8List?> getNextFrame() async {
    try {
      final result = await _channel.invokeMethod<Uint8List>('getNextFrame');
      return result;
    } catch (_) {
      return null;
    }
  }

  Future<void> dispose() async {
    try {
      await _channel.invokeMethod('dispose');
      if (_tempFile != null && await _tempFile!.exists()) {
        await _tempFile!.delete();
      }
    } catch (_) {}
    _tempFile = null;
  }
}
