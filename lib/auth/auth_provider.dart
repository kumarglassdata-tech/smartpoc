import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../env_config.dart';
import 'db_service.dart';

// Google Sign-In + direct-Postgres email/password auth, mirroring the
// reference app exactly (including its unsalted SHA-256 password hashing
// and web guest-mode fallback) - see docs/ARCHITECTURE.md for the accepted
// tradeoffs around embedding DB admin credentials in a client app.

class AuthProvider extends ChangeNotifier {
  bool _isLoggedIn = false;
  String _username = '';
  String _email = '';
  String _photoUrl = '';
  int? _userId;
  bool _isDbAdmin = false;
  bool _isDbSuperAdmin = false;
  bool _hasPreferences = true;

  // google_sign_in_web's init reads `clientId` eagerly (as a field
  // initializer, before any UI interaction) and crashes the whole app on
  // web with an unhandled null-check if it's missing - so on web, only
  // construct it once a real GOOGLE_WEB_CLIENT_ID exists. Native platforms
  // resolve their client from the registered SHA-1, so they're unaffected.
  final GoogleSignIn? _googleSignIn = (kIsWeb && EnvConfig.googleWebClientId.isEmpty)
      ? null
      : GoogleSignIn(
          scopes: ['email', 'profile'],
          clientId: kIsWeb ? EnvConfig.googleWebClientId : null,
          serverClientId: !kIsWeb && EnvConfig.googleWebClientId.isNotEmpty ? EnvConfig.googleWebClientId : null,
        );
  final DbService _dbService = DbService();

  bool get isLoggedIn => _isLoggedIn;
  String get username => _username;
  String get email => _email;
  String get photoUrl => _photoUrl;
  int? get userId => _userId;
  bool get isAdmin => _isLoggedIn && _isDbAdmin;
  bool get isSuperAdmin => _isLoggedIn && _isDbSuperAdmin;
  bool get hasPreferences => _hasPreferences;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    _username = prefs.getString('username') ?? '';
    _email = prefs.getString('email') ?? '';
    _photoUrl = prefs.getString('photoUrl') ?? '';
    _userId = prefs.getInt('userId');
    _isDbAdmin = prefs.getBool('isDbAdmin') ?? false;
    _isDbSuperAdmin = prefs.getBool('isDbSuperAdmin') ?? false;
    _hasPreferences = prefs.getBool('hasPreferences') ?? true;

