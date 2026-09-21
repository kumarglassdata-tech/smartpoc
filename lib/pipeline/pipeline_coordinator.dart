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

  // Send CE output as-is in its exact raw format (with Myna_Context wrapper)
  final Map<String, dynamic> bePayload = contextEngineOutput.containsKey('Myna_Context')
      ? Map<String, dynamic>.from(contextEngineOutput)
      : {'Myna_Context': contextEngineOutput};

  // Only inject voice_nlu into Myna_Context when IE has active voice NLU data (not null)
  if (activeVoiceNlu != null) {
    final nluJson = activeVoiceNlu.toJson();
    final mynaContext = bePayload['Myna_Context'];
    if (mynaContext is Map<String, dynamic>) {
      mynaContext['voice_nlu'] = nluJson;
    } else if (mynaContext is Map) {
      bePayload['Myna_Context'] = {
        ...mynaContext,
        'voice_nlu': nluJson,
      };
    }
  }

  final behaviourEngineRaw = await behaviourEngineClient.process(bePayload);
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
  final isLifestyleFrame = behaviourEngineResponse.frameType == 'lifestyle';
  final isGateOpen = behaviourEngineResponse.gateOpen == true;

  // For commerce frame: send relevance_score directly.
  // For lifestyle frame: if gate_open == true, send commerce_score.
  double scoreForAh;
  if (isLifestyleFrame) {
    if (isGateOpen) {
      scoreForAh = (behaviourEngineResponse.commerceScore ?? 0).toDouble();
    } else {
      scoreForAh = 0.0;
    }
  } else {
    scoreForAh = (behaviourEngineResponse.relevanceScore ?? 0).toDouble();
  }

  final ecomHubInput = EcomHubInput(
    timestampMs: contextEngineResponse.timestampMs,
    relevanceScore: scoreForAh,
    topSalientObjects: topSalientObjects.isNotEmpty
        ? topSalientObjects
        : [SalientObject(className: gazeTarget ?? 'unknown', salienceScore: scoreForAh)],
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
      relevanceScore: scoreForAh,
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

  // Ecom Hub re-fires on:
  // - lifestyle frame: gate_open == true and commerce_score > 0
  // - commerce frame: active relevance_score > 0, scene objects changing, gaze target changing, or relevance rising
  final relevanceRose = scoreForAh - _lastEcomRelevance >= 0.15;
  final shouldRunEcom = isLifestyleFrame
      ? (isGateOpen && scoreForAh > 0.0)
      : (scoreForAh > 0.0 ||
          _lastEcomSceneObjects == null ||
          !_setEquals(sceneObjectNames, _lastEcomSceneObjects!) ||
          groundedTarget != _lastEcomGazeTarget ||
          relevanceRose);

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
      final productQuery = gazeTarget ?? (topSalientObjects.isNotEmpty ? topSalientObjects.first.className : null);
      final remainingResults = await Future.wait([
        ecomAdHandlerClient.getBuy(userId: userId, className: productQuery),
        ecomAdHandlerClient.getRecommend(userId: userId),
        if (productQuery != null && productQuery.isNotEmpty)
          ecomAdHandlerClient.getInstantRecommendations(
            product: productQuery,
            relevanceScore: scoreForAh,
            userId: userId,
          )
        else
          Future.value(null),
      ]);
      ecomAdHandlerRaw = EcomAdHandlerRaw(
        input: inputResult,
        buy: remainingResults[0],
        recommendGet: remainingResults[1],
        recommendPost: remainingResults[2],
        analyze: null,
        lifebalance: null,
      );
    } catch (error) {
      ecomAdHandlerRaw = EcomAdHandlerRaw(error: error.toString());
    }
    _lastEcomSceneObjects = sceneObjectNames;
    _lastEcomGazeTarget = groundedTarget;
    _lastEcomRelevance = scoreForAh;
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
