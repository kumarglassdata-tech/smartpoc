import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_logger.dart';
import '../../app_theme.dart';
import '../../auth/auth_provider.dart';
import '../../session/session_provider.dart';

/// Card allowing users to register and batch-remove owned products via
/// POST /api/v1/be/owned_objects/{user_id} and POST /api/v1/be/owned_objects/{user_id}/remove.
class OwnedObjectsCard extends StatefulWidget {
  final VoidCallback? onObjectsUpdated;
  final VoidCallback? onObjectsRemoved;

  const OwnedObjectsCard({
    super.key,
    this.onObjectsUpdated,
    this.onObjectsRemoved,
  });

  @override
  State<OwnedObjectsCard> createState() => _OwnedObjectsCardState();
}

class _OwnedObjectsCardState extends State<OwnedObjectsCard> {
  final List<String> _productList = [];

  final Set<String> _selectedProducts = {};
  final TextEditingController _customProductController = TextEditingController();
  bool _isPosting = false;
  bool _isRemoving = false;
  bool _hasFetchedFromBe = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchFromBE());
  }

  @override
  void dispose() {
    _customProductController.dispose();
    super.dispose();
  }

  Future<void> _fetchFromBE({bool force = false}) async {
    if ((_hasFetchedFromBe && !force) || !mounted) return;
    try {
      final auth = context.read<AuthProvider>();
      final session = context.read<SessionProvider>();
      final uid = auth.userId ?? session.userId ?? 'default_user';

      final remoteObjects = await session.behaviourEngineClient.getOwnedObjects(userId: uid);
      if (!mounted) return;

      setState(() {
        final serverList = <String>[];
        for (final item in remoteObjects) {
          final name = item['object']?.toString() ?? item['product_name']?.toString();
          if (name != null && name.isNotEmpty) {
            serverList.add(name);
          }
        }
        _productList.clear();
        _productList.addAll(serverList);
        _hasFetchedFromBe = true;
      });
    } catch (_) {}
  }

  Future<void> _addCustomProduct() async {
    final text = _customProductController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      if (!_productList.contains(text)) {
        _productList.add(text);
      }
      _selectedProducts.add(text);
      _customProductController.clear();
    });

    // Automatically POST new product to Behaviour Engine
    await _postSelectedObjects(customList: [text], showNotification: true);
  }

  Future<void> _postSelectedObjects({List<String>? customList, bool showNotification = true}) async {
    final toPost = customList ?? _selectedProducts.toList();
    if (toPost.isEmpty || _isPosting) return;

    setState(() => _isPosting = true);

    try {
      final auth = context.read<AuthProvider>();
      final session = context.read<SessionProvider>();
      final uid = auth.userId ?? session.userId ?? 'default_user';

      AppLogger.log('OWNED_OBJECTS_UI', 'Posting/Registering ${toPost.length} objects for user $uid -> POST /api/v1/be/owned_objects/$uid');

      await session.behaviourEngineClient.addOwnedObjects(
        userId: uid,
        products: toPost,
      );

      if (!mounted) return;

      setState(() {
        _isPosting = false;
      });

      if (showNotification) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: AppColors.success, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Registered ${toPost.length} item${toPost.length == 1 ? '' : 's'} to Behaviour Engine DB (${toPost.join(', ')})',
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.surfaceMuted,
            duration: const Duration(seconds: 4),
          ),
        );
      }

      await _fetchFromBE(force: true);
      widget.onObjectsUpdated?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isPosting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to register owned objects: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _removeSelectedObjects() async {
    if (_selectedProducts.isEmpty || _isRemoving) return;

    final toRemove = _selectedProducts.toList();
    setState(() => _isRemoving = true);

    try {
      final auth = context.read<AuthProvider>();
      final session = context.read<SessionProvider>();
      final uid = auth.userId ?? session.userId ?? 'default_user';

      AppLogger.log('OWNED_OBJECTS_UI', 'Deleting ${toRemove.length} objects for user $uid -> DELETE /api/v1/be/owned_objects/$uid');

      await session.behaviourEngineClient.deleteOwnedObjects(
        userId: uid,
        products: toRemove,
      );

      if (!mounted) return;

      setState(() {
        _productList.removeWhere((item) => toRemove.contains(item));
        _selectedProducts.clear();
        _isRemoving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.delete_outline, color: AppColors.accent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Deleted ${toRemove.length} owned item${toRemove.length == 1 ? '' : 's'} from Behaviour Engine DB (${toRemove.join(', ')})',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.surfaceMuted,
          duration: const Duration(seconds: 4),
        ),
      );

      await _fetchFromBE(force: true);
      widget.onObjectsRemoved?.call();
      widget.onObjectsUpdated?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isRemoving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete owned objects: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.accentTint,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.inventory_2_outlined, color: AppColors.accent, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Owned Objects & Products',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      'POST to register or batch remove items in Behaviour Engine',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Chips of owned products
          if (_productList.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No owned products in list. Add products below.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _productList.map((product) {
                final isSelected = _selectedProducts.contains(product);
                return FilterChip(
                  label: Text(
                    product,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? Colors.white : AppColors.textPrimary,
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: AppColors.accent,
                  backgroundColor: AppColors.surfaceMuted,
                  checkmarkColor: Colors.white,
                  side: BorderSide(
                    color: isSelected ? AppColors.accentStrong : AppColors.border,
                    width: 1.2,
                  ),
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedProducts.add(product);
                      } else {
                        _selectedProducts.remove(product);
                      }
                    });
                  },
                );
              }).toList(),
            ),

          const SizedBox(height: 12),

          // Custom product input field
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: TextField(
                    controller: _customProductController,
                    onSubmitted: (_) => _addCustomProduct(),
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Enter product name to POST...',
                      hintStyle: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      filled: true,
                      fillColor: AppColors.surfaceMuted,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: AppColors.accent),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: _isPosting ? null : _addCustomProduct,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accentTint,
                  foregroundColor: AppColors.accentStrong,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                icon: _isPosting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_circle_outline, size: 16),
                label: const Text('Add & POST', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Action Buttons: POST Register and POST Batch Remove
          Row(
            children: [
              // Register (POST) Button
              Expanded(
                child: FilledButton.icon(
                  onPressed: _selectedProducts.isEmpty || _isPosting || _isRemoving ? null : () => _postSelectedObjects(),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.success,
                    disabledBackgroundColor: AppColors.surfaceMuted,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: _isPosting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.cloud_upload_outlined, size: 18),
                  label: Text(
                    _isPosting
                        ? 'Posting...'
                        : _selectedProducts.isEmpty
                            ? 'POST Register'
                            : 'POST (${_selectedProducts.length})',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                      color: _selectedProducts.isEmpty ? AppColors.textSecondary : Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Remove (POST /remove) Button
              Expanded(
                child: FilledButton.icon(
                  onPressed: _selectedProducts.isEmpty || _isPosting || _isRemoving ? null : _removeSelectedObjects,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.danger,
                    disabledBackgroundColor: AppColors.surfaceMuted,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: _isRemoving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.delete_sweep_outlined, size: 18),
                  label: Text(
                    _isRemoving
                        ? 'Removing...'
                        : _selectedProducts.isEmpty
                            ? 'Remove'
                            : 'Remove (${_selectedProducts.length})',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                      color: _selectedProducts.isEmpty ? AppColors.textSecondary : Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
