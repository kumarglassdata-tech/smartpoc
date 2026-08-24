// POST body for /inp and /recommend - the ecom hub's GET endpoints
// (/buy, /recommend, /analyze, /lifebalance) take no parameters at all; the
// server already has context from the /inp POST. Verified against a known
// working reference implementation (C:\Dev\smartglass_flutter).
class SalientObject {
  final String className;
  final double salienceScore;

  const SalientObject({required this.className, required this.salienceScore});

  Map<String, dynamic> toJson() => {'class_name': className, 'salience_score': salienceScore};
}

class EcomHubInput {
  final int timestampMs;
  final double relevanceScore;
  final List<SalientObject> topSalientObjects;
  final dynamic userId;

  const EcomHubInput({
    required this.timestampMs,
    required this.relevanceScore,
    this.topSalientObjects = const [],
    this.userId,
  });

  Map<String, dynamic> toJson() => {
    'timestamp_ms': timestampMs,
    'relevance_score': relevanceScore,
    'top_salient_objects': topSalientObjects.map((object) => object.toJson()).toList(),
    'context_overrides': const {},
    if (userId != null) 'user_id': userId,
  };
}
