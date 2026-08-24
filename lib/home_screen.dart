import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_theme.dart';
import 'auth/auth_provider.dart';
import 'choose_source_screen.dart';
import 'insights_screen.dart';
import 'live_session_screen.dart';

import 'particle_background.dart';
import 'recommendation_utils.dart';
import 'session/session_provider.dart';
import 'sources/source_manager.dart';
import 'stats_service.dart';

class HomeScreen extends StatelessWidget {
  final VoidCallback onOpenProfile;

  const HomeScreen({super.key, required this.onOpenProfile});

  Future<void> _stopSession(BuildContext context) => context.read<SessionProvider>().stopRuntime();

  Future<void> _startSession(BuildContext context) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChooseSourceScreen()));
  }

  void _openLiveSession(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LiveSessionScreen()));
  }

  String _sourceLabel(SourceType type) {
    switch (type) {
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

    return Scaffold(
      body: ParticleBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
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
                      onTap: onOpenProfile,
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
                FilledButton(
                  onPressed: () => sessionState.isRuntimeActive ? _stopSession(context) : _startSession(context),
                  child: Text(sessionState.isRuntimeActive ? 'Stop Session' : 'Start Session'),
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
                  future: session.statsService.load(),
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
                      return Container(
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
                      );
                    }).toList(),
                  ),
              ],
            ),
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
