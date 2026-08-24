import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'package:flutter_silero_vad/flutter_silero_vad.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../app_logger.dart';
import '../behaviour_engine/behaviour_engine_input.dart';
import '../env_config.dart';
import 'interaction_engine_input.dart';
import 'interaction_engine_wake_word.dart';
import 'speaker_profile.dart';
import 'speaker_verification_client.dart';
import 'web_pcm_player_stub.dart' if (dart.library.html) 'web_pcm_player_web.dart';

// Silence gap before an utterance is considered finished - short rather than
// 0ms so a brief inter-word pause doesn't cut the user off mid-sentence, but
// still reads as "immediate" end_of_speech.
const _silenceTimeout = Duration(milliseconds: 500);
// Grace period for the first silence check right after a wake-word trigger -
// deliberately much longer than _silenceTimeout: people pause to gather
// their query right after saying the wake phrase, and 500ms here was
// closing the utterance before they'd said anything at all.
const _postWakeGrace = Duration(milliseconds: 2000);
// How long plain VAD keeps listening after a response before requiring the
// wake word again - gives the user a real follow-up window instead of
// forcing "Hey Myna" again for every single turn.
const _conversationTimeout = Duration(seconds: 5);
// How long a received voice_nlu stays eligible for the next BE request.
const _voiceNluTtl = Duration(seconds: 15);
// Safety cap on one continuous utterance - guards against a stuck
// amplitude-VAD false-positive (see _evaluateFrame) leaving _isSpeaking
// true forever with no end_of_speech ever sent.
const _maxUtteranceDuration = Duration(seconds: 8);

// Persistent WebSocket to the Interaction Engine: hands-free voice
// (wake-word + VAD gated mic streaming, TTS playback, barge-in) plus a
// telemetry sink for per-tick BE state. Sends get no direct reply - replies
// arrive later as unrelated inbound messages.
class InteractionEngineClient {
  final String interactionWsUrl;
  InteractionEngineClient({String? interactionWsUrl})
    : interactionWsUrl = interactionWsUrl ?? EnvConfig.interactionWsUrl;

  WebSocketChannel? _channel;
  String? _sessionId;
  dynamic _userId;
  bool _intentionalDisconnect = false;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  // Exponential backoff (500ms -> 8s cap) - a real network/DNS outage was
  // observed hammering a fixed 500ms retry continuously for the whole gap.
  Duration _reconnectDelay = const Duration(milliseconds: 500);
  static const _reconnectDelayMax = Duration(seconds: 8);

  final AudioRecorder _audioRecorder = AudioRecorder();
  StreamSubscription<Uint8List>? _micSubscription;
  FlutterSileroVad? _vad;
  WakeWordDetector? _wakeWordDetector;
  bool _wakeWordEnabled = false;

  SpeakerProfile? _speakerProfile;
  SpeakerVerificationClient? _speakerVerificationClient;
  bool _isVerifyingSpeaker = false;
  final List<int> _verificationBuffer = [];

  bool _vadActive = false;
  bool _isSpeaking = false;
  bool _conversationActive = false;
  bool _awaitingPostWakeSpeech = false;
  DateTime? _speechStartedAt;
  Timer? _silenceTimer;
  Timer? _conversationTimeoutTimer;
  final List<int> _audioAccumulator = [];
  final List<int> _preBuffer = [];
  static const _preBufferMaxBytes = 32000; // 16kHz * 16-bit mono * 1s
  final List<int> _preBufferSamples = [];
  static const _preBufferMaxSamples = 16000; // 16kHz mono * 1s

  bool _isPlaying = false;
  bool _isStopping = false;
  final List<Uint8List> _audioQueue = [];
  bool _isProcessingQueue = false;
  final _webPcmPlayer = WebPcmPlayer();

  // Separate from _audioAccumulator (which is only for building an outgoing
  // utterance) - fed while the assistant is talking, purely to detect barge-in.
  final List<int> _bargeInAccumulator = [];
  DateTime? _lastBargeInAttemptAt;

