import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;

// Matches the resize CE's object detector gets reliable detections from in
// live testing - a raw takePicture() frame at native resolution was not.
Uint8List _resizeImageTo640x480(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  final resized = img.copyResize(decoded, width: 640, height: 480);
  return Uint8List.fromList(img.encodeJpg(resized, quality: 80));
}

// Continuous camera capture for SourceManager's phone adapter - separate
// from TestScreen's own direct CameraController used by the manual Capture
// & Send button.
class CameraService extends ChangeNotifier with WidgetsBindingObserver {
  CameraService() {
    WidgetsBinding.instance.addObserver(this);
  }

  CameraController? _controller;
  Timer? _captureTimer;
  bool _isInitialized = false;
  bool _isStreaming = false;
  bool _wasStreamingBeforeBackground = false;
  bool _captureInFlight = false;
  Uint8List? _lastFrameBytes;
  String? _errorMessage;

  bool get isInitialized => _isInitialized;
  bool get isStreaming => _isStreaming;
  Uint8List? get lastFrameBytes => _lastFrameBytes;
  String? get errorMessage => _errorMessage;
  CameraController? get controller => _controller;

  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _errorMessage = 'No cameras available on this device.';
        notifyListeners();
        return;
      }
      final selectedCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      _controller = CameraController(
        selectedCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: kIsWeb ? null : ImageFormatGroup.jpeg,
      );
      await _controller!.initialize();
      _isInitialized = true;
      _errorMessage = null;
      notifyListeners();
    } catch (error) {
      _errorMessage = 'Camera initialization failed: $error';
      notifyListeners();
    }
  }

  Future<void> startStreaming() async {
    await initialize();
    if (_controller == null || !_controller!.value.isInitialized) return;
    _isStreaming = true;
    _errorMessage = null;
    notifyListeners();
    _captureTimer = Timer.periodic(const Duration(milliseconds: 2000), _captureFrame);
  }

  Future<void> _captureFrame(Timer timer) async {
    if (!_isStreaming || _controller == null || !_controller!.value.isInitialized || _captureInFlight) return;
    _captureInFlight = true;
    try {
      final picture = await _controller!.takePicture();
      final rawBytes = await picture.readAsBytes();
      final bytes = await compute(_resizeImageTo640x480, rawBytes);
      _lastFrameBytes = bytes;
      _errorMessage = null;
      try {
        await File(picture.path).delete();
      } catch (_) {}
    } catch (error) {
      _errorMessage = 'Frame capture failed: $error';
    } finally {
      _captureInFlight = false;
      notifyListeners();
    }
  }

  Future<void> stopStreaming() async {
    _isStreaming = false;
    _captureTimer?.cancel();
    _captureTimer = null;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _handleAppBackgrounded();
    } else if (state == AppLifecycleState.resumed && _wasStreamingBeforeBackground) {
      _wasStreamingBeforeBackground = false;
      startStreaming();
    }
  }

  // A notification banner (or anything that briefly takes focus) sends the
  // app through inactive/paused then straight back to resumed - stopStreaming()
  // below clears _isStreaming, so the resumed check above must remember it was
  // streaming beforehand rather than reading the flag it just cleared, or the
  // camera never reinitializes and the preview stays black until the session
  // is manually ended and restarted.
  Future<void> _handleAppBackgrounded() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    _wasStreamingBeforeBackground = _isStreaming;
    await stopStreaming();
    await _controller?.dispose();
    _controller = null;
    _isInitialized = false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    stopStreaming();
    _controller?.dispose();
    super.dispose();
  }
}
