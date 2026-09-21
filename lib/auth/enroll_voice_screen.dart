import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../app_theme.dart';
import '../auth/auth_provider.dart';
import '../interaction_engine/speaker_profile.dart';
import '../interaction_engine/speaker_verification_client.dart';
import '../particle_background.dart';

class EnrollVoiceScreen extends StatefulWidget {
  const EnrollVoiceScreen({super.key});

  @override
  State<EnrollVoiceScreen> createState() => _EnrollVoiceScreenState();
}

class _EnrollVoiceScreenState extends State<EnrollVoiceScreen> {
  final AudioRecorder _audioRecorder = AudioRecorder();
  late SpeakerProfile _profile;
  late SpeakerVerificationClient _verificationClient;
  
  bool _isInit = false;
  bool _isRecording = false;
  final List<int> _audioBuffer = [];
  StreamSubscription<Uint8List>? _audioSub;

  String _statusMessage = "Press the button below and read the text.";
  int _samplesEnrolled = 0;
  
  final String _paragraph = """Once upon a time in a quiet village, there lived a kind baker. Every morning, he woke up before the sun to bake fresh bread. The scent of warm pastries filled the cool air, waking the town. People would gather around his shop, sharing stories and laughter. It was a simple life, but it brought everyone joy and a sense of belonging.""";

  @override
  void initState() {
    super.initState();
    _initVerification();
  }

  Future<void> _initVerification() async {
    final auth = context.read<AuthProvider>();
    final uid = await auth.resolveUserId();
    final userId = (uid != null && uid != 0)
        ? uid.toString()
        : (auth.email.isNotEmpty ? auth.email : 'default_user');
    
    _profile = SpeakerProfile(userId: userId);
    await _profile.load();
    _samplesEnrolled = _profile.embeddings.length;

    _verificationClient = SpeakerVerificationClient();
    await _verificationClient.init();

    setState(() {
      _isInit = true;
      if (_samplesEnrolled >= SpeakerProfile.maxEnrollSamples) {
        _statusMessage = "Enrollment complete! You can now test your voice.";
      }
    });
  }

  @override
  void dispose() {
    _stopRecording();
    _audioRecorder.dispose();
    _verificationClient.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (await _audioRecorder.hasPermission()) {
      _audioBuffer.clear();
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
      
      _audioSub = stream.listen((data) {
        _audioBuffer.addAll(data);
      });

      setState(() {
        _isRecording = true;
        _statusMessage = "Recording... Read the text out loud.";
      });
    } else {
      setState(() {
        _statusMessage = "Microphone permission denied.";
      });
    }
  }

  Future<void> _stopRecording({bool isTesting = false}) async {
    if (!_isRecording) return;
    
    await _audioRecorder.stop();
    await _audioSub?.cancel();
    _audioSub = null;
    
    setState(() {
      _isRecording = false;
      _statusMessage = "Processing audio...";
    });

    if (_audioBuffer.isEmpty) {
      setState(() {
        _statusMessage = "No audio recorded. Please try again.";
      });
      return;
    }

    // Convert Uint8List to Int16List (little endian)
    final byteData = ByteData.view(Uint8List.fromList(_audioBuffer).buffer);
    final int16List = Int16List(byteData.lengthInBytes ~/ 2);
    for (int i = 0; i < int16List.length; i++) {
      int16List[i] = byteData.getInt16(i * 2, Endian.little);
    }

    final emb = await _verificationClient.extractEmbedding(int16List);

    if (isTesting) {
      if (emb == null) {
        setState(() {
          _statusMessage = "Audio too short or silent. Try speaking clearly.";
        });
        return;
      }
      final result = _profile.classify(emb);
      setState(() {
        _statusMessage = "Test Result: ${result.$1.toUpperCase()} (Similarity: ${result.$2.toStringAsFixed(2)})";
      });
    } else {
      final result = _profile.enrollFromSample(emb);
      setState(() {
        if (result == "success") {
          _samplesEnrolled = _profile.embeddings.length;
          if (_samplesEnrolled >= SpeakerProfile.maxEnrollSamples) {
            _statusMessage = "Enrollment complete! You can now test your voice.";
          } else {
            _statusMessage = "Sample saved! $_samplesEnrolled/${SpeakerProfile.maxEnrollSamples}. Please read again.";
          }
        } else {
          _statusMessage = "Failed: $result";
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInit) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final bool canEnroll = _samplesEnrolled < SpeakerProfile.maxEnrollSamples;

    return Scaffold(
      appBar: AppBar(
        title: Text('Voice Enrollment', style: TextStyle(color: AppColors.textPrimary)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
      ),
      body: ParticleBackground(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                "Enroll Your Voice",
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.menu_book_rounded, size: 20, color: AppColors.accentStrong),
                        const SizedBox(width: 8),
                        Text(
                          "Read this story paragraph out loud:",
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _paragraph,
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.6,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: _isRecording ? Colors.red.withValues(alpha: 0.1) : AppColors.accentTint,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _statusMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _isRecording ? Colors.redAccent : AppColors.accentStrong,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              
              if (canEnroll) ...[
                Text(
                  "Progress: $_samplesEnrolled / ${SpeakerProfile.maxEnrollSamples}",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: GestureDetector(
                    onTap: () {
                      if (_isRecording) {
                        _stopRecording(isTesting: false);
                      } else {
                        _startRecording();
                      }
                    },
                    child: Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isRecording ? Colors.red : AppColors.accent,
                        boxShadow: [
                          BoxShadow(
                            color: (_isRecording ? Colors.red : AppColors.accent).withValues(alpha: 0.4),
                            blurRadius: 20,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: Icon(_isRecording ? Icons.stop_rounded : Icons.mic, size: 42, color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _isRecording ? "Recording in progress... Tap to finish & save" : "Tap the button to start recording, tap again when done",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
              ] else ...[
                const Divider(),
                const SizedBox(height: 16),
                Text(
                  "Test Verification",
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Center(
                  child: GestureDetector(
                    onTap: () {
                      if (_isRecording) {
                        _stopRecording(isTesting: true);
                      } else {
                        _startRecording();
                      }
                    },
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isRecording ? Colors.orange : AppColors.surface,
                        border: Border.all(color: AppColors.accent, width: 2.5),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.accent.withValues(alpha: 0.2),
                            blurRadius: 15,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Icon(_isRecording ? Icons.stop_rounded : Icons.mic, size: 36, color: _isRecording ? Colors.white : AppColors.accent),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _isRecording ? "Listening... Tap to test voice against profile" : "Tap to test voice, tap again when finished speaking",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 24),
                TextButton.icon(
                  icon: const Icon(Icons.refresh, color: Colors.redAccent, size: 18),
                  onPressed: () {
                    setState(() {
                      _profile.embeddings.clear();
                      _samplesEnrolled = 0;
                      _profile.save();
                      _statusMessage = "Profile reset. Please enroll again.";
                    });
                  },
                  label: const Text("Reset Voice Profile", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
