import '../behaviour_engine/behaviour_engine_input.dart';

// Telemetry payload for the "telemetry" WS message - field names match
// IE_WebSocket_Voice_Stream_Reference.pdf / the working reference app's
// toInteractionRequest() exactly.
class InteractionTelemetry {
  final dynamic userId;
  final String sessionId;
  final String? behavioralState;
  final double? confidenceScore;
  final double? relevanceScore;
  final double? hesitationScore;
  final String? gazeTarget;
  final List<String> sceneObjects;
  final List<Map<String, dynamic>> topSalientObjects;
  final bool gateOpen;
  final double cpuTemp;
  final bool throttled;

  const InteractionTelemetry({
    this.userId,
    required this.sessionId,
    this.behavioralState,
    this.confidenceScore,
    this.relevanceScore,
    this.hesitationScore,
    this.gazeTarget,
    this.sceneObjects = const [],
    this.topSalientObjects = const [],
    this.gateOpen = true,
    this.cpuTemp = 34.0,
    this.throttled = false,
  });

  Map<String, dynamic> toJson() => {
    'user_id': userId ?? 0,
    'session_id': sessionId,
    'behavioral_state': behavioralState,
    'confidence_score': confidenceScore,
    'relevance_score': relevanceScore,
    'hesitation_score': hesitationScore ?? 0.0,
    'gaze_target': gazeTarget,
    'scene_objects': sceneObjects,
    'top_salient_objects': topSalientObjects,
    'gate_open': gateOpen,
    'cpu_temp': cpuTemp,
    'throttled': throttled,
  };
}

// Parses the voice_nlu object IE embeds in its "status" message
// (status.bcp.voice_nlu, or top-level status.voice_nlu /
// status.voice_assistant_response as fallbacks) - reuses BehaviourEngineInput's
// VoiceNlu since it's the exact shape BE expects back.
VoiceNlu? parseVoiceNlu(Map<String, dynamic> status) {
  final bcp = status['bcp'];
  final raw =
      (bcp is Map ? bcp['voice_nlu'] : null) ?? status['voice_nlu'] ?? status['voice_assistant_response'];
  if (raw is! Map) return null;
  final rhinoActive = raw['rhino_active'];
  if (rhinoActive != true) return null;
  return VoiceNlu(
    rhinoActive: true,
    activeIntent: raw['active_intent'] as String?,
    intentConfidence: (raw['intent_confidence'] as num?)?.toDouble(),
  );
}
