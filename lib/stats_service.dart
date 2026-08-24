import 'package:shared_preferences/shared_preferences.dart';

import 'auth/db_service.dart';

// Lifetime usage counters for the Insights screen. Writes through to the
// shared daily_stats/category_stats tables (see DbService) for exact,
// cross-device totals, with SharedPreferences kept as the on-device fallback
// (web has no raw Postgres socket; also used if the DB is briefly
// unreachable). Every number here is a real running total - nothing here is
// a fabricated/demo value.
class StatsService {
  static const _totalSessionsKey = 'stats_total_sessions';
  static const _totalObjectsSeenKey = 'stats_total_objects_seen';
  static const _totalMatchesKey = 'stats_total_matches';
  static const _dailySessionsPrefix = 'stats_daily_sessions_';
  static const _categoryPrefix = 'stats_category_';

  final DbService _dbService;
  final int userId;

  StatsService({required this.userId, DbService? dbService}) : _dbService = dbService ?? DbService();

  Future<void> recordSessionStarted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_totalSessionsKey, (prefs.getInt(_totalSessionsKey) ?? 0) + 1);
    final todayKey = _dailySessionsPrefix + _dateKey(DateTime.now());
    await prefs.setInt(todayKey, (prefs.getInt(todayKey) ?? 0) + 1);
    await _dbService.recordDailyStats(userId, sessions: 1);
  }

  Future<void> recordDetections({required int objectsSeen, required int matches}) async {
    if (objectsSeen == 0 && matches == 0) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_totalObjectsSeenKey, (prefs.getInt(_totalObjectsSeenKey) ?? 0) + objectsSeen);
    await prefs.setInt(_totalMatchesKey, (prefs.getInt(_totalMatchesKey) ?? 0) + matches);
    await _dbService.recordDailyStats(userId, objectsSeen: objectsSeen, matches: matches);
  }

  // Accumulates the behaviour engine's own top_salient_objects (class_name +
  // salience_score) over time, so the lifestyle-breakdown card reflects real
  // BE output instead of invented categories.
  Future<void> recordSalientObjects(List<MapEntry<String, double>> objects) async {
    if (objects.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    for (final entry in objects) {
      final key = _categoryPrefix + entry.key;
      await prefs.setDouble(key, (prefs.getDouble(key) ?? 0) + entry.value);
    }
    await _dbService.recordCategoryStats(userId, {for (final e in objects) e.key: e.value});
  }

  Future<StatsSnapshot> load() async {
    final dbStats = await _dbService.getWeeklyStats(userId);
    if (dbStats.isNotEmpty) {
      final categoryTotals = (dbStats['category_totals'] as Map?) ?? const {};
      return StatsSnapshot(
        totalSessions: dbStats['total_sessions'] as int? ?? 0,
        totalObjectsSeen: dbStats['total_objects_seen'] as int? ?? 0,
        totalMatches: dbStats['total_matches'] as int? ?? 0,
        last7DaysSessionCounts: List<int>.from(dbStats['last_7_days_session_counts'] as List? ?? const []),
        categoryTotals: categoryTotals.map((key, value) => MapEntry('$key', (value as num).toDouble())),
      );
    }
    return _loadLocal();
  }

  Future<StatsSnapshot> _loadLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final dailyCounts = <int>[];
    for (int i = 6; i >= 0; i--) {
      final day = now.subtract(Duration(days: i));
      dailyCounts.add(prefs.getInt(_dailySessionsPrefix + _dateKey(day)) ?? 0);
    }
    final categoryTotals = <String, double>{};
    for (final key in prefs.getKeys()) {
      if (key.startsWith(_categoryPrefix)) {
        categoryTotals[key.substring(_categoryPrefix.length)] = prefs.getDouble(key) ?? 0;
      }
    }
    return StatsSnapshot(
      totalSessions: prefs.getInt(_totalSessionsKey) ?? 0,
      totalObjectsSeen: prefs.getInt(_totalObjectsSeenKey) ?? 0,
      totalMatches: prefs.getInt(_totalMatchesKey) ?? 0,
      last7DaysSessionCounts: dailyCounts,
      categoryTotals: categoryTotals,
    );
  }

  String _dateKey(DateTime date) => '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

class StatsSnapshot {
  final int totalSessions;
  final int totalObjectsSeen;
  final int totalMatches;
  final List<int> last7DaysSessionCounts;
  final Map<String, double> categoryTotals;

  const StatsSnapshot({
    required this.totalSessions,
    required this.totalObjectsSeen,
    required this.totalMatches,
    required this.last7DaysSessionCounts,
    this.categoryTotals = const {},
  });
}
