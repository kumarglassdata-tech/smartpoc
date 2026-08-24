import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../app_theme.dart';
import 'auth_provider.dart';

// Shown right after the native launch screen, before routing to login/home -
// Myna's logo (a real myna bird) glows and gently bobs/tilts like it's
// flying, then hands off to the router's own redirect logic once the
// animation has played (auth/settings are already loaded by main() before
// this even mounts, so there's no real loading wait to hide).
class SplashScreen extends StatefulWidget {
  final AuthProvider auth;

  const SplashScreen({super.key, required this.auth});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _glow;
  late final Animation<double> _float;
  late final Animation<double> _tilt;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
    _glow = Tween<double>(begin: 0.3, end: 0.7).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _float = Tween<double>(begin: -14, end: 14).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _tilt = Tween<double>(begin: -0.09, end: 0.09).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    Future.delayed(const Duration(milliseconds: 1900), () {
      if (!mounted) return;
      context.go(widget.auth.isLoggedIn ? '/home' : '/login');
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark,
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(0, _float.value),
              child: Transform.rotate(
                angle: _tilt.value,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: AppColors.accent.withValues(alpha: _glow.value), blurRadius: 70, spreadRadius: 25),
                    ],
                  ),
                  child: child,
                ),
              ),
            );
          },
          child: SvgPicture.asset('assets/images/myna-logo.svg', width: 140, height: 140),
        ),
      ),
    );
  }
}
