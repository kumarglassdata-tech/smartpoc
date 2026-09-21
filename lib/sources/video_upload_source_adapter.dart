import 'dart:async';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../location_service.dart';
import 'source_adapter.dart';
import 'video_decoder_stub.dart' if (dart.library.html) 'video_decoder_web.dart';

// Streams frames from a user-uploaded image/video file instead of a live
// camera - useful for testing the pipeline against a fixed, repeatable input.
class VideoUploadSourceAdapter implements SourceAdapter {
  final LocationService _locationService;

  final _videoController = StreamController<VideoFrame>.broadcast();
  final _locationController = StreamController<LocationSample>.broadcast();
  final _healthController = StreamController<SourceHealth>.broadcast();

  bool _isActive = false;
  bool _waitingForResponse = false;
  Timer? _nextFrameTimer;
  Timer? _watchdogTimer;
  Timer? _healthTimer;

  Uint8List? _uploadedBytes;
  String? _fileName;
  bool _isImage = true;
  final _videoDecoder = VideoDecoder();

  VideoUploadSourceAdapter({required LocationService location}) : _locationService = location;

  void setUploadedFile(Uint8List bytes, String name, bool isImage) {
    _uploadedBytes = bytes;
    _fileName = name;
    _isImage = isImage;

    if (!isImage) {
      _videoDecoder.loadVideo(bytes, fileName: name).then((_) {
        if (_isActive && !_waitingForResponse) _emitFrame();
      });
    } else if (_isActive && !_waitingForResponse) {
      _emitFrame();
    }
  }

  @override
  Stream<VideoFrame> get videoStream => _videoController.stream;
  @override
  Stream<LocationSample> get locationStream => _locationController.stream;
  @override
  Stream<SourceHealth> get healthStream => _healthController.stream;
  @override
  bool get isActive => _isActive;

  @override
  Future<void> start() async {
    if (_isActive) return;
    _isActive = true;
    _waitingForResponse = false;

    await _locationService.start();
    _locationService.addListener(_onLocationChanged);

    if (!_isImage && _uploadedBytes != null) {
      await _videoDecoder.loadVideo(_uploadedBytes!, fileName: _fileName);
    }

    _healthTimer?.cancel();
    _healthTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _healthController.add(SourceHealth(
        status: SourceHealthStatus.healthy,
        message: _fileName != null ? 'Streaming from file: $_fileName' : 'Waiting for file upload',
      )),
    );
    _healthController.add(SourceHealth(
      status: SourceHealthStatus.healthy,
      message: _fileName != null ? 'Video ingestion started: $_fileName' : 'Video ingestion started (no file yet)',
    ));

    // Emit the first frame to initiate the response-gated pipeline cycle
    _emitFrame();
  }

  @override
  void notifyFrameProcessed() {
    if (!_isActive) return;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _waitingForResponse = false;

    // Response arrived: schedule next frame with a 500ms delay
    _nextFrameTimer?.cancel();
    _nextFrameTimer = Timer(const Duration(milliseconds: 500), () {
      if (_isActive && !_waitingForResponse) {
        _emitFrame();
      }
    });
  }

  Future<void> _emitFrame() async {
    if (!_isActive) return;
    _nextFrameTimer?.cancel();
    _nextFrameTimer = null;
    _waitingForResponse = true;

    // 10s Watchdog: In case network drops or server fails to respond, advance automatically
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer(const Duration(seconds: 10), () {
      if (_isActive && _waitingForResponse) {
        _waitingForResponse = false;
        _emitFrame();
      }
    });

    final uploaded = _uploadedBytes;

    if (uploaded != null && _isImage) {
      final resized = _resizeImageTo640x480(uploaded);
      _videoController.add(VideoFrame(bytes: resized));
      return;
    }
    if (uploaded != null && !_isImage) {
      final frameBytes = await _videoDecoder.getNextFrame();
      if (frameBytes != null) {
        _videoController.add(VideoFrame(bytes: frameBytes));
        return;
      }
    }
    _videoController.add(VideoFrame(bytes: _placeholderJpeg(), width: 128, height: 128));
  }

  static Uint8List _resizeImageTo640x480(Uint8List bytes) {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return bytes;
      if (decoded.width <= 640 && decoded.height <= 480) return bytes;
      final resized = img.copyResize(decoded, width: 640, height: 480);
      return Uint8List.fromList(img.encodeJpg(resized, quality: 80));
    } catch (_) {
      return bytes;
    }
  }

  Uint8List _placeholderJpeg() {
    try {
      final image = img.Image(width: 128, height: 128);
      img.fill(image, color: img.ColorRgb8(40, 40, 40));
      return Uint8List.fromList(img.encodeJpg(image));
    } catch (_) {
      return Uint8List.fromList([0, 1, 2, 3]);
    }
  }

  void _onLocationChanged() {
    final lat = _locationService.latitude;
    final lon = _locationService.longitude;
    if (lat != null && lon != null) {
      _locationController.add(LocationSample(latitude: lat, longitude: lon));
    }
  }

  @override
  Future<void> stop() async {
    _isActive = false;
    _waitingForResponse = false;
    _nextFrameTimer?.cancel();
    _nextFrameTimer = null;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _healthTimer?.cancel();
    _healthTimer = null;
    _locationService.removeListener(_onLocationChanged);
    await _locationService.stop();
    _videoDecoder.dispose();
    _healthController.add(const SourceHealth(status: SourceHealthStatus.disconnected, message: 'Video ingestion stopped'));
  }

  void dispose() {
    stop();
    _videoDecoder.dispose();
    _videoController.close();
    _locationController.close();
    _healthController.close();
  }
}
