import 'package:flutter/foundation.dart';
import 'package:postgres/postgres.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../env_config.dart';

// Direct Postgres connection for auth/session/logging - native only
// (Flutter Web can't open raw TCP sockets; AuthProvider's web path uses
// SharedPreferences-only guest accounts instead). Connection details come
// from .env, not hardcoded, but this is still a client holding admin DB
// credentials - accepted tradeoff, see docs/ARCHITECTURE.md.
class DbService {
  Connection? _connection;

  static const int _engineLogCapPerUser = 500;
  int _logWriteCount = 0;

  Future<void> connect() async {
    if (kIsWeb) return;
    if (_connection != null && _connection!.isOpen) return;
    try {
      _connection = await Connection.open(
        Endpoint(
          host: EnvConfig.dbHost,
          port: EnvConfig.dbPort,
          database: EnvConfig.dbName,
          username: EnvConfig.dbUsername,
          password: EnvConfig.dbPassword,
        ),
        settings: const ConnectionSettings(sslMode: SslMode.require),
      );
      await _initializeTables();
    } catch (error) {
      debugPrint('[DbService] Failed to connect: $error');
      rethrow;
    }
  }

  Future<void> _initializeTables() async {
    final connection = _connection;
    if (connection == null) return;

    await connection.execute('''
      CREATE TABLE IF NOT EXISTS users (
        user_id SERIAL PRIMARY KEY,
        google_id VARCHAR(255) UNIQUE,
        email VARCHAR(255) UNIQUE NOT NULL,
        password_hash VARCHAR(255),
        display_name VARCHAR(255),
        photo_url TEXT,
        is_admin BOOLEAN NOT NULL DEFAULT FALSE,
        is_superadmin BOOLEAN NOT NULL DEFAULT FALSE,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        last_login TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
    ''');
    // CREATE TABLE IF NOT EXISTS is a no-op on the real shared table, which
    // predates is_superadmin - add it explicitly for existing installs.
    try {
      await connection.execute('ALTER TABLE users ADD COLUMN IF NOT EXISTS is_superadmin BOOLEAN NOT NULL DEFAULT FALSE;');
    } catch (error) {
      debugPrint('[DbService] Failed to add is_superadmin to users: $error');
    }

    await connection.execute('''
      CREATE TABLE IF NOT EXISTS user_preferences (
        user_id INTEGER PRIMARY KEY REFERENCES users(user_id),
        categories TEXT,
        status VARCHAR(50)
      );
    ''');
    for (final column in ['brand_rating', 'cost_rating', 'speed_rating', 'reviews_rating', 'impulse_rating', 'routine_rating']) {
      try {
        await connection.execute('ALTER TABLE user_preferences ADD COLUMN IF NOT EXISTS $column INTEGER;');
      } catch (error) {
        debugPrint('[DbService] Failed to add $column to user_preferences: $error');
      }
    }

    try {
      await connection.execute('''
        CREATE TABLE IF NOT EXISTS gmail_sync (
          user_id INTEGER PRIMARY KEY,
          gmail VARCHAR(255),
          password VARCHAR(255),
          message VARCHAR(255),
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
      ''');
    } catch (error) {
      debugPrint('[DbService] Failed to create gmail_sync table: $error');
    }

    await connection.execute('''
      CREATE TABLE IF NOT EXISTS sessions (
        session_id VARCHAR(64) PRIMARY KEY,
        user_id INTEGER REFERENCES users(user_id),
        start_time TIMESTAMP DEFAULT NOW(),
        end_time TIMESTAMP,
        duration_sec INTEGER,
        status VARCHAR(20) NOT NULL DEFAULT 'active'
      );
    ''');

    try {
      await connection.execute('''
        CREATE TABLE IF NOT EXISTS engine_logs (
          log_id BIGSERIAL PRIMARY KEY,
          user_id INTEGER REFERENCES users(user_id),
          source VARCHAR(64) NOT NULL,
          message TEXT NOT NULL,
          json_payload TEXT,
          is_error BOOLEAN NOT NULL DEFAULT FALSE,
          created_at TIMESTAMP DEFAULT NOW()
        );
      ''');
      await connection.execute(
        'CREATE INDEX IF NOT EXISTS idx_engine_logs_user_created ON engine_logs(user_id, created_at DESC);',
      );
    } catch (error) {
      debugPrint('[DbService] Failed to create engine_logs table: $error');
    }

    try {
      await connection.execute('''
        CREATE TABLE IF NOT EXISTS saved_items (
          user_id INTEGER REFERENCES users(user_id),
          name VARCHAR(255) NOT NULL,
          price VARCHAR(64),
          description TEXT,
          url TEXT,
          image TEXT,
          created_at TIMESTAMP DEFAULT NOW(),
          PRIMARY KEY (user_id, name)
        );
      ''');
    } catch (error) {
      debugPrint('[DbService] Failed to create saved_items table: $error');
    }

    // Backs Insights' weekly chart/category breakdown with real per-user,
    // per-day totals instead of only ever living in this one device's
    // SharedPreferences (see StatsService).
    try {
      await connection.execute('''
        CREATE TABLE IF NOT EXISTS daily_stats (
          user_id INTEGER REFERENCES users(user_id),
          stat_date DATE NOT NULL,
          sessions_count INTEGER NOT NULL DEFAULT 0,
          objects_seen INTEGER NOT NULL DEFAULT 0,
          matches INTEGER NOT NULL DEFAULT 0,
          PRIMARY KEY (user_id, stat_date)
        );
      ''');
    } catch (error) {
      debugPrint('[DbService] Failed to create daily_stats table: $error');
    }

    try {
      await connection.execute('''
        CREATE TABLE IF NOT EXISTS category_stats (
          user_id INTEGER REFERENCES users(user_id),
          category VARCHAR(255) NOT NULL,
          total_score DOUBLE PRECISION NOT NULL DEFAULT 0,
          PRIMARY KEY (user_id, category)
        );
      ''');
    } catch (error) {
      debugPrint('[DbService] Failed to create category_stats table: $error');
    }
  }

