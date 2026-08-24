# SmartPoc — Architecture & Progress

Living doc for what exists, where, and why.

## Folder convention
One folder per engine: an `_input.dart` file (request payload types) and an `_client.dart` file
(functions that call that engine's APIs). Engine folders don't know about each other. Cross-engine
wiring lives in `pipeline/`: one `_response.dart` file per engine (parses that engine's raw JSON
into typed fields - only what later stages need, not a full mirror) plus `pipeline_coordinator.dart`,
which calls each engine in turn and trims each response into the next engine's request. Shared,
non-engine-specific files (`env_config.dart`, `app_logger.dart`, `location_service.dart`,
`app_router.dart`) stay flat at `lib/` root. A few concerns that are genuinely bigger than one
engine (auth, the session-lifetime orchestrator, camera/video capture sources, resilience/telemetry
utilities) each get their own top-level folder too - still flat, not nested layers.

```
lib/
├── main.dart                      - bootstrap only (SmartPocApp: MultiProvider + MaterialApp.router)
├── app_router.dart                - GoRouter: /login <-> /home, gated on AuthProvider.isLoggedIn
├── app_theme.dart                 - AppColors (single palette source) + buildAppTheme()
├── env_config.dart                - reads every engine URL + DB/OAuth config from .env
├── app_logger.dart                - AppLogger (on-device debug log)
├── location_service.dart          - real device GPS + reverse-geocoded city/country
├── home_shell.dart                - bottom-nav shell: Home / Activity / Profile (IndexedStack)
├── home_screen.dart                - dashboard: session status, Start/Stop, best-effort AH recs
├── choose_source_screen.dart      - pick capture source, then connect()+startRuntime()
├── activity_screen.dart           - recent sessions from DbService (native only, empty on web)
├── profile_screen.dart            - user info + links to Settings/Developer Tools/About/Log out
├── settings_screen.dart           - real toggles only (wake word, connected account)
├── debug_screen.dart              - the original raw engine test harness, moved off the main path
├── context_engine/                - CE: WebSocket
├── behaviour_engine/               - BE: HTTP
├── ecom_ad_handler/                - AH (Ecom Hub): HTTP, 6 calls
├── safety_memory/                  - SMA/MSA: HTTP
├── interaction_engine/             - IE: persistent WebSocket, voice + telemetry sink
│   ├── interaction_engine_input.dart      - InteractionTelemetry, VoiceNlu parser
│   ├── interaction_engine_client.dart     - connection, VAD, wake word, playback, barge-in
│   └── interaction_engine_wake_word.dart  - 3-stage ONNX "Hey Myna" pipeline
├── auth/                           - login + Postgres
│   ├── auth_provider.dart          - AuthProvider (Google/email-password), SettingsProvider
│   ├── db_service.dart             - DbService (direct Postgres: users/sessions/engine_logs)
│   └── login_screen.dart
├── session/
│   └── session_provider.dart       - SessionProvider: owns every engine client + latest pipeline
│                                      result for one login (screens read lastPipelineResult
│                                      instead of each running their own pipeline)
├── sources/                        - swappable capture sources feeding the pipeline
│   ├── source_adapter.dart         - SourceAdapter interface, VideoFrame/LocationSample
│   ├── source_manager.dart         - SourceManager (active adapter + auto-fallback to phone)
│   ├── camera_service.dart         - continuous camera capture for the phone adapter
│   ├── phone_source_adapter.dart
│   ├── video_upload_source_adapter.dart (+ video_decoder_stub.dart / video_decoder_web.dart)
├── diagnostics/
│   ├── telemetry_service.dart      - FPS/latency/dropped-frame counters
│   └── health_monitor.dart         - polls circuit-breaker state for BE/AH/SMA + source health
└── pipeline/
    ├── context_engine_response.dart   - parses CE's Myna_Context
    ├── behaviour_engine_response.dart - parses BE's /process response
    ├── ecom_ad_handler_response.dart  - raw responses from AH's 6 calls
    ├── safety_memory_response.dart    - parses the safety agent's /inp response
    ├── circuit_breaker.dart           - CircuitBreaker (closed/open/halfOpen), shared utility
    ├── engine_registry.dart           - logical engine name -> base URL
    └── pipeline_coordinator.dart      - runPipeline(): ce -> {be, safety memory} -> ah, + IE hooks
```
**All 5 planned engines are built**: context, behaviour, ecom hub, safety memory, interaction.
Each new engine gets its own folder following the same two-file pattern (interaction engine needed
a third file for its self-contained wake-word pipeline - same idea as a `_response.dart`, just
engine-specific instead of pipeline-specific).

`scripts/cors_proxy.js` - a standalone (unused by the app) local CORS-forwarding tool for
manual web testing against the ecom hub if ever needed again; not currently wired into anything.

## UI: theme + primary screens
`app_theme.dart` holds the entire color palette as named `AppColors` constants (pulled from a
Figma/AI-generated redesign mockup) - every screen references these tokens instead of literal
`Color(0x...)` values, so re-theming the whole app is a one-file edit. `buildAppTheme()` wires them
into a Material 3 `ThemeData` (buttons, inputs, cards, switches, bottom nav) so most widgets pick up
the look for free.

`/home` routes to `HomeShell` (bottom nav: Home / Activity / Profile), not the raw engine harness.
Each screen is real data or an honest empty state, never a fabricated one:
- **Home** - session/source status card, Start/Stop Session, a compact voice-status strip, and
  "Recommended for you" built from `SessionProvider.lastPipelineResult`. AH's response shape isn't
  documented (see `pipeline/ecom_ad_handler_response.dart`), so `_extractRecommendations()` in
  `home_screen.dart` best-effort-matches common list/name/price keys and falls back to "nothing
  matched" text rather than guessing at fields that might not exist.
- **Choose Source** - Live Camera (real, wired to `SourceManager.switchSource` +
  `SessionProvider.connect()`/`startRuntime()`) and Recorded Video (`SourceType.videoUpload` exists
  but has no file-picker wired up yet - shown as "Coming soon" rather than half-built).
- **Activity** - `DbService.getRecentSessions()` (new query, `sessions` table). Empty on web with an
  explicit "not available on web" message, since `DbService` is `kIsWeb`-gated to begin with.
- **Profile / Settings** - real user info from `AuthProvider`, a real wake-word toggle
  (`SettingsProvider` + live `interactionEngineClient.setWakeWordEnabled()` if connected), and a
  link to **Developer Tools** (`debug_screen.dart`) - the original manual Connect/Capture &
  Send/paste-JSON/raw-response harness, kept in full rather than deleted, just moved off the main
  path.

## Context engine (WebSocket)
- Endpoint: `CONTEXT_ENGINE_URL` (.env) = `wss://myna.glassdata.ai/api/v1/ce/stream`
- Per frame: send a JSON text message, then the raw JPEG bytes as a binary message.
- Request JSON: `{gps_coordinates: {lat, lon}, temperature_c, facing_mode}`
- Server replies with two messages per frame: a JSON result under top-level key `Myna_Context`
  (rich behavior/scene/gaze/activity telemetry), then a processed JPEG (binary).
- `ContextEngineClient` stores the two separately (`lastJsonOutput`/`lastImageOutput`, each
  overwritten by the newest of its kind) and exposes `onJsonOutput`/`onImageOutput` callbacks.
- `pipeline/context_engine_response.dart` (`ContextEngineResponse.parse()`) pulls out the fields
  later stages need, including `vlmDescription` (from `omni_context_vlm.detailed_description`)
  and typed `sceneObjects` (incl. `confidence`, needed by both safety memory and the AH/SMA
  change-detection gating described below).
- Two capture paths feed CE: the manual **Capture & Send** button, and `SessionProvider`'s
  **Start Session** auto-capture loop (pulls frames from whichever `SourceManager` adapter -
  phone camera or an uploaded video/image - is active). Both call the same
  `ContextEngineClient.sendFrame()`.

## Behaviour engine (HTTP) - contract verified against real API doc
Endpoints in `.env`:
- `BEHAVIOUR_ENGINE_POST_URL` = `https://myna.glassdata.ai/api/v1/be/process` (built + wired)
- `BEHAVIOUR_GET_EPISODES_URL` = `.../be/analytics/episodes` (not called yet)
- `BEHAVIOUR_GET_GRAPH_URL` = `.../be/analytics/graph` (not called yet)

`BehaviourEngineInput` matches `be_api_reference.md.pdf` exactly: `session_id`, `user_id`,
`timestamp_ms`, `context_metadata.overall_confidence`, `gaze_grounding`, `scene_objects`,
`interaction_primitives`, `hand_object_events`, `omni_context_vlm`, `location_information`,
`gps_coordinates`, optional `voice_nlu`. `toJson()` omits null/unset fields so BE's own documented
fallback chains resolve them instead of us overriding a good fallback with a worse guess. Built in
`pipeline_coordinator.dart` directly from `ContextEngineResponse` (no separate mapper file).

`BehaviourEngineClient.process()` POSTs and returns the raw response (shape varies: `commerce` /
`lifestyle` / motion-suppression). Wrapped in a `CircuitBreaker` (default thresholds: 10 failures /
15s recovery) - see "Resilience layer" below.

`pipeline/behaviour_engine_response.dart` (`BehaviourEngineResponse.parse()`) pulls out
`lifestyleCluster`, `behavioralState`, `recommendedProduct`, `userId`, `relevanceScore`,
`topSalientObjects`, and (added for the interaction engine's telemetry) `stateConfidence`
(`state_confidence`) and `hesitationScore` (`hesitation_score`).

### Mapping gaps (BE request built in pipeline_coordinator.dart)
- `product_rotation.active` - always `false`, no CE signal for it yet.
- `pickup.active`/`pickup.object_id` - derived from CE's `hand_object_events.event_type ==
  'pickup'`; unverified against a real pickup event.
- `attention_grounding` is intentionally omitted - BE's own fallback chain already reads
  `gaze_grounding.grounded_target`, which we do send.

## Ecom hub (HTTP) - real deployed endpoints, contract cross-checked against a working reference app
Cross-checked against `C:\Dev\smartglass_flutter\lib\core\engines\ecom\ecom_client.dart` (same
backend, called "Action Hub" there). Two real contract bugs found and fixed early on:
1. **GET endpoints take zero parameters.** The server already has context from the `/inp` POST.
2. **The `/inp`/`/recommend` POST body doesn't include `gaze_target` or `scene_objects`.** Real
   fields: `timestamp_ms`, `relevance_score`, `top_salient_objects` (`{class_name,
   salience_score}`), `context_overrides` (`{}`), `user_id`.

- `.env`: `ECOM_HUB_BASE_URL` (`/ah/inp`), `_BUY_URL`, `_RECOMMEND_URL`, `_LIFEBALANCE_URL`,
  `_ANALYZE_URL` - each a full URL.
- `EcomAdHandlerClient`: `postInput`/`postRecommend` take an `EcomHubInput`; `getBuy`/
  `getRecommend`/`getAnalyze`/`getLifebalance` take nothing. Wrapped in a `CircuitBreaker` tuned
  stricter than the default (4 failures / 30s recovery) since one pipeline tick fans out to 5 HTTP
  calls here, so failures accumulate faster than a single-call engine.
- **Verified live end-to-end on Android** - real responses from all 6 calls.
- **CORS (web testing only, doesn't affect Android):** `access-control-allow-origin` is locked to
  `https://myna.glassdata.ai`, so browser calls from any other origin fail client-side with
  `net::ERR_FAILED` even though the server responds fine. `scripts/cors_proxy.js` exists as an
  unused workaround if web testing of this leg is ever needed - not wired into the app; prefer
  Android for this engine.
- **Now gated, not fired every frame** - see "Change-gated calls" under Pipeline below.

## Safety memory (HTTP) - Memory Safety Agent, per MSEAPI.pdf v3
- `SAFETY_MEMORY_URL` (.env) = `https://myna.glassdata.ai/api/v1/msa/`. **Path prefix is `msa`,
  not `sma`** - confirmed by 404-vs-503 probing (`sma` = flat 404 on every route = doesn't exist;
  `msa` = 503 on every route = exists, service was down at the time). `msa` also matches the doc's
  module name (`GD_MYNA_MSA`).
- `SafetyMemoryClient`: `postAllergy(AllergyRequest)`, `postInp(SafetyMemoryInput)`, `getHealth()`,
  `getMemoryQuery({userId})`. Wrapped in a `CircuitBreaker` (default thresholds).
- `SafetyMemoryInput.toJson()` wraps a subset of a CE frame:
  `Myna_Context.{camera_stream, behaviour_engine_telemetry.user_id, scene_objects:
  [{class_name, confidence}], gaze_grounding.grounded_target}`.
- `pipeline/safety_memory_response.dart` pulls out `hazardDetected`, `hazardLevel`, `triggerType`,
  `triggerObject`, `utterance`.
- **UX lesson:** the pipeline's error-isolation pattern (catch a failing engine, return a default
  instead of throwing) can make a failure indistinguishable from a genuine negative result in the
  UI - both look like `hazardDetected: false`. Fixed by checking
  `PipelineResult.safetyMemoryRaw['error']` explicitly before trusting the parsed response. The
  same principle now also applies to **skipped** runs (see below) - `SessionProvider` carries the
  last non-skipped AH/SMA result forward itself, so every screen sees a real result rather than an
  empty one on a skipped tick (see "Change-gated calls" under Pipeline below).
- **Now gated, not fired every frame** - see "Change-gated calls" under Pipeline below.

## Interaction engine (persistent WebSocket) - voice + telemetry, runs on its own clock
- Endpoint: `INTERACTION_WS_URL` (.env) = `wss://myna.glassdata.ai/api/v1/ie/ws` - the PDF's
  documented production path (`/ws`) is **not** the real one; this "local alias" path is what's
  actually deployed, confirmed live (`IE_CONNECTED` in logs).
- Connects once, on **Connect**, with `x-session-id`/`x-user-id` headers (native only - browsers
  can't set WS handshake headers). Stays connected and continuously listening for the entire
  session; **completely independent of Start Session/Stop Session**, which only toggles the
  camera auto-capture loop and never touches `interactionEngineClient` at all.
- **One session id for everything.** `SessionProvider.connect()` is the only place a session id
  gets generated (`InteractionEngineClient.generateSessionId()`, 32-char `Random.secure()`, not a
  timestamp). That same value becomes IE's `x-session-id` header, every BE `/process` call's
  `session_id`, and the Postgres `sessions` row's key. Start Session/Stop Session reuse it; they
  never generate a new one.

### Listening: wake word gates VAD
- Idle mic audio feeds a 3-stage ONNX pipeline (`interaction_engine_wake_word.dart`:
  melspectrogram -> embedding -> classifier, listening for "Hey Myna", threshold 0.35, 2s
  debounce) - ported from `C:\Dev\smartglass_flutter`'s `wake_word_detector.dart`, same models
  (`assets/models/*.onnx`, ~5.6MB total).
- Once triggered (or once VAD alone detects speech, if wake word is off), Silero VAD
  (`flutter_silero_vad`, threshold 0.5) drives `start_of_speech` -> binary PCM16 streaming ->
  `end_of_speech` (5s silence timeout). **Haptic feedback**: `HapticFeedback.lightImpact()` on
  `start_of_speech`, `.mediumImpact()` on `end_of_speech`.
- After any reply, the conversation stays open for **5 seconds** (`_conversationTimeout`) without
  needing the wake word again - tuned up from an initial 2s.

### Speaking: barge-in during playback
- TTS audio (`audio_start`/binary PCM16/`audio_end`) plays via `flutter_pcm_sound`. Mic input is
  **not** muted during playback - it's fed through Silero VAD (no amplitude fallback, since the
  assistant's own voice through the speaker is loud enough to false-trigger an amplitude
  threshold) to detect the user talking over the assistant, auto-sending `interrupt`. A manual
  **Interrupt** button in the UI does the same thing directly, since echo-cancellation behavior on
  a given device can't be verified from code alone.
- `flush_audio` (server-confirmed barge-in) discards the queued/playing audio immediately.

### The BE <-> IE voice_nlu bridge
IE's own `status` message carries a fully-formed `voice_nlu` object once IE's server-side intent
engine ("Rhino") resolves one - **not** the raw ASR transcript. Found at `status.bcp.voice_nlu`,
falling back to top-level `status.voice_nlu` / `status.voice_assistant_response` (confirmed against
`C:\Dev\smartglass_flutter`'s actual working code, not just the PDF's documented example, which
doesn't show this field). Cached client-side with a 15s TTL and folded into the *next* outgoing BE
`/process` request via `BehaviourEngineInput`'s existing optional `voiceNlu` field - no separate
endpoint, no direct coupling between the two clients. `transcript` (the raw ASR text) is
display-only, unrelated to this bridge.

### Telemetry (IE as a IE-ward sink)
After every pipeline run, `pipeline_coordinator.dart` builds an `InteractionTelemetry` from BE's
response and sends it to IE fire-and-forget (`sendTelemetry`, deduped on `gaze_target` only).

### Testing paths
- `sendTextQuery(text)` - `{"type":"text_query"}`, bypasses the mic entirely, injected server-side
  as if it were a transcript. Exposed via a **Send Text Query** field in the UI.
- `sendSetLocation(lat, lon, city, country)` - sent once per city change (via
  `SessionProvider`'s listener on `LocationService`), not on every GPS tick.

### Known real bugs found via live device testing (fixed)
- **Mic-chunk crash**: `RangeError: Offset (5) must be a multiple of BYTES_PER_ELEMENT (2)` in
  `_onMicChunk` - `Uint8List.sublistView` is a *view*, not a copy, so it preserved a non-zero,
  possibly-odd byte offset from the `record` plugin's own internal buffer. Fixed by copying into a
  fresh, zero-offset `Uint8List` before `.buffer.asInt16List()`.
- **Unhandled WebSocket exceptions on reconnect**: `IOWebSocketChannel.connect()` returns
  immediately and connects lazily: a DNS/handshake failure surfaced as a top-level "Unhandled
  Exception" instead of being caught. Fixed by awaiting `channel.ready` inside the same try/catch
  (the same pattern `ContextEngineClient` already used correctly).
- Both found on a real device, not the emulator, underscoring why device testing (not just
  `flutter analyze`/`build`) matters for anything touching native audio/sockets.

## Auth + session layer
Ported from `C:\Dev\smartglass_flutter` after two explicit scope corrections: **glasses/BLE
hardware dropped entirely** (not relevant, no physical Titan hardware here), and **Google
Sign-In needs external OAuth registration** (package name `com.smartpoc.app.smartpoc` + debug
keystore SHA-1, done outside this codebase) - email/password works immediately without it.

- **`lib/auth/auth_provider.dart`** - `AuthProvider`: Google Sign-In, email/password (SHA-256,
  unsalted - mirrors the reference exactly), web guest-mode fallback (SharedPreferences-only
  accounts, since Flutter Web can't open a raw Postgres socket). `SettingsProvider` lives in the
  same file (`wakeWordEnabled`, `preferredCamera` - the only two of the reference's five settings
  SmartPoc actually uses).
- **`lib/auth/db_service.dart`** - `DbService`: direct Postgres connection (`postgres` package),
  credentials from `.env` (`DB_HOST`/`DB_PORT`/`DB_NAME`/`DB_USERNAME`/`DB_PASSWORD`) rather than
  hardcoded in source, native-only (`kIsWeb` guard). Tables: `users`, `user_preferences`,
  `sessions`, `engine_logs`. **Known tradeoff, explicitly accepted by the user**: this embeds
  admin-level DB credentials in a client app - same tradeoff the reference makes, moved to `.env`
  for safer storage but not eliminated.
- **`lib/auth/login_screen.dart`** - minimal email/password + Google Sign-In UI.
- **`lib/session/session_provider.dart`** - `SessionProvider`: owns every engine client
  (`contextEngineClient`, `behaviourEngineClient`, `ecomAdHandlerClient`, `safetyMemoryClient`,
  `interactionEngineClient`) plus `SourceManager`, `TelemetryService`, `HealthMonitor`, and
  `DbService`, for the life of one login session, plus the latest `PipelineResult`. Every screen
  reads what it needs via `context.watch<SessionProvider>()` instead of owning its own client
  fields or re-running the pipeline itself.
- **`lib/sources/`** - `SourceAdapter` interface + `SourceManager` (active adapter + auto-fallback
  to phone on disconnect) + `meta_glasses_source_adapter.dart` (Ray-Ban Meta smart glasses via
  `MetaGlassesService` + real GPS) + `phone_source_adapter.dart` (real camera via `camera_service.dart` +
  real GPS) + `video_upload_source_adapter.dart` (decodes an uploaded image/video; video-frame
  extraction only works on web - see below). `SourceManager`'s default active type is `metaGlasses`
  with seamless fallback to `phone`. A `laptop_source_adapter.dart` from the reference was never
  ported - it wasn't real webcam capture either (hardcoded fake bytes despite the name), and
  SmartPoc doesn't target desktop.
- **`lib/diagnostics/`** - `TelemetryService` (FPS/latency counters) + `HealthMonitor` (polls
  `CircuitBreaker.state` for BE/AH/SMA + `SourceManager` health every 3s).
- **`lib/app_router.dart`** - minimal `GoRouter`: `/login` <-> `/home`, redirect on
  `AuthProvider.isLoggedIn`.

### Resilience layer
`lib/pipeline/circuit_breaker.dart` - `CircuitBreaker` (closed/open/halfOpen) wraps BE, AH, and
SMA's outgoing calls directly (each client owns a `circuitBreaker` field). **CE and IE do not get
one** - both are long-lived WebSocket connections with their own reconnect logic (CE: manual
reconnect via the Connect button; IE: 500ms auto-reconnect + 15s heartbeat), and a circuit breaker
is built for "many short calls, trip after N failures," which doesn't map onto one persistent
connection the same way.

### Role-based access - plumbing exists, nothing gates on it
`AuthProvider.isAdmin` and the `users.is_admin` Postgres column exist (ported from the reference),
but **nothing in the app currently checks it** - no admin routes, no admin-only UI, no hardcoded
super-admin email list (the reference's was dropped). It's inert until something is built to
actually gate on it.

### Known gaps / deliberate cuts
- **`video_thumbnail` package dropped.** Its Gradle script uses the removed `jcenter()` repo,
  breaking the build on this project's modern AGP - and it's the last-published version, so there
  was no newer one to bump to. Real video-frame extraction for uploaded video files only works on
  web now (via `video_decoder_web.dart`'s `<video>`/`<canvas>` approach); native falls back to a
  placeholder frame. Image uploads are unaffected either way.
- **Glasses/BLE hardware** (Titan adapter, `flutter_blue_plus`, native pairing) - not ported.
- **Google Sign-In** - code path is complete, but non-functional until the user completes the
  external OAuth Android + Web client registration (SHA-1 + package name).

## Pipeline (`pipeline_coordinator.dart`): ce -> {be, safety memory} -> ah, + ie hooks
`runPipeline(ceOutput, {behaviourEngineClient, ecomAdHandlerClient, safetyMemoryClient,
interactionEngineClient, sessionId, activeVoiceNlu}) -> PipelineResult`:
1. Parses CE output -> `ContextEngineResponse`.
2. **Change-gated calls** (see below) decide whether safety memory fires this tick.
3. Builds a `BehaviourEngineInput` from `ContextEngineResponse` (using the one stable `sessionId`,
   not CE's own per-frame echoed session value) + `activeVoiceNlu` if IE has one cached, calls BE
   `/process`, parses the response.
4. Builds `EcomHubInput` from BE's response. Change-gated calls decide whether AH's 6 calls fire.
5. Fire-and-forget: builds `InteractionTelemetry` from BE's response, sends to IE (deduped on
   `gaze_target`).
6. Awaits the safety-memory future (if one was started), caught in isolation so an AH/SMA failure
   never discards the already-computed CE/BE results.

### Change-gated calls (added after finding AH/SMA fired on every single frame)
Both AH (6 HTTP calls) and safety memory used to fire unconditionally every pipeline tick. Now
both are gated purely on the scene changing - no time-based fallback for either:
- **Ecom Hub**: fires when CE's `scene_objects` (class names) or `gaze_grounding.grounded_target`
  changed since the last time AH actually ran - mirrors the debounce in
  `C:\Dev\smartglass_flutter`'s `GateCheckStep`, added there because firing on every ~4s frame
  regardless of change was enough sustained load to tip an already-degraded backend into 502s.
- **Safety memory**: fires only when `scene_objects` changed - no fallback timer, since a missed
  allergy check has real consequences a periodic refresh doesn't meaningfully mitigate.
- Tracking state (`_lastEcomSceneObjects`/`_lastEcomGazeTarget`/`_lastSafetySceneObjects`) lives
  as module-level private variables in `pipeline_coordinator.dart`
  - the file is a plain function, not a class, so this mirrors how `InteractionEngineClient`
    already dedups its own telemetry sends as instance state, just at file scope instead.
- `PipelineResult.ecomSkipped`/`.safetySkipped` are consumed inside `SessionProvider._runPipeline()`
  itself now (see "UI: theme + primary screens" above) - the carried-forward result it stores means
  no screen has to special-case a skipped tick.

`debug_screen.dart`'s UI has 6 boxes: **Scene objects**, **VLM description**, **Lifestyle**,
**Safety hazard**, **Interaction / Voice** (live listening-state indicator + Interrupt button),
**Ecom hub responses**. Plus a "paste a CE output JSON" field + **Run Pipeline From JSON** button,
and a **Send Text Query** field for IE. **Start Session**/**Stop Session** toggle the auto-capture
loop; **Connect**/**Capture & Send** remain the original manual flow - both paths funnel into the
same `SessionProvider._runPipeline()`.

## Android setup notes
- Manifest permissions: `INTERNET`, `CAMERA` (+ camera features), `RECORD_AUDIO`,
  `ACCESS_FINE_LOCATION`/`ACCESS_COARSE_LOCATION` - none present by default after `flutter create`.
- **compileSdk/targetSdk pinned to 37 with an SDK platform alias**: the installed API 37 platform
  package is named `android-37.0` but AGP looks up a folder literally named `android-37`. Fixed by
  copying `sdk/platforms/android-37.0` to `sdk/platforms/android-37` (SDK-level, one-time) and
  hardcoding `compileSdk = 37` / `targetSdk = 37` (`permission_handler_android` requires >= 37).
- **A second, plugin-level compileSdk mismatch**: `flutter_pcm_sound`'s own `build.gradle`
  declares `compileSdkVersion 33`, too low for AndroidX deps it pulls in (need 34+), independent of
  the app module's own `compileSdk`. Fixed with a root `android/build.gradle.kts` `subprojects {}`
  block that forces every Android-library subproject to `compileSdk = 37`. This needed
  `state.executed` guarding, not a plain `afterEvaluate`/`pluginManager.withPlugin` - the Flutter
  Gradle Plugin's own `evaluationDependsOn(":app")` eagerly evaluates plugin subprojects in an
  order where some are already-evaluated by the time a naive hook would try to register.
- `video_thumbnail` (see "Known gaps" above) uses the removed `jcenter()` repo and had to be
  dropped rather than patched - no newer version exists to bump to.
- `flutter emulators` already had a `myna` AVD pre-configured.
- **Emulator package-manager corruption**: after many install cycles in one session, the `myna`
  AVD's `pm`/`system_server` started failing every install with "Broken pipe" (`cmd: Failure
  calling service package/activity`) - not a storage issue (566MB free was enough), a genuinely
  corrupted userdata image. Fixed with a full cold boot + data wipe
  (`emulator.exe -avd myna -wipe-data -no-snapshot-load`), not just an `adb kill-server` restart
  (tried first, didn't help). If this recurs, wipe before spending time on it.
  `MSYS_NO_PATHCONV=1` is needed before `adb shell` commands with leading-slash paths in Git Bash,
  otherwise it rewrites `/data` etc. as a Windows path.
- **Physical-device testing**: when the emulator's DNS resolver broke separately (system-wide,
  not just for the backend host - `ping google.com` also failed - likely a side effect of the data
  wipe not fully re-establishing network config), testing moved to a connected physical Android
  phone (`flutter run -d <device-id>`) rather than continuing to debug the emulator's network
  stack. `adb devices` needs `-s <id>` once more than one device/emulator is attached, or every
  `adb` command fails with "more than one device/emulator".

## Files

| File | Purpose |
|---|---|
| `env_config.dart` | Reads all engine URLs + DB/OAuth config from `.env` |
| `app_logger.dart` | On-device timestamped request/response log |
| `app_router.dart` | `GoRouter`, `/login` <-> `/home` gated on `AuthProvider.isLoggedIn` |
| `location_service.dart` | Real device GPS + reverse-geocoded city/country |
| `context_engine/*` | CE WebSocket client + request payload |
| `behaviour_engine/*` | BE HTTP client + request payload + `VoiceNlu` |
| `ecom_ad_handler/*` | AH HTTP client (6 calls) + request payload |
| `safety_memory/*` | SMA HTTP client + request payload |
| `interaction_engine/interaction_engine_input.dart` | `InteractionTelemetry`, `VoiceNlu` parser |
| `interaction_engine/interaction_engine_client.dart` | IE connection, VAD, wake word, playback, barge-in |
| `interaction_engine/interaction_engine_wake_word.dart` | 3-stage ONNX "Hey Myna" pipeline |
| `auth/auth_provider.dart` | `AuthProvider` (Google/email-password), `SettingsProvider` |
| `auth/db_service.dart` | Direct Postgres: users/sessions/engine_logs |
| `auth/login_screen.dart` | Login UI |
| `session/session_provider.dart` | Owns every engine client + latest `PipelineResult` for one login session |
| `sources/*` | `SourceAdapter`/`SourceManager` + phone/video-upload adapters |
| `diagnostics/telemetry_service.dart` | FPS/latency/dropped-frame counters |
| `diagnostics/health_monitor.dart` | Polls circuit-breaker + source health |
| `pipeline/*_response.dart` | Per-engine response parsers |
| `pipeline/circuit_breaker.dart` | `CircuitBreaker` shared by BE/AH/SMA clients |
| `pipeline/engine_registry.dart` | Logical engine name -> base URL |
| `pipeline/pipeline_coordinator.dart` | `runPipeline()` - full orchestration + change-gating |
| `main.dart` | Bootstrap only: `SmartPocApp` (`MultiProvider` + `MaterialApp.router`) |
| `app_theme.dart` | `AppColors` palette + `buildAppTheme()` - single theme source |
| `home_shell.dart` | Bottom-nav shell: Home / Activity / Profile |
| `home_screen.dart` | Session status, Start/Stop, voice strip, best-effort AH recommendations |
| `choose_source_screen.dart` | Pick capture source, then connect + start the runtime |
| `activity_screen.dart` | Recent sessions from `DbService` (native only) |
| `profile_screen.dart` | User info + links to Settings/Developer Tools/About/Log out |
| `settings_screen.dart` | Wake-word toggle, connected account |
| `debug_screen.dart` | Original raw engine test harness: camera preview, Connect/Capture&Send/Start&Stop Session, voice status card, 6-box result view |
| `scripts/cors_proxy.js` | Standalone, unused-by-app local CORS proxy |

## Progress

| Status | Item |
|---|---|
| ✅ | All 5 engines built and wired: context, behaviour, ecom hub, safety memory, interaction |
| ✅ | Full pipeline `ce -> {be, safety memory} -> ah` + IE telemetry/voice_nlu hooks, verified live |
| ✅ | Change-gated AH/SMA calls (scene_objects/grounded_target dedup, not every frame) |
| ✅ | Interaction engine: wake word, VAD, barge-in (auto + manual), TTS playback, haptics, verified live on a physical device |
| ✅ | Auth (Google + email/password + Postgres) + session provider layer, ported and scoped down from `smartglass_flutter` |
| ✅ | Android build issues resolved (permissions, compileSdk 37 alias, plugin-level compileSdk override, video_thumbnail removed) |
| ✅ | On-device debug log (`AppLogger`) + adb pull / Download Log button |
| ✅ | Real Home/Activity/Profile/Settings UI (`app_theme.dart` + `home_shell.dart` etc.), replacing the raw harness as the post-login screen; harness kept as Developer Tools |
| ⬜ | Google Sign-In: `GOOGLE_WEB_CLIENT_ID` is set (web works), Android SHA-1 registration status not reverified this session |
| ⬜ | Role-based access (`isAdmin`) is plumbed but nothing gates on it yet |
| ⬜ | Native video-file frame extraction (video_thumbnail dropped; web-only via canvas for now) |
| ⬜ | Remaining behaviour engine endpoints (`/episodes`, `/graph`) |
| ⬜ | `/allergy`, `/memory/query` not wired into the automatic pipeline (need explicit user input) |
| ⬜ | Route safety-memory hazard utterances into IE (`// TODO` in `pipeline_coordinator.dart` - mechanism still to be specified) |
| ⬜ | Re-parse the 6 real AH response shapes into typed fields once relied on for something beyond display |

## Testing notes
`flutter run -d web-server` on this machine hits a Windows-specific bug where DDC's debug
module loader emits some script URLs with backslashes and hangs (blank page, no console errors).
Workaround: use `flutter build web` (compiled, no DDC) and serve `build/web` as static files for
local browser testing instead. For engines with CORS restrictions or native-only behavior
(ecom hub, interaction engine's audio path), prefer Android/a physical device over web entirely.

### Web blank-page bug (root-caused and fixed)
A separate, longer-standing blank-page bug turned out to be two unrelated startup crashes, not the
DDC issue above - both were unhandled exceptions thrown before `runApp()` ever ran:
1. `WakelockPlus.enable()` has no working web channel in this setup and threw
   `PlatformException(channel-error)` uncaught. Fixed by skipping it on web (`kIsWeb` guard in
   `main.dart`) - it's a mobile-only concern anyway.
2. The generated `.dart_tool/flutter_build/*/web_plugin_registrant.dart` was stale and silently
   missing `google_sign_in_web`/`shared_preferences_web`, even though `.flutter-plugins-dependencies`
   correctly listed both - both threw `MissingPluginException` uncaught. Fixed by deleting
   `.dart_tool/flutter_build/` (not a full `flutter clean`, which fights the IDE's Dart analysis
   server for file locks on this machine) to force fresh codegen on the next build.
3. Once those were fixed, `GoogleSignIn(...)` turned out to be constructed eagerly as a field
   initializer in `AuthProvider`, which kicks off Google's hosted Identity Services script
   unconditionally at boot on web - fragile (network/origin-dependent) to run before any user
   interaction. Fixed in `auth/auth_provider.dart`: only constructed when `GOOGLE_WEB_CLIENT_ID` is
   actually set, with null-safe call sites in `loginWithGoogle()`/`logout()`.

Diagnosed by driving a headless Chromium instance directly over the DevTools Protocol (CDP) -
`Runtime.exceptionThrown` plus `node:module`'s built-in `SourceMap` class to resolve minified
`main.dart.js` positions back to real Dart source, since the browser console's printed stack text
doesn't auto-symbolicate even with a loaded `.js.map`.
