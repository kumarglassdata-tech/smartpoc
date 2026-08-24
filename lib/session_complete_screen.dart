import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'product_detail_screen.dart';
import 'session/session_provider.dart';

class SessionCompleteScreen extends StatelessWidget {
  final SessionSummary summary;

  const SessionCompleteScreen({super.key, required this.summary});

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('SESSION COMPLETE', style: TextStyle(color: AppColors.accentStrong, fontWeight: FontWeight.w700, fontSize: 12)),
              const SizedBox(height: 4),
              Text("Here's what SmartPoc saw", style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 20),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: _statCard('Duration', _formatDuration(summary.duration))),
                          const SizedBox(width: 10),
                          Expanded(child: _statCard('Objects seen', '${summary.objectsSeen}')),
                          const SizedBox(width: 10),
                          Expanded(child: _statCard('Matches', '${summary.matches}')),
                        ],
                      ),
                      if (summary.vlmDescription != null) ...[
                        const SizedBox(height: 16),
                        _sectionCard(
                          title: 'What Myna saw',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(summary.vlmDescription!, style: TextStyle(color: AppColors.textPrimary, height: 1.35)),
                              if (summary.location != null) ...[
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Icon(Icons.location_on_outlined, size: 14, color: AppColors.textSecondary),
                                    const SizedBox(width: 4),
                                    Text(summary.location!, style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                      if (summary.lifestyleScore != null || summary.lifestyleBreakdown.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _sectionCard(
                          title: 'Lifestyle balance',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (summary.lifestyleScore != null) ...[
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    Text('${summary.lifestyleScore}', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.accentStrong)),
                                    const SizedBox(width: 4),
                                    Text('/ 100', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                                  ],
                                ),
                                const SizedBox(height: 10),
                              ],
                              ...summary.lifestyleBreakdown.entries.map(
                                (entry) => Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Row(
                                    children: [
                                      Expanded(child: Text(entry.key, style: TextStyle(color: AppColors.textPrimary, fontSize: 13))),
                                      Text(entry.value, style: TextStyle(color: AppColors.accentStrong, fontWeight: FontWeight.w700, fontSize: 13)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (summary.matchedProducts.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const Text('Matched products', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 130,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: summary.matchedProducts.length,
                            separatorBuilder: (_, _) => const SizedBox(width: 10),
                            itemBuilder: (context, index) {
                              final item = summary.matchedProducts[index];
                              return GestureDetector(
                                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProductDetailScreen(item: item))),
                                child: Container(
                                  width: 130,
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: AppColors.surface,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: AppColors.border),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(10),
                                          child: item['image'] != null
                                              ? Image.network(
                                                  item['image']!,
                                                  width: double.infinity,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (context, error, stackTrace) => Container(color: AppColors.accentTint),
                                                )
                                              : Container(width: double.infinity, color: AppColors.accentTint),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(item['name'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                                      if (item['price'] != null)
                                        Text(item['price']!, style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700, fontSize: 12)),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      const Text('Detected this session', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      const SizedBox(height: 10),
                      summary.detectedItems.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Text('Nothing detected this session.', style: TextStyle(color: AppColors.textSecondary)),
                            )
                          : Column(
                              children: summary.detectedItems.map((item) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                    decoration: BoxDecoration(
                                      color: AppColors.surface,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: AppColors.border),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(child: Text(item.className, style: const TextStyle(fontWeight: FontWeight.w600))),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: item.matched ? AppColors.successTint : AppColors.surfaceMuted,
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            item.matched ? 'Match' : 'No match',
                                            style: TextStyle(
                                              color: item.matched ? AppColors.success : AppColors.textSecondary,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.accentStrong, fontSize: 13)),
          const SizedBox(height: 8),
          child,
        ],
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
          Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        ],
      ),
    );
  }
}