    if (_userId == null && _email.isNotEmpty) {
      if (kIsWeb) {
        _userId = _pseudoUserId(_email);
      } else {
        _userId = await _dbService.getUserIdByEmail(_email);
      }
      if (_userId != null) await prefs.setInt('userId', _userId!);
    }
    notifyListeners();
  }

  Future<int?> resolveUserId() async {
    if (_userId != null && _userId != 0) return _userId;
    if (_email.isNotEmpty) {
      if (kIsWeb) {
        _userId = _pseudoUserId(_email);
      } else {
        _userId = await _dbService.getUserIdByEmail(_email);
      }
      if (_userId != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('userId', _userId!);
        notifyListeners();
      }
    }
    return _userId;
  }

  // Called once the personalize-feed form is submitted (or skipped) -
  // persisted both globally and per-account so a different user logging in
  // on the same device/browser doesn't inherit this one's answer.
  Future<void> setHasPreferences(bool value) async {
    _hasPreferences = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasPreferences', value);
    if (_email.isNotEmpty) await prefs.setBool('hasPreferences_$_email', value);
    notifyListeners();
  }

  String _hashPassword(String password) => sha256.convert(utf8.encode(password)).toString();

  // Web guest mode - Flutter Web can't open a raw socket to Postgres, so
  // accounts on web are kept locally (per-browser) instead of hitting the
  // real database. Native (Android/iOS) uses Postgres via DbService.
  int _pseudoUserId(String email) => email.hashCode & 0x7fffffff;

  Future<Map<String, dynamic>> _loadWebGuestAccounts(SharedPreferences prefs) async {
    final raw = prefs.getString('webGuestAccounts');
    if (raw == null) return {};
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  Future<void> _saveWebGuestAccounts(SharedPreferences prefs, Map<String, dynamic> accounts) async {
    await prefs.setString('webGuestAccounts', jsonEncode(accounts));
  }

  Future<String?> _completeWebLogin({required String email, required String displayName, String photoUrl = ''}) async {
    final prefs = await SharedPreferences.getInstance();
    final uid = _pseudoUserId(email);
    final hasPrefs = prefs.getBool('hasPreferences_$email') ?? true;

    await prefs.setBool('isLoggedIn', true);
    await prefs.setString('username', displayName);
    await prefs.setString('email', email);
    await prefs.setString('photoUrl', photoUrl);
    await prefs.setInt('userId', uid);
    await prefs.setBool('hasPreferences', hasPrefs);

    _isLoggedIn = true;
    _username = displayName;
    _email = email;
    _photoUrl = photoUrl;
    _userId = uid;
    _hasPreferences = hasPrefs;
    notifyListeners();
    return null;
  }

  Future<String?> signUpWithEmail(String email, String password, String displayName) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final accounts = await _loadWebGuestAccounts(prefs);
      if (accounts.containsKey(normalizedEmail)) return 'Sign up failed. Email might already be in use.';
      accounts[normalizedEmail] = {'passwordHash': _hashPassword(password), 'displayName': displayName.trim()};
      await _saveWebGuestAccounts(prefs, accounts);
      // Brand new account - force the personalize-feed form once, same as
      // a fresh user_id with no user_preferences row would on native.
      await prefs.setBool('hasPreferences_$normalizedEmail', false);
      return loginWithEmail(email, password);
    }
    try {
      await _dbService.createEmailUser(email: normalizedEmail, passwordHash: _hashPassword(password), displayName: displayName.trim());
      return loginWithEmail(email, password);
    } catch (error) {
      debugPrint('[AuthProvider] Sign up error: $error');
      return 'Sign up failed. Email might already be in use.';
    }
  }

  Future<String?> loginWithEmail(String email, String password) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final accounts = await _loadWebGuestAccounts(prefs);
      final account = accounts[normalizedEmail] as Map<String, dynamic>?;
      if (account == null) return 'Account not found. Please sign up first.';
      if (account['passwordHash'] != _hashPassword(password)) return 'Invalid password.';
      return _completeWebLogin(email: normalizedEmail, displayName: account['displayName'] as String? ?? 'User');
    }
    try {
      final user = await _dbService.authenticateEmailUser(email: normalizedEmail, passwordHash: _hashPassword(password));
      if (user == null) return 'Invalid email or password.';

      final uid = user['id'] as int?;
      final dbAdmin = user['is_admin'] as bool? ?? false;
      final dbSuperAdmin = user['is_superadmin'] as bool? ?? false;
      final hasPrefs = uid != null ? await _dbService.hasPreferences(uid) : true;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isLoggedIn', true);
      await prefs.setString('username', user['display_name'] ?? 'User');
      await prefs.setString('email', user['email']);
      await prefs.setString('photoUrl', user['photo_url'] ?? '');
      if (uid != null) await prefs.setInt('userId', uid);
      await prefs.setBool('isDbAdmin', dbAdmin);
      await prefs.setBool('isDbSuperAdmin', dbSuperAdmin);
      await prefs.setBool('hasPreferences', hasPrefs);

      _isLoggedIn = true;
      _username = user['display_name'] ?? 'User';
      _email = user['email'];
      _photoUrl = user['photo_url'] ?? '';
      _userId = uid;
      _isDbAdmin = dbAdmin;
      _isDbSuperAdmin = dbSuperAdmin;
      _hasPreferences = hasPrefs;
      notifyListeners();
      return null;
    } catch (error) {
      debugPrint('[AuthProvider] Login error: $error');
      final message = error is Exception ? error.toString().replaceFirst('Exception: ', '') : 'Login failed: $error';
      return message;
    }
  }

  Future<String?> loginWithGoogle() async {
    final googleSignIn = _googleSignIn;
    if (googleSignIn == null) return 'Google Sign-In is not configured yet.';
    try {
      final account = await googleSignIn.signIn();
      if (account == null) return 'Sign-in aborted by user.';

      if (kIsWeb) {
        return _completeWebLogin(email: account.email.trim().toLowerCase(), displayName: account.displayName ?? 'User', photoUrl: account.photoUrl ?? '');
      }

      final uid = await _dbService.upsertUser(googleId: account.id, email: account.email, displayName: account.displayName, photoUrl: account.photoUrl);
      final dbAdmin = uid != null ? await _dbService.isUserAdmin(uid) : false;
      final dbSuperAdmin = uid != null ? await _dbService.isUserSuperAdmin(uid) : false;
      final hasPrefs = uid != null ? await _dbService.hasPreferences(uid) : true;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isLoggedIn', true);
      await prefs.setString('username', account.displayName ?? 'User');
      await prefs.setString('email', account.email);
      await prefs.setString('photoUrl', account.photoUrl ?? '');
      if (uid != null) await prefs.setInt('userId', uid);
      await prefs.setBool('isDbAdmin', dbAdmin);
      await prefs.setBool('isDbSuperAdmin', dbSuperAdmin);
      await prefs.setBool('hasPreferences', hasPrefs);

      _isLoggedIn = true;
      _username = account.displayName ?? 'User';
      _email = account.email;
      _photoUrl = account.photoUrl ?? '';
      _userId = uid;
      _isDbAdmin = dbAdmin;
      _isDbSuperAdmin = dbSuperAdmin;
      _hasPreferences = hasPrefs;
      notifyListeners();
      return null;
    } catch (error) {
      debugPrint('[AuthProvider] Google Sign-In error: $error');
      return 'Google Sign-In failed: $error';
    }
  }

  Future<void> logout() async {
    await _googleSignIn?.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    _isLoggedIn = false;
    _username = '';
    _email = '';
    _photoUrl = '';
    _userId = null;
    _isDbAdmin = false;
    _isDbSuperAdmin = false;
    _hasPreferences = true;
    notifyListeners();
  }

  // is_admin/is_superadmin are only read from the DB at login and then
  // cached in SharedPreferences - a role granted mid-session (e.g. via
  // AdminUsersScreen) wouldn't show up until the user logged out and back
  // in. Called from HomeShell's initState() so every app open re-checks
  // instead of trusting a possibly-stale cached value.
  Future<void> refreshRoles() async {
    if (kIsWeb || !_isLoggedIn) return;
    final uid = _userId;
    if (uid == null) return;
    final dbAdmin = await _dbService.isUserAdmin(uid);
    final dbSuperAdmin = await _dbService.isUserSuperAdmin(uid);
    if (dbAdmin == _isDbAdmin && dbSuperAdmin == _isDbSuperAdmin) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDbAdmin', dbAdmin);
    await prefs.setBool('isDbSuperAdmin', dbSuperAdmin);
    _isDbAdmin = dbAdmin;
    _isDbSuperAdmin = dbSuperAdmin;
    notifyListeners();
  }
}

