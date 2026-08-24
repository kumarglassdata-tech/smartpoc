import 'dart:async';

import 'package:flutter/foundation.dart';

import 'source_adapter.dart';

enum SourceType { metaGlasses, phone, videoUpload }

// Owns the active SourceAdapter and re-broadcasts its streams, so callers
// don't need to know which adapter is live. Auto-falls back to phone if the
// active adapter reports disconnected.
class SourceManager extends ChangeNotifier {
  final Map<SourceType, SourceAdapter> _adapters;
  SourceType _activeType = SourceType.phone;
  SourceHealth _currentHealth = const SourceHealth(status: SourceHealthStatus.disconnected, message: 'Initialized');

  StreamSubscription<VideoFrame>? _videoSub;
  StreamSubscription<LocationSample>? _locationSub;
  StreamSubscription<SourceHealth>? _healthSub;

  final _videoController = StreamController<VideoFrame>.broadcast();
  final _locationController = StreamController<LocationSample>.broadcast();

  SourceManager(this._adapters) {
    _bindStreams(_adapters[_activeType]!);
  }

  SourceType get activeType => _activeType;
  SourceAdapter get activeAdapter => _adapters[_activeType]!;
  SourceAdapter adapterFor(SourceType type) => _adapters[type]!;
  SourceHealth get currentHealth => _currentHealth;

  Stream<VideoFrame> get videoStream => _videoController.stream;
  Stream<LocationSample> get locationStream => _locationController.stream;

  Future<void> switchSource(SourceType type) async {
    if (_activeType == type && activeAdapter.isActive) return;

    await activeAdapter.stop();
    _unbindStreams();

    _activeType = type;
    final nextAdapter = _adapters[type]!;

    _bindStreams(nextAdapter);
    await nextAdapter.start();

    notifyListeners();
  }

  void _bindStreams(SourceAdapter adapter) {
    _videoSub = adapter.videoStream.listen((frame) => _videoController.add(frame));
    _locationSub = adapter.locationStream.listen((sample) => _locationController.add(sample));
    _healthSub = adapter.healthStream.listen((health) {
      _currentHealth = health;
      notifyListeners();
      if (health.status == SourceHealthStatus.disconnected && _activeType != SourceType.phone) {
        switchSource(SourceType.phone);
      }
    });
  }

  void _unbindStreams() {
    _videoSub?.cancel();
    _locationSub?.cancel();
    _healthSub?.cancel();
  }

  Future<void> startActive() async => activeAdapter.start();
  Future<void> stopActive() async => activeAdapter.stop();
  void notifyFrameProcessed() => activeAdapter.notifyFrameProcessed();

  @override
  void dispose() {
    _unbindStreams();
    _videoController.close();
    _locationController.close();
    for (final adapter in _adapters.values) {
      adapter.stop();
    }
    super.dispose();
  }
}
