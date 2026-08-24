import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../app_logger.dart';
import '../env_config.dart';
import 'context_engine_input.dart';

// Connects to the context engine, sends JSON + JPEG. Server replies with
// two separate messages per frame: a JSON result, then a processed JPEG.
class ContextEngineClient {
  final String contextEngineUrl;
  WebSocketChannel? _channel;

  Map<String, dynamic>? lastJsonOutput;
  Uint8List? lastImageOutput;

  // UI hooks into these to react without a Stream.
  void Function(Map<String, dynamic> jsonOutput)? onJsonOutput;
  void Function(Uint8List imageBytes)? onImageOutput;
  void Function(Object error)? onError;

  ContextEngineClient({String? contextEngineUrl})
    : contextEngineUrl = contextEngineUrl ?? EnvConfig.contextEngineUrl;

  Future<void> connect() async {
    AppLogger.log('CONNECT', contextEngineUrl);
    final channel = WebSocketChannel.connect(Uri.parse(contextEngineUrl));
    await channel.ready;
    _channel = channel;
    AppLogger.log('CONNECTED', contextEngineUrl);

    channel.stream.listen(
      (message) {
        if (message is String) {
          final jsonOutput = jsonDecode(message) as Map<String, dynamic>;
          lastJsonOutput = jsonOutput;
          AppLogger.log('RESPONSE_JSON', message);
          onJsonOutput?.call(jsonOutput);
        } else {
          final imageBytes = message as Uint8List;
          lastImageOutput = imageBytes;
          AppLogger.log('RESPONSE_IMAGE', '${imageBytes.length} bytes');
          onImageOutput?.call(imageBytes);
        }
      },
      onError: (Object error) {
        AppLogger.log('ERROR', '$error');
        onError?.call(error);
      },
    );
  }

  void sendFrame(ContextEngineInput input, Uint8List jpegBytes) {
    final channel = _channel;
    if (channel == null) return;
    final inputJson = jsonEncode(input.toJson());
    AppLogger.log('REQUEST_JSON', inputJson);
    AppLogger.log('REQUEST_IMAGE', '${jpegBytes.length} bytes');
    channel.sink.add(inputJson);
    channel.sink.add(jpegBytes);
  }

  Future<void> disconnect() async {
    AppLogger.log('DISCONNECT', contextEngineUrl);
    await _channel?.sink.close();
    _channel = null;
  }
}
