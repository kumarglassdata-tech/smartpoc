import 'dart:math' as math;
import 'dart:typed_data';

class KaldiFbank {
  static const double preemphCoeff = 0.97;
  static const int nMels = 80;

  static double _hzToMel(double hz) {
    return 2595.0 * math.log(1.0 + hz / 700.0) / math.ln10;
  }

  static List<List<double>> _kaldiMelFilterbank(
      int nMels, int nFft, int sampleRate,
      {double lowFreq = 20.0, double highFreq = 0.0}) {
    final double nyquist = 0.5 * sampleRate;
    if (highFreq <= 0.0) {
      highFreq = nyquist + highFreq;
    }
    final int numFftBins = nFft ~/ 2;
    final double fftBinWidth = sampleRate.toDouble() / nFft;
    final double melLow = _hzToMel(lowFreq);
    final double melHigh = _hzToMel(highFreq);
    final double melDelta = (melHigh - melLow) / (nMels + 1);

    final melOfBin = List<double>.generate(
        numFftBins, (i) => _hzToMel(fftBinWidth * i));

    final fbank = List.generate(nMels, (_) => List<double>.filled(numFftBins, 0.0));

    for (int m = 0; m < nMels; m++) {
      final double left = melLow + m * melDelta;
      final double center = left + melDelta;
      final double right = left + 2.0 * melDelta;

      for (int i = 0; i < numFftBins; i++) {
        final double mel = melOfBin[i];
        final double rising = (mel - left) / (center - left);
        final double falling = (right - mel) / (right - center);
        fbank[m][i] = math.max(0.0, math.min(rising, falling));
      }
    }
    return fbank;
  }

  // Basic Radix-2 FFT (Out-of-place for power spectrum)
  static List<double> _powerSpectrum(List<double> realInput) {
    int n = realInput.length;
    int nFft = 1;
    while (nFft < n) nFft *= 2;

    List<double> real = List.filled(nFft, 0.0);
    List<double> imag = List.filled(nFft, 0.0);
    for (int i = 0; i < n; i++) real[i] = realInput[i];

    // Bit reversal
    int j = 0;
    for (int i = 0; i < nFft - 1; i++) {
      if (i < j) {
        double tr = real[i];
        double ti = imag[i];
        real[i] = real[j];
        imag[i] = imag[j];
        real[j] = tr;
        imag[j] = ti;
      }
      int k = nFft ~/ 2;
      while (k <= j) {
        j -= k;
        k ~/= 2;
      }
      j += k;
    }

    // Cooley-Tukey
    for (int l = 1; l <= (math.log(nFft) / math.ln2).round(); l++) {
      int m = 1 << l;
      double wmReal = math.cos(-2.0 * math.pi / m);
      double wmImag = math.sin(-2.0 * math.pi / m);

      for (int k = 0; k < nFft; k += m) {
        double wReal = 1.0;
        double wImag = 0.0;
        for (int i = 0; i < m ~/ 2; i++) {
          double tReal = wReal * real[k + i + m ~/ 2] - wImag * imag[k + i + m ~/ 2];
          double tImag = wReal * imag[k + i + m ~/ 2] + wImag * real[k + i + m ~/ 2];
          double uReal = real[k + i];
          double uImag = imag[k + i];
          real[k + i] = uReal + tReal;
          imag[k + i] = uImag + tImag;
          real[k + i + m ~/ 2] = uReal - tReal;
          imag[k + i + m ~/ 2] = uImag - tImag;
          double nextWReal = wReal * wmReal - wImag * wmImag;
          double nextWImag = wReal * wmImag + wImag * wmReal;
          wReal = nextWReal;
          wImag = nextWImag;
        }
      }
    }

    List<double> power = List.filled(nFft ~/ 2, 0.0);
    for (int i = 0; i < power.length; i++) {
      power[i] = real[i] * real[i] + imag[i] * imag[i];
    }
    return power;
  }

