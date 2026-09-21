import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_theme.dart';
import 'auth/auth_provider.dart';
import 'behaviour_analysis_screen.dart';
import 'choose_source_screen.dart';
import 'features/owned_objects/owned_objects_card.dart';
import 'features/schedule/weekly_schedule_screen.dart';
import 'features/schedule/widgets/deep_analysis_card.dart';
import 'features/schedule/widgets/feature_attribution_insights_card.dart';
import 'insights_screen.dart';
import 'live_session_screen.dart';
import 'models/weekly_schedule_model.dart';
import 'particle_background.dart';
import 'product_detail_screen.dart';
import 'recommendation_utils.dart';
import 'services/schedule_parser_service.dart';
import 'session/session_provider.dart';
import 'sources/source_manager.dart';
import 'stats_service.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback onOpenProfile;

  const HomeScreen({super.key, required this.onOpenProfile});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Future<StatsSnapshot>? _statsFuture;
  int? _lastUserId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = context.read<SessionProvider>();
    final uid = session.userId is int ? session.userId as int : 0;
    if (_statsFuture == null || _lastUserId != uid) {
      _lastUserId = uid;
      _statsFuture = session.statsService.load();
    }
  }

  void _refreshStats() {
    if (mounted) {
      setState(() {
        final session = context.read<SessionProvider>();
        _statsFuture = session.statsService.load();
      });
    }
  }

  Future<void> _stopSession(BuildContext context) => context.read<SessionProvider>().stopRuntime();

  Future<void> _startSession(BuildContext context) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChooseSourceScreen()));
    _refreshStats();
  }

  void _openLiveSession(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LiveSessionScreen()));
  }

  String _sourceLabel(SourceType type) {
    switch (type) {
      case SourceType.metaGlasses:
        return 'Meta Ray-Ban Glasses';
      case SourceType.phone:
        return 'Phone Camera';
      case SourceType.videoUpload:
        return 'Recorded Video';
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final session = context.watch<SessionProvider>();
    final sessionState = session.state;
    final ie = session.interactionEngineClient;
    final greetingName = auth.username.isNotEmpty ? auth.username.split(' ').first : 'there';

    // "Recommended for you" is deliberately GET /ah/recommend specifically -
    // broader browsing suggestions, not the exact-match-only buy/recommendPost
    // pairing that live-session/session-complete's "Matched products" uses.
    final recommendations = session.lastPipelineResult != null
        ? extractRecommendations(session.lastPipelineResult!.ecomAdHandlerRaw.recommendGet)
        : const <Map<String, String>>[];

    final String voiceLine;
    if (!ie.isConnected) {
      voiceLine = 'Voice assistant not connected';
    } else if (ie.isPlaying) {
      voiceLine = 'Assistant speaking...';
    } else if (ie.isSpeaking) {
      voiceLine = 'Listening to you...';
    } else if (ie.wakeWordEnabled) {
      voiceLine = "Say 'Hey Myna' to talk";
    } else {
      voiceLine = 'Listening - speak anytime';
    }

    return ParticleBackground(
      child: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 80),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Hi, $greetingName', style: Theme.of(context).textTheme.headlineSmall),
                          const SizedBox(height: 2),
                          Text('Ready to see something new?', style: TextStyle(color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    _AnimatedProfileAvatar(
                      photoUrl: auth.photoUrl,
                      name: greetingName,
                      onTap: widget.onOpenProfile,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: sessionState.isRuntimeActive ? () => _openLiveSession(context) : null,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: AppColors.dark, borderRadius: BorderRadius.circular(18)),
                    child: Row(
                      children: [
                        Icon(Icons.camera_alt_outlined, color: AppColors.accent),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_sourceLabel(session.sourceManager.activeType), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: sessionState.isRuntimeActive ? AppColors.success : AppColors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    sessionState.isRuntimeActive
                                        ? 'Session active · ${sessionState.framesCaptured} frames'
                                        : (sessionState.isConnected ? 'Connected' : 'Not connected'),
                                    style: TextStyle(color: AppColors.accentTint, fontSize: 13),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: sessionState.isRuntimeActive ? AppColors.danger : AppColors.accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 2,
                      ),
                      onPressed: () => sessionState.isRuntimeActive ? _stopSession(context) : _startSession(context),
                      icon: Icon(
                        sessionState.isRuntimeActive ? Icons.stop_circle_outlined : Icons.play_circle_filled_rounded,
                        size: 22,
                      ),
                      label: Text(
                        sessionState.isRuntimeActive ? 'Stop Session' : 'Start Session',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // ── Live Behaviour Engine (BE) Hub & Analytics ──────────────
                _BehaviourEngineLiveHubCard(
                  session: session,
                  isRuntimeActive: sessionState.isRuntimeActive,
                ),
                const SizedBox(height: 16),
                // Location & Place Options Selector Card on Main UI
                _LocationContextCard(
                  locationService: session.locationService,
                  onLocationUpdated: (lat, lon, place, city) {
                    session.locationService.setManualLocation(
                      latitude: lat,
                      longitude: lon,
                      placeName: place,
                      city: city,
                    );
                    final uid = auth.userId ?? session.userId;
                    session.behaviourEngineClient.postLocation(
                      userId: uid != null && uid != 0 ? uid : 'default_user',
                      label: place,
                      lat: lat,
                      lon: lon,
                      radiusM: 100,
                    );
                  },
                ),
                const SizedBox(height: 16),
                // Owned Objects & Products Management Card (Batch Remove via BE)
                OwnedObjectsCard(
                  onObjectsUpdated: _refreshStats,
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: ie.isConnected ? AppColors.success.withValues(alpha: 0.5) : AppColors.border, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        ie.isPlaying || ie.isSpeaking ? Icons.graphic_eq : Icons.mic_none,
                        color: ie.isConnected ? AppColors.success : AppColors.accentStrong,
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(voiceLine, style: TextStyle(color: AppColors.textPrimary))),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                FutureBuilder<StatsSnapshot>(
                  future: _statsFuture,
                  builder: (context, snapshot) {
                    final stats = snapshot.data;
                    return InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InsightsScreen())),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Your week in style', style: TextStyle(fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 2),
                                  Text(
                                    stats == null
                                        ? 'Loading...'
                                        : '${stats.totalSessions} ${stats.totalSessions == 1 ? 'session' : 'sessions'} · ${stats.totalObjectsSeen} items viewed',
                                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right, color: AppColors.textSecondary),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
                Text('Recommended for you', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: AppColors.textPrimary)),
                const SizedBox(height: 12),
                if (recommendations.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      session.lastPipelineResult == null
                          ? 'Start a session to see recommendations here.'
                          : "The ecom hub responded, but nothing matched the fields this screen looks for. See Profile > Developer Tools for the raw response.",
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                else
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: recommendations.map((item) {
                      return InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProductDetailScreen(item: item))),
                        child: Container(
                          width: (MediaQuery.of(context).size.width - 20 * 2 - 12) / 2,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: item['image'] != null
                                    ? Image.network(
                                        item['image']!,
                                        height: 72,
                                        width: double.infinity,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) => Container(height: 72, color: AppColors.accentTint),
                                      )
                                    : Container(height: 72, color: AppColors.accentTint),
                              ),
                              const SizedBox(height: 8),
                              Text(item['name']!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                              if (item['price'] != null) ...[
                                const SizedBox(height: 2),
                                Text(item['price']!, style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700)),
                              ],
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
        ),
      );
  }
}

// Animated profile avatar: pops DOWN on press, springs UP with elastic
// overshoot on release for a satisfying tactile bounce feel.
class _AnimatedProfileAvatar extends StatefulWidget {
  final String photoUrl;
  final String name;
  final VoidCallback onTap;

  const _AnimatedProfileAvatar({
    required this.photoUrl,
    required this.name,
    required this.onTap,
  });

  @override
  State<_AnimatedProfileAvatar> createState() => _AnimatedProfileAvatarState();
}

class _AnimatedProfileAvatarState extends State<_AnimatedProfileAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      reverseDuration: const Duration(milliseconds: 500),
    );
    // forward = squish down to 0.82, reverse = elastic bounce back
    _scale = Tween<double>(begin: 1.0, end: 0.82).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: Curves.easeIn,
        reverseCurve: Curves.elasticOut,
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) => _ctrl.forward();

  void _onTapUp(TapUpDetails _) {
    _ctrl.reverse();
    widget.onTap();
  }

  void _onTapCancel() => _ctrl.reverse();

  @override
  Widget build(BuildContext context) {
    final initial =
        widget.name.isNotEmpty ? widget.name[0].toUpperCase() : '?';

    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: ScaleTransition(
        scale: _scale,
        child: _AvatarFace(photoUrl: widget.photoUrl, initial: initial),
      ),
    );
  }
}

