import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../app_logger.dart';

// Streams raw 16kHz mono PCM16 chunks (the IE TTS websocket's binary
// messages) through the Web Audio API, mirroring flutter_pcm_sound's
// queue-fed playback on native - flutter_pcm_sound has no web build, so
// without this the assistant's spoken responses were silently dropped on
// web (text/transcript still worked, audio never played).
class WebPcmPlayer {
  static const _sampleRate = 16000;

  web.AudioContext? _context;
  num _nextStartTime = 0;
  bool _isPlaying = false;
  final List<web.AudioBufferSourceNode> _activeNodes = [];

  Future<void> start() async {
    final context = _context ??= web.AudioContext();
    // Every AudioContext is born 'suspended' until explicitly resumed -
    // without this, buffer sources schedule fine but the context never
    // actually renders audio, so playback is silent with no error anywhere.
    if (context.state == 'suspended') {
      await context.resume().toDart;
    }
    _nextStartTime = context.currentTime;
    _isPlaying = true;
  }

  Future<void> feed(Uint8List pcm16Bytes) async {
    final context = _context;
    if (context == null || !_isPlaying) return;
    try {
      final aligned = pcm16Bytes.length % 2 == 0 ? pcm16Bytes : Uint8List.sublistView(pcm16Bytes, 0, pcm16Bytes.length - 1);
      final samples = aligned.buffer.asInt16List(aligned.offsetInBytes, aligned.length ~/ 2);
      final frameCount = samples.length;
      if (frameCount == 0) return;

      final floatSamples = Float32List(frameCount);
      for (var i = 0; i < frameCount; i++) {
        floatSamples[i] = samples[i] / 32768.0;
      }

      final buffer = context.createBuffer(1, frameCount, _sampleRate);
      buffer.copyToChannel(floatSamples.toJS, 0);

      final source = context.createBufferSource();
      source.buffer = buffer;
      source.connect(context.destination);

      final now = context.currentTime;
      final startAt = _nextStartTime > now ? _nextStartTime : now;
      source.start(startAt);
      _nextStartTime = startAt + frameCount / _sampleRate;

      _activeNodes.add(source);
      void onEnded(web.Event event) {
        _activeNodes.remove(source);
      }

      source.addEventListener('ended', onEnded.toJS);
    } catch (error) {
      AppLogger.log('IE_ERROR', 'WebPcmPlayer.feed failed: $error');
    }
  }

  // Called on audio_end: playback is scheduled ahead of real time (that's
  // what makes chunk-to-chunk output gapless), so when this fires there is
  // usually still unplayed audio sitting in the future - stopping nodes
  // immediately here would silently cut a short reply off before any of it
  // is heard. Wait for the scheduled tail to actually finish instead, same
  // as the native path waiting for FlutterPcmSound's queue to drain.
  Future<void> finish() async {
    _isPlaying = false;
    final context = _context;
    if (context != null) {
      final remainingMs = ((_nextStartTime - context.currentTime) * 1000).clamp(0, 4000);
      if (remainingMs > 0) await Future.delayed(Duration(milliseconds: remainingMs.round()));
    }
    _activeNodes.clear();
  }

  // Hard interrupt for barge-in/flush: unlike finish(), this deliberately
  // cuts off whatever is still scheduled right away.
  Future<void> stop() async {
    _isPlaying = false;
    for (final node in _activeNodes) {
      try {
        node.stop();
      } catch (_) {}
    }
    _activeNodes.clear();
    _nextStartTime = _context?.currentTime ?? 0;
  }

  void dispose() {
    unawaited(stop());
    _context?.close();
    _context = null;
  }
}
