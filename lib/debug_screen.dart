import 'dart:async';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import 'app_logger.dart';
import 'app_theme.dart';
import 'auth/auth_provider.dart';
import 'context_engine/context_engine_input.dart';
import 'session/session_provider.dart';

// Raw engine test harness - the original TestScreen, kept in full for live
// verification against the real backend. Reachable from Profile >
// Developer Tools rather than being the primary post-login screen.
class DebugScreen extends StatefulWidget {
  const DebugScreen({super.key});

  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen> {
  final _ceJsonInputController = TextEditingController();
  final _textQueryController = TextEditingController();
  String _status = 'Not connected';
  String _voiceText = '(not connected)';
  void Function(double)? _previousWakeWordCallback;
  void Function(double)? _myWakeWordCallback;
  void Function(String, String?)? _previousToastCallback;
  void Function(String, String?)? _myToastCallback;

  SessionProvider get _session => context.read<SessionProvider>();

  @override
  void initState() {
    super.initState();
    final session = _session;
    session.contextEngineClient.onError = (error) =>
        setState(() => _status = 'Error: $error');
    session.interactionEngineClient.onTranscript = (text) =>
        setState(() => _voiceText = 'Heard: $text');
    session.interactionEngineClient.onFinalResponse = (text) =>
        setState(() => _voiceText = 'Assistant: $text');
    session.interactionEngineClient.onStatus = (status) => setState(
      () => _voiceText = 'Mode: ${status['dialogue_mode'] ?? 'idle'}',
    );
    _previousToastCallback = session.interactionEngineClient.onToast;
    _myToastCallback = (message, level) {
      _previousToastCallback?.call(message, level);
      setState(() => _voiceText = 'Toast: $message');
    };
    session.interactionEngineClient.onToast = _myToastCallback;
    _previousWakeWordCallback =
        session.interactionEngineClient.onWakeWordDetected;
    _myWakeWordCallback = (score) {
      _previousWakeWordCallback?.call(score);
      setState(
        () => _voiceText =
            'Wake word detected (${score.toStringAsFixed(2)}) - listening...',
      );
    };
    session.interactionEngineClient.onWakeWordDetected = _myWakeWordCallback;
    // isSpeaking/isPlaying/conversationActive don't have their own callbacks -
    // this fires on every change so the listening indicator stays live.
    session.interactionEngineClient.onStateChanged = () => setState(() {});
    // Reuses SessionProvider's own CameraService instead of opening a second
    // CameraController - two controllers fighting over the same physical
    // camera fails with "Unsupported set of inputs/outputs provided" and
    // knocks out whichever controller the rest of the app is using.
    unawaited(session.cameraService.initialize());
  }

  Future<void> _connect() async {
    setState(() => _status = 'Connecting...');
    if (!_session.cameraService.isInitialized) {
      unawaited(_session.cameraService.initialize());
    }
    await _session.connect();
    if (!mounted) return;
    setState(
      () => _status = _session.state.isConnected
          ? 'Connected'
          : 'Connect failed: ${_session.state.lastError}',
    );
  }

  Future<void> _startSession() async {
    await _session.startRuntime();
    if (!mounted) return;
    setState(() => _status = 'Session running (auto-capture)');
  }

  Future<void> _stopSession() async {
    await _session.stopRuntime();
    if (!mounted) return;
    setState(() => _status = 'Session stopped');
  }

  void _sendTextQuery() {
    final text = _textQueryController.text.trim();
    if (text.isEmpty) return;
    _session.interactionEngineClient.sendTextQuery(text);
    _textQueryController.clear();
  }

  void _interrupt() => _session.interactionEngineClient.triggerBargeIn();

  Future<void> _captureAndSend() async {
    final cameraController = _session.cameraService.controller;
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    final capturedFile = await cameraController.takePicture();
    final jpegBytes = await capturedFile.readAsBytes();

    final locationService = _session.locationService;
    final input = ContextEngineInput(
      gpsCoordinates: GpsCoordinates(
        lat: locationService.latitude ?? 12.9716,
        lon: locationService.longitude ?? 77.5946,
      ),
      temperatureC: 38.5,
      facingMode: 'environment',
      userId: _session.userId,
    );
    _session.contextEngineClient.sendFrame(input, jpegBytes);
    setState(() => _status = 'Frame sent');
  }

  // Lets you paste a CE output JSON directly and run it through be+ah,
  // without connecting a camera - useful for testing against a known frame.
  void _runPipelineFromJsonInput() {
    try {
      final ceOutput =
          jsonDecode(_ceJsonInputController.text) as Map<String, dynamic>;
      setState(() => _status = 'Running pipeline from pasted JSON...');
      _session.runPipelineFromJson(ceOutput);
    } catch (error) {
      setState(() => _status = 'Invalid JSON: $error');
    }
  }

  Future<void> _downloadLog() async {
    final logFile = AppLogger.logFile;
    if (logFile == null) {
      setState(() => _status = 'No log file on this platform (Android only)');
      return;
    }
    await SharePlus.instance.share(ShareParams(files: [XFile(logFile.path)]));
  }

  Future<void> _logout() async {
    await context.read<AuthProvider>().logout();
  }

  @override
  void dispose() {
    if (identical(
      _session.interactionEngineClient.onWakeWordDetected,
      _myWakeWordCallback,
    )) {
      _session.interactionEngineClient.onWakeWordDetected =
          _previousWakeWordCallback;
    }
    if (identical(_session.interactionEngineClient.onToast, _myToastCallback)) {
      _session.interactionEngineClient.onToast = _previousToastCallback;
    }
    _ceJsonInputController.dispose();
    _textQueryController.dispose();
    super.dispose();
  }

  Widget _voiceStatusCard() {
    final ie = _session.interactionEngineClient;
    final String stateText;
    if (!ie.isConnected) {
      stateText = 'Not connected';
    } else if (ie.isPlaying) {
      stateText = 'Assistant speaking...';
    } else if (ie.isSpeaking) {
      stateText = 'Listening to you...';
    } else if (ie.conversationActive) {
      stateText = 'Listening (follow-up, no wake word needed)';
    } else if (ie.wakeWordEnabled) {
      stateText = "Say 'Hey Myna' to talk";
    } else {
      stateText = 'Listening (no wake word - speak anytime)';
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.accentTint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            ie.isPlaying ? Icons.volume_up : Icons.mic,
            color: AppColors.accentStrong,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              stateText,
              style: TextStyle(color: AppColors.textPrimary),
            ),
          ),
          if (ie.isPlaying)
            TextButton(onPressed: _interrupt, child: const Text('Interrupt')),
        ],
      ),
    );
  }

  Widget _infoBox(String title, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(
            content,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final sessionState = session.state;
    final pipelineResult = session.lastPipelineResult;
    final email = context.watch<AuthProvider>().email;

    final sceneObjectsText = pipelineResult == null
        ? '(none yet)'
        : (pipelineResult.contextEngineResponse.sceneObjects.isEmpty
              ? '(none detected)'
              : pipelineResult.contextEngineResponse.sceneObjects
                    .map((o) => o.className ?? 'unknown')
                    .join(', '));
    final vlmDescriptionText =
        pipelineResult?.contextEngineResponse.vlmDescription ?? '(none yet)';
    final lifestyleText =
        pipelineResult?.behaviourEngineResponse.lifestyleCluster ??
        '(none yet)';
    final hazardText = pipelineResult == null
        ? '(none yet)'
        : (() {
            final smaError = pipelineResult.safetyMemoryRaw['error'];
            if (smaError != null) return 'Safety memory failed: $smaError';
            final sma = pipelineResult.safetyMemoryResponse;
            return sma.hazardDetected
                ? '${sma.hazardLevel}: ${sma.utterance}'
                : 'No hazard detected';
          })();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Developer Tools'),
        actions: [
          if (email.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(child: Text(email)),
            ),
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            children: [
              SizedBox(
                height: 120,
                child: ListenableBuilder(
                  listenable: session.cameraService,
                  builder: (context, _) {
                    final cameraController = session.cameraService.controller;
                    if (cameraController == null ||
                        !cameraController.value.isInitialized) {
                      return const Center(child: Text('Initializing camera…'));
                    }
                    return CameraPreview(cameraController);
                  },
                ),
              ),
              const SizedBox(height: 12),
              Text('Status: $_status'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _connect,
                      child: const Text('Connect'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: _captureAndSend,
                      child: const Text('Capture & Send'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: sessionState.isRuntimeActive
                          ? null
                          : _startSession,
                      child: const Text('Start Session'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: sessionState.isRuntimeActive
                          ? _stopSession
                          : null,
                      child: const Text('Stop Session'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _downloadLog,
                  child: const Text('Download Log'),
                ),
              ),
              const SizedBox(height: 16),
              _voiceStatusCard(),
              const SizedBox(height: 16),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Send a text query to IE (mic bypass):'),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textQueryController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'e.g. what is on sale?',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _sendTextQuery,
                    child: const Text('Send'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Or paste a CE output JSON:'),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _ceJsonInputController,
                maxLines: 4,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '{"Myna_Context": {...}}',
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _runPipelineFromJsonInput,
                  child: const Text('Run Pipeline From JSON'),
                ),
              ),
              const SizedBox(height: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoBox('Scene objects', sceneObjectsText),
                  const SizedBox(height: 12),
                  _infoBox('VLM description', vlmDescriptionText),
                  const SizedBox(height: 12),
                  _infoBox('Lifestyle', lifestyleText),
                  const SizedBox(height: 12),
                  _infoBox('Safety hazard', hazardText),
                  const SizedBox(height: 12),
                  _infoBox('Interaction / Voice', _voiceText),
                  if (session.lastPipelineError != null) ...[
                    const SizedBox(height: 12),
                    _infoBox('Pipeline error', session.lastPipelineError!),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
