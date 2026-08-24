import '../behaviour_engine/behaviour_engine_client.dart';
import '../behaviour_engine/behaviour_engine_input.dart';
import '../ecom_ad_handler/ecom_ad_handler_client.dart';
import '../ecom_ad_handler/ecom_ad_handler_input.dart';
import '../interaction_engine/interaction_engine_client.dart';
import '../interaction_engine/interaction_engine_input.dart';
import '../safety_memory/safety_memory_client.dart';
import '../safety_memory/safety_memory_input.dart';
import 'behaviour_engine_response.dart';
import 'context_engine_response.dart';
import 'ecom_ad_handler_response.dart';
import 'safety_memory_response.dart';

// The main pipeline: context engine -> behaviour engine + safety memory ->
// ecom ad handler. Each hop parses the previous engine's response (see the
// sibling *_response.dart files), then trims only the fields the next
// engine actually needs into its request.
class PipelineResult {
  final ContextEngineResponse contextEngineResponse;
  final Map<String, dynamic> behaviourEngineRaw;
  final BehaviourEngineResponse behaviourEngineResponse;
  final EcomAdHandlerRaw ecomAdHandlerRaw;
  final Map<String, dynamic> safetyMemoryRaw;
  final SafetyMemoryResponse safetyMemoryResponse;
  // True when this run skipped the network call entirely (scene unchanged) -
  // callers should leave whatever they were already displaying alone rather
  // than overwrite it with this run's (empty) raw/response fields.
  final bool ecomSkipped;
  final bool safetySkipped;

  const PipelineResult({
    required this.contextEngineResponse,
    required this.behaviourEngineRaw,
    required this.behaviourEngineResponse,
    required this.ecomAdHandlerRaw,
    required this.safetyMemoryRaw,
    required this.safetyMemoryResponse,
    this.ecomSkipped = false,
    this.safetySkipped = false,
  });
}

// Ecom Hub (6 HTTP calls per run) and Safety Memory are gated purely on the
// scene actually changing, rather than firing on every frame - mirrors the
// debounce added to C:\Dev\smartglass_flutter's GateCheckStep after firing
// on every ~4s frame regardless of change was enough sustained load to tip
// an already-degraded backend into sustained 502s. No time-based fallback
// for either - both only re-fire when scene_objects/grounded_target change.
Set<String>? _lastEcomSceneObjects;
String? _lastEcomGazeTarget;
num _lastEcomRelevance = 0;

Set<String>? _lastSafetySceneObjects;

bool _setEquals<T>(Set<T> a, Set<T> b) => a.length == b.length && a.containsAll(b);

// These gates live at module scope so they survive across pipeline runs
// within one session - but that also means they survive across separate
// Begin/End Session cycles in the same app process. Without a reset, a new
// session that happens to see the same first object as a previous session
// gets shouldRunEcom/shouldRunSafety = false on its very first tick, so ah
// never gets called at all until the scene changes to something new. Call
// this from startRuntime() so every session starts with a clean gate.
void resetPipelineGates() {
  _lastEcomSceneObjects = null;
  _lastEcomGazeTarget = null;
  _lastEcomRelevance = 0;
  _lastSafetySceneObjects = null;
}

