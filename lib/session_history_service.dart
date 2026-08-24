import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

// Local, SharedPreferences-backed session history - works identically on web
// and native (unlike DbService, which needs a raw Postgres socket that
// browsers can't open). ActivityScreen falls back to this whenever the real
// `sessions` table comes back empty, so session history is visible on web too.
class SessionHistoryService {
  static const _key = 'session_history';
  static const _maxEntries = 50;

  Future<void> recordSessionStarted(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    final entries = _load(prefs);
    entries.add({
      'session_id': sessionId,
      'start_time': DateTime.now().toIso8601String(),
      'end_time': null,
      'duration_sec': null,
      'status': 'active',
    });
    while (entries.length > _maxEntries) {
      entries.removeAt(0);
    }
    await prefs.setString(_key, jsonEncode(entries));
  }

  Future<void> recordSessionEnded(String sessionId, int durationSec) async {
    final prefs = await SharedPreferences.getInstance();
    final entries = _load(prefs);
    final index = entries.lastIndexWhere((e) => e['session_id'] == sessionId);
    final now = DateTime.now().toIso8601String();
    if (index != -1) {
      entries[index]['end_time'] = now;
      entries[index]['duration_sec'] = durationSec;
      entries[index]['status'] = 'completed';
    } else {
      entries.add({
        'session_id': sessionId,
        'start_time': now,
        'end_time': now,
        'duration_sec': durationSec,
        'status': 'completed',
      });
    }
    await prefs.setString(_key, jsonEncode(entries));
  }

  Future<List<Map<String, dynamic>>> getRecentSessions({int limit = 20}) async {
    final prefs = await SharedPreferences.getInstance();
    final entries = _load(prefs);
    entries.sort((a, b) => (b['start_time'] as String).compareTo(a['start_time'] as String));
    return entries.take(limit).map((e) {
      return {
        'session_id': e['session_id'],
        'start_time': DateTime.tryParse(e['start_time'] as String? ?? ''),
        'end_time': e['end_time'] != null ? DateTime.tryParse(e['end_time'] as String) : null,
        'duration_sec': e['duration_sec'],
        'status': e['status'],
      };
    }).toList();
  }

  List<Map<String, dynamic>> _load(SharedPreferences prefs) {
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }
}
