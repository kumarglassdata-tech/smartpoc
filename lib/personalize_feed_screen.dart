import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_theme.dart';
import 'auth/auth_provider.dart';
import 'auth/db_service.dart';

// One-time onboarding form shown right after signup (gated by
// AuthProvider.hasPreferences via the router's redirect) - categories +
// shopping-habit ratings submit together in a single savePreferences() call,
// matching smartglass_flutter's user_preferences workflow against the same
// shared DB. Native only for the DB write; web still walks through the form
// so the UX is identical, it just can't persist to Postgres.
class PersonalizeFeedScreen extends StatefulWidget {
  const PersonalizeFeedScreen({super.key});

  @override
  State<PersonalizeFeedScreen> createState() => _PersonalizeFeedScreenState();
}

class _PersonalizeFeedScreenState extends State<PersonalizeFeedScreen> {
  static const _categories = ['Fashion', 'Mobiles', 'Beauty', 'Electronics', 'Home', 'Grocery', 'Sports'];
  static const _categoryIcons = {
    'Fashion': Icons.checkroom,
    'Mobiles': Icons.smartphone,
    'Beauty': Icons.face_retouching_natural,
    'Electronics': Icons.laptop_mac,
    'Home': Icons.home_outlined,
    'Grocery': Icons.local_grocery_store_outlined,
    'Sports': Icons.sports_soccer,
  };

  final Set<String> _selectedCategories = {};
  int _brandRating = 3;
  int _costRating = 3;
  int _speedRating = 3;
  int _reviewsRating = 3;
  int _impulseRating = 3;
  int _routineRating = 3;
  bool _isBusy = false;

  Future<void> _submit({required bool skip}) async {
    setState(() => _isBusy = true);
    final auth = context.read<AuthProvider>();
    final userId = auth.userId;
    try {
      if (!kIsWeb && userId != null) {
        await DbService().savePreferences(
          userId: userId,
          categories: skip ? '' : _selectedCategories.join(','),
          brandRating: skip ? 0 : _brandRating,
          costRating: skip ? 0 : _costRating,
          speedRating: skip ? 0 : _speedRating,
          reviewsRating: skip ? 0 : _reviewsRating,
          impulseRating: skip ? 0 : _impulseRating,
          routineRating: skip ? 0 : _routineRating,
          status: skip ? 'skipped' : 'success',
        );
      }
      await auth.setHasPreferences(true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save preferences: $error')));
      }
    }
    if (mounted) setState(() => _isBusy = false);
  }

  Widget _ratingRow(String title, String description, int value, ValueChanged<int> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(
            text: TextSpan(
              style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
              children: [
                TextSpan(text: '$title  ', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.accentStrong)),
                TextSpan(text: description),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text('Disagree', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(5, (i) {
                    final score = i + 1;
                    final selected = value == score;
                    return GestureDetector(
                      onTap: () => onChanged(score),
                      child: Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selected ? AppColors.accent : AppColors.surfaceMuted,
                          border: Border.all(color: selected ? AppColors.accent : AppColors.border),
                        ),
                        child: Text(
                          '$score',
                          style: TextStyle(color: selected ? Colors.white : AppColors.textSecondary, fontWeight: FontWeight.w700, fontSize: 12),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              Text('Agree', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Personalize Your Feed')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tell us what you love to shop for', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text('Select multiple - you can change this later.', style: TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 20),
              SizedBox(
                height: 88,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _categories.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final category = _categories[index];
                    final selected = _selectedCategories.contains(category);
                    return GestureDetector(
                      onTap: () => setState(() => selected ? _selectedCategories.remove(category) : _selectedCategories.add(category)),
                      child: Column(
                        children: [
                          Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              color: selected ? AppColors.accentTint : AppColors.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: selected ? AppColors.accent : AppColors.border, width: selected ? 2 : 1),
                            ),
                            child: Icon(_categoryIcons[category], color: selected ? AppColors.accentStrong : AppColors.textSecondary),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            category,
                            style: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.w700 : FontWeight.w400, color: selected ? AppColors.accentStrong : AppColors.textSecondary),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Divider(color: AppColors.border),
              const SizedBox(height: 12),
              Text('Rate your shopping habits', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              _ratingRow('1. Brand', 'I prefer buying from well-known, premium brands.', _brandRating, (v) => setState(() => _brandRating = v)),
              _ratingRow('2. Cost', 'Finding the lowest price is my top priority.', _costRating, (v) => setState(() => _costRating = v)),
              _ratingRow('3. Speed', 'I prefer items available for immediate delivery.', _speedRating, (v) => setState(() => _speedRating = v)),
              _ratingRow('4. Reviews', 'I rely on high ratings and reviews before buying.', _reviewsRating, (v) => setState(() => _reviewsRating = v)),
              _ratingRow('5. Impulse', 'I make quick, impulsive decisions when I like something.', _impulseRating, (v) => setState(() => _impulseRating = v)),
              _ratingRow('6. Routine', 'I tend to buy the same types of products repeatedly.', _routineRating, (v) => setState(() => _routineRating = v)),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _isBusy ? null : () => _submit(skip: false),
                child: _isBusy
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Start Shopping'),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: _isBusy ? null : () => _submit(skip: true),
                child: const Text('Skip for now'),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
