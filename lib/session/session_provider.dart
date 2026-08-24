import 'dart:async';

import 'package:flutter/foundation.dart';

import '../auth/auth_provider.dart';
import '../auth/db_service.dart';
import '../behaviour_engine/behaviour_engine_client.dart';
import '../context_engine/context_engine_client.dart';
import '../context_engine/context_engine_input.dart';
import '../diagnostics/health_monitor.dart';
import '../diagnostics/telemetry_service.dart';
import '../ecom_ad_handler/ecom_ad_handler_client.dart';
import '../interaction_engine/interaction_engine_client.dart';
import '../location_service.dart';
import '../pipeline/ecom_ad_handler_response.dart';
import '../pipeline/pipeline_coordinator.dart';
import '../pipeline/safety_memory_response.dart';
import '../recommendation_utils.dart';
import '../safety_memory/safety_memory_client.dart';
import '../sources/camera_service.dart';
import '../sources/phone_source_adapter.dart';
import '../sources/source_adapter.dart';
import '../sources/source_manager.dart';
import '../sources/video_upload_source_adapter.dart';
import '../session_history_service.dart';
import '../stats_service.dart';

class DetectedSessionItem {
  final String className;
  final bool matched;

  const DetectedSessionItem({required this.className, required this.matched});
}

class SessionSummary {
  final Duration duration;
  final int objectsSeen;
  final int matches;
  final List<DetectedSessionItem> detectedItems;
  final List<Map<String, String>> matchedProducts;
  final String? vlmDescription;
  final int? lifestyleScore;
  final Map<String, String> lifestyleBreakdown;
  final String? location;

  const SessionSummary({
    required this.duration,
    required this.objectsSeen,
    required this.matches,
    required this.detectedItems,
    this.matchedProducts = const [],
    this.vlmDescription,
    this.lifestyleScore,
    this.lifestyleBreakdown = const {},
    this.location,
  });
}

class SessionState {
  final bool isConnected;
  final bool isRuntimeActive;
  final int framesCaptured;
  final String? lastError;

  const SessionState({this.isConnected = false, this.isRuntimeActive = false, this.framesCaptured = 0, this.lastError});

  SessionState copyWith({bool? isConnected, bool? isRuntimeActive, int? framesCaptured, String? lastError}) {
    return SessionState(
      isConnected: isConnected ?? this.isConnected,
      isRuntimeActive: isRuntimeActive ?? this.isRuntimeActive,
      framesCaptured: framesCaptured ?? this.framesCaptured,
      lastError: lastError,
    );
  }
}

// Owns every engine client + the source-adapter/telemetry/health apparatus
// for one login session. TestScreen reads engine clients and session
// identity from here instead of constructing its own; the manual
// Connect/Capture & Send flow and this provider's continuous startRuntime()
// loop both end up calling the same runPipeline() in lib/pipeline/.
class SessionProvider extends ChangeNotifier {
  final CameraService cameraService;
  final LocationService locationService;
  final SettingsProvider settingsProvider;
  final AuthProvider authProvider;

  final contextEngineClient = ContextEngineClient();
  final behaviourEngineClient = BehaviourEngineClient();
  final ecomAdHandlerClient = EcomAdHandlerClient();
  final safetyMemoryClient = SafetyMemoryClient();
  final interactionEngineClient = InteractionEngineClient();

  late final SourceManager sourceManager;
  final telemetryService = TelemetryService();
  late final HealthMonitor healthMonitor;
  final _dbService = DbService();
  final _sessionHistoryService = SessionHistoryService();

  String? _sessionId;
  SessionState _state = const SessionState();
  StreamSubscription<VideoFrame>? _videoSub;
  String? _lastSentLocationCity;
  PipelineResult? _lastPipelineResult;
  String? _lastPipelineError;
  bool _pipelineTicking = false;
  EcomAdHandlerRaw _carriedEcomRaw = const EcomAdHandlerRaw();
  Map<String, dynamic> _carriedSafetyRaw = const {};
  SafetyMemoryResponse _carriedSafetyResponse = const SafetyMemoryResponse();