  String? _lastSentGazeTarget;
  VoiceNlu? _activeVoiceNlu;
  Timer? _voiceNluTimer;
  VoiceNlu? get activeVoiceNlu => _activeVoiceNlu;

  bool get isConnected => _channel != null;
  bool get isSpeaking => _isSpeaking;
  bool get isPlaying => _isPlaying;
  bool get wakeWordEnabled => _wakeWordEnabled;
  bool get conversationActive => _conversationActive;

  void Function(String text)? onTranscript;
  void Function(Map<String, dynamic> status)? onStatus;
  void Function(String message, String? level)? onToast;
  void Function(String text)? onFinalResponse;
  void Function(double score)? onWakeWordDetected;
  // Fires whenever isConnected/isSpeaking/isPlaying/conversationActive change,
  // so the UI can reflect real listening state without polling.
  void Function()? onStateChanged;

  static String generateSessionId() {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    return List.generate(32, (_) => chars[random.nextInt(chars.length)]).join();
  }

  // --- Setup ---------------------------------------------------------------

  Future<void> init() async {
    // AudioSession config and PCM playback are native-only, and the Silero
    // VAD package has no web build - but mic streaming (record) and the
    // wake-word ONNX pipeline both have real web implementations, so those
    // still run on web via startVad()/setWakeWordEnabled() below.
    if (kIsWeb) return;

    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
      avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.defaultToSpeaker,
      avAudioSessionMode: AVAudioSessionMode.voiceChat,
      androidAudioAttributes: AndroidAudioAttributes(
        contentType: AndroidAudioContentType.speech,
        usage: AndroidAudioUsage.voiceCommunication,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransientMayDuck,
      androidWillPauseWhenDucked: false,
    ));
    await FlutterPcmSound.setup(sampleRate: 16000, channelCount: 1);