Future<PipelineResult> runPipeline(
  Map<String, dynamic> contextEngineOutput, {
  required BehaviourEngineClient behaviourEngineClient,
  required EcomAdHandlerClient ecomAdHandlerClient,
  required SafetyMemoryClient safetyMemoryClient,
  required InteractionEngineClient interactionEngineClient,
  required String sessionId,
  VoiceNlu? activeVoiceNlu,
}) async {
  final contextEngineResponse = ContextEngineResponse.parse(contextEngineOutput);

  final sceneObjectNames = contextEngineResponse.sceneObjects
      .map((sceneObject) => sceneObject.className)
      .whereType<String>()
      .toSet();
  final groundedTarget = contextEngineResponse.gazeGrounding.groundedTarget;

  final shouldRunSafety = _lastSafetySceneObjects == null || !_setEquals(sceneObjectNames, _lastSafetySceneObjects!);

  // Safety memory's /inp only needs ce's parsed output, so it's fired here,
  // concurrently with the be call below - not awaited until after be.
  Future<dynamic>? safetyMemoryFuture;
  if (shouldRunSafety) {
    final safetyMemoryInput = SafetyMemoryInput(
      userId: contextEngineResponse.userId,
      sceneObjects: contextEngineResponse.sceneObjects
          .where((sceneObject) => sceneObject.className != null && sceneObject.confidence != null)
          .map(
            (sceneObject) => SafetyMemorySceneObject(
              className: sceneObject.className!,
              confidence: sceneObject.confidence!,
            ),
          )
          .toList(),
      groundedTarget: groundedTarget,
    );
    safetyMemoryFuture = safetyMemoryClient.postInp(safetyMemoryInput);
    _lastSafetySceneObjects = sceneObjectNames;
  }

  final behaviourEngineInput = BehaviourEngineInput(
    sessionId: sessionId,
    userId: contextEngineResponse.userId,
    timestampMs: contextEngineResponse.timestampMs,
    overallConfidence: contextEngineResponse.overallConfidence,
    gazeGrounding: GazeGrounding(
      groundedTarget: contextEngineResponse.gazeGrounding.groundedTarget,
      gazeCoordinates: _coordinatesFromXY(
        contextEngineResponse.gazeGrounding.x,
        contextEngineResponse.gazeGrounding.y,
      ),
      alignmentScore: contextEngineResponse.gazeGrounding.alignmentScore,
      spatialProximityPx: contextEngineResponse.gazeGrounding.spatialProximityPx,
    ),
    sceneObjects: contextEngineResponse.sceneObjects
        .map(
          (sceneObject) => SceneObject(
            objectId: sceneObject.objectId?.toString(),
            className: sceneObject.className,
            bboxXyxy: sceneObject.bboxXyxy,
          ),
        )
        .toList(),
    interactionPrimitives: InteractionPrimitives(
      wristPosition: _coordinatesFromMap(contextEngineResponse.wristPosition),
      pickupActive: contextEngineResponse.handEvent.eventType == 'pickup',
      pickupObjectId: contextEngineResponse.handEvent.eventType == 'pickup'
          ? contextEngineResponse.handEvent.overlapObjectId
          : null,
      shelfReachActive: contextEngineResponse.shelfReachActive,
      // No product-rotation signal from the context engine yet - stays false.
    ),
    handObjectEvents: contextEngineResponse.handEvent.eventType != 'none'
        ? [
            HandObjectEvent(
              eventType: contextEngineResponse.handEvent.eventType,
              objectId: contextEngineResponse.handEvent.overlapObjectId,
            ),
          ]
        : const [],
    omniContextVlm: contextEngineResponse.omniContextVlm,
    locationInformation: contextEngineResponse.locationInformation,
    gpsCoordinates: contextEngineResponse.gpsCoordinates,
    voiceNlu: activeVoiceNlu,
  );
  final behaviourEngineRaw = await behaviourEngineClient.process(behaviourEngineInput);
  final behaviourEngineResponse = BehaviourEngineResponse.parse(behaviourEngineRaw);

  // relevance_score and top_salient_objects come from BE's response (both
  // are literal fields there). gaze_target/scene_objects are NOT sent - the
  // real contract doesn't take them (verified against a known working
  // reference implementation), gazeTarget below is only used to build a
  // fallback salient object when BE doesn't provide any.
  final userId =
      behaviourEngineResponse.userId?.toString() ??
      contextEngineResponse.userId?.toString() ??
      'default_user';
  final gazeTarget =
      behaviourEngineResponse.recommendedProduct ?? contextEngineResponse.gazeGrounding.groundedTarget;
  final topSalientObjects = behaviourEngineResponse.topSalientObjects
      .where((object) => object.className != null && object.salienceScore != null)
      .map((object) => SalientObject(className: object.className!, salienceScore: object.salienceScore!))
      .toList();
  var relevanceScore = behaviourEngineResponse.relevanceScore ?? 0;
  if (relevanceScore == 0 && topSalientObjects.isNotEmpty) {
    relevanceScore = topSalientObjects.first.salienceScore;
  }
  final ecomHubInput = EcomHubInput(
    timestampMs: contextEngineResponse.timestampMs,
    relevanceScore: relevanceScore,
    topSalientObjects: topSalientObjects.isNotEmpty
        ? topSalientObjects
        : [SalientObject(className: gazeTarget ?? 'unknown', salienceScore: relevanceScore)],
    userId: userId,
  );

  // Fire-and-forget - IE's real answer never correlates to this send, so it
  // must not block or fail the pipeline's return.
  interactionEngineClient.sendTelemetry(
    InteractionTelemetry(
      userId: userId,
      sessionId: sessionId,
      behavioralState: behaviourEngineResponse.behavioralState,
      confidenceScore: behaviourEngineResponse.stateConfidence,
      relevanceScore: relevanceScore,
      hesitationScore: behaviourEngineResponse.hesitationScore,
      gazeTarget: gazeTarget,
      sceneObjects: contextEngineResponse.sceneObjects
          .map((sceneObject) => sceneObject.className)
          .whereType<String>()
          .toList(),
      topSalientObjects: ecomHubInput.topSalientObjects
          .map((object) => {'class_name': object.className, 'salience_score': object.salienceScore})
          .toList(),
    ),
  );

  // Ecom Hub re-fires on scene_objects/grounded_target changing, or on
  // relevance climbing meaningfully on the SAME object - sustained dwell on
  // one object raising relevance toward real purchase intent (e.g. 40% ->
  // 97%) is exactly the moment a fresh /buy call matters most, and it would
  // otherwise never re-fire since the scene never "changes" while held still.
  final relevanceRose = relevanceScore - _lastEcomRelevance >= 0.15;
  final shouldRunEcom = _lastEcomSceneObjects == null ||
      !_setEquals(sceneObjectNames, _lastEcomSceneObjects!) ||
      groundedTarget != _lastEcomGazeTarget ||
      relevanceRose;

  // /inp primes the server's context for this user (gaze_target/scene_objects/
  // top_salient_objects) - /buy and /recommend read that just-set context back,
  // so /inp must complete first. Firing all 6 together (the old behaviour) let
  // /buy/recommend race ahead of /inp's write and come back with stale/generic
  // data instead of the actual current object - confirmed against a manual
  // Postman /buy call made right after /inp, which returned real matched links.
  EcomAdHandlerRaw ecomAdHandlerRaw;
  final ecomSkipped = !shouldRunEcom;
  if (!shouldRunEcom) {
    ecomAdHandlerRaw = const EcomAdHandlerRaw();
  } else {
    try {
      final inputResult = await ecomAdHandlerClient.postInput(ecomHubInput);
      final remainingResults = await Future.wait([
        ecomAdHandlerClient.getBuy(ecomHubInput),
        ecomAdHandlerClient.getRecommend(),
        ecomAdHandlerClient.postRecommend(ecomHubInput),
        ecomAdHandlerClient.getAnalyze(),
        ecomAdHandlerClient.getLifebalance(),
      ]);
      ecomAdHandlerRaw = EcomAdHandlerRaw(
        input: inputResult,
        buy: remainingResults[0],
        recommendGet: remainingResults[1],
        recommendPost: remainingResults[2],
        analyze: remainingResults[3],
        lifebalance: remainingResults[4],
      );
    } catch (error) {
      ecomAdHandlerRaw = EcomAdHandlerRaw(error: error.toString());
    }
    _lastEcomSceneObjects = sceneObjectNames;
    _lastEcomGazeTarget = groundedTarget;
    _lastEcomRelevance = relevanceScore;
  }

  // TODO: route safety-memory hazard utterances to IE once the mechanism is confirmed.
  Map<String, dynamic> safetyMemoryRaw;
  SafetyMemoryResponse safetyMemoryResponse;
  if (safetyMemoryFuture == null) {
    safetyMemoryRaw = const {'skipped': true};
    safetyMemoryResponse = const SafetyMemoryResponse();
  } else {
    try {
      safetyMemoryRaw = await safetyMemoryFuture as Map<String, dynamic>;
      safetyMemoryResponse = SafetyMemoryResponse.parse(safetyMemoryRaw);
    } catch (error) {
      safetyMemoryRaw = {'error': error.toString()};
      safetyMemoryResponse = const SafetyMemoryResponse();
    }
  }

  return PipelineResult(
    contextEngineResponse: contextEngineResponse,
    behaviourEngineRaw: behaviourEngineRaw,
    behaviourEngineResponse: behaviourEngineResponse,
    ecomAdHandlerRaw: ecomAdHandlerRaw,
    safetyMemoryRaw: safetyMemoryRaw,
    safetyMemoryResponse: safetyMemoryResponse,
    ecomSkipped: ecomSkipped,
    safetySkipped: !shouldRunSafety,
  );
}

GazeCoordinates? _coordinatesFromXY(double? x, double? y) =>
    (x != null && y != null) ? GazeCoordinates(x: x, y: y) : null;

GazeCoordinates? _coordinatesFromMap(Map<String, dynamic>? value) {
  if (value == null) return null;
  final x = value['x'];
  final y = value['y'];
  if (x is! num || y is! num) return null;
  return GazeCoordinates(x: x.toDouble(), y: y.toDouble());
}
