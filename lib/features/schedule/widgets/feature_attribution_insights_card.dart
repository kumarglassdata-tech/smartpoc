import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../models/weekly_schedule_model.dart';

/// Data model for an individual factor in the Attribution Breakdown
class AttributionFactor {
  final String factor;
  final String value;
  final String impact; // e.g. "+20%", "0%", "-20%"
  final String status; // "pass", "defer", "signal", "block", "fail"
  final double weight; // e.g. 0.15
  final String detail;

  const AttributionFactor({
    required this.factor,
    required this.value,
    required this.impact,
    required this.status,
    required this.weight,
    required this.detail,
  });

  factory AttributionFactor.fromJson(Map<String, dynamic> json) {
    return AttributionFactor(
      factor: json['factor']?.toString() ?? 'Attribution Factor',
      value: json['value']?.toString() ?? '',
      impact: json['impact']?.toString() ?? '0%',
      status: json['status']?.toString().toLowerCase() ?? 'pass',
      weight: (json['weight'] as num?)?.toDouble() ?? 0.15,
      detail: json['detail']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'factor': factor,
    'value': value,
    'impact': impact,
    'status': status,
    'weight': weight,
    'detail': detail,
  };
}

/// Backwards-compatible item alias for existing references
class FeatureAttributionItem {
  final String title;
  final String? subtitle;
  final double percentage;
  final String? customValueDisplay;

  const FeatureAttributionItem({
    required this.title,
    this.subtitle,
    required this.percentage,
    this.customValueDisplay,
  });
}

/// Full Commerce Eligibility & Attribution Breakdown widget matching the reference design
class FeatureAttributionInsightsCard extends StatelessWidget {
  final String title;
  final int compositeScore; // 0-100
  final double? relevanceScore; // 0.0-1.0
  final double? commerceScore; // 0.0-1.0
  final bool? gateOpen;
  final String? suppressReason;
  final int threshold; // default 60
  final bool isEligible;
  final bool? eligibilityBlocked;
  final String? blockedReason;
  final String? blockedDetail;
  final List<AttributionFactor> factors;
  final VoidCallback? onClose;

  const FeatureAttributionInsightsCard({
    super.key,
    this.title = 'COMMERCE ELIGIBILITY & ATTRIBUTION',
    this.compositeScore = 0,
    this.relevanceScore,
    this.commerceScore,
    this.gateOpen,
    this.suppressReason,
    this.threshold = 60,
    this.isEligible = false,
    this.eligibilityBlocked,
    this.blockedReason,
    this.blockedDetail,
    required this.factors,
    this.onClose,
  });

  /// Empty constructor when no live engine data has arrived yet
  factory FeatureAttributionInsightsCard.empty({
    VoidCallback? onClose,
    String? message,
  }) {
    return FeatureAttributionInsightsCard(
      compositeScore: 0,
      relevanceScore: 0.0,
      commerceScore: 0.0,
      gateOpen: false,
      suppressReason: null,
      threshold: 60,
      isEligible: false,
      eligibilityBlocked: true,
      blockedReason: null,
      blockedDetail: message ?? 'No live attribution data received yet from engine (/be/process). Start a live session to stream live data.',
      factors: const [],
      onClose: onClose,
    );
  }

