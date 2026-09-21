import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class ActivityMediaPlayer extends StatefulWidget {
  final String assetPath;
  final String activityTitle;
  final double width;
  final double height;
  final BorderRadius borderRadius;

  const ActivityMediaPlayer({
    super.key,
    required this.assetPath,
    required this.activityTitle,
    this.width = 140,
    this.height = 95,
    this.borderRadius = const BorderRadius.all(Radius.circular(10)),
  });

  @override
  State<ActivityMediaPlayer> createState() => _ActivityMediaPlayerState();
}

class _ActivityMediaPlayerState extends State<ActivityMediaPlayer> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  @override
  void didUpdateWidget(covariant ActivityMediaPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetPath != widget.assetPath) {
      _controller?.dispose();
      _controller = null;
      _isInitialized = false;
      _hasError = false;
      _initVideo();
    }
  }

  Future<void> _initVideo() async {
    try {
      final controller = VideoPlayerController.asset(widget.assetPath);
      _controller = controller;
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0.0); // mute
      await controller.play();
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: widget.borderRadius,
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: widget.borderRadius,
              child: _buildMediaContent(),
            ),
          ),
          Positioned(
            top: 6,
            left: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF262D3D).withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                widget.activityTitle.toUpperCase(),
                style: const TextStyle(
                  color: Color(0xFF60A5FA),
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaContent() {
    if (_isInitialized && _controller != null && _controller!.value.isInitialized) {
      return FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: _controller!.value.size.width > 0 ? _controller!.value.size.width : 200,
          height: _controller!.value.size.height > 0 ? _controller!.value.size.height : 200,
          child: VideoPlayer(_controller!),
        ),
      );
    }

    if (_hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.motion_photos_on_rounded, size: 28, color: Color(0xFFE8963C)),
            const SizedBox(height: 2),
            Text(
              widget.activityTitle,
              style: const TextStyle(fontSize: 10, color: Color(0xFF4B5563), fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }

    return const Center(
      child: SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE8963C)),
      ),
    );
  }
}
