import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'auth/db_service.dart';

// "Interested" list - the mockup's Save to Interested is itself client-side
// only (no backend wishlist endpoint exists), so this writes through to the
// shared saved_items table (see DbService) for real cross-device persistence,
// with the previous SharedPreferences-only store kept as a local cache/
// fallback for web (no raw Postgres socket there) and offline use.
class SavedItemsService {
  final DbService _dbService;
  final int userId;

  SavedItemsService({required this.userId, DbService? dbService}) : _dbService = dbService ?? DbService();

  String get _key => userId != 0 ? 'saved_items_${userId}_v1' : 'saved_items_v1';

  Future<List<Map<String, String>>> load() async {
    if (userId != 0) {
      final dbItems = await _dbService.getSavedItems(userId);
      if (dbItems.isNotEmpty) {
        unawaited(_persist(dbItems));
        return dbItems;
      }
    }
    return _loadLocal();
  }

  Future<List<Map<String, String>>> _loadLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key) ?? prefs.getString('saved_items_v1');
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded.map((e) => Map<String, String>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<bool> isSaved(String name) async {
    final items = await load();
    return items.any((item) => item['name'] == name);
  }

  Future<void> save(Map<String, String> item) async {
    final items = await _loadLocal();
    if (items.any((existing) => existing['name'] == item['name'])) return;
    items.add(item);
    await _persist(items);
    if (userId != 0) {
      await _dbService.saveItem(userId, item);
    }
  }

  Future<void> remove(String name) async {
    final items = await _loadLocal();
    items.removeWhere((item) => item['name'] == name);
    await _persist(items);
    if (userId != 0) {
      await _dbService.removeSavedItem(userId, name);
    }
  }

  Future<void> _persist(List<Map<String, String>> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(items));
  }
}