  // Accumulated for the CURRENT runtime only - reset on every startRuntime(),
  // frozen into a SessionSummary on stopRuntime() for SessionCompleteScreen.
  // "Objects seen" is the count of distinct class names in
  // _sessionDetectedItems, not a running per-frame tally - the same object
  // sitting in frame for many ticks should count once, not once per tick.
  DateTime? _runtimeStartedAt;
  int _sessionMatches = 0;
  final Map<String, bool> _sessionDetectedItems = {};
  final Map<String, Map<String, String>> _sessionMatchedProducts = {};
  String? _sessionLastVlmDescription;
  int? _sessionLifestyleScore;
  Map<String, String> _sessionLifestyleBreakdown = {};
  SessionSummary? _lastSessionSummary;

  // Live voice-pipeline text, so LiveSessionScreen can show "is this
  // actually working" without the user needing to check the debug log.
  String? _lastTranscript;
  String? _lastVoiceResponse;

  SessionSummary? get lastSessionSummary => _lastSessionSummary;
  // Built fresh on every access rather than cached - SessionProvider is a
  // single app-lifetime instance (see main.dart), so a cached StatsService
  // would freeze in whichever account's userId was live the first time this
  // was touched and keep writing/reading that account's rows forever, even
  // after a different user logs in on the same app instance.
  StatsService get statsService => StatsService(dbService: _dbService, userId: userId is int ? userId as int : 0);
  String? get lastTranscript => _lastTranscript;
  String? get lastVoiceResponse => _lastVoiceResponse;

  // Live (in-progress) view of the same accumulators, for LiveSessionScreen's
  // own display - lastSessionSummary only exists once stopRuntime() freezes it.
  DateTime? get runtimeStartedAt => _runtimeStartedAt;
  int get sessionObjectsSeen => _sessionDetectedItems.length;
  int get sessionMatches => _sessionMatches;
  List<String> get sessionDetectedItemNames => _sessionDetectedItems.keys.toList();

  PipelineResult? get lastPipelineResult => _lastPipelineResult;
  String? get lastPipelineError => _lastPipelineError;
  bool get isPipelineTicking => _pipelineTicking;

  SessionProvider({required this.cameraService, required this.locationService, required this.settingsProvider, required this.authProvider}) {
    sourceManager = SourceManager({
      SourceType.phone: PhoneSourceAdapter(camera: cameraService, location: locationService),
      SourceType.videoUpload: VideoUploadSourceAdapter(location: locationService),
    });
    healthMonitor = HealthMonitor(
      behaviourEngineClient: behaviourEngineClient,
      ecomAdHandlerClient: ecomAdHandlerClient,
      safetyMemoryClient: safetyMemoryClient,
      sourceManager: sourceManager,
    );
    locationService.addListener(_onLocationChanged);
  }

  // Dedups on city, not every GPS tick - set_location is a "user has a geo
  // fix" signal for store/geo-aware queries, not a live tracking stream.
  void _onLocationChanged() {
    final lat = locationService.latitude;
    final lon = locationService.longitude;
    final city = locationService.city;
    final country = locationService.country;
    if (lat == null || lon == null || city == null || country == null) return;
    if (city == _lastSentLocationCity) return;
    _lastSentLocationCity = city;
    interactionEngineClient.sendSetLocation(lat: lat, lon: lon, city: city, country: country);
  }

  dynamic get userId => authProvider.userId ?? 0;
  String get sessionId => _sessionId ?? '';
  SessionState get state => _state;