  Future<int?> upsertUser({required String googleId, required String email, String? displayName, String? photoUrl}) async {
    await connect();
    if (_connection == null) return null;

    final result = await _connection!.execute(
      Sql.named('''
        INSERT INTO users (google_id, email, display_name, photo_url, last_login)
        VALUES (@googleId, @email, @displayName, @photoUrl, CURRENT_TIMESTAMP)
        ON CONFLICT (email)
        DO UPDATE SET google_id = EXCLUDED.google_id, display_name = EXCLUDED.display_name,
          photo_url = EXCLUDED.photo_url, last_login = CURRENT_TIMESTAMP
        RETURNING user_id;
      '''),
      parameters: {'googleId': googleId, 'email': email, 'displayName': displayName, 'photoUrl': photoUrl},
    );
    return result.isNotEmpty ? result.first[0] as int : null;
  }

  Future<void> createEmailUser({required String email, required String passwordHash, required String displayName}) async {
    await connect();
    if (_connection == null) throw Exception('No DB connection');

    final result = await _connection!.execute(
      Sql.named('''
        INSERT INTO users (email, password_hash, display_name, last_login)
        VALUES (@email, @passwordHash, @displayName, CURRENT_TIMESTAMP)
        ON CONFLICT (email)
        DO UPDATE SET password_hash = EXCLUDED.password_hash,
          display_name = COALESCE(users.display_name, EXCLUDED.display_name), last_login = CURRENT_TIMESTAMP
        WHERE users.password_hash IS NULL
        RETURNING user_id;
      '''),
      parameters: {'email': email, 'passwordHash': passwordHash, 'displayName': displayName},
    );
    if (result.isEmpty) throw Exception('Email already in use with a password.');
  }

