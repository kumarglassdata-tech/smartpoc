import 'dart:async';

import '../location_service.dart';
import 'camera_service.dart';
import 'source_adapter.dart';

class PhoneSourceAdapter implements SourceAdapter {
  final CameraService _cameraService;
  final LocationService _locationService;

  final _videoController = StreamController<VideoFrame>.broadcast();
  final _locationController = StreamController<LocationSample>.broadcast();
  final _healthController = StreamController<SourceHealth>.broadcast();

  bool _isActive = false;
  Timer? _healthTimer;

  PhoneSourceAdapter({required CameraService camera, required LocationService location})
    : _cameraService = camera,
      _locationService = location;

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

    await _cameraService.startStreaming();
    _cameraService.addListener(_onCameraChanged);
    _locationService.addListener(_onLocationChanged);
    unawaited(_locationService.start());

    _healthTimer?.cancel();
    _healthTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _healthController.add(const SourceHealth(status: SourceHealthStatus.healthy, message: 'Phone sensors active')),
    );
    _healthController.add(const SourceHealth(status: SourceHealthStatus.healthy, message: 'Phone source started'));
  }

  void _onCameraChanged() {
    final bytes = _cameraService.lastFrameBytes;
    if (bytes != null && bytes.isNotEmpty) {
      _videoController.add(VideoFrame(bytes: bytes));
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
  void notifyFrameProcessed() {}

  @override
  Future<void> stop() async {
    _isActive = false;
    _cameraService.removeListener(_onCameraChanged);
    _locationService.removeListener(_onLocationChanged);
    _healthTimer?.cancel();
    _healthTimer = null;
    await _cameraService.stopStreaming();
    await _locationService.stop();
    _healthController.add(const SourceHealth(status: SourceHealthStatus.disconnected, message: 'Phone source stopped'));
  }

  void dispose() {
    stop();
    _videoController.close();
    _locationController.close();
    _healthController.close();
  }
}
