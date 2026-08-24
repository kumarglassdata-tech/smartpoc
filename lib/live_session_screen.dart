import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_theme.dart';
import 'insights_screen.dart';
import 'matched_products_screen.dart';
import 'recommendation_utils.dart';
import 'session/session_provider.dart';
import 'session_complete_screen.dart';
import 'sources/source_adapter.dart';

// The screen a running session actually lands on: live camera feed + what
// the pipeline is seeing right now (scene objects) and recommending (ecom
// hub matches). Matches the mockup's own live-session screen (LIVE badge +
// timer, viewfinder reticle, detected-item chips, "View all N" into the full
// matched list) - that screen is only reachable via the mockup's own
// "Recorded Video" path, verified directly against the mockup.
class LiveSessionScreen extends StatefulWidget {
  const LiveSessionScreen({super.key});

  @override
  State<LiveSessionScreen> createState() => _LiveSessionScreenState();
}

class _LiveSessionScreenState extends State<LiveSessionScreen> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _formatElapsed(Duration? d) {
    if (d == null) return '00:00';
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _endSession(BuildContext context) async {
    final session = context.read<SessionProvider>();
    await session.stopRuntime();
    final summary = session.lastSessionSummary;
    if (!context.mounted || summary == null) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => SessionCompleteScreen(summary: summary)));
  }

  Widget _bracketCorner({required bool top, required bool left}) {
    return Positioned(
      top: top ? 0 : null,
      bottom: top ? null : 0,
      left: left ? 0 : null,
      right: left ? null : 0,
      child: CustomPaint(size: const Size(28, 28), painter: _CornerPainter(top: top, left: left)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final elapsed = session.runtimeStartedAt != null ? DateTime.now().difference(session.runtimeStartedAt!) : null;
    final detectedNames = session.sessionDetectedItemNames;
    final recommendations = session.lastPipelineResult != null
        ? extractEcomRecommendations(session.lastPipelineResult!.ecomAdHandlerRaw, limit: 20)
        : const <Map<String, String>>[];
    final previewMatches = recommendations.take(3).toList();

    // Commerce relevance score from the behaviour engine (0–1, or null before first result)
    final relevanceScore = session.lastPipelineResult?.behaviourEngineResponse.relevanceScore;
    final vlmDescription = session.lastPipelineResult?.contextEngineResponse.vlmDescription;
    final isPipelineTicking = session.isPipelineTicking;
    final ie = session.interactionEngineClient;
    final lastTranscript = session.lastTranscript;
    final lastVoiceResponse = session.lastVoiceResponse;
    final showVoiceStatus = ie.isSpeaking || ie.isPlaying || (lastTranscript?.isNotEmpty ?? false) || (lastVoiceResponse?.isNotEmpty ?? false);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _endSession(context);
      },
      child: Scaffold(
        backgroundColor: AppColors.dark,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    _iconButton(Icons.close, () => _endSession(context)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(20)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.danger)),
                          const SizedBox(width: 6),
                          const Text('LIVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Text(_formatElapsed(elapsed), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InsightsScreen())),
                    icon: const Icon(Icons.show_chart, size: 16, color: Colors.white),
                    label: const Text('View analytics dashboard', style: TextStyle(color: Colors.white)),
                    style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.white.withValues(alpha: 0.2))),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // ── Camera preview ─────────────────────────────────────────
              // Taller + full width so the viewfinder fills the screen well.
              Expanded(
                flex: 5,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: ListenableBuilder(
                        listenable: session.cameraService,
                        builder: (context, _) {
                          final controller = session.cameraService.controller;
                          if (controller == null || !controller.value.isInitialized) {
                            return StreamBuilder<VideoFrame>(
                              stream: session.sourceManager.videoStream,
                              builder: (context, snapshot) {
                                if (!snapshot.hasData) return const SizedBox.shrink();
                                return SizedBox.expand(
                                  child: FittedBox(
                                    fit: BoxFit.cover,
                                    child: Image.memory(
                                      snapshot.data!.bytes,
                                      gaplessPlayback: true,
                                    ),
                                  ),
                                );
                              },
                            );
                          }
                          return SizedBox.expand(
                            child: FittedBox(
                              fit: BoxFit.cover,
                              child: SizedBox(
                                width: controller.value.previewSize?.height ?? 1,
                                height: controller.value.previewSize?.width ?? 1,
                                child: CameraPreview(controller),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    SizedBox(
                      width: 260,
                      height: 260,
                      child: Stack(
                        children: [
                          _bracketCorner(top: true, left: true),
                          _bracketCorner(top: true, left: false),
                          _bracketCorner(top: false, left: true),
                          _bracketCorner(top: false, left: false),
                        ],
                      ),
                    ),
                    // What the VLM currently sees, as a translucent caption
                    // bar over the preview - real omni_context_vlm output,
                    // not shown anywhere else while a session is live.
                    if (vlmDescription != null && vlmDescription.isNotEmpty)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          color: Colors.black.withValues(alpha: 0.3),
                          child: Text(
                            vlmDescription,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 12.5, height: 1.3),
                          ),
                        ),
                      ),
                    // Progress pill - visible only while a captured frame is
                    // actually in flight through ce/be/ah, so a multi-second
                    // engine round-trip doesn't look like a frozen screen.
                    if (isPipelineTicking)
                      Positioned(
                        top: vlmDescription != null && vlmDescription.isNotEmpty ? 54 : 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(20)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                              ),
                              const SizedBox(width: 6),
                              const Text('Analyzing…', style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                    // Detected-item chips + capture status, overlaid at the
                    // bottom of the preview so they stay visible regardless
                    // of how the outer column allocates space.
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 12,
                      child: Column(
                        children: [
                          if (detectedNames.isNotEmpty)
                            SizedBox(
                              height: 32,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                itemCount: detectedNames.length,
                                separatorBuilder: (_, _) => const SizedBox(width: 8),
                                itemBuilder: (context, index) => Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(20)),
                                  alignment: Alignment.center,
                                  child: Text('•  ${detectedNames[index]}', style: const TextStyle(color: Colors.white, fontSize: 13)),
                                ),
                              ),
                            ),
                          const SizedBox(height: 8),
                          // Live voice-pipeline readout - transcript/response
                          // text made visible so it's obvious the voice
                          // pipeline is actually running even before/without
                          // audible TTS playback.
                          if (showVoiceStatus)
                            Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(14)),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(ie.isPlaying ? Icons.volume_up : Icons.mic, size: 14, color: Colors.white),
                                      const SizedBox(width: 6),
                                      Text(
                                        ie.isPlaying ? 'Myna is speaking' : 'Listening…',
                                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                  if (lastTranscript != null && lastTranscript.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text('You: $lastTranscript', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                  ],
                                  if (lastVoiceResponse != null && lastVoiceResponse.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text('Myna: $lastVoiceResponse', maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12)),
                                  ],
                                ],
                              ),
                            ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.danger)),
                              const SizedBox(width: 8),
                              const Text('Listening and capturing...', style: TextStyle(color: Colors.white70)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // ── Matched products panel ──────────────────────────────────
              Expanded(
                flex: 3,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  decoration: BoxDecoration(color: AppColors.background, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text('Matched products', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                          const Spacer(),
                          // ── Circular relevance score ────────────────────
                          _RelevanceRing(score: relevanceScore),
                          if (recommendations.isNotEmpty) ...[
                            const SizedBox(width: 12),
                            GestureDetector(
                              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MatchedProductsScreen(items: recommendations, vlmDescription: vlmDescription))),
                              child: Text('View all ${recommendations.length}', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600, fontSize: 13)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: previewMatches.isEmpty
                            ? Center(
                                child: session.state.isRuntimeActive
                                    ? Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          SizedBox(
                                            width: 28,
                                            height: 28,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.5,
                                              valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text('Scanning for products…', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                                        ],
                                      )
                                    : Text('No matches yet.', style: TextStyle(color: AppColors.textSecondary)),
                              )
                            : ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: previewMatches.length,
                                separatorBuilder: (_, _) => const SizedBox(width: 10),
                                itemBuilder: (context, index) {
                                  final item = previewMatches[index];
                                  return Container(
                                    width: 96,
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: AppColors.surface,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: AppColors.border),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(10),
                                            child: item['image'] != null
                                                ? Image.network(item['image']!, fit: BoxFit.cover, width: double.infinity,
                                                    errorBuilder: (_, _, _) => Container(color: AppColors.accentTint))
                                                : Container(color: AppColors.accentTint),
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(item['name'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                                        if (item['price'] != null) Text(item['price']!, style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700, fontSize: 12)),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: 10),
                      FilledButton(
                        onPressed: () => _endSession(context),
                        style: FilledButton.styleFrom(backgroundColor: AppColors.dark),
                        child: const Text('End Session'),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconButton(IconData icon, VoidCallback onPressed) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onPressed,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  final bool top;
  final bool left;

  const _CornerPainter({required this.top, required this.left});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.accent
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path();
    final horizontalY = top ? 0.0 : size.height;
    final verticalX = left ? 0.0 : size.width;
    if (left) {
      path.moveTo(0, horizontalY + (top ? size.height * 0.6 : -size.height * 0.6));
      path.lineTo(verticalX, horizontalY);
      path.lineTo(size.width * 0.6, horizontalY);
    } else {
      path.moveTo(size.width - size.width * 0.6, horizontalY);
      path.lineTo(verticalX, horizontalY);
      path.lineTo(verticalX, horizontalY + (top ? size.height * 0.6 : -size.height * 0.6));
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CornerPainter oldDelegate) => false;
}

// ── Circular commerce relevance score ring ────────────────────────────────────
// Animates smoothly to each new score (0.0–1.0) from the behaviour engine.
// Shows "–" before the first pipeline result arrives.
class _RelevanceRing extends StatefulWidget {
  final double? score;

  const _RelevanceRing({this.score});

  @override
  State<_RelevanceRing> createState() => _RelevanceRingState();
}

class _RelevanceRingState extends State<_RelevanceRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _anim = Tween<double>(begin: 0, end: widget.score?.clamp(0.0, 1.0) ?? 0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    if (widget.score != null) _ctrl.forward();
  }

  @override
  void didUpdateWidget(covariant _RelevanceRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.score != widget.score && widget.score != null) {
      final from = _anim.value;
      final to = widget.score!.clamp(0.0, 1.0);
      _anim = Tween<double>(begin: from, end: to).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
      );
      _ctrl
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, _) {
        final v = _anim.value;
        // grey < 0.4, amber 0.4–0.7, green > 0.7
        final Color arcColor = v < 0.4
            ? AppColors.textSecondary
            : v < 0.7
                ? AppColors.accent
                : AppColors.success;

        return SizedBox(
          width: 44,
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: v,
                strokeWidth: 3.5,
                backgroundColor: arcColor.withValues(alpha: 0.15),
                valueColor: AlwaysStoppedAnimation<Color>(arcColor),
                strokeCap: StrokeCap.round,
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.score == null ? '–' : '${(v * 100).round()}',
                    style: TextStyle(
                      fontSize: widget.score == null ? 14 : 11,
                      fontWeight: FontWeight.w800,
                      color: arcColor,
                      height: 1,
                    ),
                  ),
                  if (widget.score != null)
                    Text('%', style: TextStyle(fontSize: 7, color: arcColor, fontWeight: FontWeight.w700)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

