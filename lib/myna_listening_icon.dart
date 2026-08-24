import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

// Same myna-logo.svg used on the login screen, given a slow to-and-fro sway
// whenever the interaction engine is connected and listening for "Hey Myna" -
// a quiet always-on-mic cue instead of a static icon.
class MynaListeningIcon extends StatefulWidget {
  final bool isActive;
  final double size;

  const MynaListeningIcon({super.key, required this.isActive, this.size = 28});

  @override
  State<MynaListeningIcon> createState() => _MynaListeningIconState();
}

class _MynaListeningIconState extends State<MynaListeningIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _sway;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300));
    _sway = Tween<double>(begin: -0.13, end: 0.13).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    if (widget.isActive) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant MynaListeningIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.isActive && _controller.isAnimating) {
      _controller.stop();
      _controller.animateTo(0.5, duration: const Duration(milliseconds: 200));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logo = SvgPicture.asset('assets/images/myna-logo.svg', width: widget.size, height: widget.size);
    return AnimatedBuilder(
      animation: _sway,
      builder: (context, child) => Transform.rotate(angle: _sway.value, child: child),
      child: logo,
    );
  }
}