  Future<Map<String, dynamic>?> authenticateEmailUser({required String email, required String passwordHash}) async {
    await connect();
    if (_connection == null) throw Exception('No DB connection');

    final result = await _connection!.execute(
      Sql.named('SELECT user_id, email, display_name, photo_url, password_hash, is_admin, is_superadmin FROM users WHERE email = @email LIMIT 1'),
      parameters: {'email': email},
    );
    if (result.isEmpty) throw Exception('Account not found. Please sign up first.');

    final row = result.first;
    final storedHash = row[4];
    if (storedHash == null) {
      throw Exception('This account uses Google Sign-In. Use that, or Sign Up to link a password.');
    }
    if (storedHash != passwordHash) throw Exception('Invalid password.');

    await _connection!.execute(
      Sql.named('UPDATE users SET last_login = CURRENT_TIMESTAMP WHERE email = @email'),
      parameters: {'email': email},
    );

    return {'id': row[0], 'email': row[1], 'display_name': row[2], 'photo_url': row[3], 'is_admin': row[5], 'is_superadmin': row[6]};
  }

  Future<int?> getUserIdByEmail(String email) async {
    if (kIsWeb) return null;
    await connect();
    if (_connection == null) return null;
    try {
      final result = await _connection!.execute(
        Sql.named('SELECT user_id FROM users WHERE email = @email LIMIT 1'),
        parameters: {'email': email.trim().toLowerCase()},
      );
      if (result.isNotEmpty) {
        return result.first[0] as int?;
      }
    } catch (e) {
      debugPrint('[DbService] getUserIdByEmail failed: $e');
    }
    return null;
  }

  Future<bool> isUserAdmin(int userId) async {
    await connect();
    if (_connection == null) return false;
    final result = await _connection!.execute(
      Sql.named('SELECT is_admin FROM users WHERE user_id = @userId'),
      parameters: {'userId': userId},
    );
    return result.isEmpty ? false : (result.first[0] as bool? ?? false);
  }

  Future<bool> isUserSuperAdmin(int userId) async {
    await connect();
    if (_connection == null) return false;
    final result = await _connection!.execute(
      Sql.named('SELECT is_superadmin FROM users WHERE user_id = @userId'),
      parameters: {'userId': userId},
    );
    return result.isEmpty ? false : (result.first[0] as bool? ?? false);
  }

  Future<bool> hasPreferences(int userId) async {
    await connect();
    if (_connection == null) return false;
    final result = await _connection!.execute(
      Sql.named('SELECT 1 FROM user_preferences WHERE user_id = @userId'),
      parameters: {'userId': userId},
    );
    return result.isNotEmpty;
  }

  Future<void> savePreferences({
    required int userId,
    required String categories,
    required int brandRating,
    required int costRating,
    required int speedRating,
    required int reviewsRating,
    required int impulseRating,
    required int routineRating,
    String status = 'success',
  }) async {
    await connect();
    if (_connection == null) throw Exception('No DB connection');
    await _connection!.execute(
      Sql.named('''
        INSERT INTO user_preferences (user_id, categories, brand_rating, cost_rating, speed_rating, reviews_rating, impulse_rating, routine_rating, status)
        VALUES (@userId, @categories, @brandRating, @costRating, @speedRating, @reviewsRating, @impulseRating, @routineRating, @status)
        ON CONFLICT (user_id) DO UPDATE SET
          categories = EXCLUDED.categories, brand_rating = EXCLUDED.brand_rating, cost_rating = EXCLUDED.cost_rating,
          speed_rating = EXCLUDED.speed_rating, reviews_rating = EXCLUDED.reviews_rating,
          impulse_rating = EXCLUDED.impulse_rating, routine_rating = EXCLUDED.routine_rating, status = EXCLUDED.status
      '''),
      parameters: {
        'userId': userId,
        'categories': categories,
        'brandRating': brandRating,
        'costRating': costRating,
        'speedRating': speedRating,
        'reviewsRating': reviewsRating,
        'impulseRating': impulseRating,
        'routineRating': routineRating,
        'status': status,
      },
    );
  }

  // App-password (not the real account password) for parsing order-confirmation
  // emails - stored in plaintext to match the existing gmail_sync table this
  // shares with smartglass_flutter. Same tradeoff as the DB credentials
  // above; see docs/ARCHITECTURE.md.
  Future<void> saveGmailSync(int userId, String email, String appPassword, String message) async {
    await connect();
    if (_connection == null) throw Exception('No DB connection');
    await _connection!.execute(
      Sql.named('''
        INSERT INTO gmail_sync (user_id, gmail, password, message)
        VALUES (@userId, @email, @password, @message)
        ON CONFLICT (user_id) DO UPDATE SET
          gmail = EXCLUDED.gmail, password = EXCLUDED.password, message = EXCLUDED.message, created_at = CURRENT_TIMESTAMP
      '''),
      parameters: {'userId': userId, 'email': email, 'password': appPassword, 'message': message},
    );
  }

