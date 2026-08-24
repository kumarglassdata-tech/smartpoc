import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:flutter/foundation.dart';

import 'kaldi_fbank.dart';

class SpeakerVerificationClient {
  OrtSession? _session;
  bool _isInit = false;

  Future<void> init() async {
    if (_isInit) return;
    try {
      final ort = OnnxRuntime();
      _session = await ort.createSessionFromAsset('assets/models/voxceleb_ECAPA512.onnx');
      _isInit = true;
    } catch (e) {
      debugPrint('Error initializing SpeakerVerificationClient: $e');
    }
  }

  Future<List<double>?> extractEmbedding(Int16List pcmData, {int sampleRate = 16000}) async {
    if (!_isInit || _session == null) {
      return null;
    }

    final feats = KaldiFbank.extractFeatures(pcmData, sampleRate);
    if (feats.isEmpty) {
      return null;
    }

    final int nFrames = feats.length ~/ KaldiFbank.nMels;
    if (nFrames < 25) { // MIN_EMBED_FRAMES (~250ms)
      return null;
    }

    try {
      final inputName = _session!.inputNames.first;
      final ortInput = await OrtValue.fromList(feats, [1, nFrames, KaldiFbank.nMels]);

      final outputs = await _session!.run({inputName: ortInput});
      final outputName = _session!.outputNames.first;
      final ortOutput = outputs[outputName]!;

      final rawList = await ortOutput.asFlattenedList();
      
      await ortInput.dispose();
      await ortOutput.dispose();

      final List<double> vec = rawList.map((e) => (e as num).toDouble()).toList();
      
      // L2 Normalize
      double norm = 0.0;
      for (final v in vec) {
        norm += v * v;
      }
      norm = math.sqrt(norm);
      if (norm > 1e-6) {
        for (int i = 0; i < vec.length; i++) {
          vec[i] /= norm;
        }
      }
      return vec;
    } catch (e) {
      debugPrint('Error extracting embedding: $e');
      return null;
    }
  }

  void dispose() {
    // ONNX session cleanup is managed by OnnxRuntime natively if needed,
    // though flutter_onnxruntime doesn't strictly require session disposal 
    // unless explicitly supported.
  }
}
