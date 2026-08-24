import 'dart:async';
import 'package:flutter/foundation.dart';
import '../location_service.dart';
import '../services/meta_glasses_service.dart';
import 'source_adapter.dart';

class MetaGlassesSourceAdapter implements SourceAdapter {
  final MetaGlassesService glassesService;
  final LocationService location;

  final _videoController = StreamController<VideoFrame>.broadcast();
  final _locationController = StreamController<LocationSample>.broadcast();
  final _healthController = StreamController<SourceHealth>.broadcast();

  StreamSubscription<Uint8List>? _frameSub;
  VoidCallback? _statusListener;
  VoidCallback? _locationListener;
  bool _active = false;

  MetaGlassesSourceAdapter({
    MetaGlassesService? glassesService,
    required this.location,
  }) : glassesService = glassesService ?? MetaGlassesService.instance {
    _statusListener = _onStatusChanged;
    this.glassesService.statusNotifier.addListener(_statusListener!);

    _locationListener = _onLocationChanged;
    location.addListener(_locationListener!);
  }

  void _onStatusChanged() {
    final status = glassesService.statusNotifier.value;
    final msg = glassesService.statusMessageNotifier.value ?? '';
    switch (status) {
      case MetaGlassesStatus.streaming:
        _healthController.add(
          SourceHealth(status: SourceHealthStatus.healthy, message: msg.isNotEmpty ? msg : 'Streaming live video'),
        );
        break;
      case MetaGlassesStatus.connected:
      case MetaGlassesStatus.connecting:
      case MetaGlassesStatus.registered:
      case MetaGlassesStatus.registering:
        _healthController.add(
          SourceHealth(status: SourceHealthStatus.degraded, message: msg.isNotEmpty ? msg : 'Connecting to glasses...'),
        );
        break;
      case MetaGlassesStatus.disconnected:
      case MetaGlassesStatus.error:
        _healthController.add(
          SourceHealth(status: SourceHealthStatus.disconnected, message: msg.isNotEmpty ? msg : 'Glasses disconnected'),
        );
        break;
    }
  }

  void _onLocationChanged() {
    final lat = location.latitude;
    final lon = location.longitude;
    if (lat != null && lon != null) {
      _locationController.add(LocationSample(latitude: lat, longitude: lon));
    }
  }

  @override
  Stream<VideoFrame> get videoStream => _videoController.stream;

  @override
  Stream<LocationSample> get locationStream => _locationController.stream;

  @override
  Stream<SourceHealth> get healthStream => _healthController.stream;

  @override
  bool get isActive => _active;

  @override
  Future<void> start() async {
    if (_active) return;
    _active = true;

    _frameSub?.cancel();
    _frameSub = glassesService.frameStream.listen((bytes) {
      if (!_active) return;
      _videoController.add(VideoFrame(bytes: bytes));
    });

    final started = await glassesService.startCameraStream();
    if (!started && glassesService.statusNotifier.value != MetaGlassesStatus.streaming) {
      _active = false;
      throw Exception(
        glassesService.statusMessageNotifier.value ?? 'Could not start Meta Glasses stream. Ensure Meta View is paired.',
      );
    }

    _onLocationChanged();
  }

  @override
  Future<void> stop() async {
    _active = false;
    await _frameSub?.cancel();
    _frameSub = null;
    await glassesService.stopCameraStream();
    _healthController.add(
      const SourceHealth(status: SourceHealthStatus.disconnected, message: 'Stream stopped'),
    );
  }

  @override
  void notifyFrameProcessed() {}

  void dispose() {
    stop();
    if (_statusListener != null) {
      glassesService.statusNotifier.removeListener(_statusListener!);
    }
    if (_locationListener != null) {
      location.removeListener(_locationListener!);
    }
    _videoController.close();
    _locationController.close();
    _healthController.close();
  }
}
