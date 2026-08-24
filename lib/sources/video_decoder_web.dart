import 'dart:async';
import 'dart:convert';
import 'package:web/web.dart' as web;
import 'dart:js_interop';
import 'dart:typed_data';

// Web video frame extraction - decodes via a hidden <video>/<canvas> pair
// since there's no file-based thumbnailer available in the browser.
class VideoDecoder {
  web.HTMLVideoElement? _video;
  web.HTMLCanvasElement? _canvas;
  double _duration = 0.0;
  double _currentTime = 0.0;
  String? _objectUrl;

  Future<void> loadVideo(Uint8List bytes, {String? fileName}) async {
    try {
      if (_objectUrl != null) web.URL.revokeObjectURL(_objectUrl!);
      _video?.remove();

      var mimeType = 'video/mp4';
      final ext = fileName?.split('.').last.toLowerCase();
      if (ext == 'webm') mimeType = 'video/webm';
      if (ext == 'ogg' || ext == 'ogv') mimeType = 'video/ogg';
      if (ext == 'mov') mimeType = 'video/quicktime';

      final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
      _objectUrl = web.URL.createObjectURL(blob);

      final video = web.document.createElement('video') as web.HTMLVideoElement
        ..src = _objectUrl!
        ..muted = true
        ..autoplay = false
        ..preload = 'auto'
        ..setAttribute('playsinline', 'true');
      video.style.display = 'none';
      web.document.body?.append(video);
      video.load();

      final completer = Completer<void>();
      final callback = ((web.Event _) { 
        if (!completer.isCompleted) completer.complete();
      }).toJS;
      video.addEventListener('loadedmetadata', callback);

      await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => null,
      );
      video.removeEventListener('loadedmetadata', callback);

      _video = video;
      _duration = video.duration.toDouble();
      if (_duration == 0.0 || _duration.isNaN) _duration = 30.0;
      _currentTime = 0.0;
      _canvas = web.document.createElement('canvas') as web.HTMLCanvasElement
        ..width = video.videoWidth > 0 ? video.videoWidth : 640
        ..height = video.videoHeight > 0 ? video.videoHeight : 480;
    } catch (_) {}
  }

  Future<Uint8List?> getNextFrame() async {
    final video = _video;
    final canvas = _canvas;
    if (video == null || canvas == null) return null;
    if (_currentTime >= _duration) _currentTime = 0.0;

    try {
      video.currentTime = _currentTime;
      
      final completer = Completer<void>();
      final callback = ((web.Event _) { 
        if (!completer.isCompleted) completer.complete(); 
      }).toJS;
      video.addEventListener('seeked', callback);

      await completer.future.timeout(
        const Duration(milliseconds: 1500),
        onTimeout: () => null,
      );
      video.removeEventListener('seeked', callback);

      final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D;
      ctx.drawImage(video, 0, 0);
      final dataUrl = canvas.toDataURL('image/jpeg', 0.85.toJS);
      final commaIndex = dataUrl.indexOf(',');
      if (commaIndex == -1) return null;
      final frameBytes = base64Decode(dataUrl.substring(commaIndex + 1));
      _currentTime += 3.0;
      return frameBytes;
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    try {
      _video?.remove();
      if (_objectUrl != null) web.URL.revokeObjectURL(_objectUrl!);
    } catch (_) {}
    _video = null;
    _canvas = null;
    _objectUrl = null;
  }
}