  static Float32List extractFeatures(Int16List samples, int sampleRate) {
    // 1. Trim silence (top_db = 30)
    final trimmed = _trimSilence(samples);

    final int frameLen = (sampleRate * 0.025).round();
    final int hopLen = (sampleRate * 0.010).round();

    if (trimmed.length < frameLen) {
      return Float32List(0);
    }

    final int nFrames = 1 + (trimmed.length - frameLen) ~/ hopLen;
    int nFft = 1;
    while (nFft < frameLen) nFft *= 2;
    
    final fbank = _kaldiMelFilterbank(nMels, nFft, sampleRate);
    final List<List<double>> feats = [];

    // Hamming window
    final hamming = List<double>.generate(
        frameLen, (i) => 0.54 - 0.46 * math.cos(2.0 * math.pi * i / (frameLen - 1)));

    for (int i = 0; i < nFrames; i++) {
      final int start = i * hopLen;
      List<double> frame = List.filled(frameLen, 0.0);
      for (int j = 0; j < frameLen; j++) {
        // Kaldi scales to float32 domain around -32768 to 32767
        frame[j] = trimmed[start + j].toDouble();
      }

      // Remove DC
      double mean = 0.0;
      for (int j = 0; j < frameLen; j++) mean += frame[j];
      mean /= frameLen;
      for (int j = 0; j < frameLen; j++) frame[j] -= mean;

      // Preemphasis (replicate pad on left)
      List<double> preemph = List.filled(frameLen, 0.0);
      preemph[0] = frame[0] - preemphCoeff * frame[0];
      for (int j = 1; j < frameLen; j++) {
        preemph[j] = frame[j] - preemphCoeff * frame[j - 1];
      }

      // Window
      for (int j = 0; j < frameLen; j++) {
        preemph[j] *= hamming[j];
      }

      // FFT Power
      final power = _powerSpectrum(preemph);

      // Mel filterbank
      List<double> mel = List.filled(nMels, 0.0);
      for (int m = 0; m < nMels; m++) {
        for (int k = 0; k < nFft ~/ 2; k++) {
          mel[m] += power[k] * fbank[m][k];
        }
      }

      // Log
      for (int m = 0; m < nMels; m++) {
        mel[m] = math.log(math.max(mel[m], 1e-7)); 
      }
      feats.add(mel);
    }

    // CMN (Cepstral Mean Normalization)
    if (feats.isNotEmpty) {
      List<double> mean = List.filled(nMels, 0.0);
      for (int i = 0; i < nFrames; i++) {
        for (int m = 0; m < nMels; m++) {
          mean[m] += feats[i][m];
        }
      }
      for (int m = 0; m < nMels; m++) {
        mean[m] /= nFrames;
      }
      for (int i = 0; i < nFrames; i++) {
        for (int m = 0; m < nMels; m++) {
          feats[i][m] -= mean[m];
        }
      }
    }

    // Flatten for ONNX (T, 80)
    final flatFeats = Float32List(nFrames * nMels);
    int idx = 0;
    for (int i = 0; i < nFrames; i++) {
      for (int m = 0; m < nMels; m++) {
        flatFeats[idx++] = feats[i][m];
      }
    }
    return flatFeats;
  }

  static Int16List _trimSilence(Int16List samples,
      {double topDb = 40.0, int frameLength = 2048, int hopLength = 512}) {
    if (samples.length < frameLength) return samples;
    final int nFrames = 1 + (samples.length - frameLength) ~/ hopLength;
    List<double> rms = List.filled(nFrames, 0.0);
    double peak = 0.0;

    for (int i = 0; i < nFrames; i++) {
      final int start = i * hopLength;
      double sumSq = 0.0;
      for (int j = 0; j < frameLength; j++) {
        final val = samples[start + j].toDouble();
        sumSq += val * val;
      }
      rms[i] = math.sqrt((sumSq / frameLength) + 1e-12);
      if (rms[i] > peak) peak = rms[i];
    }

    if (peak <= 0.0) return samples;

    int firstVoiced = -1;
    int lastVoiced = -1;

    for (int i = 0; i < nFrames; i++) {
      final double db = 20.0 * math.log(rms[i] / peak + 1e-12) / math.ln10;
      if (db > -topDb) {
        if (firstVoiced == -1) firstVoiced = i;
        lastVoiced = i;
      }
    }

    if (firstVoiced == -1) return samples;

    final int startIdx = firstVoiced * hopLength;
    final int endIdx = math.min(samples.length, lastVoiced * hopLength + frameLength);
    return Int16List.sublistView(samples, startIdx, endIdx);
  }
}
