// Request payload for POST {behaviourEnginePostUrl} (Behavioral Context
// Payload). Field names match be_api_reference.md.pdf exactly. Optional
// fields are omitted from toJson() when null/empty so BE's own fallback
// chains (documented in that PDF) can resolve them instead of us sending
// a worse value that outranks a better fallback.

class GazeCoordinates {
  final double x;
  final double y;

  const GazeCoordinates({required this.x, required this.y});

  Map<String, dynamic> toJson() => {'x': x, 'y': y};
}

class GazeGrounding {
  final String? groundedTarget;
  final GazeCoordinates? gazeCoordinates;
  final double? alignmentScore;
  final double? spatialProximityPx;

  const GazeGrounding({
    this.groundedTarget,
    this.gazeCoordinates,
    this.alignmentScore,
    this.spatialProximityPx,
  });

  Map<String, dynamic> toJson() => {
    if (groundedTarget != null) 'grounded_target': groundedTarget,
    if (gazeCoordinates != null) 'gaze_coordinates': gazeCoordinates!.toJson(),
    if (alignmentScore != null) 'alignment_score': alignmentScore,
    if (spatialProximityPx != null) 'spatial_proximity_px': spatialProximityPx,
  };
}

class SceneObject {
  final String? objectId;
  final String? className;
  final List<double>? bboxXyxy;
  final String? description;

  const SceneObject({this.objectId, this.className, this.bboxXyxy, this.description});

  Map<String, dynamic> toJson() => {
    if (objectId != null) 'object_id': objectId,
    if (className != null) 'class_name': className,
    if (bboxXyxy != null) 'bbox_xyxy': bboxXyxy,
    if (description != null) 'description': description,
  };
}

class HandObjectEvent {
  final String eventType;
  final dynamic objectId;

  const HandObjectEvent({required this.eventType, this.objectId});

  Map<String, dynamic> toJson() => {
    'event_type': eventType,
    if (objectId != null) 'object_id': objectId,
  };
}

class InteractionPrimitives {
  final GazeCoordinates? wristPosition;
  final bool pickupActive;
  final dynamic pickupObjectId;
  final bool shelfReachActive;
  final bool productRotationActive;

  const InteractionPrimitives({
    this.wristPosition,
    this.pickupActive = false,
    this.pickupObjectId,
    this.shelfReachActive = false,
    this.productRotationActive = false,
  });

  Map<String, dynamic> toJson() => {
    if (wristPosition != null) 'wrist_position': wristPosition!.toJson(),
    'pickup': {'active': pickupActive, if (pickupObjectId != null) 'object_id': pickupObjectId},
    'shelf_reach': {'active': shelfReachActive},
    'product_rotation': {'active': productRotationActive},
  };
}

// Only send if a voice utterance actually resolved this frame.
class VoiceNlu {
  final bool rhinoActive;
  final String? activeIntent;
  final double? intentConfidence;

  const VoiceNlu({required this.rhinoActive, this.activeIntent, this.intentConfidence});

  Map<String, dynamic> toJson() => {
    'rhino_active': rhinoActive,
    if (activeIntent != null) 'active_intent': activeIntent,
    if (intentConfidence != null) 'intent_confidence': intentConfidence,
  };
}

class BehaviourEngineInput {
  final String sessionId;
  final dynamic userId;
  final int timestampMs;
  final double? overallConfidence;
  final GazeGrounding gazeGrounding;
  final List<SceneObject> sceneObjects;
  final InteractionPrimitives interactionPrimitives;
  final List<HandObjectEvent> handObjectEvents;
  final Map<String, dynamic>? omniContextVlm;
  final Map<String, dynamic>? locationInformation;
  final Map<String, dynamic>? gpsCoordinates;
  final VoiceNlu? voiceNlu;

  const BehaviourEngineInput({
    required this.sessionId,
    this.userId,
    required this.timestampMs,
    this.overallConfidence,
    required this.gazeGrounding,
    this.sceneObjects = const [],
    required this.interactionPrimitives,
    this.handObjectEvents = const [],
    this.omniContextVlm,
    this.locationInformation,
    this.gpsCoordinates,
    this.voiceNlu,
  });

  Map<String, dynamic> toJson() => {
    'session_id': sessionId,
    if (userId != null) 'user_id': userId,
    'timestamp_ms': timestampMs,
    if (overallConfidence != null) 'context_metadata': {'overall_confidence': overallConfidence},
    'gaze_grounding': gazeGrounding.toJson(),
    'scene_objects': sceneObjects.map((sceneObject) => sceneObject.toJson()).toList(),
    'interaction_primitives': interactionPrimitives.toJson(),
    'hand_object_events': handObjectEvents.map((event) => event.toJson()).toList(),
    if (omniContextVlm != null) 'omni_context_vlm': omniContextVlm,
    if (locationInformation != null) 'location_information': locationInformation,
    if (gpsCoordinates != null) 'gps_coordinates': gpsCoordinates,
    if (voiceNlu != null) 'voice_nlu': voiceNlu!.toJson(),
  };
}