  Future<List<Map<String, dynamic>>> getAllUsersForAdmin() async {
    await connect();
    if (_connection == null) return [];
    final result = await _connection!.execute('''
      SELECT users.user_id, email, display_name, last_login, is_admin, is_superadmin
      FROM users ORDER BY last_login DESC
    ''');
    return result
        .map((r) => {'user_id': r[0], 'email': r[1], 'display_name': r[2], 'last_login': r[3], 'is_admin': r[4], 'is_superadmin': r[5]})
        .toList();
  }

  Future<void> setUserAdminStatus(int userId, bool isAdmin) async {
    await connect();
    if (_connection == null) throw Exception('No DB connection');
    await _connection!.execute(
      Sql.named('UPDATE users SET is_admin = @isAdmin WHERE user_id = @userId'),
      parameters: {'isAdmin': isAdmin, 'userId': userId},
    );
  }

  Future<void> setUserSuperAdminStatus(int userId, bool isSuperAdmin) async {
    await connect();
    if (_connection == null) throw Exception('No DB connection');
    await _connection!.execute(
      Sql.named('UPDATE users SET is_superadmin = @isSuperAdmin WHERE user_id = @userId'),
      parameters: {'isSuperAdmin': isSuperAdmin, 'userId': userId},
    );
  }

  Future<void> deleteUser(int userId) async {
    await connect();
    if (_connection == null) throw Exception('No DB connection');
    await _connection!.execute(Sql.named('DELETE FROM user_preferences WHERE user_id = @userId'), parameters: {'userId': userId});
    await _connection!.execute(Sql.named('DELETE FROM gmail_sync WHERE user_id = @userId'), parameters: {'userId': userId});
    await _connection!.execute(Sql.named('DELETE FROM sessions WHERE user_id = @userId'), parameters: {'userId': userId});
    await _connection!.execute(Sql.named('DELETE FROM engine_logs WHERE user_id = @userId'), parameters: {'userId': userId});
    await _connection!.execute(Sql.named('DELETE FROM users WHERE user_id = @userId'), parameters: {'userId': userId});
  }

  static const String _sessionPointerIdKey = 'session_pointer_id';

  // Opens a session row keyed by the pipeline's own generated sessionId (the
  // same value sent to BE/IE for that run). Best-effort - swallows DB
  // failures so callers never block the actual capture pipeline on this.
  Future<void> startSession(int userId, String sessionId) async {
    try {
      await connect();
      if (_connection == null) return;

      final prefs = await SharedPreferences.getInstance();
      final pointerId = prefs.getString(_sessionPointerIdKey);
      if (pointerId != null && pointerId != sessionId) {
        try {
          await _connection!.execute(
            Sql.named("UPDATE sessions SET status = 'abandoned' WHERE session_id = @id AND status = 'active'"),
            parameters: {'id': pointerId},
          );
        } catch (_) {}
      }

      await _connection!.execute(
        Sql.named('''
          INSERT INTO sessions (session_id, user_id, status)
          VALUES (@sessionId, @userId, 'active')
          ON CONFLICT (session_id) DO NOTHING
        '''),
        parameters: {'sessionId': sessionId, 'userId': userId},
      );
      await prefs.setString(_sessionPointerIdKey, sessionId);
    } catch (error) {
      debugPrint('[DbService] Failed to start session: $error');
    }
  }