  Future<void> connect() async {
    final sessionId = InteractionEngineClient.generateSessionId();
    _sessionId = sessionId;
    contextEngineClient.onJsonOutput = _runPipeline;
    contextEngineClient.onError = (error) {
      _isProcessingFrame = false;
      sourceManager.notifyFrameProcessed();
      notifyListeners();
    };
    interactionEngineClient.onStateChanged = notifyListeners;
    interactionEngineClient.onTranscript = (text) {
      _lastTranscript = text;
      notifyListeners();
    };
    interactionEngineClient.onFinalResponse = (text) {
      _lastVoiceResponse = text;
      notifyListeners();
    };

    // Tags which call actually failed - without this, every failure in here
    // collapses to the same generic message (e.g. a bare null-check error),
    // impossible to act on from a bug report alone.
    Future<T> step<T>(String name, Future<T> Function() action) async {
      try {
        return await action();
      } catch (error) {
        throw Exception('$name: $error');
      }
    }

    try {
      await step('CE.connect', () => contextEngineClient.connect());
      await step('IE.init', () => interactionEngineClient.init());
      final uid = await authProvider.resolveUserId();
      final userIdentifier = (uid != null && uid != 0)
          ? uid.toString()
          : (authProvider.email.isNotEmpty ? authProvider.email : 'default_user');
      await step('IE.connect', () => interactionEngineClient.connect(sessionId: sessionId, userId: userIdentifier));
      await step('IE.setWakeWordEnabled', () => interactionEngineClient.setWakeWordEnabled(settingsProvider.wakeWordEnabled));
      await step('IE.startVad', () => interactionEngineClient.startVad());
      unawaited(locationService.start());
      healthMonitor.start();
      _state = _state.copyWith(isConnected: true, lastError: null);
    } catch (error) {
      _state = _state.copyWith(isConnected: false, lastError: '$error');
    }
    notifyListeners();
  }

  // Fires whenever context engine pushes a Myna_Context frame result, from
  // either the manual Capture & Send button or startRuntime()'s auto-capture
  // loop - both send frames through the same contextEngineClient. Screens
  // read the result via lastPipelineResult instead of each owning their own
  // pipeline-running logic.
  Future<void> _runPipeline(Map<String, dynamic> ceOutput) async {
    _pipelineTicking = true;
    notifyListeners();
    try {
      final result = await runPipeline(
        ceOutput,
        behaviourEngineClient: behaviourEngineClient,
        ecomAdHandlerClient: ecomAdHandlerClient,
        safetyMemoryClient: safetyMemoryClient,
        interactionEngineClient: interactionEngineClient,
        sessionId: sessionId,
        activeVoiceNlu: interactionEngineClient.activeVoiceNlu,
      );
      // A skipped ah/sma call returns empty placeholders (see
      // pipeline_coordinator.dart) - carry the last real value forward so
      // watchers never see a flash of "no data" on a skipped tick.
      if (!result.ecomSkipped) _carriedEcomRaw = result.ecomAdHandlerRaw;
      if (!result.safetySkipped) {
        _carriedSafetyRaw = result.safetyMemoryRaw;
        _carriedSafetyResponse = result.safetyMemoryResponse;
      }
      _lastPipelineResult = PipelineResult(
        contextEngineResponse: result.contextEngineResponse,
        behaviourEngineRaw: result.behaviourEngineRaw,
        behaviourEngineResponse: result.behaviourEngineResponse,
        ecomAdHandlerRaw: _carriedEcomRaw,
        safetyMemoryRaw: _carriedSafetyRaw,
        safetyMemoryResponse: _carriedSafetyResponse,
        ecomSkipped: result.ecomSkipped,
        safetySkipped: result.safetySkipped,
      );
      _lastPipelineError = null;

      // Real, cumulative session tallies for SessionCompleteScreen/Insights -
      // counted off result.ecomAdHandlerRaw (not the carried-forward copy),
      // so a skipped tick (empty raw) naturally contributes zero here rather
      // than double-counting the previous tick's matches.
      final sceneObjectNames = result.contextEngineResponse.sceneObjects.map((o) => o.className).whereType<String>().toList();
      // "Matches" is honestly the real POST /ah/recommend product count, not
      // the richer buy+recommendPost merge extractEcomRecommendations shows
      // in the Matched products cards - counting the merge here would let a
      // /buy-only hit inflate a number that's supposed to mean "recommend
      // actually returned N real products this tick".
      final tickRecommendations = extractEcomRecommendations(result.ecomAdHandlerRaw, limit: 20);
      final tickMatchCount = extractRecommendations(result.ecomAdHandlerRaw.recommendPost, limit: 20).length;
      _sessionMatches += tickMatchCount;
      final tickHasMatch = tickMatchCount > 0;
      final newlySeenNames = sceneObjectNames.where((name) => !_sessionDetectedItems.containsKey(name)).toSet();
      for (final name in sceneObjectNames) {
        _sessionDetectedItems[name] = (_sessionDetectedItems[name] ?? false) || tickHasMatch;
      }
      unawaited(statsService.recordDetections(objectsSeen: newlySeenNames.length, matches: tickMatchCount));

      // Frozen into SessionSummary on stopRuntime() - real matched products
      // (deduped by name), the last VLM caption seen, and the ecom hub's own
      // /lifebalance response, all otherwise only visible mid-session.
      for (final product in tickRecommendations) {
        final name = product['name'];
        if (name != null) _sessionMatchedProducts[name] = product;
      }
      final vlmDescription = result.contextEngineResponse.vlmDescription;
      if (vlmDescription != null && vlmDescription.isNotEmpty) {
        _sessionLastVlmDescription = vlmDescription;
      }
      final lifebalance = result.ecomAdHandlerRaw.lifebalance;
      if (lifebalance is Map) {
        final score = lifebalance['life_balance_score'];
        if (score is num) _sessionLifestyleScore = score.round();
        final breakdown = lifebalance['breakdown'];
        if (breakdown is Map) {
          _sessionLifestyleBreakdown = breakdown.map((key, value) => MapEntry('$key', '$value'));
        }
      }

      final tickSalientObjects = result.behaviourEngineResponse.topSalientObjects
          .where((o) => o.className != null)
          .map((o) => MapEntry(o.className!, o.salienceScore ?? 1.0))
          .toList();
      unawaited(statsService.recordSalientObjects(tickSalientObjects));

      unawaited(logEngineEvent('pipeline', 'Pipeline complete'));
    } catch (error) {
      _lastPipelineError = '$error';
      unawaited(logEngineEvent('pipeline', 'Pipeline failed: $error', isError: true));
    } finally {
      _pipelineTicking = false;
      _isProcessingFrame = false;
      sourceManager.notifyFrameProcessed();
      notifyListeners();
    }
  }

