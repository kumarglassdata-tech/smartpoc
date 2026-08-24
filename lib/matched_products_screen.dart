import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'product_detail_screen.dart';

class MatchedProductsScreen extends StatelessWidget {
  final List<Map<String, String>> items;
  final String? vlmDescription;

  const MatchedProductsScreen({super.key, required this.items, this.vlmDescription});

  @override
  Widget build(BuildContext context) {
    final description = vlmDescription;
    return Scaffold(
      appBar: AppBar(title: const Text('Matched Products')),
      body: CustomScrollView(
        slivers: [
          if (description != null && description.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Container(
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
                      Text('WHAT MYNA SAW', style: TextStyle(color: AppColors.accentStrong, fontWeight: FontWeight.w700, fontSize: 11)),
                      const SizedBox(height: 6),
                      Text(description, style: TextStyle(color: AppColors.textPrimary, height: 1.35)),
                    ],
                  ),
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.82,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final item = items[index];
                  return InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProductDetailScreen(item: item))),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: item['image'] != null
                                  ? Image.network(
                                      item['image']!,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => Container(color: AppColors.accentTint),
                                    )
                                  : Container(width: double.infinity, color: AppColors.accentTint),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(item['name'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                          if (item['price'] != null) ...[
                            const SizedBox(height: 2),
                            Text(item['price']!, style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700)),
                          ],
                        ],
                      ),
                    ),
                  );
                },
                childCount: items.length,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
