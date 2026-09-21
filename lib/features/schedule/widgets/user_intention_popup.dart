import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../models/weekly_schedule_model.dart';

class UserIntentionCard extends StatelessWidget {
  final String activityName;
  final String emoji;
  final double intentionPercent; // e.g. 0.75 for 75%
  final String? customOverline;
  final Color ringColor;
  final Color trackColor;
  final VoidCallback? onClose;

  const UserIntentionCard({
    super.key,
    required this.activityName,
    this.emoji = '💼',
    this.intentionPercent = 0.75,
    this.customOverline = 'USER INTENTION MAY BE:',
    this.ringColor = const Color(0xFF3B82F6),
    this.trackColor = const Color(0xFF1E2433),
    this.onClose,
  });

  factory UserIntentionCard.fromSlot(
    ScheduleActivitySlot slot, {
    double intentionPercent = 0.75,
    VoidCallback? onClose,
  }) {
    return UserIntentionCard(
      activityName: slot.activity,
      emoji: slot.emoji,
      intentionPercent: intentionPercent,
      onClose: onClose,
    );
  }

  @override
  Widget build(BuildContext context) {
    final percentInt = (intentionPercent * 100).toInt();

    return Container(
      constraints: const BoxConstraints(minWidth: 260, maxWidth: 320),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      decoration: BoxDecoration(
        color: const Color(0xFF11141C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF222B3D),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: ringColor.withValues(alpha: 0.08),
            blurRadius: 30,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Overline Header
          Row(
            children: [
              Expanded(
                child: Text(
                  customOverline ?? 'USER INTENTION MAY BE:',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    color: Color(0xFF71717A),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onClose != null) ...[
                const SizedBox(width: 6),
                InkWell(
                  onTap: onClose,
                  borderRadius: BorderRadius.circular(12),
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(Icons.close, size: 14, color: Color(0xFF71717A)),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),

          // Divider Bar
          Container(
            height: 1.8,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF1D4ED8).withValues(alpha: 0.2),
                  const Color(0xFF3B82F6),
                  const Color(0xFF1D4ED8).withValues(alpha: 0.2),
                ],
              ),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          const SizedBox(height: 18),

          // Activity title row with percentage badge
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                emoji,
                style: const TextStyle(fontSize: 22),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  activityName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),
              // 75% Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF261907),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: const Color(0xFF9A5B0B),
                    width: 1,
                  ),
                ),
                child: Text(
                  '$percentInt%',
                  style: const TextStyle(
                    color: Color(0xFFF59E0B),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Circular Donut Progress Indicator
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.0, end: intentionPercent.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, val, child) {
              return SizedBox(
                width: 116,
                height: 116,
                child: CustomPaint(
                  painter: _DonutRingPainter(
                    progress: val,
                    ringColor: ringColor,
                    trackColor: trackColor,
                    strokeWidth: 16.0,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

class _DonutRingPainter extends CustomPainter {
  final double progress;
  final Color ringColor;
  final Color trackColor;
  final double strokeWidth;

  _DonutRingPainter({
    required this.progress,
    required this.ringColor,
    required this.trackColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // 1. Draw track circle
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, trackPaint);

    // 2. Draw active progress arc (starts from top -pi/2)
    if (progress > 0) {
      final sweepAngle = 2 * math.pi * progress;
      final activePaint = Paint()
        ..color = ringColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        sweepAngle,
        false,
        activePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DonutRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.ringColor != ringColor ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

/// Helper method to open User Intention Popup Dialog
Future<void> showUserIntentionDialog(
  BuildContext context, {
  required String activityName,
  String emoji = '💼',
  double intentionPercent = 0.75,
  String? customOverline,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.65),
    builder: (ctx) {
      return Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Center(
          child: UserIntentionCard(
            activityName: activityName,
            emoji: emoji,
            intentionPercent: intentionPercent,
            customOverline: customOverline,
            onClose: () => Navigator.of(ctx).pop(),
          ),
        ),
      );
    },
  );
}

/// Helper method to open User Intention BottomSheet
Future<void> showUserIntentionBottomSheet(
  BuildContext context, {
  required String activityName,
  String emoji = '💼',
  double intentionPercent = 0.75,
  String? customOverline,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) {
      return SafeArea(
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.88,
          ),
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
          decoration: BoxDecoration(
            color: const Color(0xFF0F1218),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: const Color(0xFF222B3D)),
          ),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF333D50),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                UserIntentionCard(
                  activityName: activityName,
                  emoji: emoji,
                  intentionPercent: intentionPercent,
                  customOverline: customOverline,
                  onClose: () => Navigator.of(ctx).pop(),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
