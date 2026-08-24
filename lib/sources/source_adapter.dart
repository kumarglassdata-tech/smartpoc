import 'dart:typed_data';

class VideoFrame {
  final Uint8List bytes;
  final int width;
  final int height;

  const VideoFrame({required this.bytes, this.width = 0, this.height = 0});
}

class LocationSample {
  final double latitude;
  final double longitude;

  const LocationSample({required this.latitude, required this.longitude});
}

enum SourceHealthStatus { healthy, degraded, disconnected }

class SourceHealth {
  final SourceHealthStatus status;
  final String message;

  const SourceHealth({required this.status, required this.message});
}

// One swappable capture source (phone camera, synthetic test generator,
// uploaded file) feeding the same downstream pipeline. Video is the only
// stream SmartPoc's engines currently consume - audio input to BE/CE comes
// through the interaction engine's own mic pipeline instead, so no
// audioStream here.
abstract class SourceAdapter {
  Stream<VideoFrame> get videoStream;
  Stream<LocationSample> get locationStream;
  Stream<SourceHealth> get healthStream;

  Future<void> start();
  Future<void> stop();
  bool get isActive;

  void notifyFrameProcessed() {}
}
