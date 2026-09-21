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
  final bool? gateOpen;
  final double? commerceScore;
  final String? suppressReason;
  final String? eligibilityBlockedReason;
  final String? eligibilityStatus;
  final bool? eligibleLifestyleException;
  final bool? objectCommerceEligible;
  final num? eligibilityScore;
  final List<BehaviourEngineSalientObject> topSalientObjects;
  final List<dynamic>? attributionBreakdown;
  final num? compositeAttributionScore;
  final bool? eligibilityBlocked;
  final String? blockedReason;
  final Map<String, dynamic> rawJson;

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
    this.gateOpen,
    this.commerceScore,
    this.suppressReason,
    this.eligibilityBlockedReason,
    this.eligibilityStatus,
    this.eligibleLifestyleException,
    this.objectCommerceEligible,
    this.eligibilityScore,
    this.topSalientObjects = const [],
    this.attributionBreakdown,
    this.compositeAttributionScore,
    this.eligibilityBlocked,
    this.blockedReason,
    this.rawJson = const {},
  });

  factory BehaviourEngineResponse.parse(Map<String, dynamic> beOutput) {
    final frameType = beOutput['frame_type'] as String?;
    final gateOpen = beOutput['gate_open'] as bool? ??
        beOutput['ie_commerce_eligibility']?['gate_open'] as bool?;
    final commerceScore = (beOutput['commerce_score'] ??
            beOutput['ie_commerce_eligibility']?['commerce_score'] ??
            beOutput['score'] ??
            beOutput['eligibility_score'])
        ?.toDouble();
    final suppressReason = beOutput['suppress_reason']?.toString() ??
        beOutput['blocked_reason']?.toString();
    final eligibilityBlockedReason =
        beOutput['eligibility_blocked_reason']?.toString();
    final eligibilityStatus = beOutput['eligibility_status']?.toString() ??
        beOutput['ie_commerce_eligibility']?['status']?.toString();
    final eligibleLifestyleException =
        beOutput['eligible_lifestyle_exception'] as bool?;
    final objectCommerceEligible =
        beOutput['object_commerce_eligible'] as bool? ??
            beOutput['ie_commerce_eligibility']?['commerce_eligible'] as bool?;
    final eligibilityScore = (beOutput['eligibility_score'] ??
        beOutput['composite_attribution_score'] ??
        beOutput['ie_commerce_eligibility']?['eligibility_score']) as num?;

    return BehaviourEngineResponse(
      frameType: frameType,
      sessionId: beOutput['session_id'] as String?,
      userId: beOutput['user_id'],
      behavioralState: beOutput['behavioral_state'] as String?,
      recommendedProduct: beOutput['recommended_product'] as String?,
      lifestyleCluster: beOutput['lifestyle_cluster'] as String?,
      relevanceScore: (beOutput['relevance_score'] as num?)?.toDouble(),
      stateConfidence: (beOutput['state_confidence'] as num?)?.toDouble(),
      hesitationScore: (beOutput['hesitation_score'] as num?)?.toDouble(),
      gateOpen: gateOpen,
      commerceScore: commerceScore,
      suppressReason: suppressReason,
      eligibilityBlockedReason: eligibilityBlockedReason,
      eligibilityStatus: eligibilityStatus,
      eligibleLifestyleException: eligibleLifestyleException,
      objectCommerceEligible: objectCommerceEligible,
      eligibilityScore: eligibilityScore,
      topSalientObjects: (beOutput['top_salient_objects'] as List? ?? [])
          .whereType<Map>()
          .map((object) => BehaviourEngineSalientObject.parse(object.cast<String, dynamic>()))
          .toList(),
      attributionBreakdown: beOutput['attribution_breakdown'] as List<dynamic>? ??
          beOutput['eligibility_attribution'] as List<dynamic>? ??
          beOutput['ie_commerce_eligibility']?['attribution_breakdown'] as List<dynamic>? ??
          beOutput['attribution'] as List<dynamic>?,
      compositeAttributionScore: (beOutput['composite_attribution_score'] ??
          beOutput['composite_score'] ??
          eligibilityScore) as num?,
      eligibilityBlocked: beOutput['eligibility_blocked'] as bool? ??
          beOutput['blocked'] as bool? ??
          (eligibilityStatus == 'blocked' || eligibilityBlockedReason != null),
      blockedReason: suppressReason ?? eligibilityBlockedReason,
      rawJson: beOutput,
    );
  }
}
