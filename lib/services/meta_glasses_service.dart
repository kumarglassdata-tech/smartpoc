import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum MetaGlassesStatus {
  disconnected,
  registering,
  registered,
  connecting,
  connected,
  streaming,
  error,
}

class MetaGlassesService {
  static final MetaGlassesService instance = MetaGlassesService._internal();

  MetaGlassesService._internal() {
    _initChannels();
  }

  static const MethodChannel _methodChannel = MethodChannel('com.smartpoc.app/meta_glasses');
  static const EventChannel _eventsChannel = EventChannel('com.smartpoc.app/meta_glasses/events');
  static const EventChannel _framesChannel = EventChannel('com.smartpoc.app/meta_glasses/frames');

  final ValueNotifier<MetaGlassesStatus> statusNotifier = ValueNotifier<MetaGlassesStatus>(MetaGlassesStatus.disconnected);
  final ValueNotifier<String?> statusMessageNotifier = ValueNotifier<String?>(null);
  final ValueNotifier<List<String>> discoveredDevicesNotifier = ValueNotifier<List<String>>(<String>[]);
  final ValueNotifier<String?> connectedDeviceNameNotifier = ValueNotifier<String?>(null);
  final ValueNotifier<Uint8List?> currentFrameNotifier = ValueNotifier<Uint8List?>(null);

  final StreamController<Uint8List> _frameStreamController = StreamController<Uint8List>.broadcast();

  Stream<Uint8List> get frameStream => _frameStreamController.stream;
  bool get isStreaming => statusNotifier.value == MetaGlassesStatus.streaming;
  bool get isConnected =>
      statusNotifier.value == MetaGlassesStatus.connected ||
      statusNotifier.value == MetaGlassesStatus.streaming;

  void _initChannels() {
    // Listen to device and state events
    _eventsChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is Map) {
          final type = event['type']?.toString();
          switch (type) {
            case 'registration_state':
              final state = event['state']?.toString();
              if (state == 'REGISTERED' || state == 'AVAILABLE') {
                if (statusNotifier.value == MetaGlassesStatus.disconnected ||
                    statusNotifier.value == MetaGlassesStatus.registering) {
                  statusNotifier.value = MetaGlassesStatus.registered;
                  statusMessageNotifier.value = 'Meta DAT Registered';
                }
              }
              break;

            case 'devices_updated':
              final rawList = event['devices'];
              if (rawList is List) {
                final devices = rawList.map((e) => e.toString()).toList();
                discoveredDevicesNotifier.value = devices;
                if (devices.isNotEmpty &&
                    (statusNotifier.value == MetaGlassesStatus.disconnected ||
                        statusNotifier.value == MetaGlassesStatus.registered)) {
                  statusNotifier.value = MetaGlassesStatus.connected;
                  statusMessageNotifier.value = '${devices.length} Glasses Found';
                }
              }
              break;

            case 'device_metadata':
              final linkState = event['linkState']?.toString();
              final deviceName = event['name']?.toString() ?? 'Ray-Ban Meta';
              connectedDeviceNameNotifier.value = deviceName;
              if (linkState == 'CONNECTED') {
                if (statusNotifier.value != MetaGlassesStatus.streaming) {
                  statusNotifier.value = MetaGlassesStatus.connected;
                }
                statusMessageNotifier.value = '$deviceName Ready';
              }
              break;

            case 'stream_state':
              final state = event['state']?.toString();
              if (state == 'STREAMING') {
                statusNotifier.value = MetaGlassesStatus.streaming;
                statusMessageNotifier.value = 'Streaming live video';
              } else if (state == 'STOPPED') {
                if (statusNotifier.value == MetaGlassesStatus.streaming) {
                  statusNotifier.value = MetaGlassesStatus.connected;
                  statusMessageNotifier.value = 'Stream stopped';
                }
              }
              break;

            case 'camera_permission':
              final granted = event['granted'] == true;
              if (!granted) {
                statusNotifier.value = MetaGlassesStatus.error;
                statusMessageNotifier.value = 'Camera permission denied on Meta View';
              }
              break;

            case 'error':
              final message = event['message']?.toString() ?? 'Unknown error';
              statusMessageNotifier.value = message;
              break;
          }
        }
      },
      onError: (dynamic error) {
        debugPrint('[MetaGlassesService] Events stream error: $error');
      },
    );

    // Listen to high-speed JPEG frame stream
    _framesChannel.receiveBroadcastStream().listen(
      (dynamic frameData) {
        if (frameData is Uint8List) {
          currentFrameNotifier.value = frameData;
          _frameStreamController.add(frameData);
        }
      },
      onError: (dynamic error) {
        debugPrint('[MetaGlassesService] Frames stream error: $error');
      },
    );
  }

  Future<bool> startRegistration() async {
    try {
      statusNotifier.value = MetaGlassesStatus.registering;
      statusMessageNotifier.value = 'Opening Meta View registration...';
      final res = await _methodChannel.invokeMethod<bool>('startRegistration');
      return res ?? false;
    } catch (e) {
      statusNotifier.value = MetaGlassesStatus.error;
      statusMessageNotifier.value = 'Registration error: $e';
      return false;
    }
  }

  Future<bool> checkCameraPermission() async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('checkCameraPermission');
      return res ?? false;
    } catch (e) {
      debugPrint('[MetaGlassesService] checkCameraPermission error: $e');
      return false;
    }
  }

  Future<bool> requestCameraPermission() async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('requestCameraPermission');
      return res ?? false;
    } catch (e) {
      debugPrint('[MetaGlassesService] requestCameraPermission error: $e');
      return false;
    }
  }

  Future<bool> checkMicrophonePermission() async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('checkMicrophonePermission');
      return res ?? false;
    } catch (e) {
      debugPrint('[MetaGlassesService] checkMicrophonePermission error: $e');
      return false;
    }
  }

  Future<bool> requestMicrophonePermission() async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('requestMicrophonePermission');
      return res ?? false;
    } catch (e) {
      debugPrint('[MetaGlassesService] requestMicrophonePermission error: $e');
      return false;
    }
  }

  Future<List<String>> getDiscoveredDevices() async {
    try {
      final res = await _methodChannel.invokeListMethod<String>('getDiscoveredDevices');
      final list = res ?? <String>[];
      discoveredDevicesNotifier.value = list;
      return list;
    } catch (e) {
      debugPrint('[MetaGlassesService] getDiscoveredDevices error: $e');
      return <String>[];
    }
  }

  Future<bool> startCameraStream() async {
    try {
      statusNotifier.value = MetaGlassesStatus.connecting;
      statusMessageNotifier.value = 'Connecting to Ray-Ban Meta glasses...';
      final res = await _methodChannel.invokeMethod<bool>('startCameraStream');
      if (res == true) {
        statusNotifier.value = MetaGlassesStatus.streaming;
        statusMessageNotifier.value = 'Live stream connected';
        return true;
      }
      return false;
    } catch (e) {
      statusNotifier.value = MetaGlassesStatus.error;
      statusMessageNotifier.value = 'Connection error: $e';
      return false;
    }
  }

  Future<bool> stopCameraStream() async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('stopCameraStream');
      if (statusNotifier.value == MetaGlassesStatus.streaming) {
        statusNotifier.value = MetaGlassesStatus.connected;
        statusMessageNotifier.value = 'Stream stopped';
      }
      return res ?? false;
    } catch (e) {
      debugPrint('[MetaGlassesService] stopCameraStream error: $e');
      return false;
    }
  }
}
