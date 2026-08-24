import 'dart:math';

import 'package:flutter/material.dart';

import 'app_theme.dart';

// Slow-drifting dot/line network behind a screen's content, matching the
// reference dashboard's dark-background texture. Positions are normalized
// (0..1) so it scales to any screen size without regenerating particles.
class ParticleBackground extends StatefulWidget {
  final Widget child;

  const ParticleBackground({super.key, required this.child});

  @override
  State<ParticleBackground> createState() => _ParticleBackgroundState();
}

class _Particle {
  Offset position;
  Offset velocity;
  final double radius;
  final Color color;

  _Particle({required this.position, required this.velocity, required this.radius, required this.color});
}

class _ParticleBackgroundState extends State<ParticleBackground> with SingleTickerProviderStateMixin {
  static const _colors = [Color(0xFF4C8DFF), Color(0xFF4C9A6A), Color(0xFFE8963C), Color(0xFF9C6ADE)];

  late final AnimationController _controller;
  late final List<_Particle> _particles;
  Duration _lastElapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    final random = Random(7);
    _particles = List.generate(40, (_) {
      final angle = random.nextDouble() * 2 * pi;
      final speed = 0.01 + random.nextDouble() * 0.02;
      return _Particle(
        position: Offset(random.nextDouble(), random.nextDouble()),
        velocity: Offset(cos(angle) * speed, sin(angle) * speed),
        radius: 2.5 + random.nextDouble() * 3,
        color: _colors[random.nextInt(_colors.length)],
      );
    });
    _controller = AnimationController(vsync: this, duration: const Duration(days: 1))
      ..addListener(_tick)
      ..repeat();
  }

  void _tick() {
    final elapsed = _controller.lastElapsedDuration ?? Duration.zero;
    final dt = (elapsed - _lastElapsed).inMilliseconds / 1000.0;
    _lastElapsed = elapsed;
    if (dt <= 0 || dt > 0.5) return;
    for (final p in _particles) {
      var nx = p.position.dx + p.velocity.dx * dt;
      var ny = p.position.dy + p.velocity.dy * dt;
      var vx = p.velocity.dx;
      var vy = p.velocity.dy;
      if (nx < 0 || nx > 1) {
        vx = -vx;
        nx = nx.clamp(0.0, 1.0);
      }
      if (ny < 0 || ny > 1) {
        vy = -vy;
        ny = ny.clamp(0.0, 1.0);
      }
      p.position = Offset(nx, ny);
      p.velocity = Offset(vx, vy);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => CustomPaint(painter: _ParticlePainter(_particles, isDark: AppColors.isDark)),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final bool isDark;

  _ParticlePainter(this.particles, {required this.isDark});

  static const _linkDistance = 0.22;

  @override
  void paint(Canvas canvas, Size size) {
    final dotAlpha = isDark ? 0.9 : 0.55;
    final lineAlpha = isDark ? 0.4 : 0.22;

    final points = [for (final p in particles) Offset(p.position.dx * size.width, p.position.dy * size.height)];

    for (int i = 0; i < particles.length; i++) {
      for (int j = i + 1; j < particles.length; j++) {
        final d = (particles[i].position - particles[j].position).distance;
        if (d < _linkDistance) {
          final opacity = (1 - d / _linkDistance) * lineAlpha;
          canvas.drawLine(
            points[i],
            points[j],
            Paint()
              ..color = particles[i].color.withValues(alpha: opacity)
              ..strokeWidth = 1,
          );
        }
      }
    }

    for (int i = 0; i < particles.length; i++) {
      canvas.drawCircle(points[i], particles[i].radius, Paint()..color = particles[i].color.withValues(alpha: dotAlpha));
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter oldDelegate) => true;
}
