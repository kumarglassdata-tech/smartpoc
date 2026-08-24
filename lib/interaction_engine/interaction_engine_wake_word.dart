import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

const int _windowSamples = 32000; // 2.0s @ 16kHz
const int _inferenceIntervalSamples = 4000; // ~250ms @ 16kHz
const int _melBins = 32;
const int _embeddingWindow = 76;
const int _embeddingStride = 8;
const int _embeddingDim = 96;
const int _minEmbeddings = 16;

// "Hey Myna" wake-word pipeline (melspectrogram -> speech embedding ->
// classifier, all ONNX) over a rolling 2s audio window. Ported from the
// working reference app - same models, same tuned constants.
class WakeWordDetector {
  OrtSession? _melSession;
  OrtSession? _embeddingSession;
  OrtSession? _classifierSession;

  final Int16List _window = Int16List(_windowSamples);
  int _samplesSinceInference = 0;
  bool _inferencing = false;
  bool _disposed = false;
  DateTime? _lastFiredAt;

  // Reverted to the bundled hey_mynaa.onnx model's tuned/validated threshold -
  // lowering to 0.25 made it trigger without the wake phrase being said at
  // all (false positives), a worse problem than the under-triggering it was
  // meant to fix.
  final double threshold = 0.35;
  final Duration debounce = const Duration(seconds: 2);

  final _scoreController = StreamController<double>.broadcast();
  Stream<double> get scoreStream => _scoreController.stream;

  final _detectedController = StreamController<double>.broadcast();
  Stream<double> get detectedStream => _detectedController.stream;

  Future<void> init() async {
    final ort = OnnxRuntime();
    _melSession = await ort.createSessionFromAsset('assets/models/melspectrogram.onnx');
    _embeddingSession = await ort.createSessionFromAsset('assets/models/embedding_model.onnx');
    _classifierSession = await ort.createSessionFromAsset('assets/models/hey_mynaa.onnx');
  }

  // Feeds raw mic samples into the rolling 2s window - cheap, safe on every
  // mic chunk. Triggers a pipeline run roughly every ~250ms of new audio.
  void processChunk(Int16List samples) {
    if (_melSession == null || _disposed) return;
    final n = samples.length;
    if (n >= _windowSamples) {
      _window.setRange(0, _windowSamples, samples, n - _windowSamples);
    } else {
      _window.setRange(0, _windowSamples - n, _window, n);
      _window.setRange(_windowSamples - n, _windowSamples, samples);
    }

    _samplesSinceInference += n;
    if (_samplesSinceInference >= _inferenceIntervalSamples && !_inferencing) {
      _samplesSinceInference = 0;
      _inferencing = true;
      _runInference().catchError((Object e) {
        debugPrint('[WakeWordDetector] Inference error: $e');
      }).whenComplete(() => _inferencing = false);
    }
  }

  Future<void> _runInference() async {
    final melSession = _melSession;
    final embeddingSession = _embeddingSession;
    final classifierSession = _classifierSession;
    if (melSession == null || embeddingSession == null || classifierSession == null || _disposed) return;

    // Normalize int16 PCM to [-1, 1] float32 - the mel model expects this,
    // unlike Silero VAD's raw-magnitude convention.
    final audio = Float32List(_windowSamples);
    for (int i = 0; i < _windowSamples; i++) {
      audio[i] = _window[i] / 32768.0;
    }

    final melInput = await OrtValue.fromList(audio, [1, _windowSamples]);
    Float32List melFlat;
    try {
      final melOutputs = await melSession.run({melSession.inputNames.first: melInput});
      final melOutput = melOutputs[melSession.outputNames.first]!;
      try {
        final raw = await melOutput.asFlattenedList();
        melFlat = Float32List(raw.length);
        for (int i = 0; i < raw.length; i++) {
          melFlat[i] = (raw[i] as num) / 10.0 + 2.0;
        }
      } finally {
        await melOutput.dispose();
      }
    } finally {
      await melInput.dispose();
    }

    final timeFrames = melFlat.length ~/ _melBins;
    if (timeFrames < _embeddingWindow || _disposed) return;

    final embeddings = <Float32List>[];
    for (int start = 0; start + _embeddingWindow <= timeFrames; start += _embeddingStride) {
      // Re-checked every iteration, not just once - dispose() can land mid-loop
      // (this can run a dozen-plus native calls per cycle), and continuing to
      // call .run() on a session that's being closed is what crashes natively
      // (JNI abort, uncatchable from Dart) rather than throwing a Dart error.
      if (_disposed) return;
      final windowView = Float32List.sublistView(melFlat, start * _melBins, (start + _embeddingWindow) * _melBins);
      final embInput = await OrtValue.fromList(windowView, [1, _embeddingWindow, _melBins, 1]);
      try {
        final embOutputs = await embeddingSession.run({embeddingSession.inputNames.first: embInput});
        final embOutput = embOutputs[embeddingSession.outputNames.first]!;
        try {
          final raw = await embOutput.asFlattenedList();
          embeddings.add(Float32List.fromList(raw.map((e) => (e as num).toDouble()).toList()));
        } finally {
          await embOutput.dispose();
        }
      } finally {
        await embInput.dispose();
      }
    }

    if (embeddings.length < _minEmbeddings || _disposed) return;
    final last16 = embeddings.sublist(embeddings.length - _minEmbeddings);

    final classifierInput = Float32List(_minEmbeddings * _embeddingDim);
    for (int i = 0; i < _minEmbeddings; i++) {
      classifierInput.setRange(i * _embeddingDim, (i + 1) * _embeddingDim, last16[i]);
    }

    final clsInput = await OrtValue.fromList(classifierInput, [1, _minEmbeddings, _embeddingDim]);
    double score;
    try {
      final clsOutputs = await classifierSession.run({classifierSession.inputNames.first: clsInput});
      final clsOutput = clsOutputs[classifierSession.outputNames.first]!;
      try {
        final raw = await clsOutput.asFlattenedList();
        score = (raw.first as num).toDouble();
      } finally {
        await clsOutput.dispose();
      }
    } finally {
      await clsInput.dispose();
    }

    if (_scoreController.hasListener) _scoreController.add(score);

    final now = DateTime.now();
    final canFire = _lastFiredAt == null || now.difference(_lastFiredAt!) >= debounce;
    if (score >= threshold && canFire) {
      _lastFiredAt = now;
      if (_detectedController.hasListener) _detectedController.add(score);
    }
  }

  // Zeroes the rolling window - call when the mic stream restarts so stale
  // audio from before a gap isn't treated as continuous.
  void reset() {
    _window.fillRange(0, _windowSamples, 0);
    _samplesSinceInference = 0;
  }

  Future<void> dispose() async {
    // Flip this before closing anything, then give an in-flight _runInference()
    // a moment to notice and bail via its own _disposed checks - closing a
    // session out from under a live .run() call is a native JNI abort, not a
    // catchable Dart exception (this is the documented flutter_onnxruntime
    // dispose-during-inference race).
    _disposed = true;
    var waited = 0;
    while (_inferencing && waited < 2000) {
      await Future.delayed(const Duration(milliseconds: 20));
      waited += 20;
    }
    await _melSession?.close();
    await _embeddingSession?.close();
    await _classifierSession?.close();
    await _scoreController.close();
    await _detectedController.close();
  }
}
