import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_theme.dart';
import 'auth/auth_provider.dart';
import 'particle_background.dart';
import 'product_detail_screen.dart';
import 'saved_items_service.dart';

class InterestedScreen extends StatefulWidget {
  const InterestedScreen({super.key});

  @override
  State<InterestedScreen> createState() => _InterestedScreenState();
}

class _InterestedScreenState extends State<InterestedScreen> {
  late Future<List<Map<String, String>>> _itemsFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final auth = context.read<AuthProvider>();
    _itemsFuture = auth.resolveUserId().then((uid) {
      final service = SavedItemsService(userId: uid ?? 0);
      return service.load();
    });
  }

  Future<void> _openItem(Map<String, String> item) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ProductDetailScreen(item: item)));
    if (mounted) setState(_load);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Interested')),
      body: ParticleBackground(
        child: RefreshIndicator(
          onRefresh: () async {
            setState(_load);
            await _itemsFuture;
          },
          child: FutureBuilder<List<Map<String, String>>>(
            future: _itemsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final items = snapshot.data ?? const [];
              if (items.isEmpty) {
                return ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    const SizedBox(height: 60),
                    Text(
                      "Nothing saved yet. Open a matched product during a session and tap Save to Interested.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                );
              }
              return GridView.builder(
                padding: const EdgeInsets.all(20),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.82,
                ),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _openItem(item),
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
                                      errorBuilder: (context, error, stackTrace) => Container(color: AppColors.accentTint),
                                    )
                                  : Container(width: double.infinity, color: AppColors.accentTint),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            item['name'] ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          if (item['price'] != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              item['price']!,
                              style: TextStyle(
                                color: AppColors.accent,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
