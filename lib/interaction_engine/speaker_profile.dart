import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

class SpeakerProfile {
  final String userId;
  List<List<double>> embeddings = [];
  int? enrolledAt;

  static const double userSimThreshold = 0.32;
  static const double otherSimThreshold = 0.25;
  static const double enrollConsistencyMinSimilarity = 0.30;
  static const int maxEnrollSamples = 4;

  SpeakerProfile({required this.userId});

  String get _storageKey => 'speaker_profile_$userId';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    String? dataStr = prefs.getString(_storageKey);

    // Fallback/Migration: If not found under current key (e.g. numeric user_id),
    // check if there's any previously enrolled profile (e.g. saved under email)
    if (dataStr == null) {
      final allKeys = prefs.getKeys();
      for (final key in allKeys) {
        if (key.startsWith('speaker_profile_')) {
          final candidateStr = prefs.getString(key);
          if (candidateStr != null) {
            try {
              final parsed = jsonDecode(candidateStr) as Map<String, dynamic>;
              if (parsed['embeddings'] != null && (parsed['embeddings'] as List).isNotEmpty) {
                dataStr = candidateStr;
                // Persist under current key for future direct loads
                await prefs.setString(_storageKey, dataStr);
                break;
              }
            } catch (_) {}
          }
        }
      }
    }

    if (dataStr != null) {
      try {
        final data = jsonDecode(dataStr) as Map<String, dynamic>;
        if (data.containsKey('embeddings')) {
          final List dynamicList = data['embeddings'];
          embeddings = dynamicList.map((e) {
            final innerList = e as List;
            return innerList.map((v) => (v as num).toDouble()).toList();
          }).toList();
        }
        enrolledAt = data['enrolled_at'] as int?;
      } catch (_) {
        embeddings = [];
      }
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    final dataStr = jsonEncode({
      'user_id': userId,
      'embeddings': embeddings,
      'enrolled_at': enrolledAt,
    });
    await prefs.setString(_storageKey, dataStr);
  }

  bool get isEnrolled => embeddings.isNotEmpty;

  List<double>? get meanEmbedding {
    if (embeddings.isEmpty) return null;
    final dim = embeddings[0].length;
    final mean = List<double>.filled(dim, 0.0);
    for (final emb in embeddings) {
      for (int i = 0; i < dim; i++) {
        mean[i] += emb[i];
      }
    }
    double norm = 0.0;
    for (int i = 0; i < dim; i++) {
      mean[i] /= embeddings.length;
      norm += mean[i] * mean[i];
    }
    norm = math.sqrt(norm);
    if (norm > 1e-6) {
      for (int i = 0; i < dim; i++) {
        mean[i] /= norm;
      }
    }
    return mean;
  }

  static double cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;
    double dot = 0.0, normA = 0.0, normB = 0.0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    final denom = math.sqrt(normA) * math.sqrt(normB);
    return denom < 1e-9 ? 0.0 : dot / denom;
  }

  double similarity(List<double>? candidate) {
    final ref = meanEmbedding;
    if (ref == null || candidate == null) return 0.0;
    return cosineSimilarity(ref, candidate);
  }

  String enrollFromSample(List<double>? emb) {
    if (emb == null) return "too_short_or_unembeddable";

    if (embeddings.isNotEmpty) {
      final sim = similarity(emb);
      if (sim < enrollConsistencyMinSimilarity) {
        return "inconsistent_with_profile (sim=${sim.toStringAsFixed(3)})";
      }
    }

    embeddings.add(emb);
    if (embeddings.length > maxEnrollSamples) {
      embeddings = embeddings.sublist(embeddings.length - maxEnrollSamples);
    }
    enrolledAt ??= DateTime.now().millisecondsSinceEpoch;
    save();
    return "success";
  }

  (String label, double sim) classify(List<double>? emb) {
    if (emb == null || !isEnrolled) return ("unknown", 0.0);
    final sim = similarity(emb);
    if (sim >= userSimThreshold) return ("user", sim);
    if (sim < otherSimThreshold) return ("other", sim);
    return ("unknown", sim);
  }
}
