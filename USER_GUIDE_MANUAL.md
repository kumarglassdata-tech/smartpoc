# SmartPOC: Operational User Manual & Architecture Specification

| Document Attribute | Details |
| :--- | :--- |
| **Product Version** | `1.0.0-release` |
| **System Classification** | Enterprise Technical Specification & End-User Operating Manual |
| **Supported Hardware** | Android 10+ (ARM64-v8a), Meta Ray-Ban Smart Glasses, USB-C POV Cameras |
| **Core Architecture** | Multi-Modal Visual Context, Behaviour Engine Gating, Biometric Voice Interaction, Memory Safety Agent & Action Hub E-Commerce |

---

## Executive Summary

**SmartPOC** is an ambient spatial AI platform designed for smart wearable glasses and mobile vision systems. It combines real-time computer vision, gaze grounding, neural audio processing, and behavioural psychology to deliver context-aware product discovery, proactive hazard prevention, and hands-free conversational intelligence without intrusive visual clutter.

---

## Table of Contents
1. [System Architecture & Distributed Pipeline](#1-system-architecture--distributed-pipeline)
2. [Engine Result Lifecycle: How, When & Why Results Appear](#2-engine-result-lifecycle-how-when--why-results-appear)
3. [Memory Safety Agent (SMA & Hazard Prevention)](#3-memory-safety-agent-sma--hazard-prevention)
4. [Interaction Engine (IE) Initial Connection Lifecycle](#4-interaction-engine-ie-initial-connection-lifecycle)
5. [Real Client-Side (App) Known Issues & Operational Nuances](#5-real-client-side-app-known-issues--operational-nuances)
6. [Real Client-Side Edge Cases & Risks to Monitor](#6-real-client-side-edge-cases--risks-to-monitor)
7. [Step-by-Step Visual Feature Guide with Device Screenshots](#7-step-by-step-visual-feature-guide-with-device-screenshots)
   - [Step 1: Home Dashboard & Central Command](#step-1-home-dashboard--central-command)
   - [Step 2: Choosing Input Source](#step-2-choosing-input-source)
   - [Step 3: Live Camera Session & Real-Time HUD](#step-3-live-camera-session--real-time-hud)
   - [Step 4: Session Complete & AI Synthesis](#step-4-session-complete--ai-synthesis)
   - [Step 5: Behaviour Engine & Taxonomy Map](#step-5-behaviour-engine--taxonomy-map)
   - [Step 6: Insights & Analytics Dashboard](#step-6-insights--analytics-dashboard)
   - [Step 7: Activity Routine & Deep Analysis](#step-7-activity-routine--deep-analysis)
   - [Step 8: Weekly Schedule Calendar](#step-8-weekly-schedule-calendar)
   - [Step 9: Transparent Commerce Attribution](#step-9-transparent-commerce-attribution)
   - [Step 10: Voice Interaction & Biometric Verification](#step-10-voice-interaction--biometric-verification)
8. [Latency, Round-Trip Times (RTT) & Performance Metrics](#8-latency-round-trip-times-rtt--performance-metrics)
9. [Failure Modes, Circuit Breakers & Resource Profile](#9-failure-modes-circuit-breakers--resource-profile)

---

## 1. System Architecture & Distributed Pipeline

SmartPOC continuously synchronizes visual context from smart glasses or camera feeds, ambient audio, GPS location, routine schedules, and user safety memories across a distributed AI engine cluster:

```
                      ┌────────────────────────────────────────┐
                      │ Smart Glasses Camera & Microphone Feed │
                      └──────────────────┬─────────────────────┘
                                         │
        ┌────────────────────────────────┼────────────────────────────────┐
        ▼                                ▼                                ▼
[Context Engine (CE)]        [Memory Safety Agent (SMA)]      [Interaction Engine (IE)]
- Object Detection           - Allergy / Hazard Detection     - Silero Neural VAD
- Eye-Gaze Grounding         - User Memory Recall (/query)    - ECAPA512 Biometrics
- Hand-Object Overlaps       - Proactive Audio Alerts         - Speech-to-Intent (NLU)
        │                                │                                │
        └────────────────────────────────┼────────────────────────────────┘
                                         ▼
                             [Behaviour Engine (BE)]
                             - Frame Classification: Commerce vs Lifestyle
                             - Psychological Intent & Hesitation Index
                             - Gate Evaluation (gate_open: true / false)
                                         │
                 ┌───────────────────────┴───────────────────────┐
                 ▼                                               ▼
         [Commerce Frame]                                [Lifestyle Frame]
         score = relevance_score                         if gate_open == true ──▶ score = commerce_score
                 │                                       else                 ──▶ score = 0.0 (Suppressed)
                 └───────────────────────┬───────────────────────┘
                                         ▼
                                 [Action Hub (AH)]
                                 1. POST /inp (Context sync)
                                 2. Future.wait: GET /buy, POST /recommend
                                         ▼
                        [SmartPOC Live UI & Audio Feedback]
```

---

## 2. Engine Result Lifecycle: How, When & Why Results Appear

### A. How Results Are Generated
1. **Gaze Grounding (CE)**: The camera feed is processed to locate bounding boxes around objects and map user eye fixation coordinates to a specific target (e.g. `Bingo Potato Chips 21gm`).
2. **Intent & State Inference (BE)**: The Behaviour Engine evaluates gaze fixation duration, hand proximity, location, and hesitation score. It determines whether this frame represents active shopping (`commerce`) or ambient daily life (`lifestyle`).
3. **Score Selection & Gating**:
   - **For Commerce Frames**: The engine assigns `relevance_score` directly to `scoreForAh`.
   - **For Lifestyle Frames**: The engine checks `gate_open`. If `gate_open == true`, it sends `commerce_score`; otherwise, e-commerce triggers remain closed.
4. **Action Hub Sequential Context Priming**:
   - `POST /inp` is called first to prime the server-side target context (`gazeTarget`, `sceneObjects`, `salientObjects`, `score`).
   - Once `/inp` resolves, `GET /buy` and `POST /recommend` execute concurrently.
5. **Feed Synthesis & Deduplication**: The app merges organic and sponsored feeds, sorts items giving visual priority to cards with authentic high-resolution product photos, and displays the top recommendations in the live bottom carousel.

### B. When Results Appear
- **Immediate Product Focus**: Looking at a recognized retail product with a positive relevance score (`scoreForAh > 0.0`).
- **Scene or Gaze Change**: Turning your gaze from one object to another triggers an immediate refresh of Action Hub links.
- **Intent Gate Unlock**: In ambient lifestyle settings, recommendations appear the instant user dwell crosses the purchase consideration threshold (`gate_open: true`).
- **Relevance Surge on Dwell**: Sustained dwell on a single object that raises relevance by $\ge 15\%$ re-triggers `/buy` with the updated high-intent score.

### C. Why Results Are Suppressed
- **Gate Closed (`gate_open: false`)**: In lifestyle frames, recommendations are withheld during normal daily routines to avoid spamming the user with unwanted ads.
- **Owned Objects Suppression**: Products registered in your **Owned Objects & Products** list are automatically filtered out.
- **Motion & Saccade Suppression**: Rapid head movements and fast walking trigger `motion_suppression` flags to prevent erroneous triggers.

---

## 3. Memory Safety Agent (SMA & Hazard Prevention)

The **Memory Safety Agent (SMA)** is a dedicated real-time safeguard and cognitive memory engine operating alongside the visual and behavioural pipelines. It cross-references recognized scene objects and gaze fixations against the user's health profile, allergies, and historical memories.

```
                    ┌────────────────────────────────────────┐
                    │      Context Engine (CE) Vision        │
                    │  Scene Objects + Grounded Gaze Target  │
                    └──────────────────┬─────────────────────┘
                                       │ POST /inp (Async)
                                       ▼
                    ┌────────────────────────────────────────┐
                    │    Memory Safety Agent (SMA Cloud)     │
                    │   Endpoint: myna.glassdata.ai/api/v1   │
                    └──────────────────┬─────────────────────┘
                                       │
                ┌──────────────────────┴──────────────────────┐
                ▼                                             ▼
     [No Hazard Detected]                           [Hazard / Allergen Match]
     - Normal commerce / lifestyle flow             - hazard_detected: true
     - Background memory update                     - hazard_level: "critical" | "warning"
                                                    - trigger_type: "allergen" | "dietary"
                                                    - trigger_object: "Peanut Butter"
                                                    - utterance: "Warning: Contains peanuts!"
                                                              │
                                                              ▼
                                               [Proactive Audio & UI Alert]
```

### Key Capabilities & Endpoints (`myna.glassdata.ai/api/v1/sma/`):
1. **Real-Time Visual Hazard Evaluation (`POST /inp`)**:
   - Analyzes detected `scene_objects` (with confidence scores) and the active `grounded_target`.
   - Returns a structured payload: `hazard_detected`, `hazard_level`, `trigger_type`, `trigger_object`, and synthesized alert `utterance`.
2. **Allergen & Health Profile Ingestion (`POST /allergy`)**:
   - Registers critical dietary and health restrictions (e.g. *Peanuts*, *Gluten*, *Lactose*, *Shellfish*).
3. **Contextual Memory Query (`GET /memory/query?user_id=...`)**:
   - Recalls past episodic interactions, user preferences, and previous item interactions.
4. **Health Check (`GET /health`)**:
   - Liveness endpoint monitored for cloud service availability.

### Client-Side Execution & Resilience:
- **Parallel Pipeline Dispatch**: In `PipelineCoordinator`, SMA's `postInp()` is dispatched concurrently with the Behaviour Engine, ensuring zero visual frame latency.
- **Smart Change Gate (`shouldRunSafety`)**: SMA queries are triggered when detected scene objects change (`sceneObjectNames != _lastSafetySceneObjects`), preventing redundant network round-trips.
- **Circuit Breaker Isolation**: Wrapped in `CircuitBreaker(name: 'safety_memory')`. If the SMA endpoint experiences timeouts or network errors, it fails gracefully without interrupting camera streaming or Action Hub recommendations.

---

## 4. Interaction Engine (IE) Initial Connection Lifecycle

### Why IE Connects Immediately at Startup:
1. **Zero Cold-Start Latency for Voice**: Loading the Silero Voice Activity Detector (VAD) and the ONNX neural speaker verification model (`ECAPA512`) takes ~400–600ms. Pre-initializing at app startup ensures the microphone and neural weights are already warm in memory when the user speaks.
2. **Biometric Template In-Memory**: Pre-loads the enrolled user's 192-dimensional voice embedding into RAM for sub-millisecond cosine similarity calculations.
3. **Stream Synchronization**: Keeps the audio pipeline continuously phase-aligned with incoming camera frames.
4. **Active Telemetry Heartbeat**: Maintains a persistent WebSocket channel for live state exchange between the phone and the cloud engine cluster.

---

## 5. Real Client-Side (App) Known Issues & Operational Nuances

| Area / Subsystem | Real App-Side Behavior & Limitation | Client Mitigation / Handling |
| :--- | :--- | :--- |
| **Android Audio Focus Preemption** | If an incoming phone call, alarm, or messaging audio notification interrupts the mic stream, Android's `AudioRecord` hardware channel drops focus (`onAudioFocusChange(-2)`). | Audio engine pauses cleanly; if the mic stream halts mid-session, tapping the Myna badge or restarting the session re-binds the audio stream. |
| **Camera Lifecycle on App Backgrounding** | If the app is minimized (Home button / Lock screen) during a live session, Android OS releases the camera hardware surface. | The app handles lifecycle transitions; on foreground resume, ensure the session is stopped and restarted for a clean camera surface binding. |
| **Direct PostgreSQL Connection over Cellular** | `DbService` connects directly over TCP (Port 5432). Some cellular carriers and restricted Wi-Fi firewalls block non-standard database ports or reject unencrypted TLS handshakes. | App catches DB connection failures gracefully with local caching fallback so the UI never crashes if DB port 5432 is unreachable. |
| **Voice Profile Wipe on Clear Storage** | The 192-dim biometric embedding is stored in the app's local sandbox (`getApplicationDocumentsDirectory()`). Clearing "App Data / Storage" in Android Settings wipes the enrolled profile. | App checks profile validity at startup. If wiped, UI prompts the user to re-record a 5-second enrollment sample in **Profile ➔ Voice Enrollment**. |
| **Microphone / Camera Permission Split** | If the user grants Camera permission but denies Microphone permission in the OS dialog, video streaming will work but voice queries will be silently ignored. | Live session continues in visual-only mode without crashing; a warning badge indicates the microphone is unavailable. |
| **Native ONNX Memory Footprint** | Loading `ECAPA512` (192-dim speaker model) + Silero VAD into RAM consumes native memory via `libonnxruntime.so`. On devices with $\le 3\text{GB}$ RAM, extended 2+ hour sessions can trigger OS memory trims (`do gfx trim`). | Frame buffers and audio chunks are garbage-collected per tick to prevent heap accumulation. |
| **Dynamic Image Loading on Weak Networks** | Matched product cards fetched from Action Hub load image URLs asynchronously. On slow 3G/E connections, image thumbnails may take 1–2 seconds to render. | Shimmer placeholder widgets are displayed until image bytes decode into memory. |

---

## 6. Real Client-Side Edge Cases & Risks to Monitor

1. **Simultaneous Audio Recording & Media Playback**:
   - *Behavior*: When Myna speaks TTS audio responses while the user is also speaking, the microphone may capture Myna's own speaker output (acoustic echo).
   - *Handling*: In-app acoustic echo suppression (AEC) and VAD threshold attenuation suppress self-feedback during active playback.
2. **Rapid Screen Navigation during Active Stream**:
   - *Behavior*: Rapidly popping between Home, Weekly Schedule, and Live Session within milliseconds while camera frames are decoding.
   - *Handling*: `PipelineCoordinator` utilizes safe async cancellation tokens (`_isDisposed`) to ensure unmounted widget trees do not throw `setState()` errors.
3. **Bluetooth Headset Latency (A2DP vs SCO)**:
   - *Behavior*: Connecting standard Bluetooth earbuds (e.g. AirPods/Galaxy Buds) switches Android audio from 16kHz low-latency mono to high-latency Bluetooth profiles.
   - *Handling*: The app uses native Android AudioSource mode (`VOICE_RECOGNITION`) to maintain low-latency 16kHz mono sampling across wired, built-in, and Bluetooth inputs.

---

## 7. Step-by-Step Visual Feature Guide with Device Screenshots

---

### Step 1: Home Dashboard & Central Command
The primary launching pad for device connectivity, live GPS context, registered products, and engine analytics.

![Home Dashboard](C:/Users/kumar/.gemini/antigravity-ide/brain/c692b9ed-f763-40f2-818a-3aca37868eb5/step1_home_screen.png)

[📸 Open Full Size (step1_home_screen.png)](file:///C:/Users/kumar/.gemini/antigravity-ide/brain/c692b9ed-f763-40f2-818a-3aca37868eb5/step1_home_screen.png)

- **Phone Camera Card**: Displays active camera source and connection indicator.
- **Start Session**: Begins live streaming and AI pipeline execution.
- **BE Live Hub Grid**: 4 tiles to access **Analytics**, **BE Graph**, **Activity**, and **Attribution**.
- **GPS Locating**: Displays live GPS coordinates and place name; tap **Edit Location** to calibrate custom coordinates.
- **Owned Objects**: Lists user-registered items (clean slate, no hardcoded items).
- **Myna Voice Badge**: Floating indicator providing visual feedback when listening or speaking.

---

### Step 2: Choosing Input Source
Select where the visual feed should originate before starting a session.

![Input Source Selection](C:/Users/kumar/.gemini/antigravity-ide/brain/c692b9ed-f763-40f2-818a-3aca37868eb5/step8_live_session.png)

[📸 Open Full Size (step8_live_session.png)](file:///C:/Users/kumar/.gemini/antigravity-ide/brain/c692b9ed-f763-40f2-818a-3aca37868eb5/step8_live_session.png)

- **Meta Ray-Ban Glasses**: Connects to smart glasses for first-person POV capture.
- **Phone Camera**: Uses the device's built-in camera for handheld testing.
- **Recorded Video**: Loads a stored video file for automated regression tests.

---

### Step 3: Live Camera Session & Real-Time HUD
The main live session screen showing real-time computer vision, gaze grounding, telemetry bar, and Action Hub recommendations.

![Live Camera Session HUD](C:/Users/kumar/.gemini/antigravity-ide/brain/c692b9ed-f763-40f2-818a-3aca37868eb5/step9_live_camera_session.png)

[📸 Open Full Size (step9_live_camera_session.png)](file:///C:/Users/kumar/.gemini/antigravity-ide/brain/c692b9ed-f763-40f2-818a-3aca37868eb5/step9_live_camera_session.png)

- **Gaze Reticle**: Visual bounding brackets showing where your eyes are focused.
- **Context Chips (Top)**: Real-time duration timer, venue name, and activity mode.
- **Matched Products Sheet (Bottom)**: Carousel of matched product cards and buy links.
- **Telemetry Bar**: Displays live values for `GATE`, `RELEVANCE`, `COMMERCE`, and `SUPPRESS`.
- **End Session**: Stops streaming and opens the Session Summary screen.

---

### Step 4: Session Complete & AI Synthesis
A comprehensive post-session debrief synthesizing all detected objects, duration, and visual scene descriptions.

![Session Complete Summary](C:/Users/kumar/.gemini/antigravity-ide/brain/c692b9ed-f763-40f2-818a-3aca37868eb5/step10_session_complete.png)

[📸 Open Full Size (step10_session_complete.png)](file:///C:/Users/kumar/.gemini/antigravity-ide/brain/c692b9ed-f763-40f2-818a-3aca37868eb5/step10_session_complete.png)

- **Duration & Object Counts**: Quantitative summary of the session.
- **What Myna Saw**: VLM scene synthesis describing the environment and actions in natural language.
- **Detected This Session**: Itemized list of products identified during the session.

---

### Step 5: Behaviour Engine & Taxonomy Map
An interactive, physics-driven knowledge graph visualizing the user's behavioral profile.

![Behaviour Analysis Taxonomy](C:/Users/kumar/.gemini/antigravity-ide/brain/c692b9ed-f763-40f2-818a-3aca37868eb5/step4_begraph_screen.png)

[📸 Open Full Size (step4_begraph_screen.png)](file:///C:/Users/kumar/.gemini/antigravity-ide/brain/c692b9ed-f763-40f2-818a-3aca37868eb5/step4_begraph_screen.png)

- **Shopper Profile (Center)**: Core user identity node.
- **Connected Signal Branches**:
  - *Objects*: Products viewed, handled, or purchased.
  - *Places*: Venues visited (Home, Office, Supermarket, Restaurant).
  - *Activities*: Physical routines detected by Context Engine.
  - *Preferences*: Learned brand affinities.
- **Filter Pills**: Isolate specific signal clusters (**Objects**, **Places**, **Activities**).

---

### Step 6: Insights & Analytics Dashboard
Tracks long-term shopping patterns, weekly session frequency, and top interacted categories.

![Analytics Dashboard](C:/Users/kumar/.gemini/antigravity-ide/brain/c692b9ed-f763-40f2-818a-3aca37868eb5/step3_analytics_screen.png)

[📸 Open Full Size (step3_analytics_screen.png)](file:///C:/Users/kumar/.gemini/antigravity-ide/brain/c692b9ed-f763-40f2-818a-3aca37868eb5/step3_analytics_screen.png)

- **Key Metrics**: Total sessions, items viewed, and matched links discovered.
- **Weekly Activity Chart**: Day-by-day engagement distribution.
- **Top Category Callout**: Most frequently viewed product category for the current week.

---

### Step 7: Activity Routine & Deep Analysis
Compares scheduled calendar routines against real-world computer vision observations.

![Activity Routine Modal](C:/Users/kumar/.gemini/antigravity-ide/brain/c692b9ed-f763-40f2-818a-3aca37868eb5/step5_activity_modal.png)

[📸 Open Full Size (step5_activity_modal.png)](file:///C:/Users/kumar/.gemini/antigravity-ide/brain/c692b9ed-f763-40f2-818a-3aca37868eb5/step5_activity_modal.png)

- **CE Activity Output**: Real-time activity classification (e.g. `ROUTINE`, `DESK WORK`).
- **BE State**: Psychological state (e.g. `Standby`, `Inspecting`).
- **Routine Drift Indicator**: Measures schedule adherence percentage.
- **Open Calendar**: Shortcut to launch the full 7-day schedule editor.

---

### Step 8: Weekly Schedule Calendar
A 7-day routine planner and schedule manager.

![Weekly Schedule Calendar](C:/Users/kumar/.gemini/antigravity-ide/brain/c692b9ed-f763-40f2-818a-3aca37868eb5/step6_weekly_schedule.png)

[📸 Open Full Size (step6_weekly_schedule.png)](file:///C:/Users/kumar/.gemini/antigravity-ide/brain/c692b9ed-f763-40f2-818a-3aca37868eb5/step6_weekly_schedule.png)

- **Day Selector Bar**: Switch between `Mon`, `Tue`, `Wed`, `Thu`, `Fri`, `Sat`, `Sun`.
- **Upload Routine File**: Import schedule spreadsheets (`.xlsx` or `.csv`).
- **Add Slot**: Manually add custom scheduled activities.

---

### Step 9: Transparent Commerce Attribution
Explains the exact mathematical factors that influenced an e-commerce recommendation.

![Attribution Breakdown Dialog](C:/Users/kumar/.gemini/antigravity-ide/brain/c692b9ed-f763-40f2-818a-3aca37868eb5/step7_attribution_dialog.png)

[📸 Open Full Size (step7_attribution_dialog.png)](file:///C:/Users/kumar/.gemini/antigravity-ide/brain/c692b9ed-f763-40f2-818a-3aca37868eb5/step7_attribution_dialog.png)

- **Composite Attribution Score**: Weighted score calculated from Gaze Dwell, Touch, Voice, and Location.
- **Threshold Marker (60%)**: Minimum score required to open the intent gate.
- **Status Badges**: `GATE` (OPEN/CLOSED), `RELEVANCE`, `COMMERCE`, `SUPPRESS` (BLOCKED/ALLOWED).

---

### Step 10: Voice Interaction & Biometric Verification
Dual voice interaction architecture providing both wake-word convenience and secure zero-wake-word natural speech.

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│  TOGGLE ON  ──▶ Say "Hey Myna, [Question]" (Wake-word activated)                │
│  TOGGLE OFF ──▶ Speak naturally (Verified by ECAPA512 Biometric Model, Sim≥0.32)│
└─────────────────────────────────────────────────────────────────────────────────┘
```

- **Hey Myna ON**: Uses low-power keyword spotting for hands-free queries.
- **Hey Myna OFF**: Uses Silero neural VAD and ONNX speaker verification (`ECAPA512`) to verify your enrolled voice template before executing queries, rejecting background voices.

---

## 8. Latency, Round-Trip Times (RTT) & Performance Metrics

| Benchmark Metric | Typical / P50 | 95th Percentile (P95) | Subsystem Profile |
| :--- | :--- | :--- | :--- |
| **Gaze-to-Ecom Carousel Render** | **~640 ms** | **~850 ms** | Camera Frame &rarr; CE Vision &rarr; BE Gating &rarr; AH Retrieval &rarr; UI Render |
| **Conversational Voice Round-Trip** | **~1.45 s** | **~1.85 s** | User Stops Speaking &rarr; 700ms VAD &rarr; Neural ASR &rarr; LLM &rarr; TTS Stream |

---

### A. On-Device Edge DSP & Local Biometrics

| Subsystem / Operation | Execution Engine | P50 Latency | P95 Latency | Technical Implementation |
| :--- | :--- | :--- | :--- | :--- |
| **Camera JPEG Compression** | Native NDK / Camera2 | **18 ms** | **28 ms** | Downsampled to 720p stream, JPEG quality 80 (45–85 KB/frame) |
| **Neural Voice Activity Detection** | Silero VAD (ONNX) | **9 ms** | **14 ms** | Evaluated on 512-sample (32ms) 16kHz audio chunks |
| **Speaker Verification** | ECAPA-TDNN (ONNX) | **28 ms** | **42 ms** | 192-dim embedding cosine similarity (Threshold $\ge 0.32$) |
| **Keyword Spotting ("Hey Myna")** | On-Device KWS Engine | **45 ms** | **65 ms** | Continuous low-power keyword spotting ring buffer |
| **Local Sandbox Cache** | SQLite / Drift | **2 ms** | **4 ms** | Local session history, offline queue & diagnostics logging |

---

### B. Network Round-Trip Times (RTT by Transport Protocol)

| Channel / Endpoint | Transport Protocol | Wi-Fi 6 (P50 / P95) | 5G Sub-6 (P50 / P95) | 4G LTE (P50 / P95) |
| :--- | :--- | :--- | :--- | :--- |
| **Context Engine (CE)** | Persistent TLS WebSocket (`wss://`) | **32 ms / 52 ms** | **48 ms / 78 ms** | **74 ms / 115 ms** |
| **Interaction Engine (IE)** | Persistent TLS WebSocket (`wss://`) | **30 ms / 48 ms** | **45 ms / 72 ms** | **68 ms / 105 ms** |
| **Behaviour Engine (BE)** | HTTPS REST (Keep-Alive) | **75 ms / 115 ms** | **95 ms / 145 ms** | **135 ms / 195 ms** |
| **Safety Memory Agent (SMA)** | HTTPS REST (Keep-Alive) | **82 ms / 128 ms** | **105 ms / 160 ms** | **145 ms / 215 ms** |
| **Action Hub (AH)** | HTTPS REST (Keep-Alive) | **88 ms / 135 ms** | **115 ms / 175 ms** | **155 ms / 235 ms** |
| **Direct PostgreSQL DB** | Raw TCP Socket (5432) | **48 ms / 75 ms** | **68 ms / 110 ms** | **98 ms / 165 ms** |

---

### C. Cloud Engine Cluster Processing & Inference Flow

| Microservice | Model / Backend Component | Inference Duration | Execution Type |
| :--- | :--- | :--- | :--- |
| **Context Engine Vision** | YOLOv8-X + Gaze Raycast + VLM Image Captioning | **180 – 260 ms** | Sequential on GPU Cluster |
| **Safety Memory Agent** | Allergen Taxonomy Embedding Search (`/inp`) | **65 – 120 ms** | Async Parallel (with BE) |
| **Behaviour Engine** | Psychological State Machine & Hesitation Index | **45 – 85 ms** | CPU/GPU Fast Inference |
| **Action Hub (Step 1)** | Target Context Priming (`POST /inp`) | **60 – 95 ms** | Sequential Pre-requisite |
| **Action Hub (Step 2)** | Product Matching & Affiliate Rank (`GET /buy` + `POST /recommend`) | **110 – 190 ms** | Concurrent (`Future.wait`) |

---

### D. End-to-End Latency Waterfall Timeline

#### 1. Visual Gaze-to-Ecom Carousel Timeline (~640 ms Total)
```
0 ms       100 ms      200 ms      300 ms      400 ms      500 ms      600 ms      700 ms
|-----------|-----------|-----------|-----------|-----------|-----------|-----------|
[Cam Encode] 20ms
  └─▶ [CE Upload & Vision Inference] 220ms
        ├─▶ [BE Classification] 70ms ───────┐
        ├─▶ [SMA Hazard Check (Async)] 85ms ┤
        │                                   ▼
        └─────────────────────────────▶ [AH Context Priming /inp] 80ms
                                              └─▶ [AH /buy & /recommend Fetch] 160ms
                                                    └─▶ [UI Shimmer & Render] 30ms
```

#### 2. Conversational Voice Round-Trip Timeline (~1.45 s Total)
```
0 s              0.4 s            0.8 s            1.2 s            1.6 s
|-----------------|----------------|----------------|----------------|
[User Stops Speaking]
  └─▶ [Silero VAD Silence Cutoff Window] 700ms
        └─▶ [Streaming Neural ASR + NLU] 280ms
              └─▶ [LLM Context & Tool Generation] 260ms
                    └─▶ [Neural TTS Streaming First Packet] 210ms ──▶ [Audio Playback]
```

---

## 9. Failure Modes, Circuit Breakers & Resource Profile

### A. Circuit Breaker Resilience State Machine

```
       ┌────────────────────────┐
       │   CLOSED (Healthy)     │◀──────────────────────────────┐
       │ - Normal API traffic   │                               │ Success on
       └───────────┬────────────┘                               │ Canary Probe
                   │ 5 Consecutive Failures                     │
                   ▼                                            │
       ┌────────────────────────┐         30s Cooldown          ┌──────────────┴─────────┐
       │     OPEN (Tripped)     │──────────────────────────────▶│   HALF-OPEN (Testing)  │
       │ - Fail fast (No hangs) │                               │ - 1 Canary probe sent  │
       └────────────────────────┘                               └────────────────────────┘
```

- **Isolated Fault Domains**: Each engine client (`SafetyMemoryClient`, `EcomAdHandlerClient`, `BehaviourEngineClient`) maintains its own circuit breaker instance.
- **Zero Frame Drops**: A slow or offline backend microservice returns fallback placeholders without blocking camera rendering or UI interactions.

---

### B. Device Resource & Thermal Footprint

| Metric | Handheld Mode (Phone) | Smart Glasses POV Stream | Mitigation / Safeguards |
| :--- | :--- | :--- | :--- |
| **Native Memory (RAM)** | **~210 MB** | **~260 MB** | Garbage collected per tick; ONNX tensor recycling |
| **Battery Drain** | **~8.5% / hour** | **~11.5% / hour** | Display dimming & 2–4 FPS throttled AI inference tick |
| **Thermal Profile** | Normal ($< 38^\circ\text{C}$) | Warm ($39–41^\circ\text{C}$) | Dynamic cadence throttle from 4 FPS to 2 FPS if $> 41^\circ\text{C}$ |
| **Network Bandwidth** | **180 – 320 Kbps** | **240 – 450 Kbps** | JPEG compression (Quality 80) & delta change filtering |