  // For the debug screen's "paste a CE JSON and run it" tool - runs the same
  // path a real captured frame would, without needing a live CE connection.
  Future<void> runPipelineFromJson(Map<String, dynamic> ceOutput) => _runPipeline(ceOutput);

  // Continuous hands-free capture, additional to the manual Capture & Send
  // button - pulls frames from whichever SourceManager adapter is active and
  // runs each one through the same ContextEngineClient.sendFrame() path.
  Future<void> startRuntime() async {
    if (_state.isRuntimeActive) return;
    resetPipelineGates();
    // Without this, a fresh session's screens read the previous session's
    // last pipeline result (VLM caption, relevance score, ecom raw) until
    // the new session's own first tick lands - looks like "showing the
    // previous session" for the first few seconds of every new session.
    _lastPipelineResult = null;
    _lastPipelineError = null;
    _carriedEcomRaw = const EcomAdHandlerRaw();
    _carriedSafetyRaw = const {};
    _carriedSafetyResponse = const SafetyMemoryResponse();
    _runtimeStartedAt = DateTime.now();
    _sessionMatches = 0;
    _sessionDetectedItems.clear();
    _sessionMatchedProducts.clear();
    _sessionLastVlmDescription = null;
    _sessionLifestyleScore = null;
    _sessionLifestyleBreakdown = {};
    _lastSessionSummary = null;
    unawaited(statsService.recordSessionStarted());

    await sourceManager.startActive();
    _videoSub = sourceManager.videoStream.listen(_onSourceFrame);
    final numericUserId = userId is int ? userId as int : 0;
    // Was awaited - same fix as stopRuntime()'s endSession call below: this
    // blocked "Begin Session" on a live Postgres round-trip for no benefit,
    // since DbService.startSession already swallows its own errors.
    unawaited(_dbService.startSession(numericUserId, sessionId));
    unawaited(_sessionHistoryService.recordSessionStarted(sessionId));
    _state = _state.copyWith(isRuntimeActive: true);
    notifyListeners();
  }

