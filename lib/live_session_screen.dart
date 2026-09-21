import 'dart:async';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_theme.dart';
import 'behaviour_analysis_screen.dart';
import 'features/owned_objects/owned_objects_card.dart';
import 'features/schedule/weekly_schedule_screen.dart';
import 'features/schedule/widgets/feature_attribution_insights_card.dart';
import 'insights_screen.dart';
import 'matched_products_screen.dart';
import 'pipeline/behaviour_engine_response.dart';
import 'pipeline/context_engine_response.dart';
import 'product_detail_screen.dart';
import 'recommendation_utils.dart';
import 'services/meta_glasses_service.dart';
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

class _LiveSessionScreenState extends State<LiveSessionScreen> with WidgetsBindingObserver {
  Timer? _ticker;
  bool _isEndingSession = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.hidden) {
      if (mounted) {
        _endSession(context);
      }
    }
  }

  String _formatElapsed(Duration? d) {
    if (d == null) return '00:00';
    if (d.inHours > 0) {
      final hours = d.inHours.toString().padLeft(2, '0');
      final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
      final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
      return '$hours:$minutes:$seconds';
    }
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _endSession(BuildContext context) async {
    if (_isEndingSession) return;
    _isEndingSession = true;
    _ticker?.cancel();

    final session = context.read<SessionProvider>();
    final startedAt = session.runtimeStartedAt;
    final liveElapsed = startedAt != null ? DateTime.now().difference(startedAt) : null;

    await session.stopRuntime(fallbackDuration: liveElapsed);
    final summary = session.lastSessionSummary;
    if (!context.mounted) return;
    if (summary != null) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => SessionCompleteScreen(summary: summary)));
    } else {
      Navigator.of(context).pop();
    }
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
    final allMatches = session.sessionMatchedProducts.isNotEmpty
        ? session.sessionMatchedProducts
        : (session.lastPipelineResult != null
            ? extractEcomRecommendations(session.lastPipelineResult!.ecomAdHandlerRaw, limit: 20)
            : const <Map<String, String>>[]);
    final recommendations = allMatches;
    final previewMatches = allMatches.take(4).toList();

    // Behaviour engine live response & relevance score
    final be = session.lastPipelineResult?.behaviourEngineResponse;
    final relevanceScore = be?.relevanceScore;
    final ce = session.lastPipelineResult?.contextEngineResponse;
    // Live scene objects from the current active frame (not historical session list)
    final liveSceneObjects = ce?.sceneObjects ?? const <ContextEngineSceneObject>[];
    final rawGrounded = ce?.gazeGrounding.groundedTarget?.trim();
    final hasValidGrounded = rawGrounded != null &&
        rawGrounded.isNotEmpty &&
        rawGrounded.toLowerCase() != 'none' &&
        rawGrounded.toLowerCase() != 'unknown';

    final rawRecProduct = be?.recommendedProduct?.trim();
    final hasValidRec = rawRecProduct != null &&
        rawRecProduct.isNotEmpty &&
        rawRecProduct.toLowerCase() != 'none' &&
        rawRecProduct.toLowerCase() != 'unknown';

    final liveGroundedTarget = hasValidGrounded ? rawGrounded : null;
    final liveRecProduct = hasValidRec ? rawRecProduct : null;

    final ceActivity = ce?.currentActivity ?? ce?.activityInformation?['activity']?.toString();
    final ceLocation = ce?.currentLocation ??
        ce?.locationInformation?['current_location']?.toString() ??
        ce?.locationInformation?['location']?.toString() ??
        ce?.locationInformation?['place']?.toString() ??
        ce?.locationInformation?['venue']?.toString() ??
        session.locationService.currentPlaceName ??
        'LOCATION';
    final vlmDescription = ce?.vlmDescription;
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
                    const SizedBox(width: 8),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        reverse: true,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
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
                            const SizedBox(width: 8),
                            // ── Live CE Location Badge ──────────────────────────────
                            InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => _showLocationContextDialog(context, session, ceLocation),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F172A).withValues(alpha: 0.85),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: const Color(0xFF38BDF8).withValues(alpha: 0.5),
                                    width: 0.9,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.location_on_rounded, color: Color(0xFF38BDF8), size: 12),
                                    const SizedBox(width: 4),
                                    Text(
                                      ceLocation.toUpperCase(),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 11,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                    ValueListenableBuilder<int?>(
                      valueListenable: MetaGlassesService.instance.batteryLevelNotifier,
                      builder: (context, battery, _) {
                        if (battery == null || battery < 0) return const SizedBox.shrink();
                        final Color batteryColor = battery > 50
                            ? AppColors.success
                            : battery > 20
                                ? Colors.amber
                                : AppColors.danger;
                        final IconData batteryIcon = battery > 80
                            ? Icons.battery_full_rounded
                            : battery > 60
                                ? Icons.battery_6_bar_rounded
                                : battery > 40
                                    ? Icons.battery_4_bar_rounded
                                    : battery > 20
                                        ? Icons.battery_2_bar_rounded
                                        : Icons.battery_alert_rounded;
                        return Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(batteryIcon, color: batteryColor, size: 14),
                                const SizedBox(width: 4),
                                Text(
                                  '$battery%',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(_formatElapsed(elapsed), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              // ── Live Behaviour Engine (BE) Quick-Access Bar ──────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  height: 34,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    children: [
                      // Location Context Chip
                      _beActionChip(
                        icon: Icons.location_on_rounded,
                        label: 'Loc: ${ceLocation.toUpperCase()}',
                        accentColor: const Color(0xFF38BDF8),
                        onTap: () => _showLocationContextDialog(context, session, ceLocation),
                      ),
                      const SizedBox(width: 8),
                      // Activity & Routine Analysis
                      _beActionChip(
                        icon: Icons.directions_run_rounded,
                        label: ceActivity != null ? 'Activity: ${ceActivity.toUpperCase()}' : 'Activity & Routine',
                        accentColor: const Color(0xFFF59E0B),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const WeeklyScheduleScreen()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Analytics Dashboard
                      _beActionChip(
                        icon: Icons.auto_graph_rounded,
                        label: 'Analytics',
                        accentColor: AppColors.accent,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const InsightsScreen()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Behaviour Analysis Graph
                      _beActionChip(
                        icon: Icons.hub_outlined,
                        label: 'Behaviour Graph',
                        accentColor: const Color(0xFF60A5FA),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const BehaviourAnalysisScreen()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Commerce Attribution
                      _beActionChip(
                        icon: Icons.attractions_outlined,
                        label: 'Attribution',
                        accentColor: const Color(0xFF10B981),
                        onTap: () {
                          final be = session.lastPipelineResult?.behaviourEngineResponse;
                          showFeatureAttributionDialog(
                            context,
                            beOutput: be != null
                                ? {
                                    ...be.rawJson,
                                    if (be.behavioralState != null) 'behavioral_state': be.behavioralState,
                                    if (be.relevanceScore != null) 'relevance_score': be.relevanceScore,
                                    if (be.stateConfidence != null) 'state_confidence': be.stateConfidence,
                                    if (be.hesitationScore != null) 'hesitation_score': be.hesitationScore,
                                    if (be.lifestyleCluster != null) 'lifestyle_cluster': be.lifestyleCluster,
                                    if (be.recommendedProduct != null) 'recommended_product': be.recommendedProduct,
                                    if (be.attributionBreakdown != null) 'attribution_breakdown': be.attributionBreakdown,
                                    if (be.compositeAttributionScore != null) 'composite_attribution_score': be.compositeAttributionScore,
                                    if (be.eligibilityBlocked != null) 'eligibility_blocked': be.eligibilityBlocked,
                                    if (be.blockedReason != null) 'blocked_reason': be.blockedReason,
                                    if (ceLocation.isNotEmpty) 'venue': ceLocation,
                                    'schedule_activity': ?ceActivity,
                                  }
                                : null,
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      // Owned Objects
                      _beActionChip(
                        icon: Icons.inventory_2_outlined,
                        label: 'Owned Objects',
                        accentColor: const Color(0xFFA855F7),
                        onTap: () {
                          showModalBottomSheet(
                            context: context,
                            backgroundColor: Colors.transparent,
                            isScrollControlled: true,
                            builder: (_) => SafeArea(
                              child: Container(
                                constraints: BoxConstraints(
                                  maxHeight: MediaQuery.of(context).size.height * 0.88,
                                ),
                                padding: EdgeInsets.only(
                                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                                  left: 16,
                                  right: 16,
                                  top: 16,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.background,
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: SingleChildScrollView(
                                  physics: const BouncingScrollPhysics(),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 4,
                                        margin: const EdgeInsets.only(bottom: 12),
                                        decoration: BoxDecoration(
                                          color: AppColors.border,
                                          borderRadius: BorderRadius.circular(2),
                                        ),
                                      ),
                                      const OwnedObjectsCard(),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
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
                          _LiveDetectedObjectsBar(
                            sceneObjects: liveSceneObjects,
                            groundedTarget: liveGroundedTarget,
                            recommendedProduct: liveRecProduct,
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
                              const Flexible(
                                child: Text(
                                  'Listening and capturing...',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: Colors.white70),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // ── Matched products panel ──────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                decoration: BoxDecoration(color: AppColors.background, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Flexible(
                          child: Text(
                            'Matched products',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // ── Circular relevance score ────────────────────
                        _RelevanceRing(score: relevanceScore),
                        if (recommendations.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MatchedProductsScreen(items: recommendations, vlmDescription: vlmDescription))),
                            child: Text('View all ${recommendations.length}', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600, fontSize: 13)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 100,
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
                                return Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(14),
                                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProductDetailScreen(item: item))),
                                    child: Container(
                                      width: 104,
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
                                              child: (item['image'] != null && item['image']!.isNotEmpty && !item['image']!.contains('via.placeholder.com'))
                                                  ? Image.network(item['image']!, fit: BoxFit.cover, width: double.infinity,
                                                      errorBuilder: (_, _, _) => Container(color: AppColors.accentTint, child: Center(child: Icon(Icons.shopping_bag_outlined, color: AppColors.accent, size: 20))))
                                                  : Container(color: AppColors.accentTint, child: Center(child: Icon(Icons.shopping_bag_outlined, color: AppColors.accent, size: 20))),
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(item['name'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11)),
                                          if (item['price'] != null) Text(item['price']!, style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700, fontSize: 11)),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 8),
                    // ── Live BE Metrics Strip (Under Matched Products) ──
                    _buildLiveBeMetricsStrip(context, session, be, ceLocation, ceActivity),
                    const SizedBox(height: 8),
                    Center(
                      child: SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton.icon(
                          onPressed: () => _endSession(context),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.danger.withValues(alpha: 0.9),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            elevation: 2,
                          ),
                          icon: const Icon(Icons.stop_circle_outlined, size: 20),
                          label: const Text('End Session', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLocationContextDialog(
    BuildContext context,
    SessionProvider session,
    String currentLocationName,
  ) {
    final placeCtrl = TextEditingController(text: currentLocationName);
    final lat = session.locationService.latitude;
    final lon = session.locationService.longitude;
    final city = session.locationService.city ?? (lat != null ? '${lat.toStringAsFixed(4)}, ${lon?.toStringAsFixed(4)}' : 'Locating...');
    final ce = session.lastPipelineResult?.contextEngineResponse;
    final ceRawLoc = ce?.locationInformation;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            left: 20,
            right: 20,
            top: 16,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF0E131F),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.location_on_rounded, color: Color(0xFF38BDF8), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'LOCATION CONTEXT',
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                          ),
                        ),
                        Text(
                          currentLocationName.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: ceRawLoc != null
                          ? AppColors.success.withValues(alpha: 0.2)
                          : Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: ceRawLoc != null ? AppColors.success : AppColors.border,
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      ceRawLoc != null ? 'LIVE CE' : 'GPS / LOCAL',
                      style: TextStyle(
                        color: ceRawLoc != null ? AppColors.success : AppColors.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B).withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.my_location_rounded, color: Color(0xFF94A3B8), size: 14),
                        const SizedBox(width: 6),
                        Text(
                          lat != null && lon != null
                              ? '$city • ${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)}'
                              : city,
                          style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    if (ceRawLoc != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'CE Context: ${jsonEncode(ceRawLoc)}',
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: placeCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Override Place Context (e.g. WORK, OFFICE, HOME)',
                  labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                  filled: true,
                  fillColor: const Color(0xFF1E293B).withValues(alpha: 0.5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF334155)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF334155)),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF38BDF8),
                    foregroundColor: const Color(0xFF090D16),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Update Context', style: TextStyle(fontWeight: FontWeight.w700)),
                  onPressed: () {
                    final newPlace = placeCtrl.text.trim().isNotEmpty
                        ? placeCtrl.text.trim().toUpperCase()
                        : currentLocationName;
                    session.locationService.setManualLocation(
                      latitude: lat ?? 0.0,
                      longitude: lon ?? 0.0,
                      placeName: newPlace,
                      city: city,
                    );
                    Navigator.pop(ctx);
                  },
                ),
              ),
            ],
          ),
        );
      },
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

  Widget _beActionChip({
    required IconData icon,
    required String label,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: accentColor.withValues(alpha: 0.5), width: 1.0),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: accentColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveBeMetricsStrip(
    BuildContext context,
    SessionProvider session,
    BehaviourEngineResponse? be,
    String ceLocation,
    String? ceActivity,
  ) {
    final relevance = be?.relevanceScore;
    final commerce = be?.commerceScore;
    final composite = be?.compositeAttributionScore;
    final gateOpen = be?.gateOpen == true ||
        be?.eligibleLifestyleException == true ||
        be?.objectCommerceEligible == true;
    final suppressReason = be?.suppressReason ?? be?.blockedReason;
    final blocked = be?.eligibilityBlocked;
    final hasBeData = be != null;

    final gateStr = hasBeData
        ? (gateOpen ? 'OPEN' : 'CLOSED')
        : '—';
    final relevanceStr = relevance != null
        ? relevance.toStringAsFixed(2)
        : (hasBeData ? '0.00' : '—');
    final commerceStr = commerce != null
        ? commerce.toStringAsFixed(2)
        : (hasBeData && composite != null ? (composite / 100.0).toStringAsFixed(2) : '—');
    final suppressStr = suppressReason ??
        (hasBeData ? (blocked == true ? 'BLOCKED' : 'NONE') : '—');

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        showFeatureAttributionDialog(
          context,
          beOutput: be != null
              ? {
                  ...be.rawJson,
                  if (be.frameType != null) 'frame_type': be.frameType,
                  if (be.behavioralState != null) 'behavioral_state': be.behavioralState,
                  if (be.relevanceScore != null) 'relevance_score': be.relevanceScore,
                  if (be.commerceScore != null) 'commerce_score': be.commerceScore,
                  if (be.gateOpen != null) 'gate_open': be.gateOpen,
                  if (be.suppressReason != null) 'suppress_reason': be.suppressReason,
                  if (be.stateConfidence != null) 'state_confidence': be.stateConfidence,
                  if (be.hesitationScore != null) 'hesitation_score': be.hesitationScore,
                  if (be.lifestyleCluster != null) 'lifestyle_cluster': be.lifestyleCluster,
                  if (be.recommendedProduct != null) 'recommended_product': be.recommendedProduct,
                  if (be.attributionBreakdown != null) 'attribution_breakdown': be.attributionBreakdown,
                  if (be.compositeAttributionScore != null) 'composite_attribution_score': be.compositeAttributionScore,
                  if (be.eligibilityBlocked != null) 'eligibility_blocked': be.eligibilityBlocked,
                  if (be.blockedReason != null) 'blocked_reason': be.blockedReason,
                  if (ceLocation.isNotEmpty) 'venue': ceLocation,
                  'schedule_activity': ?ceActivity,
                }
              : null,
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF13151E),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: gateOpen
                ? const Color(0xFF10B981).withValues(alpha: 0.6)
                : const Color(0xFF222636),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: _beLiveMetricItem(
                label: 'GATE',
                value: gateStr,
                valueColor: hasBeData
                    ? (gateOpen ? const Color(0xFF10B981) : const Color(0xFFEF4444))
                    : const Color(0xFF94A3B8),
                isBadge: true,
                badgeBg: hasBeData && gateOpen
                    ? const Color(0xFF10B981).withValues(alpha: 0.15)
                    : null,
              ),
            ),
            Container(width: 1, height: 22, color: const Color(0xFF222636)),
            Expanded(
              flex: 4,
              child: _beLiveMetricItem(
                label: 'RELEVANCE',
                value: relevanceStr,
                valueColor: relevance != null ? const Color(0xFF38BDF8) : const Color(0xFF94A3B8),
              ),
            ),
            Container(width: 1, height: 22, color: const Color(0xFF222636)),
            Expanded(
              flex: 4,
              child: _beLiveMetricItem(
                label: 'COMMERCE',
                value: commerceStr,
                valueColor: commerce != null
                    ? const Color(0xFF34D399)
                    : (composite != null && composite >= 60 ? const Color(0xFF10B981) : const Color(0xFF94A3B8)),
              ),
            ),
            Container(width: 1, height: 22, color: const Color(0xFF222636)),
            Expanded(
              flex: 5,
              child: _beLiveMetricItem(
                label: 'SUPPRESS',
                value: suppressStr,
                valueColor: suppressReason != null ? const Color(0xFFF59E0B) : const Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _beLiveMetricItem({
    required String label,
    required String value,
    required Color valueColor,
    bool isBadge = false,
    Color? badgeBg,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: Color(0xFF8E92A4),
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 1),
        Container(
          padding: isBadge ? const EdgeInsets.symmetric(horizontal: 4, vertical: 1) : EdgeInsets.zero,
          decoration: isBadge && badgeBg != null
              ? BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(4),
                )
              : null,
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
          ),
        ),
      ],
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

        return Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.surfaceMuted.withValues(alpha: 0.6),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: widget.score == null ? 0 : v.clamp(0.02, 1.0),
                strokeWidth: 3.5,
                backgroundColor: AppColors.border.withValues(alpha: 0.4),
                valueColor: AlwaysStoppedAnimation<Color>(
                  widget.score == null ? AppColors.border : arcColor,
                ),
                strokeCap: StrokeCap.round,
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    widget.score == null ? '–' : '${(v * 100).round()}',
                    style: TextStyle(
                      fontSize: widget.score == null ? 14 : 12,
                      fontWeight: FontWeight.w800,
                      color: widget.score == null ? AppColors.textSecondary : arcColor,
                      height: 1,
                    ),
                  ),
                  if (widget.score != null)
                    Text(
                      '%',
                      style: TextStyle(
                        fontSize: 8,
                        color: arcColor.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Live Detected Objects Bar (Real-time frame detections only) ─────────────
class _LiveDetectedObjectsBar extends StatelessWidget {
  final List<ContextEngineSceneObject> sceneObjects;
  final String? groundedTarget;
  final String? recommendedProduct;

  const _LiveDetectedObjectsBar({
    this.sceneObjects = const [],
    this.groundedTarget,
    this.recommendedProduct,
  });

  @override
  Widget build(BuildContext context) {
    // Gather all valid live items from the current active frame
    final validSceneObjects = sceneObjects.where((obj) {
      final name = obj.className?.trim();
      return name != null &&
          name.isNotEmpty &&
          name.toLowerCase() != 'none' &&
          name.toLowerCase() != 'unknown';
    }).toList();

    final hasDirectTarget = groundedTarget != null && groundedTarget!.trim().isNotEmpty;
    final hasRec = recommendedProduct != null && recommendedProduct!.trim().isNotEmpty;

    if (validSceneObjects.isEmpty && !hasDirectTarget && !hasRec) {
      return const SizedBox.shrink();
    }

    final List<Widget> pills = [];

    // Prominent focus badge for gaze-grounded target
    if (hasDirectTarget) {
      pills.add(
        _LiveDetectionPill(
          label: groundedTarget!.trim(),
          isGrounded: true,
          confidence: null,
        ),
      );
    }

    for (final obj in validSceneObjects) {
      final name = obj.className?.trim();
      if (name == null || name.isEmpty) continue;
      if (hasDirectTarget && name.toLowerCase() == groundedTarget!.trim().toLowerCase()) {
        continue;
      }
      pills.add(
        _LiveDetectionPill(
          label: name,
          isGrounded: false,
          confidence: obj.confidence,
        ),
      );
    }

    if (pills.isEmpty && hasRec) {
      pills.add(
        _LiveDetectionPill(
          label: recommendedProduct!.trim(),
          isGrounded: true,
          confidence: null,
        ),
      );
    }

    return Center(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: pills.map((pill) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: pill,
          )).toList(),
        ),
      ),
    );
  }
}

class _LiveDetectionPill extends StatelessWidget {
  final String label;
  final bool isGrounded;
  final double? confidence;

  const _LiveDetectionPill({
    required this.label,
    required this.isGrounded,
    this.confidence,
  });

  @override
  Widget build(BuildContext context) {
    final confPercent = confidence != null ? '${(confidence! * 100).round()}%' : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isGrounded ? const Color(0xFF10B981) : AppColors.accent.withValues(alpha: 0.8),
          width: isGrounded ? 1.4 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: (isGrounded ? const Color(0xFF10B981) : AppColors.accent).withValues(alpha: 0.28),
            blurRadius: 8,
            spreadRadius: 1,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isGrounded ? const Color(0xFF10B981) : const Color(0xFF38BDF8),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
          if (confPercent != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                confPercent,
                style: TextStyle(
                  color: isGrounded ? const Color(0xFF34D399) : const Color(0xFF93C5FD),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}