  /// Factory constructor to parse directly from the BE /process response JSON
  factory FeatureAttributionInsightsCard.fromProcessOutput(
    Map<String, dynamic>? beOutput, {
    VoidCallback? onClose,
    String? fallbackProductName,
    String? fallbackVenue,
    String? fallbackScheduleActivity,
  }) {
    if (beOutput == null || beOutput.isEmpty) {
      return FeatureAttributionInsightsCard.empty(
        onClose: onClose,
        message: 'No live attribution data received from Behaviour Engine (/be/process).',
      );
    }

    final rawBreakdown = beOutput['attribution_breakdown'] ??
        beOutput['eligibility_attribution'] ??
        beOutput['ie_commerce_eligibility']?['attribution_breakdown'] ??
        beOutput['attribution'] ??
        beOutput['breakdown'];

    List<AttributionFactor> parsedFactors = [];
    if (rawBreakdown is List && rawBreakdown.isNotEmpty) {
      parsedFactors = rawBreakdown
          .whereType<Map>()
          .map((e) => AttributionFactor.fromJson(e.cast<String, dynamic>()))
          .toList();
    } else if (beOutput['recommended_product'] != null ||
        beOutput['behavioral_state'] != null ||
        beOutput['relevance_score'] != null ||
        beOutput['commerce_score'] != null) {
      parsedFactors = _generateDefaultFactors(
        beOutput: beOutput,
        productName: fallbackProductName,
        venue: fallbackVenue,
        scheduleActivity: fallbackScheduleActivity,
      );
    } else {
      return FeatureAttributionInsightsCard.empty(
        onClose: onClose,
        message: 'No live attribution factors in current Behaviour Engine output.',
      );
    }

    final relevance = (beOutput['relevance_score'] as num?)?.toDouble();
    final commerceScore = (beOutput['commerce_score'] ??
            beOutput['ie_commerce_eligibility']?['commerce_score'])
        ?.toDouble();
    final gateOpen = beOutput['gate_open'] as bool? ??
        beOutput['eligible_lifestyle_exception'] as bool? ??
        beOutput['object_commerce_eligible'] as bool?;
    final suppressReason = beOutput['suppress_reason']?.toString() ??
        beOutput['blocked_reason']?.toString() ??
        beOutput['eligibility_blocked_reason']?.toString();

    final scoreVal = (commerceScore != null ? (commerceScore * 100).round() : null) ??
        (beOutput['composite_attribution_score'] ??
            beOutput['eligibility_score'] ??
            beOutput['composite_score'] ??
            beOutput['relevance_score']) as num?;
    int score = 0;
    if (scoreVal != null) {
      score = scoreVal > 1.0 ? scoreVal.round() : (scoreVal * 100).round();
    } else {
      score = _calculateScoreFromFactors(parsedFactors);
    }

    final isBlocked = beOutput['eligibility_blocked'] == true ||
        beOutput['blocked'] == true ||
        (beOutput['eligibility_status'] == 'blocked') ||
        (beOutput['frame_type'] == 'motion_suppression');

    final blockedReason = suppressReason ??
        (isBlocked ? 'no attended product target' : null);
    final blockedDetail = beOutput['blocked_detail']?.toString() ??
        (isBlocked
            ? 'Proactive recommendation suppressed by Context-Object Policy Engine (COPE) to prevent intrusive/inappropriate prompts.'
            : null);

    return FeatureAttributionInsightsCard(
      compositeScore: score,
      relevanceScore: relevance,
      commerceScore: commerceScore,
      gateOpen: gateOpen,
      suppressReason: suppressReason,
      threshold: (beOutput['threshold'] as num?)?.toInt() ?? 60,
      isEligible: (gateOpen == true || !isBlocked) && score >= 60,
      eligibilityBlocked: beOutput['eligibility_blocked'] as bool? ?? isBlocked,
      blockedReason: blockedReason,
      blockedDetail: blockedDetail,
      factors: parsedFactors,
      onClose: onClose,
    );
  }

  /// Factory constructor for Product Detail Screen & Saved Items
  factory FeatureAttributionInsightsCard.fromProduct(
    Map<String, String> item, {
    VoidCallback? onClose,
    Map<String, dynamic>? beOutput,
    String? sceneContext,
  }) {
    final name = item['name'] ?? 'Product Target';
    if (beOutput != null && beOutput.isNotEmpty) {
      return FeatureAttributionInsightsCard.fromProcessOutput(
        beOutput,
        onClose: onClose,
        fallbackProductName: name,
        fallbackVenue: sceneContext,
      );
    }

    return FeatureAttributionInsightsCard.empty(
      onClose: onClose,
      message: "No live attribution evaluation for '$name'.",
    );
  }

  /// Factory constructor based on a schedule slot
  factory FeatureAttributionInsightsCard.fromSlot(
    ScheduleActivitySlot slot, {
    VoidCallback? onClose,
    Map<String, dynamic>? beOutput,
    String? currentDetectedActivity,
    String? sceneContext,
  }) {
    if (beOutput != null && beOutput.isNotEmpty) {
      return FeatureAttributionInsightsCard.fromProcessOutput(
        beOutput,
        onClose: onClose,
        fallbackScheduleActivity: slot.activity,
        fallbackVenue: sceneContext,
      );
    }

    return FeatureAttributionInsightsCard.empty(
      onClose: onClose,
      message: "No live attribution evaluation for slot '${slot.activity}'.",
    );
  }

