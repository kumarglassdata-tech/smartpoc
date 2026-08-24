// Request payloads for the Memory Safety Agent (MSEAPI.pdf v3).

// POST /allergy - natural-language allergy statement to store.
class AllergyRequest {
  final dynamic userId;
  final String userQuery;

  const AllergyRequest({this.userId, required this.userQuery});

  Map<String, dynamic> toJson() => {
    if (userId != null) 'user_id': userId,
    'user_query': userQuery,
  };
}

class SafetyMemorySceneObject {
  final String className;
  final double confidence;

  const SafetyMemorySceneObject({required this.className, required this.confidence});

  Map<String, dynamic> toJson() => {'class_name': className, 'confidence': confidence};
}

// POST /inp - a subset of a CE Myna_Context frame, evaluated against the
// user's stored allergies.
class SafetyMemoryInput {
  final dynamic userId;
  final List<SafetyMemorySceneObject> sceneObjects;
  final String? groundedTarget;

  const SafetyMemoryInput({this.userId, this.sceneObjects = const [], this.groundedTarget});

  Map<String, dynamic> toJson() => {
    'Myna_Context': {
      'camera_stream': 'Processed',
      'behaviour_engine_telemetry': {if (userId != null) 'user_id': userId},
      'scene_objects': sceneObjects.map((sceneObject) => sceneObject.toJson()).toList(),
      'gaze_grounding': {if (groundedTarget != null) 'grounded_target': groundedTarget},
    },
  };
}
