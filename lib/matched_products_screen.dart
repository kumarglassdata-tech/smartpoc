import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_theme.dart';
import 'product_detail_screen.dart';

class MatchedProductsScreen extends StatelessWidget {
  final List<Map<String, String>> items;
  final String? vlmDescription;

  const MatchedProductsScreen({super.key, required this.items, this.vlmDescription});

  Future<void> _openStore(BuildContext context, String? url) async {
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final description = vlmDescription;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Matched Products & Recommendations', style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: AppColors.surface,
        elevation: 0,
      ),
      body: items.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shopping_bag_outlined, size: 48, color: AppColors.textSecondary),
                  const SizedBox(height: 12),
                  Text('No matched products yet', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: AppColors.textPrimary)),
                  const SizedBox(height: 4),
                  Text('Look at commercial items during live session to discover links.', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              itemCount: items.length + (description != null && description.isNotEmpty ? 1 : 0),
              itemBuilder: (context, index) {
                if (description != null && description.isNotEmpty && index == 0) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.remove_red_eye_outlined, size: 16, color: AppColors.accentStrong),
                            const SizedBox(width: 6),
                            Text('SESSION VISUAL CONTEXT', style: TextStyle(color: AppColors.accentStrong, fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 0.5)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(description, style: TextStyle(color: AppColors.textPrimary, fontSize: 14, height: 1.4)),
                      ],
                    ),
                  );
                }

                final itemIndex = (description != null && description.isNotEmpty) ? index - 1 : index;
                final item = items[itemIndex];
                final rankNum = itemIndex + 1;
                final name = item['name'] ?? 'Product';
                final price = item['price'];
                final platform = item['platform'] ?? 'Amazon';
                final rating = item['rating'];
                final delivery = item['delivery'];
                final offer = item['offer'];
                final matchScore = item['match_score'] ?? item['trigger_score'] ?? '95%';
                final triggerObj = item['trigger_object'] ?? name;
                final triggerScore = item['trigger_score'] ?? matchScore;
                final behavioralState = item['behavioral_state'] ?? 'Engaged';
                final triggerReason = item['trigger_reason'] ?? 'Visual gaze fixation on $triggerObj ($triggerScore relevance)';
                final capturedTime = item['captured_time'];
                final imageUrl = item['image'];
                final storeUrl = item['url'];

                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: rankNum == 1 ? AppColors.accent.withValues(alpha: 0.4) : AppColors.border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(18),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProductDetailScreen(item: item))),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── Header: Rank Badge + Match Score + Merchant Platform ──
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: rankNum == 1 ? AppColors.accent : AppColors.surfaceMuted,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '#$rankNum ${rankNum == 1 ? "Top Match" : "Alternative"}',
                                    style: TextStyle(
                                      color: rankNum == 1 ? Colors.white : AppColors.textPrimary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppColors.successTint,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '$matchScore Match',
                                    style: TextStyle(
                                      color: AppColors.success,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceMuted,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: AppColors.border),
                                  ),
                                  child: Text(
                                    platform,
                                    style: TextStyle(
                                      color: AppColors.accentStrong,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // ── Product Details Row: Image + Title + Price + Delivery ──
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    width: 80,
                                    height: 80,
                                    color: AppColors.accentTint,
                                    child: (imageUrl != null && imageUrl.isNotEmpty && !imageUrl.contains('via.placeholder.com'))
                                        ? Image.network(
                                            imageUrl,
                                            width: 80,
                                            height: 80,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, _, _) => Center(child: Icon(Icons.shopping_bag_outlined, color: AppColors.accent, size: 32)),
                                          )
                                        : Center(child: Icon(Icons.shopping_bag_outlined, color: AppColors.accent, size: 32)),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, height: 1.25),
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          if (price != null)
                                            Text(
                                              price,
                                              style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800, fontSize: 16),
                                            ),
                                          if (offer != null) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: AppColors.accentTint,
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                offer,
                                                style: TextStyle(color: AppColors.accentStrong, fontSize: 10, fontWeight: FontWeight.w600),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          if (rating != null) ...[
                                            Icon(Icons.star_rounded, size: 15, color: Colors.amber[700]),
                                            const SizedBox(width: 3),
                                            Text(rating, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                                            const SizedBox(width: 10),
                                          ],
                                          if (delivery != null)
                                            Expanded(
                                              child: Text(
                                                delivery,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w500),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),

                            // ── FROZEN CONTEXT SNAPSHOT ("Why Myna Recommended This At That Moment") ──
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.background,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.auto_awesome, size: 14, color: AppColors.accent),
                                      const SizedBox(width: 6),
                                      Text(
                                        'WHY MYNA RECOMMENDED THIS',
                                        style: TextStyle(color: AppColors.accentStrong, fontWeight: FontWeight.w800, fontSize: 10, letterSpacing: 0.4),
                                      ),
                                      if (capturedTime != null) ...[
                                        const Spacer(),
                                        Text(capturedTime, style: TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w500)),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    triggerReason,
                                    style: TextStyle(color: AppColors.textPrimary, fontSize: 12, height: 1.35),
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: [
                                      _MetricPill(icon: Icons.center_focus_strong, label: 'Target: $triggerObj'),
                                      _MetricPill(icon: Icons.analytics_outlined, label: 'Confidence: $triggerScore'),
                                      _MetricPill(icon: Icons.psychology_outlined, label: 'State: $behavioralState'),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),

                            // ── Direct Store Action ──
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProductDetailScreen(item: item))),
                                    icon: const Icon(Icons.info_outline, size: 16),
                                    label: const Text('Attribution Details', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  ),
                                ),
                                if (storeUrl != null && storeUrl.isNotEmpty) ...[
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: () => _openStore(context, storeUrl),
                                      icon: const Icon(Icons.shopping_cart_outlined, size: 16),
                                      label: Text('Buy on $platform', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: AppColors.accent,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 8),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetricPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