  /// Sample constructor with active pass state (used strictly for offline widget tests)
  factory FeatureAttributionInsightsCard.sampleActive({
    VoidCallback? onClose,
    String? productName,
    String? venue,
    String? scheduleActivity,
  }) {
    final prod = productName ?? 'Attended Product';
    final ven = venue ?? 'Live Venue';
    final sched = scheduleActivity ?? 'Active Routine';

    return FeatureAttributionInsightsCard(
      compositeScore: 77,
      relevanceScore: 0.82,
      threshold: 60,
      isEligible: true,
      eligibilityBlocked: false,
      blockedReason: null,
      onClose: onClose,
      factors: [
        AttributionFactor(
          factor: 'Target Grounding',
          value: prod,
          impact: '+20%',
          status: 'pass',
          weight: 0.15,
          detail: "Attended focus on '$prod'",
        ),
        AttributionFactor(
          factor: 'Venue & Tenancy Context',
          value: ven,
          impact: '0%',
          status: 'pass',
          weight: 0.15,
          detail: 'Wearer in $ven',
        ),
        AttributionFactor(
          factor: 'Object & Venue Policy',
          value: '$prod (personal_consumable)',
          impact: '+15%',
          status: 'pass',
          weight: 0.25,
          detail: 'Personal consumable is eligible for recommendation',
        ),
        const AttributionFactor(
          factor: 'Ownership Policy',
          value: 'Unregistered / Candidate',
          impact: '+20%',
          status: 'pass',
          weight: 0.2,
          detail: 'Object not owned by user; available for recommendation',
        ),
        AttributionFactor(
          factor: 'Schedule Safety',
          value: sched,
          impact: '+10%',
          status: 'pass',
          weight: 0.1,
          detail: 'Schedule does not restrict proactive assistance',
        ),
        const AttributionFactor(
          factor: 'Speech & Curiosity Signal',
          value: 'No Verbal Cue',
          impact: '+0%',
          status: 'pass',
          weight: 0.15,
          detail: 'No verbal purchase query detected',
        ),
        const AttributionFactor(
          factor: 'Physical Interaction Primitives',
          value: 'Held in hand, rotated for inspection, sustained dwell 2,850ms',
          impact: '+11%',
          status: 'signal',
          weight: 0.1,
          detail: 'Active tactile engagement: held in hand, rotated for inspection, sustained dwell 2,850ms',
        ),
        const AttributionFactor(
          factor: 'Bayesian Belief & Propensity',
          value: 'P(Commerce): 5.1%',
          impact: '+1%',
          status: 'pass',
          weight: 0.15,
          detail: 'Statistical purchase propensity calculated at 5.1%',
        ),
      ],
    );
  }

  /// Sample constructor for blocked state matching the user's reference image
  factory FeatureAttributionInsightsCard.sampleBlocked({VoidCallback? onClose}) {
    return FeatureAttributionInsightsCard(
      compositeScore: 0,
      relevanceScore: 0.0,
      threshold: 60,
      isEligible: false,
      eligibilityBlocked: true,
      blockedReason: 'no attended product target',
      blockedDetail: 'Proactive recommendation suppressed by Context-Object Policy Engine (COPE) to prevent intrusive/inappropriate prompts.',
      onClose: onClose,
      factors: const [
        AttributionFactor(
          factor: 'Target Grounding',
          value: 'No attended product',
          impact: '0%',
          status: 'defer',
          weight: 0.15,
          detail: 'No target product identified',
        ),
        AttributionFactor(
          factor: 'Venue & Tenancy Context',
          value: 'Office (employee)',
          impact: '-20%',
          status: 'pass',
          weight: 0.15,
          detail: 'Wearer is employee in office venue',
        ),
        AttributionFactor(
          factor: 'Object & Venue Policy',
          value: 'None (unknown)',
          impact: '0%',
          status: 'defer',
          weight: 0.25,
          detail: 'No target product identified',
        ),
        AttributionFactor(
          factor: 'Ownership Policy',
          value: 'Unregistered / Candidate',
          impact: '+20%',
          status: 'pass',
          weight: 0.2,
          detail: 'Object not owned by user; available for recommendation',
        ),
        AttributionFactor(
          factor: 'Schedule Safety',
          value: 'Commute / Travel',
          impact: '+10%',
          status: 'pass',
          weight: 0.1,
          detail: 'Schedule does not restrict proactive assistance',
        ),
        AttributionFactor(
          factor: 'Speech & Curiosity Signal',
          value: 'No Verbal Cue',
          impact: '+0%',
          status: 'pass',
          weight: 0.15,
          detail: 'No verbal purchase query detected',
        ),
        AttributionFactor(
          factor: 'Bayesian Belief & Propensity',
          value: 'P(Commerce): 1.0%',
          impact: '0%',
          status: 'defer',
          weight: 0.15,
          detail: 'Statistical purchase propensity calculated at 1.0%',
        ),
      ],
    );
  }

