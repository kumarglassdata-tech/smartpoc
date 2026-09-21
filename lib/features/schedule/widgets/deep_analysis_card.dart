import 'package:flutter/material.dart';
import '../../../models/weekly_schedule_model.dart';
import 'activity_media_player.dart';

class ActivityMediaHelper {
  static String getMediaAssetForActivity(String activity) {
    final act = activity.toLowerCase().trim();
    if (act.contains('wak') || act.contains('alarm') || act.contains('morn')) {
      return 'assets/gifs/Waking Up.mp4';
    } else if (act.contains('bath') || act.contains('shower') || act.contains('wash')) {
      return 'assets/gifs/Bathing.mp4';
    } else if (act.contains('eat') || act.contains('food') || act.contains('lunch') || act.contains('dinner') || act.contains('breakfast')) {
      return 'assets/gifs/Eating.mp4';
    } else if (act.contains('work') || act.contains('office') || act.contains('job') || act.contains('study') || act.contains('meet')) {
      return 'assets/gifs/Working.mp4';
    } else if (act.contains('shop') || act.contains('store') || act.contains('market') || act.contains('buy')) {
      return 'assets/gifs/Shopping.mp4';
    } else if (act.contains('relax') || act.contains('watch') || act.contains('movie') || act.contains('tv') || act.contains('social') || act.contains('transit')) {
      return 'assets/gifs/Relaxing.mp4';
    }
    return 'assets/gifs/Working.mp4';
  }

  static String getSceneContextForActivity(String activity) {
    final act = activity.toLowerCase().trim();
    if (act.contains('wak') || act.contains('morn')) {
      return 'bedroom • Home';
    } else if (act.contains('bath') || act.contains('shower')) {
      return 'bathroom • Indoor';
    } else if (act.contains('eat') || act.contains('food')) {
      return 'dining / kitchen • Indoor';
    } else if (act.contains('work') || act.contains('office')) {
      return 'office • Environment';
    } else if (act.contains('shop') || act.contains('store')) {
      return 'retail / market • Public';
    } else if (act.contains('transit')) {
      return 'transit / vehicle • Commute';
    } else if (act.contains('watch') || act.contains('relax')) {
      return 'living room • Home';
    }
    return 'indoor • Environment';
  }
}

class DeepAnalysisCard extends StatelessWidget {
  final ScheduleActivitySlot slot;
  final String? customActualActivity;
  final double driftFraction;
  final String? customScene;
  final String? behavioralState;
  final double? relevanceScore;
  final VoidCallback? onTap;

  const DeepAnalysisCard({
    super.key,
    required this.slot,
    this.customActualActivity,
    this.driftFraction = 0.0,
    this.customScene,
    this.behavioralState,
    this.relevanceScore,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final assetPath = ActivityMediaHelper.getMediaAssetForActivity(slot.activity);
    final scene = customScene ?? ActivityMediaHelper.getSceneContextForActivity(slot.activity);
    final actual = customActualActivity ?? slot.activity.toLowerCase();
    final isOnSchedule = driftFraction <= 0.2;
    final driftPercentage = (driftFraction * 100).toInt();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF161412),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF2C2622),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left media thumbnail with activity badge
            ActivityMediaPlayer(
              assetPath: assetPath,
              activityTitle: slot.activity,
              width: 140,
              height: 104,
              borderRadius: BorderRadius.circular(10),
            ),
            const SizedBox(width: 14),

            // Right details section
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Scheduled activity overline
                  Text(
                    'SCHEDULED ACTIVITY',
                    style: const TextStyle(
                      color: Color(0xFF8C827A),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 3),

                  // Title with icon
                  Row(
                    children: [
                      Text(
                        slot.emoji,
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          slot.activity,
                          style: const TextStyle(
                            color: Color(0xFFF5EBE1),
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),

                  // Scene context
                  Text(
                    'Scene: $scene',
                    style: const TextStyle(
                      color: Color(0xFFA89F95),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),

                  // Schedule drift header and value
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'SCHEDULE DRIFT',
                        style: TextStyle(
                          color: Color(0xFF8E92A4),
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                      Text(
                        '$driftPercentage% ${isOnSchedule ? "(Aligned)" : "(Shifted)"}',
                        style: TextStyle(
                          color: isOnSchedule ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Enhanced, clearly visible drift progress bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      height: 7,
                      width: double.infinity,
                      color: const Color(0xFF2B2622),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final barWidth = constraints.maxWidth * driftFraction.clamp(0.05, 1.0);
                          return Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              width: barWidth,
                              height: 7,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(4),
                                gradient: LinearGradient(
                                  colors: isOnSchedule
                                      ? [const Color(0xFF00BFA5), const Color(0xFF10B981)]
                                      : [const Color(0xFFF59E0B), const Color(0xFFEF4444)],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),

                  // Sched -> Actual label
                  Row(
                    children: [
                      Expanded(
                        child: RichText(
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          text: TextSpan(
                            style: const TextStyle(fontSize: 10, color: Color(0xFF9E9891)),
                            children: [
                              const TextSpan(text: 'Actual (CE): '),
                              TextSpan(
                                text: actual.toUpperCase(),
                                style: TextStyle(
                                  color: isOnSchedule ? const Color(0xFF34D399) : const Color(0xFFFBBF24),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Status badges row (On schedule + BE Behavioural State)
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      // On schedule badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isOnSchedule ? const Color(0xFF064E3B).withValues(alpha: 0.5) : const Color(0xFF451A03).withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isOnSchedule ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isOnSchedule ? Icons.check_rounded : Icons.schedule_rounded,
                              size: 11,
                              color: isOnSchedule ? const Color(0xFF34D399) : const Color(0xFFFBBF24),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              isOnSchedule ? 'On Schedule' : 'Drifted',
                              style: TextStyle(
                                color: isOnSchedule ? const Color(0xFF34D399) : const Color(0xFFFBBF24),
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Behaviour state badge (BE Output)
                      if (behavioralState != null && behavioralState!.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E2330),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFF38BDF8),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            'State: $behavioralState',
                            style: const TextStyle(
                              color: Color(0xFF7DD3FC),
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),

                      // Pattern / Relevance badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF221E1A),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF38312B),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          relevanceScore != null
                              ? 'Match: ${(relevanceScore! * 100).toInt()}%'
                              : 'Pattern: ${(driftFraction * 0.5).toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Color(0xFFD1D5DB),
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                          ),
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
    );
  }
}
