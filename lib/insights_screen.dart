import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_theme.dart';
import 'particle_background.dart';
import 'session/session_provider.dart';
import 'stats_service.dart';

// Mirrors the mockup's "Your Insights" screen. Every number is a real,
// locally-tracked running total (see stats_service.dart) - "Time saved" from
// the mockup has no honest way to compute from anything this app measures,
// so it's replaced with "Matches found" (real) rather than faked.
class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  late Future<StatsSnapshot> _statsFuture;

  @override
  void initState() {
    super.initState();
    _statsFuture = context.read<SessionProvider>().statsService.load();
  }

  static const _dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your Insights')),
      body: ParticleBackground(
        child: FutureBuilder<StatsSnapshot>(
          future: _statsFuture,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final stats = snapshot.data!;
            final maxDay = stats.last7DaysSessionCounts.fold(
              0,
              (max, v) => v > max ? v : max,
            );

            final categoryEntries = stats.categoryTotals.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value));
            final categoryTotal = stats.categoryTotals.values.fold(
              0.0,
              (sum, v) => sum + v,
            );
            final topCategory = categoryEntries.isNotEmpty
                ? categoryEntries.first
                : null;
            final topCategoryPct = (topCategory != null && categoryTotal > 0)
                ? (topCategory.value / categoryTotal * 100).round()
                : null;

            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _statCard('Sessions', '${stats.totalSessions}'),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _statCard(
                        'Items viewed',
                        '${stats.totalObjectsSeen}',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _statCard(
                        'Matches found',
                        '${stats.totalMatches}',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'This week',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 80,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: List.generate(7, (i) {
                            final count = stats.last7DaysSessionCounts[i];
                            final heightFraction = maxDay == 0
                                ? 0.0
                                : count / maxDay;
                            return Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Container(
                                      height: 6 + 58 * heightFraction,
                                      decoration: BoxDecoration(
                                        color: count > 0
                                            ? AppColors.accent
                                            : AppColors.border,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: _dayLabels
                            .map(
                              (label) => Expanded(
                                child: Center(
                                  child: Text(
                                    label,
                                    style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Top category',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        topCategory != null
                            ? '${topCategory.key} made up $topCategoryPct% of what you viewed this week'
                            : 'No behaviour data yet - it fills in as you run live sessions.',
                        style: TextStyle(
                          color: AppColors.accentStrong,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (stats.totalSessions == 0) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Start a session to begin building your insights.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _statCard(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
          ),
        ],
      ),
    );
  }
}