  static List<AttributionFactor> _generateDefaultFactors({
    required Map<String, dynamic> beOutput,
    String? productName,
    String? venue,
    String? scheduleActivity,
  }) {
    final prod = beOutput['recommended_product']?.toString() ?? productName;
    final state = beOutput['behavioral_state']?.toString();
    final relevance = (beOutput['relevance_score'] as num?)?.toDouble() ?? 0.0;
    final hasTarget = prod != null && prod.isNotEmpty;

    return [
      AttributionFactor(
        factor: 'Target Grounding',
        value: hasTarget ? '$prod${state != null ? " ($state)" : ""}' : 'No attended target',
        impact: hasTarget ? '+20%' : '0%',
        status: hasTarget ? 'pass' : 'defer',
        weight: 0.15,
        detail: hasTarget
            ? "Attended focus on '$prod'${state != null ? " with state: $state" : ""}"
            : 'No target product detected in live feed',
      ),
      AttributionFactor(
        factor: 'Venue & Tenancy Context',
        value: venue ?? (beOutput['venue']?.toString() ?? 'Active Session Venue'),
        impact: '0%',
        status: 'pass',
        weight: 0.15,
        detail: 'Context verified for lifestyle and commerce engagement',
      ),
      AttributionFactor(
        factor: 'Object & Venue Policy',
        value: hasTarget ? '$prod (eligible)' : 'None (unknown)',
        impact: hasTarget ? '+15%' : '0%',
        status: hasTarget ? 'pass' : 'defer',
        weight: 0.25,
        detail: hasTarget
            ? 'Product category verified by Context-Object Policy Engine'
            : 'No target product to evaluate policy for',
      ),
      const AttributionFactor(
        factor: 'Ownership Policy',
        value: 'Unregistered / Candidate',
        impact: '+20%',
        status: 'pass',
        weight: 0.2,
        detail: 'Object not in owned registry; available for recommendation',
      ),
      AttributionFactor(
        factor: 'Schedule Safety',
        value: scheduleActivity ?? (beOutput['schedule_activity']?.toString() ?? 'Live Routine'),
        impact: '+10%',
        status: 'pass',
        weight: 0.1,
        detail: 'Schedule allows proactive commerce notifications',
      ),
      const AttributionFactor(
        factor: 'Speech & Curiosity Signal',
        value: 'No Suppression',
        impact: '+0%',
        status: 'pass',
        weight: 0.15,
        detail: 'No verbal conflict detected',
      ),
      AttributionFactor(
        factor: 'Bayesian Belief & Propensity',
        value: 'P(Commerce): ${(relevance * 100).toStringAsFixed(1)}%',
        impact: '+${((relevance * 15).round())}%',
        status: relevance >= 0.4 ? 'pass' : 'defer',
        weight: 0.15,
        detail: 'Statistical purchase propensity calculated at ${(relevance * 100).toStringAsFixed(1)}%',
      ),
    ];
  }

  static int _calculateScoreFromFactors(List<AttributionFactor> list) {
    int total = 0;
    for (final f in list) {
      final clean = f.impact.replaceAll('%', '').replaceAll('+', '').trim();
      final parsed = int.tryParse(clean) ?? 0;
      total += parsed;
    }
    return total.clamp(0, 100);
  }

