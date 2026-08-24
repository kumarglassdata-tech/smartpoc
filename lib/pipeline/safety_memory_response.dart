// Parsed Memory Safety Agent /inp response (MSEAPI.pdf v3).
class SafetyMemoryResponse {
  final bool hazardDetected;
  final String? hazardLevel;
  final String? triggerType;
  final String? triggerObject;
  final String? utterance;

  const SafetyMemoryResponse({
    this.hazardDetected = false,
    this.hazardLevel,
    this.triggerType,
    this.triggerObject,
    this.utterance,
  });

  factory SafetyMemoryResponse.parse(Map<String, dynamic> smaOutput) => SafetyMemoryResponse(
    hazardDetected: smaOutput['hazard_detected'] as bool? ?? false,
    hazardLevel: smaOutput['hazard_level'] as String?,
    triggerType: smaOutput['trigger_type'] as String?,
    triggerObject: smaOutput['trigger_object'] as String?,
    utterance: smaOutput['utterance'] as String?,
  );
}
