import 'dart:typed_data';

// Native builds play TTS audio via flutter_pcm_sound directly in
// InteractionEngineClient - this stub only exists so the same import line
// resolves on both platforms (see web_pcm_player_web.dart for the real one).
class WebPcmPlayer {
  Future<void> start() async {}

  Future<void> feed(Uint8List pcm16Bytes) async {}

  Future<void> finish() async {}

  Future<void> stop() async {}

  void dispose() {}
}
