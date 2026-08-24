import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartpoc/interaction_engine/kaldi_fbank.dart';
import 'package:smartpoc/interaction_engine/speaker_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('KaldiFbank DSP Feature Extraction Tests', () {
    test('extractFeatures extracts (N, 80) filterbanks correctly from synthetic signal', () {
      // 1 second of 16kHz audio with 440Hz sine wave
      final sampleRate = 16000;
      final samples = Int16List(sampleRate);
      for (int i = 0; i < sampleRate; i++) {
        final t = i / sampleRate;
        final val = (math.sin(2 * math.pi * 440 * t) * 16000).toInt();
        samples[i] = val;
      }

      final feats = KaldiFbank.extractFeatures(samples, sampleRate);
      expect(feats, isNotEmpty);
      expect(feats.length % KaldiFbank.nMels, equals(0));

      final nFrames = feats.length ~/ KaldiFbank.nMels;
      expect(nFrames, greaterThan(25)); // Must be >= 25 frames for ECAPA embedding
    });

    test('extractFeatures returns empty on pure silence / short audio', () {
      final samples = Int16List(100); // Only 100 samples (~6ms), way below 25ms frame
      final feats = KaldiFbank.extractFeatures(samples, 16000);
      expect(feats.length, equals(0));
    });
  });

  group('SpeakerProfile Logic Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Profile initializes empty and isEnrolled is false', () async {
      final profile = SpeakerProfile(userId: 'test@example.com');
      await profile.load();
      expect(profile.isEnrolled, isFalse);
      expect(profile.meanEmbedding, isNull);
      expect(profile.embeddings, isEmpty);
    });

    test('Cosine similarity matches identical and orthogonal vectors', () {
      final a = [1.0, 0.0, 0.0];
      final b = [1.0, 0.0, 0.0];
      final c = [0.0, 1.0, 0.0];
      final d = [-1.0, 0.0, 0.0];

      expect(SpeakerProfile.cosineSimilarity(a, b), closeTo(1.0, 1e-5));
      expect(SpeakerProfile.cosineSimilarity(a, c), closeTo(0.0, 1e-5));
      expect(SpeakerProfile.cosineSimilarity(a, d), closeTo(-1.0, 1e-5));
    });

    test('Enrollment succeeds for first sample and enforces consistency for subsequent samples', () async {
      final profile = SpeakerProfile(userId: 'user_123');
      await profile.load();

      // Normalized 192-dim vector A
      final sampleA = List<double>.generate(192, (i) => i % 2 == 0 ? 0.1 : -0.1);
      final normA = math.sqrt(sampleA.fold(0.0, (sum, v) => sum + v * v));
      final normVecA = sampleA.map((v) => v / normA).toList();

      // 1. First sample should always succeed
      final res1 = profile.enrollFromSample(normVecA);
      expect(res1, equals('success'));
      expect(profile.isEnrolled, isTrue);
      expect(profile.embeddings.length, equals(1));

      // 2. Similar sample (high similarity) should succeed
      final sampleSimilar = List<double>.generate(192, (i) => normVecA[i] + (i % 3 == 0 ? 0.01 : -0.01));
      final normSim = math.sqrt(sampleSimilar.fold(0.0, (sum, v) => sum + v * v));
      final normVecSim = sampleSimilar.map((v) => v / normSim).toList();

      final res2 = profile.enrollFromSample(normVecSim);
      expect(res2, equals('success'));
      expect(profile.embeddings.length, equals(2));

      // 3. Inconsistent sample (orthogonal/negative similarity < 0.35) should be rejected
      final sampleOrthogonal = List<double>.generate(192, (i) => i % 2 == 0 ? -normVecA[i] : normVecA[i]);
      final normOrth = math.sqrt(sampleOrthogonal.fold(0.0, (sum, v) => sum + v * v));
      final normVecOrth = sampleOrthogonal.map((v) => v / normOrth).toList();

      final res3 = profile.enrollFromSample(normVecOrth);
      expect(res3, startsWith('inconsistent_with_profile'));
      expect(profile.embeddings.length, equals(2)); // Rejected, length remains 2
    });

    test('Classification properly returns user, other, or unknown', () async {
      final profile = SpeakerProfile(userId: 'test_user');
      await profile.load();

      final sample = List<double>.generate(192, (i) => 1.0 / math.sqrt(192));
      profile.enrollFromSample(sample);

      // Same speaker
      final (labelUser, simUser) = profile.classify(sample);
      expect(labelUser, equals('user'));
      expect(simUser, closeTo(1.0, 1e-4));

      // Dissimilar speaker (orthogonal vector)
      final sampleOther = List<double>.generate(192, (i) => (i < 96 ? 1.0 : -1.0) / math.sqrt(192));
      final (labelOther, simOther) = profile.classify(sampleOther);
      expect(labelOther, equals('other'));
      expect(simOther, lessThan(SpeakerProfile.otherSimThreshold));
    });

    test('Profile persists to SharedPreferences and reloads correctly', () async {
      final profile1 = SpeakerProfile(userId: 'persist_user');
      await profile1.load();

      final sample = List<double>.generate(192, (i) => (i + 1.0) / 192.0);
      final norm = math.sqrt(sample.fold(0.0, (s, v) => s + v * v));
      final normVec = sample.map((v) => v / norm).toList();

      profile1.enrollFromSample(normVec);
      expect(profile1.isEnrolled, isTrue);

      // New profile instance with same userId should load saved data
      final profile2 = SpeakerProfile(userId: 'persist_user');
      await profile2.load();
      expect(profile2.isEnrolled, isTrue);
      expect(profile2.embeddings.length, equals(1));
      expect(profile2.similarity(normVec), closeTo(1.0, 1e-4));
    });
  });
}
