import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_theme.dart';
import 'auth/auth_provider.dart';
import 'features/schedule/widgets/feature_attribution_insights_card.dart';
import 'saved_items_service.dart';
import 'session/session_provider.dart';

class ProductDetailScreen extends StatefulWidget {
  final Map<String, String> item;

  const ProductDetailScreen({super.key, required this.item});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  bool _isSaved = false;
  bool _isBusy = false;

  Future<SavedItemsService> _getService() async {
    final auth = context.read<AuthProvider>();
    final uid = await auth.resolveUserId();
    return SavedItemsService(userId: uid ?? 0);
  }

  @override
  void initState() {
    super.initState();
    _getService().then((service) => service.isSaved(widget.item['name'] ?? '')).then((saved) {
      if (mounted) setState(() => _isSaved = saved);
    });
  }

  Future<void> _toggleSave() async {
    setState(() => _isBusy = true);
    final service = await _getService();
    if (_isSaved) {
      await service.remove(widget.item['name'] ?? '');
    } else {
      await service.save(widget.item);
    }
    if (!mounted) return;
    setState(() {
      _isSaved = !_isSaved;
      _isBusy = false;
    });
  }

  Future<void> _openInStore() async {
    final url = widget.item['url'];
    if (url == null) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final hasUrl = item['url'] != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Product Details')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 10,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: item['image'] != null
                    ? Image.network(
                        item['image']!,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(color: AppColors.accentTint),
                      )
                    : Container(color: AppColors.accentTint),
              ),
            ),
            const SizedBox(height: 18),
            Text(item['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 20)),
            if (item['price'] != null) ...[
              const SizedBox(height: 4),
              Text(item['price']!, style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700, fontSize: 16)),
            ],
            if (item['description'] != null) ...[
              const SizedBox(height: 16),
              Container(
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
                    Text('SPOTTED BY MYNA', style: TextStyle(color: AppColors.accentStrong, fontWeight: FontWeight.w700, fontSize: 11)),
                    const SizedBox(height: 6),
                    Text(item['description']!, style: TextStyle(color: AppColors.textPrimary)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            // Why Myna Recommended This (Frozen Commerce Eligibility & Attribution Breakdown)
            Consumer<SessionProvider>(
              builder: (context, session, _) {
                Map<String, dynamic>? frozenBeOutput;
                final jsonStr = item['be_output_json'];
                if (jsonStr != null && jsonStr.isNotEmpty) {
                  try {
                    frozenBeOutput = jsonDecode(jsonStr) as Map<String, dynamic>?;
                  } catch (_) {}
                }
                final beOutput = frozenBeOutput ?? session.lastPipelineResult?.behaviourEngineRaw;
                return FeatureAttributionInsightsCard.fromProduct(
                  item,
                  beOutput: beOutput,
                  sceneContext: item['vlm_description'] ?? session.lastSessionSummary?.vlmDescription,
                );
              },
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: _isBusy ? null : _toggleSave,
              child: Text(_isSaved ? 'Saved to Interested' : 'Save to Interested'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: hasUrl ? _openInStore : null,
              child: Text(hasUrl ? 'Open in Store' : 'No store link available'),
            ),
          ],
        ),
      ),
    );
  }
}
