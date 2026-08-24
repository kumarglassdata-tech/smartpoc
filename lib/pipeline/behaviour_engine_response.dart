// Parsed behaviour-engine /process response - only the fields later engines
// need. Response shape varies (commerce/lifestyle/motion-suppression per
// be_api_reference.md.pdf) - every field here is nullable since none of them
// appear in all three variants.

class BehaviourEngineSalientObject {
  final String? className;
  final double? salienceScore;

  const BehaviourEngineSalientObject({this.className, this.salienceScore});

  factory BehaviourEngineSalientObject.parse(Map<String, dynamic> json) =>
      BehaviourEngineSalientObject(
        className: json['class_name'] as String?,
        salienceScore: (json['salience_score'] as num?)?.toDouble(),
      );
}

class BehaviourEngineResponse {
  final String? frameType;
  final String? sessionId;
  final dynamic userId;
  final String? behavioralState;
  final String? recommendedProduct;
  final String? lifestyleCluster;
  final double? relevanceScore;
  final double? stateConfidence;
  final double? hesitationScore;
  final List<BehaviourEngineSalientObject> topSalientObjects;

  const BehaviourEngineResponse({
    this.frameType,
    this.sessionId,
    this.userId,
    this.behavioralState,
    this.recommendedProduct,
    this.lifestyleCluster,
    this.relevanceScore,
    this.stateConfidence,
    this.hesitationScore,
    this.topSalientObjects = const [],
  });

  factory BehaviourEngineResponse.parse(Map<String, dynamic> beOutput) {
    return BehaviourEngineResponse(
      frameType: beOutput['frame_type'] as String?,
      sessionId: beOutput['session_id'] as String?,
      userId: beOutput['user_id'],
      behavioralState: beOutput['behavioral_state'] as String?,
      recommendedProduct: beOutput['recommended_product'] as String?,
      lifestyleCluster: beOutput['lifestyle_cluster'] as String?,
      relevanceScore: (beOutput['relevance_score'] as num?)?.toDouble(),
      stateConfidence: (beOutput['state_confidence'] as num?)?.toDouble(),
      hesitationScore: (beOutput['hesitation_score'] as num?)?.toDouble(),
      topSalientObjects: (beOutput['top_salient_objects'] as List? ?? [])
          .whereType<Map>()
          .map((object) => BehaviourEngineSalientObject.parse(object.cast<String, dynamic>()))
          .toList(),
    );
  }
}