  Future<void> endSession(String sessionId) async {
    try {
      await connect();
      if (_connection == null) return;

      await _connection!.execute(
        Sql.named('''
          UPDATE sessions
          SET end_time = NOW(), duration_sec = EXTRACT(EPOCH FROM (NOW() - start_time))::INTEGER, status = 'completed'
          WHERE session_id = @id AND status = 'active'
        '''),
        parameters: {'id': sessionId},
      );

      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_sessionPointerIdKey) == sessionId) {
        await prefs.remove(_sessionPointerIdKey);
      }
    } catch (error) {
      debugPrint('[DbService] Failed to end session: $error');
    }
  }

  Future<List<Map<String, dynamic>>> getRecentSessions(int userId, {int limit = 20}) async {
    try {
      await connect();
      if (_connection == null) return [];
      final result = await _connection!.execute(
        Sql.named('''
          SELECT session_id, start_time, end_time, duration_sec, status
          FROM sessions WHERE user_id = @userId ORDER BY start_time DESC LIMIT @limit
        '''),
        parameters: {'userId': userId, 'limit': limit},
      );
      return result
          .map((r) => {'session_id': r[0], 'start_time': r[1], 'end_time': r[2], 'duration_sec': r[3], 'status': r[4]})
          .toList();
    } catch (error) {
      debugPrint('[DbService] Failed to load recent sessions: $error');
      return [];
    }
  }

  // Best-effort - failures are swallowed so logging can never block or crash
  // the actual engine call it's describing.
  Future<void> logEngineEvent({
    required int userId,
    required String source,
    required String message,
    String? jsonPayload,
    bool isError = false,
  }) async {
    try {
      await connect();
      if (_connection == null) return;

      await _connection!.execute(
        Sql.named('''
          INSERT INTO engine_logs (user_id, source, message, json_payload, is_error)
          VALUES (@userId, @source, @message, @jsonPayload, @isError)
        '''),
        parameters: {'userId': userId, 'source': source, 'message': message, 'jsonPayload': jsonPayload, 'isError': isError},
      );

      _logWriteCount++;
      if (_logWriteCount % 20 == 0) {
        await _connection!.execute(
          Sql.named('''
            DELETE FROM engine_logs
            WHERE user_id = @userId
              AND log_id NOT IN (
                SELECT log_id FROM engine_logs WHERE user_id = @userId ORDER BY created_at DESC LIMIT @cap
              )
          '''),
          parameters: {'userId': userId, 'cap': _engineLogCapPerUser},
        );
      }
    } catch (error) {
      debugPrint('[DbService] Failed to persist engine log: $error');
    }
  }

  // Best-effort - the local SharedPreferences cache in SavedItemsService is
  // already written before this runs, so a connection hiccup here shouldn't
  // surface as an uncaught rejection to whatever fire-and-forget UI code
  // called save()/remove() without its own try/catch.
  Future<void> saveItem(int userId, Map<String, String> item) async {
    try {
      await connect();
      if (_connection == null) return;
      await _connection!.execute(
        Sql.named('''
          INSERT INTO saved_items (user_id, name, price, description, url, image)
          VALUES (@userId, @name, @price, @description, @url, @image)
          ON CONFLICT (user_id, name) DO NOTHING
        '''),
        parameters: {
          'userId': userId,
          'name': item['name'],
          'price': item['price'],
          'description': item['description'],
          'url': item['url'],
          'image': item['image'],
        },
      );
    } catch (error) {
      debugPrint('[DbService] Failed to save item: $error');
    }
  }

  Future<void> removeSavedItem(int userId, String name) async {
    try {
      await connect();
      if (_connection == null) return;
      await _connection!.execute(
        Sql.named('DELETE FROM saved_items WHERE user_id = @userId AND name = @name'),
        parameters: {'userId': userId, 'name': name},
      );
    } catch (error) {
      debugPrint('[DbService] Failed to remove saved item: $error');
    }
  }

  // Was missing the try/catch every other read method here has (getWeeklyStats
  // etc.) - a connect() failure threw straight out of SavedItemsService.load(),
  // past its own local-cache fallback, and the screen's FutureBuilder rendered
  // that rejection as an empty "Nothing saved yet" list instead of falling
  // back to what was actually saved on-device.
  Future<List<Map<String, String>>> getSavedItems(int userId) async {
    try {
      await connect();
      if (_connection == null) return [];
      final result = await _connection!.execute(
        Sql.named('SELECT name, price, description, url, image FROM saved_items WHERE user_id = @userId ORDER BY created_at DESC'),
        parameters: {'userId': userId},
      );
      return result.map((r) {
        final item = <String, String>{'name': '${r[0]}'};
        if (r[1] != null) item['price'] = '${r[1]}';
        if (r[2] != null) item['description'] = '${r[2]}';
        if (r[3] != null) item['url'] = '${r[3]}';
        if (r[4] != null) item['image'] = '${r[4]}';
        return item;
      }).toList();
    } catch (error) {
      debugPrint('[DbService] Failed to load saved items: $error');
      return [];
    }
  }

  // Best-effort, upserted daily so re-running this on the same day
  // accumulates rather than overwrites.
  Future<void> recordDailyStats(int userId, {int sessions = 0, int objectsSeen = 0, int matches = 0}) async {
    try {
      await connect();
      if (_connection == null) return;
      final today = DateTime.now();
      final dateStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      await _connection!.execute(
        Sql.named('''
          INSERT INTO daily_stats (user_id, stat_date, sessions_count, objects_seen, matches)
          VALUES (@userId, @statDate, @sessions, @objectsSeen, @matches)
          ON CONFLICT (user_id, stat_date) DO UPDATE SET
            sessions_count = daily_stats.sessions_count + EXCLUDED.sessions_count,
            objects_seen = daily_stats.objects_seen + EXCLUDED.objects_seen,
            matches = daily_stats.matches + EXCLUDED.matches
        '''),
        parameters: {'userId': userId, 'statDate': dateStr, 'sessions': sessions, 'objectsSeen': objectsSeen, 'matches': matches},
      );
    } catch (error) {
      debugPrint('[DbService] Failed to record daily stats: $error');
    }
  }

  Future<void> recordCategoryStats(int userId, Map<String, double> scoresByCategory) async {
    if (scoresByCategory.isEmpty) return;
    try {
      await connect();
      if (_connection == null) return;
      for (final entry in scoresByCategory.entries) {
        await _connection!.execute(
          Sql.named('''
            INSERT INTO category_stats (user_id, category, total_score)
            VALUES (@userId, @category, @score)
            ON CONFLICT (user_id, category) DO UPDATE SET total_score = category_stats.total_score + EXCLUDED.total_score
          '''),
          parameters: {'userId': userId, 'category': entry.key, 'score': entry.value},
        );
      }
    } catch (error) {
      debugPrint('[DbService] Failed to record category stats: $error');
    }
  }

  // Exact totals (not estimates) - sums straight off daily_stats/category_stats
  // rather than keeping a separate running-total column that could drift.
  Future<Map<String, dynamic>> getWeeklyStats(int userId) async {
    try {
      await connect();
      if (_connection == null) return {};
      final totals = await _connection!.execute(
        Sql.named('SELECT COALESCE(SUM(sessions_count),0), COALESCE(SUM(objects_seen),0), COALESCE(SUM(matches),0) FROM daily_stats WHERE user_id = @userId'),
        parameters: {'userId': userId},
      );
      final now = DateTime.now();
      final dailyCounts = <int>[];
      for (int i = 6; i >= 0; i--) {
        final day = now.subtract(Duration(days: i));
        final dateStr = '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
        final result = await _connection!.execute(
          Sql.named('SELECT sessions_count FROM daily_stats WHERE user_id = @userId AND stat_date = @statDate'),
          parameters: {'userId': userId, 'statDate': dateStr},
        );
        dailyCounts.add(result.isEmpty ? 0 : (result.first[0] as int? ?? 0));
      }
      final categoryRows = await _connection!.execute(
        Sql.named('SELECT category, total_score FROM category_stats WHERE user_id = @userId'),
        parameters: {'userId': userId},
      );
      return {
        'total_sessions': totals.first[0] as int,
        'total_objects_seen': totals.first[1] as int,
        'total_matches': totals.first[2] as int,
        'last_7_days_session_counts': dailyCounts,
        'category_totals': {for (final r in categoryRows) '${r[0]}': (r[1] as num).toDouble()},
      };
    } catch (error) {
      debugPrint('[DbService] Failed to load weekly stats: $error');
      return {};
    }
  }

  Future<void> close() async {
    await _connection?.close();
    _connection = null;
  }
}