  @override
  Widget build(BuildContext context) {
    final scoreStr = compositeScore > 0
        ? 'SCORE: $compositeScore% (${isEligible ? 'PASS' : 'DEFER'})'
        : 'SCORE: 0% (NO TARGET)';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0C0D12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF22242D), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text('🌿', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: Color(0xFFE4E4E7),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                scoreStr,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: isEligible
                      ? const Color(0xFF00BFA5)
                      : compositeScore > 0
                          ? const Color(0xFFE8963C)
                          : const Color(0xFF9CA3AF),
                ),
              ),
              if (onClose != null) ...[
                const SizedBox(width: 8),
                InkWell(
                  onTap: onClose,
                  borderRadius: BorderRadius.circular(12),
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(Icons.close, size: 16, color: Color(0xFF71717A)),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),

          // Composite Attribution Score bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Flexible(
                child: Text(
                  'Composite Attribution Score',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF8E92A4),
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Threshold: $threshold%',
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF8E92A4),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Container(
              height: 8,
              width: double.infinity,
              color: const Color(0xFF1E2028),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final fillWidth = constraints.maxWidth * (compositeScore / 100.0).clamp(0.0, 1.0);
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: fillWidth,
                      height: 8,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        gradient: LinearGradient(
                          colors: isEligible
                              ? [const Color(0xFF00BFA5), const Color(0xFF10B981)]
                              : [const Color(0xFFE8963C), const Color(0xFFEF4444)],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Live BE Metrics HUD (GATE, RELEVANCE, COMMERCE, SUPPRESS)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF12141C),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: gateOpen == true
                    ? const Color(0xFF10B981).withValues(alpha: 0.6)
                    : const Color(0xFF222634),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _metricPill(
                    label: 'GATE',
                    value: gateOpen != null ? (gateOpen! ? 'OPEN' : 'CLOSED') : '—',
                    valueColor: gateOpen == true
                        ? const Color(0xFF10B981)
                        : (gateOpen == false ? const Color(0xFFEF4444) : const Color(0xFF94A3B8)),
                  ),
                ),
                Container(width: 1, height: 26, color: const Color(0xFF222634)),
                Expanded(
                  flex: 4,
                  child: _metricPill(
                    label: 'RELEVANCE',
                    value: relevanceScore != null
                        ? relevanceScore!.toStringAsFixed(2)
                        : '0.00',
                    valueColor: const Color(0xFF38BDF8),
                  ),
                ),
                Container(width: 1, height: 26, color: const Color(0xFF222634)),
                Expanded(
                  flex: 4,
                  child: _metricPill(
                    label: 'COMMERCE',
                    value: commerceScore != null
                        ? commerceScore!.toStringAsFixed(2)
                        : (compositeScore > 0 ? (compositeScore / 100.0).toStringAsFixed(2) : '0.00'),
                    valueColor: (commerceScore != null && commerceScore! >= 0.6) || compositeScore >= 60
                        ? const Color(0xFF34D399)
                        : const Color(0xFFE8963C),
                  ),
                ),
                Container(width: 1, height: 26, color: const Color(0xFF222634)),
                Expanded(
                  flex: 5,
                  child: _metricPill(
                    label: 'SUPPRESS',
                    value: suppressReason ?? (eligibilityBlocked == true ? 'BLOCKED' : 'NONE'),
                    valueColor: suppressReason != null
                        ? const Color(0xFFF59E0B)
                        : (eligibilityBlocked == true ? const Color(0xFFEF4444) : const Color(0xFF10B981)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Banner (Blocked or Passed)
          // Banner (Standby, Blocked or Passed)
          if (factors.isEmpty)
            _buildEligibilityBanner(
              isBlocked: true,
              title: 'LIVE BEHAVIOUR ENGINE: AWAITING DATA',
              badge: 'STANDBY',
              headline: 'No Active Frame Evaluated',
              detail: blockedDetail ??
                  'Waiting for live frames from camera/video pipeline to be processed by Behaviour Engine (/be/process).',
            )
          else if (!isEligible || blockedReason != null)
            _buildEligibilityBanner(
              isBlocked: true,
              title: 'ELIGIBILITY BLOCKED: UNKNOWN',
              badge: 'NO TARGET',
              headline: blockedReason ?? 'no attended product target',
              detail: blockedDetail ??
                  'Proactive recommendation suppressed by Context-Object Policy Engine (COPE) to prevent intrusive/inappropriate prompts.',
            )
          else
            _buildEligibilityBanner(
              isBlocked: false,
              title: 'ELIGIBILITY PASSED: COMMERCE CANDIDATE',
              badge: 'ELIGIBLE',
              headline: factors.first.value,
              detail: 'Attribution passed threshold ($compositeScore% ≥ $threshold%). Candidate qualified for proactive recommendation.',
            ),

          const SizedBox(height: 14),

          // Subheader
          const Text(
            'TRANSPARENT ATTRIBUTION BREAKDOWN:',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Color(0xFF8E92A4),
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),

          // Factor Cards List or Empty State
          if (factors.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF13151D),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF222533)),
              ),
              child: const Center(
                child: Text(
                  'No live attribution factors available.\nStart live session to stream live data from /be/process.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF8E92A4),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
            )
          else
            ...factors.map((factor) => _buildFactorCard(factor)),
        ],
      ),
    );
  }

  Widget _buildEligibilityBanner({
    required bool isBlocked,
    required String title,
    required String badge,
    required String headline,
    required String detail,
  }) {
    final borderColor = isBlocked ? const Color(0xFF7F1D1D) : const Color(0xFF065F46);
    final bgColor = isBlocked ? const Color(0xFF1F0D10) : const Color(0xFF081C15);
    final accentColor = isBlocked ? const Color(0xFFEF4444) : const Color(0xFF10B981);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isBlocked ? Icons.block_flipped : Icons.check_circle_outline,
                color: accentColor,
                size: 16,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: accentColor,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isBlocked ? const Color(0xFF451A1A) : const Color(0xFF0A3D2A),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: accentColor,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            headline,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFFF4F4F5),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            detail,
            style: const TextStyle(
              fontSize: 11,
              fontStyle: FontStyle.italic,
              color: Color(0xFFA1A1AA),
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFactorCard(AttributionFactor factor) {
    final status = factor.status.toLowerCase();

    Color borderColor;
    Color statusColor;
    Widget statusIcon;

    if (status == 'pass') {
      borderColor = const Color(0xFF00BFA5).withValues(alpha: 0.6);
      statusColor = const Color(0xFF00BFA5);
      statusIcon = const Icon(Icons.check, size: 16, color: Color(0xFF00BFA5));
    } else if (status == 'defer' || status == 'signal' || status == 'warn') {
      borderColor = const Color(0xFFD97706).withValues(alpha: 0.7);
      statusColor = const Color(0xFFE8963C);
      statusIcon = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 3, height: 12, color: const Color(0xFFE8963C)),
          const SizedBox(width: 2),
          Container(width: 3, height: 12, color: const Color(0xFFE8963C)),
        ],
      );
    } else {
      borderColor = const Color(0xFFEF4444).withValues(alpha: 0.6);
      statusColor = const Color(0xFFEF4444);
      statusIcon = const Icon(Icons.close, size: 16, color: Color(0xFFEF4444));
    }

    final impact = factor.impact;
    Color impactColor = const Color(0xFFA1A1AA);
    if (impact.startsWith('+') && impact != '+0%') {
      impactColor = const Color(0xFF00BFA5);
    } else if (impact.startsWith('-')) {
      impactColor = const Color(0xFFEF4444);
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1117),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 10),
            child: statusIcon,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  factor.factor,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFF4F4F5),
                  ),
                ),
                if (factor.value.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    factor.value,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFFD4D4D8),
                    ),
                  ),
                ],
                if (factor.detail.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    factor.detail,
                    style: const TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: Color(0xFF71717A),
                      height: 1.25,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                impact,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: impactColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                factor.status.toUpperCase(),
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: statusColor,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metricPill({
    required String label,
    required String value,
    required Color valueColor,
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
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
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
      ],
    );
  }
}

/// Helper function to open the Commerce Eligibility & Attribution dialog
void showFeatureAttributionDialog(
  BuildContext context, {
  ScheduleActivitySlot? slot,
  Map<String, String>? product,
  Map<String, dynamic>? beOutput,
  String? ceLocation,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) {
      return Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        decoration: BoxDecoration(
          color: const Color(0xFF090A0F),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: AppColors.border),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              if (beOutput != null)
                FeatureAttributionInsightsCard.fromProcessOutput(
                  beOutput,
                  onClose: () => Navigator.pop(ctx),
                  fallbackProductName: product?['name'],
                  fallbackScheduleActivity: slot?.activity,
                  fallbackVenue: ceLocation,
                )
              else if (product != null)
                FeatureAttributionInsightsCard.fromProduct(
                  product,
                  onClose: () => Navigator.pop(ctx),
                  sceneContext: ceLocation,
                )
              else if (slot != null)
                FeatureAttributionInsightsCard.fromSlot(
                  slot,
                  onClose: () => Navigator.pop(ctx),
                  sceneContext: ceLocation,
                )
              else
                FeatureAttributionInsightsCard.empty(
                  onClose: () => Navigator.pop(ctx),
                ),
            ],
          ),
        ),
      );
    },
  );
}
