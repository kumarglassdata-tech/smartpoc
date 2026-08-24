// Parsed context-engine output - only the fields other engines need, pulled
// out of the raw `Myna_Context` JSON. Not a full mirror of every CE field.

class ContextEngineGazeGrounding {
  final String? groundedTarget;
  final double? x;
  final double? y;
  final double? alignmentScore;
  final double? spatialProximityPx;

  const ContextEngineGazeGrounding({
    this.groundedTarget,
    this.x,
    this.y,
    this.alignmentScore,
    this.spatialProximityPx,
  });
}

class ContextEngineHandEvent {
  final String eventType;
  final dynamic overlapObjectId;

  const ContextEngineHandEvent({required this.eventType, this.overlapObjectId});
}

class ContextEngineSceneObject {
  final dynamic objectId;
  final String? className;
  final List<double>? bboxXyxy;
  final double? confidence;

  const ContextEngineSceneObject({this.objectId, this.className, this.bboxXyxy, this.confidence});
}

class ContextEngineResponse {
  final String sessionId;
  final dynamic userId;
  final int timestampMs;
  final double? overallConfidence;
  final ContextEngineGazeGrounding gazeGrounding;
  final List<ContextEngineSceneObject> sceneObjects;
  final bool shelfReachActive;
  final Map<String, dynamic>? wristPosition;
  final ContextEngineHandEvent handEvent;
  final String? vlmDescription;
  final Map<String, dynamic>? omniContextVlm;
  final Map<String, dynamic>? locationInformation;
  final Map<String, dynamic>? gpsCoordinates;

  const ContextEngineResponse({
    required this.sessionId,
    this.userId,
    required this.timestampMs,
    this.overallConfidence,
    required this.gazeGrounding,
    this.sceneObjects = const [],
    this.shelfReachActive = false,
    this.wristPosition,
    required this.handEvent,
    this.vlmDescription,
    this.omniContextVlm,
    this.locationInformation,
    this.gpsCoordinates,
  });

  factory ContextEngineResponse.parse(Map<String, dynamic> ceOutput) {
    final mynaContext = ceOutput['Myna_Context'] as Map<String, dynamic>? ?? ceOutput;
    final telemetry = mynaContext['behaviour_engine_telemetry'] as Map<String, dynamic>? ?? {};
    final contextConfidence = mynaContext['context_confidence'] as Map<String, dynamic>? ?? {};
    final gaze = mynaContext['gaze_grounding'] as Map<String, dynamic>? ?? {};
    final gazeCoordinates = gaze['gaze_coordinates'] as Map<String, dynamic>?;
    final primitives = mynaContext['interaction_primitives'] as Map<String, dynamic>? ?? {};
    final shelfReach = primitives['shelf_reach'] as Map<String, dynamic>? ?? {};
    final handEventMap = mynaContext['hand_object_events'] as Map<String, dynamic>? ?? {};
    final omniContextVlm = mynaContext['omni_context_vlm'] as Map<String, dynamic>?;

    return ContextEngineResponse(
      sessionId: telemetry['session_id'] as String? ?? 'default_session',
      userId: telemetry['user_id'],
      timestampMs:
          (mynaContext['timestamp_ms'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      overallConfidence: (contextConfidence['overall_context_reliability'] as num?)?.toDouble(),
      gazeGrounding: ContextEngineGazeGrounding(
        groundedTarget: _nullIfEmpty(gaze['grounded_target'] as String?),
        x: (gazeCoordinates?['x'] as num?)?.toDouble(),
        y: (gazeCoordinates?['y'] as num?)?.toDouble(),
        alignmentScore: (gaze['alignment_score'] as num?)?.toDouble(),
        spatialProximityPx: (gaze['spatial_proximity_px'] as num?)?.toDouble(),
      ),
      sceneObjects: (mynaContext['scene_objects'] as List? ?? [])
          .whereType<Map>()
          .map(
            (sceneObject) => ContextEngineSceneObject(
              objectId: sceneObject['object_id'],
              className: sceneObject['class_name'] as String?,
              bboxXyxy: (sceneObject['bbox_xyxy'] as List?)
                  ?.map((v) => (v as num).toDouble())
                  .toList(),
              confidence: (sceneObject['confidence'] as num?)?.toDouble(),
            ),
          )
          .toList(),
      shelfReachActive: shelfReach['active'] as bool? ?? false,
      wristPosition: primitives['wrist_position'] as Map<String, dynamic>?,
      handEvent: ContextEngineHandEvent(
        eventType: handEventMap['event_type'] as String? ?? 'none',
        overlapObjectId: handEventMap['overlap_obj_id'],
      ),
      vlmDescription: omniContextVlm?['detailed_description'] as String?,
      omniContextVlm: omniContextVlm,
      locationInformation: mynaContext['location_information'] as Map<String, dynamic>?,
      gpsCoordinates: telemetry['gps_coordinates'] as Map<String, dynamic>?,
    );
  }
}

String? _nullIfEmpty(String? value) => (value == null || value.isEmpty) ? null : value;