  bool _isProcessingFrame = false;

  void _onSourceFrame(VideoFrame frame) {
    if (_isProcessingFrame) return;
    _isProcessingFrame = true;
    final input = ContextEngineInput(
      gpsCoordinates: GpsCoordinates(
        lat: locationService.latitude ?? 12.9716,
        lon: locationService.longitude ?? 77.5946,
      ),
      temperatureC: 38.5,
      userId: userId,
    );
    contextEngineClient.sendFrame(input, frame.bytes);
    telemetryService.incrementCapturedFrames();
    _state = _state.copyWith(framesCaptured: _state.framesCaptured + 1);
    notifyListeners();
  }

  Future<void> stopRuntime() async {
    if (!_state.isRuntimeActive) return;
    _isProcessingFrame = false;
    await sourceManager.stopActive();
    await _videoSub?.cancel();
    _videoSub = null;
    // Was awaited - blocked the transition to SessionCompleteScreen on a live
    // Postgres round-trip (DbService.endSession already swallows its own
    // errors, so there's nothing here that needs waiting for).
    if (_sessionId != null) unawaited(_dbService.endSession(_sessionId!));

    final startedAt = _runtimeStartedAt;
    final duration = startedAt != null ? DateTime.now().difference(startedAt) : Duration.zero;
    _lastSessionSummary = SessionSummary(
      duration: duration,
      objectsSeen: _sessionDetectedItems.length,
      matches: _sessionMatches,
      detectedItems: _sessionDetectedItems.entries.map((e) => DetectedSessionItem(className: e.key, matched: e.value)).toList(),
      matchedProducts: _sessionMatchedProducts.values.toList(),
      vlmDescription: _sessionLastVlmDescription,
      lifestyleScore: _sessionLifestyleScore,
      lifestyleBreakdown: _sessionLifestyleBreakdown,
      location: locationService.city != null ? '${locationService.city}, ${locationService.country}' : null,
    );
    if (_sessionId != null) unawaited(_sessionHistoryService.recordSessionEnded(_sessionId!, duration.inSeconds));
    _runtimeStartedAt = null;

    _state = _state.copyWith(isRuntimeActive: false);
    notifyListeners();
  }

  Future<void> logEngineEvent(String source, String message, {String? jsonPayload, bool isError = false}) {
    final numericUserId = userId is int ? userId as int : 0;
    return _dbService.logEngineEvent(userId: numericUserId, source: source, message: message, jsonPayload: jsonPayload, isError: isError);
  }

  // DbService needs a raw Postgres socket, unavailable on web - falls back to
  // the local SharedPreferences history (also used as a native fallback if
  // the DB itself is briefly unreachable) whenever the DB comes back empty.
  Future<List<Map<String, dynamic>>> getRecentSessions({int limit = 20}) async {
    final numericUserId = userId is int ? userId as int : 0;
    final dbSessions = await _dbService.getRecentSessions(numericUserId, limit: limit);
    if (dbSessions.isNotEmpty) return dbSessions;
    return _sessionHistoryService.getRecentSessions(limit: limit);
  }

  Future<void> disconnect() async {
    await stopRuntime();
    await contextEngineClient.disconnect();
    await interactionEngineClient.dispose();
    healthMonitor.stop();
    _state = _state.copyWith(isConnected: false);
    notifyListeners();
  }

  @override
  void dispose() {
    _videoSub?.cancel();
    locationService.removeListener(_onLocationChanged);
    sourceManager.dispose();
    telemetryService.dispose();
    healthMonitor.dispose();
    super.dispose();
  }
}