class _AvatarFace extends StatelessWidget {
  final String photoUrl;
  final String initial;

  const _AvatarFace({required this.photoUrl, required this.initial});

  @override
  Widget build(BuildContext context) {
    if (photoUrl.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          photoUrl,
          width: 56,
          height: 56,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _InitialsAvatar(initial: initial),
        ),
      );
    }
    return _InitialsAvatar(initial: initial);
  }
}

class _InitialsAvatar extends StatelessWidget {
  final String initial;

  const _InitialsAvatar({required this.initial});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFFE8943A), Color(0xFFB85C00)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE8943A).withValues(alpha: 0.45),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 22,
          height: 1,
        ),
      ),
    );
  }
}

class _LocationContextCard extends StatefulWidget {
  final dynamic locationService;
  final void Function(double lat, double lon, String place, String city) onLocationUpdated;

  const _LocationContextCard({
    required this.locationService,
    required this.onLocationUpdated,
  });

  @override
  State<_LocationContextCard> createState() => _LocationContextCardState();
}

class _LocationContextCardState extends State<_LocationContextCard> {
  void _showCoordinatesDialog(BuildContext context, double currentLat, double currentLon, String currentPlace) {
    final latCtrl = TextEditingController(text: currentLat.toStringAsFixed(5));
    final lonCtrl = TextEditingController(text: currentLon.toStringAsFixed(5));
    final placeCtrl = TextEditingController(text: currentPlace);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Row(
          children: [
            Icon(Icons.edit_location_alt_outlined, color: AppColors.accent, size: 22),
            const SizedBox(width: 8),
            const Text('Enter Location & Coordinates', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: placeCtrl,
              decoration: InputDecoration(
                labelText: 'Place / Context Name',
                hintText: 'e.g. HOME, OFFICE, MALL',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: latCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: InputDecoration(
                labelText: 'Latitude',
                hintText: 'e.g. 12.9716',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: lonCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: InputDecoration(
                labelText: 'Longitude',
                hintText: 'e.g. 77.5946',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          FilledButton(
            onPressed: () {
              final lat = double.tryParse(latCtrl.text.trim()) ?? currentLat;
              final lon = double.tryParse(lonCtrl.text.trim()) ?? currentLon;
              final place = placeCtrl.text.trim().isNotEmpty ? placeCtrl.text.trim().toUpperCase() : currentPlace;
              widget.onLocationUpdated(lat, lon, place, place);
              Navigator.of(ctx).pop();
            },
            child: const Text('Update Location'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lat = widget.locationService.latitude;
    final lon = widget.locationService.longitude;
    final currentPlace = widget.locationService.currentPlaceName ?? (lat != null ? 'CURRENT LOCATION' : 'GPS LOCATING');
    final city = widget.locationService.city ?? (lat != null ? '${lat.toStringAsFixed(4)}, ${lon?.toStringAsFixed(4)}' : 'Detecting...');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(Icons.location_on, color: AppColors.accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      currentPlace,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.accentStrong,
                        fontSize: 13,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '· $city',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  lat != null && lon != null
                      ? '${lat.toStringAsFixed(4)}° N, ${lon.toStringAsFixed(4)}° E'
                      : 'Locating via device GPS...',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _showCoordinatesDialog(context, lat ?? 0.0, lon ?? 0.0, currentPlace),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.edit_location_alt_outlined, size: 14, color: AppColors.accent),
                  const SizedBox(width: 4),
                  Text('Edit Location', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BehaviourEngineLiveHubCard extends StatelessWidget {
  final SessionProvider session;
  final bool isRuntimeActive;

  const _BehaviourEngineLiveHubCard({
    required this.session,
    required this.isRuntimeActive,
  });

  void _showLiveActivityModal(BuildContext context, SessionProvider session) async {
    final auth = context.read<AuthProvider>();
    final uid = await auth.resolveUserId() ?? session.userId ?? 0;
    final parsedUid = uid is int ? uid : int.tryParse('$uid') ?? 0;
    final schedule = await ScheduleParserService.loadSchedule(parsedUid);

    final ce = session.lastPipelineResult?.contextEngineResponse;
    final be = session.lastPipelineResult?.behaviourEngineResponse;
    final ceActivity = ce?.currentActivity ??
        ce?.activityInformation?['activity']?.toString();
    final beState = be?.behavioralState;
    final relevance = be?.relevanceScore;

    final now = DateTime.now();
    final slot = schedule.getSlotForDateTime(now) ??
        (schedule.slotsByDay.isNotEmpty && schedule.slotsByDay.values.first.isNotEmpty
            ? schedule.slotsByDay.values.first.first
            : ScheduleActivitySlot(
                id: 'live_slot',
                day: 'Today',
                time: '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
                activity: ceActivity != null ? ceActivity.toUpperCase() : 'Routine',
                taskCount: 0,
                tasks: const [],
              ));

    final isMatched = ceActivity != null &&
        (slot.activity.toLowerCase().contains(ceActivity.toLowerCase()) ||
            ceActivity.toLowerCase().contains(slot.activity.toLowerCase()));
    final drift = (ceActivity == null) ? 0.0 : (isMatched ? 0.0 : 0.75);

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.90,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF13110F),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: AppColors.border, width: 1),
            ),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.accentTint,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.directions_run_rounded, color: AppColors.accent, size: 20),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Current Activity & Routine',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                'Live Cognitive Engine (CE) & Behaviour Engine (BE)',
                                style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
                              ),
                            ],
                          ),
                        ],
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: AppColors.textSecondary),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Live CE Activity & BE State Overview Banner
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'CE ACTIVITY OUTPUT',
                              style: TextStyle(
                                color: AppColors.accentStrong,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.success.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: AppColors.success, width: 0.8),
                              ),
                              child: Text(
                                'LIVE CE',
                                style: TextStyle(
                                  color: AppColors.success,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                ceActivity != null ? ceActivity.toUpperCase() : 'NO ACTIVITY DETECTED',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E2330),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFF38BDF8), width: 0.8),
                              ),
                              child: Text(
                                'BE State: ${beState ?? "Standby"}',
                                style: const TextStyle(
                                  color: Color(0xFF7DD3FC),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (ce?.activityInformation != null && ce!.activityInformation!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Metadata: ${ce.activityInformation}',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontFamily: 'monospace'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Deep Analysis Card comparing Scheduled vs Actual
                  Text(
                    'ROUTINE DRIFT & DEEP ANALYSIS',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DeepAnalysisCard(
                    slot: slot,
                    driftFraction: drift,
                    customActualActivity: ceActivity,
                    behavioralState: beState,
                    relevanceScore: relevance,
                  ),
                  const SizedBox(height: 16),

                  // View full calendar button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: BorderSide(color: AppColors.accent),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: Icon(Icons.calendar_month_outlined, color: AppColors.accent, size: 18),
                      label: Text('Open Full Weekly Schedule Calendar', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700)),
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const WeeklyScheduleScreen()),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ce = session.lastPipelineResult?.contextEngineResponse;
    final ceActivity = ce?.currentActivity ?? ce?.activityInformation?['activity']?.toString();
    final be = session.lastPipelineResult?.behaviourEngineResponse;
    final behavioralState = be?.behavioralState;
    final relevanceScore = be?.relevanceScore;
    final currentPlace = session.locationService.currentPlaceName;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isRuntimeActive ? AppColors.accent.withValues(alpha: 0.5) : AppColors.border,
          width: isRuntimeActive ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: isRuntimeActive ? AppColors.accentTint : AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.psychology_outlined,
                  color: isRuntimeActive ? AppColors.accent : AppColors.textSecondary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Behaviour Engine & Analytics',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isRuntimeActive) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: AppColors.success, width: 0.8),
                            ),
                            child: Text(
                              'LIVE',
                              style: TextStyle(
                                color: AppColors.success,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isRuntimeActive && (behavioralState != null || ceActivity != null)
                          ? 'Activity: ${ceActivity ?? "Active"} · State: ${behavioralState ?? "Engaged"} · ${(relevanceScore != null ? '${(relevanceScore * 100).toInt()}% match' : currentPlace)}'
                          : (ceActivity != null
                              ? 'Activity: $ceActivity · State: ${behavioralState ?? "Active"}'
                              : 'Live taxonomy, routine schedules & commerce attribution'),
                      style: TextStyle(
                        color: isRuntimeActive ? AppColors.accentStrong : AppColors.textSecondary,
                        fontSize: 11.5,
                        fontWeight: isRuntimeActive ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Interactive Action Grid
          Row(
            children: [
              Expanded(
                child: _hubTile(
                  icon: Icons.auto_graph_rounded,
                  title: 'Analytics',
                  subtitle: 'Dashboard',
                  color: AppColors.accent,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const InsightsScreen()),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _hubTile(
                  icon: Icons.hub_outlined,
                  title: 'BE Graph',
                  subtitle: 'Taxonomy',
                  color: const Color(0xFF38BDF8),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const BehaviourAnalysisScreen()),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _hubTile(
                  icon: Icons.directions_run_rounded,
                  title: 'Activity',
                  subtitle: ceActivity != null ? ceActivity.toUpperCase() : 'Routine · CE',
                  color: const Color(0xFFF59E0B),
                  onTap: () => _showLiveActivityModal(context, session),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _hubTile(
                  icon: Icons.attractions_outlined,
                  title: 'Attribution',
                  subtitle: 'Commerce',
                  color: const Color(0xFF10B981),
                  onTap: () {
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
                              if (ce?.currentLocation != null) 'venue': ce?.currentLocation,
                              'schedule_activity': ?ceActivity,
                            }
                          : null,
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _hubTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 10,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

