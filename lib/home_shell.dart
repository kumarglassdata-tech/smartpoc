import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_theme.dart';
import 'auth/auth_provider.dart';
import 'home_screen.dart';
import 'interaction_engine/interaction_engine_client.dart';
import 'interested_screen.dart';
import 'myna_listening_icon.dart';
import 'profile_screen.dart';
import 'session/session_provider.dart';

// Bottom-nav shell for the 3 primary post-login screens, matching the
// mockup's own Home / Interested / Profile structure (session history moved
// to Profile > Activity since it's not part of the mockup's primary nav).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;
  bool _wakeWordActive = false;
  Timer? _wakeWordHideTimer;
  late final InteractionEngineClient _ie;
  void Function(double)? _previousWakeWordCallback;
  void Function(String, String?)? _previousToastCallback;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ie = context.read<SessionProvider>().interactionEngineClient;
    _previousWakeWordCallback = _ie.onWakeWordDetected;
    _ie.onWakeWordDetected = _onWakeWordDetected;
    _previousToastCallback = _ie.onToast;
    _ie.onToast = _onToast;
    unawaited(context.read<AuthProvider>().refreshRoles());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.hidden) {
      if (mounted) {
        final session = context.read<SessionProvider>();
        unawaited(session.interactionEngineClient.stopAudioPlayback());
        if (session.isRuntimeActive) {
          unawaited(session.stopRuntime());
        }
      }
    }
  }

  void _onWakeWordDetected(double score) {
    _previousWakeWordCallback?.call(score);
    _wakeWordHideTimer?.cancel();
    setState(() => _wakeWordActive = true);
    _wakeWordHideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _wakeWordActive = false);
    });
  }

  // Surfaces client-side voice issues (e.g. mic permission denied/blocked)
  // as a SnackBar visible from any tab, since those previously failed
  // silently with no UI cue at all.
  void _onToast(String message, String? level) {
    _previousToastCallback?.call(message, level);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: level == 'error' ? AppColors.danger : null,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  void _goToProfile() => setState(() => _index = 2);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _wakeWordHideTimer?.cancel();
    if (identical(_ie.onWakeWordDetected, _onWakeWordDetected)) {
      _ie.onWakeWordDetected = _previousWakeWordCallback;
    }
    if (identical(_ie.onToast, _onToast)) {
      _ie.onToast = _previousToastCallback;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ie = context.watch<SessionProvider>().interactionEngineClient;
    final screens = [
      HomeScreen(onOpenProfile: _goToProfile),
      const InterestedScreen(),
      const ProfileScreen(),
    ];
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(index: _index, children: screens),
          // Persistent always-listening indicator - positioned to the right
          Positioned(
            bottom: 24,
            right: 20,
            child: _MynaBotButton(
              isConnected: ie.isConnected,
              isPlaying: ie.isPlaying,
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            right: 16,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _wakeWordActive ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: AnimatedScale(
                  scale: _wakeWordActive ? 1 : 0.7,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.success,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.success.withValues(alpha: 0.5),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.graphic_eq, size: 14, color: Colors.white),
                        SizedBox(width: 4),
                        Text(
                          'Hey Myna',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (value) => setState(() => _index = value),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.favorite_outline),
            activeIcon: Icon(Icons.favorite),
            label: 'Interested',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

// ─── Myna bot FAB ────────────────────────────────────────────────────────────
class _MynaBotButton extends StatefulWidget {
  final bool isConnected;
  final bool isPlaying;

  const _MynaBotButton({required this.isConnected, required this.isPlaying});

  @override
  State<_MynaBotButton> createState() => _MynaBotButtonState();
}

class _MynaBotButtonState extends State<_MynaBotButton>
    with TickerProviderStateMixin {
  // Entrance pop-in
  late final AnimationController _entranceCtrl;
  late final Animation<double> _entranceScale;

  // Tap squish
  late final AnimationController _tapCtrl;
  late final Animation<double> _tapScale;

  // Listening pulse ring
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseScale;
  late final Animation<double> _pulseOpacity;

  @override
  void initState() {
    super.initState();

    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _entranceScale = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _entranceCtrl, curve: Curves.elasticOut));

    _tapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 110),
      reverseDuration: const Duration(milliseconds: 520),
    );
    _tapScale = Tween<double>(begin: 1.0, end: 0.80).animate(
      CurvedAnimation(
        parent: _tapCtrl,
        curve: Curves.easeIn,
        reverseCurve: Curves.elasticOut,
      ),
    );

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _pulseScale = Tween<double>(
      begin: 1.0,
      end: 1.55,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeOut));
    _pulseOpacity = Tween<double>(
      begin: 0.6,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeOut));

    Future.delayed(const Duration(milliseconds: 120), () {
      if (mounted) _entranceCtrl.forward();
    });

    if (widget.isConnected) _pulseCtrl.repeat();
    if (widget.isPlaying) _startSpeakingPulse();
  }

  @override
  void didUpdateWidget(covariant _MynaBotButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isConnected && !_pulseCtrl.isAnimating) {
      _pulseCtrl.repeat();
    } else if (!widget.isConnected && _pulseCtrl.isAnimating) {
      _pulseCtrl.stop();
      _pulseCtrl.reset();
    }
    if (widget.isPlaying && !oldWidget.isPlaying) {
      _startSpeakingPulse();
    } else if (!widget.isPlaying && oldWidget.isPlaying) {
      _stopSpeakingPulse();
    }
  }

  @override
  void dispose() {
    _speakingPulseTimer?.cancel();
    _entranceCtrl.dispose();
    _tapCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) => _tapCtrl.forward();
  void _onTapUp(TapUpDetails _) => _tapCtrl.reverse();
  void _onTapCancel() => _tapCtrl.reverse();

  // Reuses the tap-squish animation as a "talking" pulse while the
  // assistant's TTS is playing, so the button visibly reacts the same way
  // it would to a real tap - the user asked for exactly that resemblance.
  Timer? _speakingPulseTimer;

  void _startSpeakingPulse() {
    _speakingPulseTimer?.cancel();
    _speakingPulseTimer = Timer.periodic(const Duration(milliseconds: 450), (
      _,
    ) {
      if (!mounted) return;
      _tapCtrl.forward().then((_) {
        if (mounted && widget.isPlaying) _tapCtrl.reverse();
      });
    });
  }

  void _stopSpeakingPulse() {
    _speakingPulseTimer?.cancel();
    _speakingPulseTimer = null;
    if (_tapCtrl.value != 0) _tapCtrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final ringColor = widget.isPlaying
        ? AppColors.accent
        : (widget.isConnected ? AppColors.success : AppColors.textSecondary);
    final glowColor = widget.isPlaying
        ? AppColors.accent
        : (widget.isConnected ? AppColors.success : AppColors.accent);
    final statusLabel = widget.isPlaying
        ? 'Speaking'
        : (widget.isConnected ? 'Listening' : 'Not connected');
    final statusColor = widget.isPlaying
        ? AppColors.accentStrong
        : (widget.isConnected ? AppColors.success : AppColors.textSecondary);

    return ScaleTransition(
      scale: _entranceScale,
      child: GestureDetector(
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onTapCancel: _onTapCancel,
        child: ScaleTransition(
          scale: _tapScale,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  // Pulsing ring — only visible when connected
                  if (widget.isConnected)
                    AnimatedBuilder(
                      animation: _pulseCtrl,
                      builder: (_, _) => Transform.scale(
                        scale: _pulseScale.value,
                        child: Container(
                          width: 68,
                          height: 68,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: ringColor.withValues(
                                alpha: _pulseOpacity.value,
                              ),
                              width: 3,
                            ),
                          ),
                        ),
                      ),
                    ),
                  // Bot circle
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.dark,
                      border: Border.all(
                        color: ringColor.withValues(
                          alpha: widget.isConnected ? 0.8 : 0.3,
                        ),
                        width: 2.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: glowColor.withValues(
                            alpha: widget.isConnected ? 0.45 : 0.12,
                          ),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: MynaListeningIcon(
                      isActive: widget.isConnected,
                      size: 40,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              // Status label
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 300),
                style: TextStyle(
                  color: statusColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
                child: Text(statusLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