// Settings actually used by SmartPoc today - trimmed from the reference's
// five fields to the two with a real consumer (interaction_engine_client's
// wake-word gate, and a future camera-source picker).
class SettingsProvider extends ChangeNotifier {
  bool _wakeWordEnabled = true;
  String _preferredCamera = 'phone';
  bool _isDarkMode = false;

  bool get wakeWordEnabled => _wakeWordEnabled;
  String get preferredCamera => _preferredCamera;
  bool get isDarkMode => _isDarkMode;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _wakeWordEnabled = prefs.getBool('wakeWordEnabled') ?? true;
    _preferredCamera = prefs.getString('preferredCamera') ?? 'phone';
    _isDarkMode = prefs.getBool('isDarkMode') ?? false;
    notifyListeners();
  }

  Future<void> setWakeWordEnabled(bool value) async {
    _wakeWordEnabled = value;
    (await SharedPreferences.getInstance()).setBool('wakeWordEnabled', value);
    notifyListeners();
  }

  Future<void> setDarkMode(bool value) async {
    _isDarkMode = value;
    (await SharedPreferences.getInstance()).setBool('isDarkMode', value);
    notifyListeners();
  }

  Future<void> setPreferredCamera(String value) async {
    _preferredCamera = value;
    (await SharedPreferences.getInstance()).setString('preferredCamera', value);
    notifyListeners();
  }
}