    try {
      final vad = FlutterSileroVad();
      final dir = await getApplicationDocumentsDirectory();
      final modelPath = '${dir.path}/silero_vad.onnx';
      final data = await rootBundle.load('assets/models/silero_vad.onnx');
      await File(modelPath).writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      // 0.5, not the library default 0.3 - quiet Android mics peak well under
      // what 0.3 reliably classifies as active.
      await vad.initialize(modelPath: modelPath, sampleRate: 16000, frameSize: 32, threshold: 0.5, minSilenceDurationMs: 0, speechPadMs: 0);
      _vad = vad;
      AppLogger.log('IE_INIT', 'Silero VAD ready');
    } catch (error) {
      AppLogger.log('IE_INIT_ERROR', 'VAD init failed: $error');
    }
  }

  // Lazily loads the wake-word ONNX pipeline. Fails open to plain VAD if the
  // models can't load, rather than leaving the gate on with nothing behind it.
  Future<void> setWakeWordEnabled(bool enabled) async {
    if (!enabled) {
      _wakeWordEnabled = false;
      _conversationActive = false;
      _clearConversationTimeout();
      onStateChanged?.call();
      return;
    }
    if (_wakeWordDetector == null) {
      final detector = WakeWordDetector();
      try {
        await detector.init();
        detector.detectedStream.listen(_onWakeWordDetected);
        _wakeWordDetector = detector;
        AppLogger.log('IE_INIT', 'Wake-word pipeline ready');
      } catch (error) {
        AppLogger.log('IE_INIT_ERROR', 'Wake-word init failed, falling back to plain VAD: $error');
      }
    }
    _wakeWordEnabled = _wakeWordDetector != null;
    onStateChanged?.call();
  }

  // --- Connection ------------------------------------------------------------

  Future<void> connect({required String sessionId, dynamic userId}) async {
    _sessionId = sessionId;
    _userId = userId;
    _intentionalDisconnect = false;
    _reconnectDelay = const Duration(milliseconds: 500);
    
    if (_userId != null) {
      _speakerProfile = SpeakerProfile(userId: _userId.toString());
      await _speakerProfile!.load();
      if (_speakerVerificationClient == null) {
        _speakerVerificationClient = SpeakerVerificationClient();
        await _speakerVerificationClient!.init();
      }
    }

    await _connectChannel();
  }

  Future<void> _connectChannel() async {
    AppLogger.log('IE_CONNECT', interactionWsUrl);
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (_) => _send(jsonEncode({'type': 'ping'})));

    try {
      _channel?.sink.close();
      final WebSocketChannel channel;
      if (kIsWeb) {
        // Browsers can't set WS handshake headers - server falls back to
        // keying the session off <client-ip>:<port>.
        channel = WebSocketChannel.connect(Uri.parse(interactionWsUrl));
      } else {
        channel = IOWebSocketChannel.connect(
          Uri.parse(interactionWsUrl),
          headers: {
            'x-session-id': ?_sessionId,
            if (_userId != null) 'x-user-id': _userId.toString(),
          },
        );
      }
      // Must await this before trusting the connection - the constructor
      // above returns immediately and connects lazily, so a DNS/handshake
      // failure surfaces here rather than as an unhandled exception later.
      await channel.ready;
      _channel = channel;
      channel.stream.listen(_onMessage, onError: _onSocketDown, onDone: () => _onSocketDown(null));
      AppLogger.log('IE_CONNECTED', interactionWsUrl);
      _reconnectDelay = const Duration(milliseconds: 500);
      onStateChanged?.call();
    } catch (error) {
      AppLogger.log('IE_ERROR', 'Connect failed: $error');
      _scheduleReconnect();
    }
  }

  void _onSocketDown(Object? error) {
    if (error != null) AppLogger.log('IE_ERROR', '$error');
    _channel = null;
    onStateChanged?.call();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_intentionalDisconnect) return;
    _channel = null;
    _reconnectTimer?.cancel();
    final delay = _reconnectDelay;
    _reconnectDelay = (_reconnectDelay * 2) > _reconnectDelayMax ? _reconnectDelayMax : _reconnectDelay * 2;
    _reconnectTimer = Timer(delay, () {
      if (!_intentionalDisconnect) _connectChannel();
    });
  }

  int _binaryChunksThisTurn = 0;

  void _onMessage(dynamic message) {
    AppLogger.log('IE_RECEIVED', 'type=${message.runtimeType}, size=${message is List<int> ? message.length : message.toString().length}');
    if (message is List<int>) {
      _binaryChunksThisTurn++;
      AppLogger.log('IE_RECEIVED', 'audio binary chunk #$_binaryChunksThisTurn, ${message.length} bytes, isPlaying=$_isPlaying');
      _onBinaryAudio(Uint8List.fromList(message));
      return;
    }
    final data = jsonDecode(message as String) as Map<String, dynamic>;
    AppLogger.log('IE_RECEIVED', message);
    switch (data['type'] as String?) {
      case 'audio_start':
        _binaryChunksThisTurn = 0;
        _startPlayback();
        break;
      case 'audio_end':
        AppLogger.log('IE_RECEIVED', 'audio_end, $_binaryChunksThisTurn chunks this turn');
        _stopPlayback();
        break;
      case 'transcript':
        onTranscript?.call(data['text'] as String? ?? '');
        break;
      case 'status':
        _cacheVoiceNlu(data);
        onStatus?.call(data);
        break;
      case 'toast':
        onToast?.call(data['message'] as String? ?? '', data['level'] as String?);
        break;
      case 'flush_audio':
        _flushAudio();
        break;
      case 'final_response':
        final text = data['text'] as String? ?? '';
        if (text.isNotEmpty) onFinalResponse?.call(text);
        break;
      // continue_listening: no action needed - mic just stays open.
    }
  }

  void _cacheVoiceNlu(Map<String, dynamic> status) {
    final voiceNlu = parseVoiceNlu(status);
    if (voiceNlu == null) return;
    _activeVoiceNlu = voiceNlu;
    _voiceNluTimer?.cancel();
    _voiceNluTimer = Timer(_voiceNluTtl, () => _activeVoiceNlu = null);
  }

  // --- Wake word + VAD -> mic streaming ---------------------------------

  Future<void> startVad() async {
    if (_vadActive) return;
    bool hasPermission;
    try {
      hasPermission = await _audioRecorder.hasPermission();
    } catch (error) {
      hasPermission = false;
      AppLogger.log('IE_ERROR', 'Mic permission check failed: $error');
    }
    if (!hasPermission) {
      AppLogger.log('IE_ERROR', 'Mic permission denied');
      onToast?.call('Microphone access is blocked - allow it in your browser/app settings to use voice.', 'error');
      return;
    }
    _vadActive = true;
    _isSpeaking = false;

    try {
      // On web, hardware audio-processing flags (autoGain, echoCancel,
      // noiseSuppress) are passed as getUserMedia constraints and can cause
      // the stream to fail silently in some browsers. Use a minimal config
      // on web; the amplitude-based VAD fallback handles detection.
      final config = kIsWeb
          ? const RecordConfig(
              encoder: AudioEncoder.pcm16bits,
              sampleRate: 16000,
              numChannels: 1,
            )
          : const RecordConfig(
              encoder: AudioEncoder.pcm16bits,
              sampleRate: 16000,
              numChannels: 1,
              autoGain: true,
              echoCancel: true,
              noiseSuppress: true,
            );
      final stream = await _audioRecorder.startStream(config);
      _micSubscription = stream.listen(_onMicChunk, onError: (_) => _restartVadAfterDrop(), onDone: _restartVadAfterDrop);
      AppLogger.log('IE_VAD', 'Listening (wake word ${_wakeWordEnabled ? "enabled" : "disabled"})');
    } catch (error) {
      _vadActive = false;
      AppLogger.log('IE_ERROR', 'Failed to start mic stream: $error');
      onToast?.call('Could not start the microphone: $error', 'error');
    }
  }

  void _restartVadAfterDrop() {
    _vadActive = false;
    _micSubscription?.cancel();
    _micSubscription = null;
    if (!_isPlaying) Future.delayed(const Duration(milliseconds: 50), startVad);
  }

  Future<void> stopVad() async {
    if (!_vadActive) return;
    _vadActive = false;
    _isSpeaking = false;
    _silenceTimer?.cancel();
    await _audioRecorder.stop();
    await _micSubscription?.cancel();
    _micSubscription = null;
    _conversationActive = false;
    _clearConversationTimeout();
    _wakeWordDetector?.reset();
  }

  Future<void> _onMicChunk(Uint8List chunk) async {
    if (!_vadActive) return;

    // Must be a real copy (not a view) into a fresh, zero-offset buffer -
    // `chunk` from the record plugin can itself be a view with a non-zero,
    // possibly odd, byte offset into a larger buffer, which asInt16List()
    // rejects unless the offset is a multiple of 2.
    final alignedLen = chunk.length - (chunk.length % 2);
    final safeChunk = Uint8List(alignedLen);
    safeChunk.setRange(0, alignedLen, chunk);
    final samples = safeChunk.buffer.asInt16List();

    if (_isPlaying) {
      // Not dropped outright - fed to VAD so the user can barge in over the
      // assistant. echoCancel on the recorder handles most of the risk of
      // the assistant's own voice false-triggering this.
      _audioAccumulator.clear();
      _bargeInAccumulator.addAll(samples);
      const targetSamples = 512;
      while (_bargeInAccumulator.length >= targetSamples) {
        final frame = _bargeInAccumulator.sublist(0, targetSamples);
        _bargeInAccumulator.removeRange(0, targetSamples);
        await _checkBargeIn(Int16List.fromList(frame));
      }
      return;
    }
    _bargeInAccumulator.clear();

    _preBuffer.addAll(safeChunk);
    if (_preBuffer.length > _preBufferMaxBytes) {
      _preBuffer.removeRange(0, _preBuffer.length - _preBufferMaxBytes);
    }
    _preBufferSamples.addAll(samples);
    if (_preBufferSamples.length > _preBufferMaxSamples) {
      _preBufferSamples.removeRange(0, _preBufferSamples.length - _preBufferMaxSamples);
    }

    final listenForWakeWord = _wakeWordEnabled && !_conversationActive;
    if (listenForWakeWord) {
      _wakeWordDetector?.processChunk(samples);
      return;
    }

    _audioAccumulator.addAll(samples);
    const targetSamples = 512; // 32ms @ 16kHz
    while (_audioAccumulator.length >= targetSamples) {
      final frame = _audioAccumulator.sublist(0, targetSamples);
      _audioAccumulator.removeRange(0, targetSamples);
      await _evaluateFrame(Int16List.fromList(frame));
    }

    if (_isVerifyingSpeaker) {
      // Accumulate samples until we have a complete utterance segment (~1.25s = 20000 samples)
      _verificationBuffer.addAll(samples);
      if (_verificationBuffer.length >= 20000) {
        _runSpeakerVerification();
      }
    } else if (_isSpeaking) {
      _send(safeChunk);
    }
  }

  Timer? _verificationSilenceTimer;

  Future<void> _evaluateFrame(Int16List frame) async {
    final vad = _vad;

    final float32 = Float32List(frame.length);
    var maxAmplitude = 0.0;
    for (var i = 0; i < frame.length; i++) {
      final value = frame[i] / 32768.0;
      float32[i] = value;
      if (value.abs() > maxAmplitude) maxAmplitude = value.abs();
    }

    var isActive = false;
    if (vad != null) {
      try {
        isActive = (await vad.predict(float32)) ?? false;
      } catch (error) {
        AppLogger.log('IE_ERROR', 'VAD predict failed: $error');
      }
    }
    // Redmi-class devices peak ~0.14, and web has no neural VAD at all (no
    // Silero build for web) - fall back to a plain amplitude threshold
    // whenever the model is unsure or unavailable. 0.04 on web turned out
    // way too sensitive - ambient mic noise (no echo/noise suppression on
    // web) sat above it continuously, so isActive never went false and
    // end_of_speech never fired. Raised to 0.70 so only real, close speech
    // registers.
    final amplitudeThreshold = kIsWeb ? 0.70 : 0.1;
    if (!isActive && maxAmplitude > amplitudeThreshold) isActive = true;

    if (isActive) {
      _silenceTimer?.cancel();
      _silenceTimer = null;
      _verificationSilenceTimer?.cancel();
      _verificationSilenceTimer = null;

      if (!_isSpeaking && !_isVerifyingSpeaker) {
        if (!_wakeWordEnabled && _speakerProfile != null && _speakerProfile!.isEnrolled) {
          _isVerifyingSpeaker = true;
          _verificationBuffer.clear();
          // Initialize verification buffer with recent audio samples (up to ~300ms onset)
          final onsetCount = min(_preBufferSamples.length, 4800);
          if (onsetCount > 0) {
            _verificationBuffer.addAll(_preBufferSamples.sublist(_preBufferSamples.length - onsetCount));
          }
          AppLogger.log('IE_VAD', 'Voice activity detected, verifying speaker profile for ${_speakerProfile!.userId} (onset: $onsetCount samples)...');
        } else {
          _beginForwardedUtterance(fromWakeWord: false, confidence: (maxAmplitude * 2.5).clamp(0.5, 1.0));
        }
      } else if (_speechStartedAt != null && DateTime.now().difference(_speechStartedAt!) > _maxUtteranceDuration) {
        // Amplitude has read "active" continuously for too long to be one
        // real utterance - almost always a stuck false-positive (ambient
        // mic noise with no echo/noise suppression, which web deliberately
        // skips) rather than genuine speech. Without this, end_of_speech
        // never fires and the server never gets asked to respond at all.
        _endUtterance();
      } else {
        _awaitingPostWakeSpeech = false;
      }
    } else if (_isSpeaking) {
      final silenceDuration = _awaitingPostWakeSpeech ? _postWakeGrace : _silenceTimeout;
      _silenceTimer ??= Timer(silenceDuration, _endUtterance);
    } else if (_isVerifyingSpeaker) {
      _verificationSilenceTimer ??= Timer(const Duration(milliseconds: 400), () {
        if (_isVerifyingSpeaker) {
          if (_verificationBuffer.length >= 8000) {
            _runSpeakerVerification();
          } else {
            _isVerifyingSpeaker = false;
            _verificationBuffer.clear();
          }
        }
      });
    } else if (_conversationActive && _conversationTimeoutTimer == null) {
      _armConversationTimeout();
    }
  }

  Future<void> _runSpeakerVerification() async {
    _verificationSilenceTimer?.cancel();
    _verificationSilenceTimer = null;
    _isVerifyingSpeaker = false;
    final int16Data = Int16List.fromList(_verificationBuffer);
    
    final emb = await _speakerVerificationClient?.extractEmbedding(int16Data);
    if (emb != null) {
      final result = _speakerProfile?.classify(emb);
      AppLogger.log('IE_VAD', 'Speaker verification result: ${result?.$1} (similarity: ${result?.$2.toStringAsFixed(2)})');
      if (result?.$1 == 'user') {
        AppLogger.log('IE_VAD', 'Speaker MATCHED enrolled user -> triggering start_of_speech');
        _beginForwardedUtterance(fromWakeWord: false, confidence: result!.$2);
        
        // Forward the buffered audio that led to this verification
        if (_isSpeaking) {
          final chunk = Uint8List(int16Data.length * 2);
          final byteData = ByteData.view(chunk.buffer);
          for (int i = 0; i < int16Data.length; i++) {
            byteData.setInt16(i * 2, int16Data[i], Endian.little);
          }
          _send(chunk);
        }
      } else {
        AppLogger.log('IE_VAD', 'Speaker verification REJECTED: ${result?.$1} (sim: ${result?.$2.toStringAsFixed(2)} < ${SpeakerProfile.userSimThreshold}) -> IGNORING other speaker.');
      }
    } else {
      AppLogger.log('IE_VAD', 'Speaker verification: audio too short/unembeddable.');
    }
    _verificationBuffer.clear();
  }

  // Runs continuously while the assistant is speaking, watching for the user
  // trying to talk over it. Debounced - interrupt only needs to fire once
  // per barge-in attempt, not on every 32ms frame the user keeps talking.
  Future<void> _checkBargeIn(Int16List frame) async {
    final vad = _vad;
    final now = DateTime.now();
    if (_lastBargeInAttemptAt != null && now.difference(_lastBargeInAttemptAt!) < const Duration(seconds: 2)) return;

    // On web there is no Silero VAD - use amplitude as a barge-in signal.
    if (vad == null) {
      if (kIsWeb) {
        var maxAmplitude = 0.0;
        for (final s in frame) {
          final v = s / 32768.0;
          if (v.abs() > maxAmplitude) maxAmplitude = v.abs();
        }
        if (maxAmplitude > 0.15) {
          _lastBargeInAttemptAt = now;
          AppLogger.log('IE_VAD', 'Barge-in (amplitude) detected on web');
          triggerBargeIn();
        }
      }
      return;
    }

    if (_lastBargeInAttemptAt != null && now.difference(_lastBargeInAttemptAt!) < const Duration(seconds: 2)) return;
    final float32 = Float32List(frame.length);
    for (var i = 0; i < frame.length; i++) {
      float32[i] = frame[i] / 32768.0;
    }
    bool isActive;
    try {
      isActive = (await vad.predict(float32)) ?? false;
    } catch (error) {
      AppLogger.log('IE_ERROR', 'Barge-in VAD predict failed: $error');
      return;
    }
    // No amplitude fallback here (unlike normal speech detection) - the
    // assistant's own TTS is loud through the speaker, so an amplitude
    // threshold would false-trigger on it constantly. The neural VAD alone
    // is the safer (if imperfect) signal for this.
    if (isActive) {
      _lastBargeInAttemptAt = now;
      AppLogger.log('IE_VAD', 'Possible barge-in detected');
      triggerBargeIn();
    }
  }

  void _onWakeWordDetected(double score) {
    if (_isSpeaking) return;
    _conversationActive = true;
    onWakeWordDetected?.call(score);
    _beginForwardedUtterance(fromWakeWord: true, confidence: score.clamp(0.5, 1.0));
  }

  void _beginForwardedUtterance({required bool fromWakeWord, required double confidence}) {
    _clearConversationTimeout();
    _isSpeaking = true;
    _speechStartedAt = DateTime.now();
    _awaitingPostWakeSpeech = fromWakeWord;
    HapticFeedback.lightImpact();
    _send(jsonEncode({
      'type': 'start_of_speech',
      'confidence': confidence,
      if (_preBuffer.isNotEmpty) 'audio_prebuffer_b64': base64Encode(_preBuffer),
    }));
    AppLogger.log('IE_VAD', 'start_of_speech (${fromWakeWord ? "wake word" : "VAD"}, confidence=${confidence.toStringAsFixed(2)})');
    onStateChanged?.call();
  }

  void _endUtterance() {
    _isSpeaking = false;
    _speechStartedAt = null;
    _awaitingPostWakeSpeech = false;
    _silenceTimer = null;
    HapticFeedback.mediumImpact();
    _send(jsonEncode({'type': 'end_of_speech'}));
    onStateChanged?.call();
    AppLogger.log('IE_VAD', 'end_of_speech');
  }

  void _armConversationTimeout() {
    _conversationTimeoutTimer = Timer(_conversationTimeout, () {
      _conversationActive = false;
      _conversationTimeoutTimer = null;
      onStateChanged?.call();
    });
  }

  void _clearConversationTimeout() {
    _conversationTimeoutTimer?.cancel();
    _conversationTimeoutTimer = null;
  }

  void triggerBargeIn() {
    if (!_isPlaying) return;
    _send(jsonEncode({
      'type': 'interrupt',
      'confidence': 1.0,
      if (_preBuffer.isNotEmpty) 'audio_prebuffer_b64': base64Encode(_preBuffer),
    }));
  }

  // --- TTS playback --------------------------------------------------------

  void _onBinaryAudio(Uint8List chunk) {
    if (_isStopping || chunk.isEmpty) return;
    final aligned = chunk.length % 2 == 0 ? chunk : Uint8List.sublistView(chunk, 0, chunk.length - 1);
    if (!_isPlaying) return; // audio_start should have started playback already.
    if (kIsWeb) {
      unawaited(_webPcmPlayer.feed(aligned));
      return;
    }
    _audioQueue.add(aligned);
    _processAudioQueue();
  }

  Future<void> _startPlayback() async {
    if (_isPlaying) return;
    _isPlaying = true;
    onStateChanged?.call();
    try {
      if (kIsWeb) {
        await _webPcmPlayer.start();
      } else {
        FlutterPcmSound.start();
      }
    } catch (error) {
      _isPlaying = false;
      onStateChanged?.call();
      AppLogger.log('IE_ERROR', 'PCM start failed: $error');
    }
  }

  Future<void> _processAudioQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;
    try {
      while (_audioQueue.isNotEmpty && _isPlaying) {
        final chunk = _audioQueue.removeAt(0);
        for (var i = 0; i < chunk.length; i += 4096) {
          if (!_isPlaying) break;
          final end = min(i + 4096, chunk.length);
          final sub = Uint8List.sublistView(chunk, i, end);
          final subAligned = sub.length % 2 == 0 ? sub : Uint8List.sublistView(sub, 0, sub.length - 1);
          try {
            await FlutterPcmSound.feed(PcmArrayInt16.fromList(subAligned.buffer.asInt16List(subAligned.offsetInBytes, subAligned.length ~/ 2)));
          } catch (error) {
            AppLogger.log('IE_ERROR', 'PCM feed failed: $error');
          }
        }
      }
    } finally {
      _isProcessingQueue = false;
    }
  }

  Future<void> _stopPlayback() async {
    if (!_isPlaying || _isStopping) return;
    _isStopping = true;
    if (kIsWeb) {
      // finish(), not stop() - Web Audio schedules buffered nodes ahead of
      // real time, so there is usually still unplayed audio queued up when
      // audio_end arrives. finish() waits for that scheduled tail to
      // actually play instead of cutting it off.
      await _webPcmPlayer.finish();
    } else {
      var waited = 0;
      while ((_audioQueue.isNotEmpty || _isProcessingQueue) && waited < 4000) {
        await Future.delayed(const Duration(milliseconds: 20));
        waited += 20;
      }
      try {
        await FlutterPcmSound.release();
        await FlutterPcmSound.setup(sampleRate: 16000, channelCount: 1);
      } catch (error) {
        AppLogger.log('IE_ERROR', 'PCM stop failed: $error');
      }
      // AudioTrack holds ~500ms of buffered audio after we stop feeding it -
      // delay before re-arming the mic so the app doesn't hear its own echo.
      await Future.delayed(const Duration(milliseconds: 1000));
    }
    _isPlaying = false;
    _isStopping = false;
    onStateChanged?.call();
    if (!_vadActive && _micSubscription == null) {
      Future.delayed(const Duration(milliseconds: 50), startVad);
    }
  }

  Future<void> _flushAudio() async {
    _audioQueue.clear();
    if (!_isPlaying) {
      _isPlaying = false;
      onStateChanged?.call();
      return;
    }
    if (kIsWeb) {
      await _webPcmPlayer.stop();
      _isPlaying = false;
      onStateChanged?.call();
      return;
    }
    _isStopping = true;
    try {
      await FlutterPcmSound.release();
      await FlutterPcmSound.setup(sampleRate: 16000, channelCount: 1);
    } catch (error) {
      AppLogger.log('IE_ERROR', 'Flush failed: $error');
    }
    _isPlaying = false;
    _isStopping = false;
    onStateChanged?.call();
  }

  // --- Telemetry / testing ---------------------------------------------

  // Dedups on gaze_target only - the field that actually reflects behavioral
  // change, unlike scene_objects which is noisy/client-derived.
  void sendTelemetry(InteractionTelemetry telemetry) {
    if (telemetry.gazeTarget != null && telemetry.gazeTarget == _lastSentGazeTarget) return;
    _lastSentGazeTarget = telemetry.gazeTarget;
    _send(jsonEncode({'type': 'telemetry', 'payload': telemetry.toJson()}));
  }

  void sendSetLocation({required double lat, required double lon, required String city, required String country}) {
    _send(jsonEncode({'type': 'set_location', 'latitude': lat, 'longitude': lon, 'city': city, 'country': country}));
  }

  // Mic-bypass testing path - injected server-side as if it were a transcript.
  void sendTextQuery(String text) => _send(jsonEncode({'type': 'text_query', 'text': text}));

  void _send(dynamic data) {
    final channel = _channel;
    if (channel == null) return;
    try {
      channel.sink.add(data);
      if (data is String) AppLogger.log('IE_SENT', data);
    } catch (error) {
      AppLogger.log('IE_ERROR', 'Send failed: $error');
    }
  }

  // --- Lifecycle -----------------------------------------------------------

  Future<void> disconnect() async {
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  Future<void> dispose() async {
    await stopVad();
    await disconnect();
    await _audioRecorder.dispose();
    if (kIsWeb) {
      _webPcmPlayer.dispose();
    } else {
      try {
        await FlutterPcmSound.release();
      } catch (_) {}
    }
    await _wakeWordDetector?.dispose();
    // Without this, a later setWakeWordEnabled(true) on this same client
    // (e.g. reconnect after disconnect()) sees a non-null _wakeWordDetector,
    // skips creating+initializing a fresh one, and starts feeding audio into
    // ONNX sessions that were just closed above.
    _wakeWordDetector = null;
    _wakeWordEnabled = false;
    _voiceNluTimer?.cancel();
  }
}
