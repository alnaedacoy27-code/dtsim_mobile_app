
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class LocalStore {
  static Map<String, bool> get permissions {
  final saved = _prefs.getString('user_permissions');

  if (saved == null) return {};

  final decoded = jsonDecode(saved) as Map<String, dynamic>;

  return decoded.map(
    (key, value) => MapEntry(key, value == true),
  );
}
  static late SharedPreferences _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static bool get isLoggedIn => _prefs.getBool('logged_in') ?? false;

  static String get displayName =>
      _prefs.getString('display_name') ?? 'Darwin Trading User';

  static String? get token => _prefs.getString('auth_token');
  static int? get userId => _prefs.getInt('user_id');
  static String? get username => _prefs.getString('username');
  static String? get role => _prefs.getString('user_role');

  static Future<void> saveSession(
    String name, {
    String? token,
    int? userId,
    String? username,
    String? role,
    Map<String, dynamic>? permissions,
  }) async {
    await _prefs.setBool('logged_in', true);
    await _prefs.setString('display_name', name);

    if (token != null) {
      await _prefs.setString('auth_token', token);
    } else {
      await _prefs.remove('auth_token');
    }

    if (userId != null) {
      await _prefs.setInt('user_id', userId);
    } else {
      await _prefs.remove('user_id');
    }

    if (username != null) {
      await _prefs.setString('username', username);
    } else {
      await _prefs.remove('username');
    }

    if (role != null) {
      await _prefs.setString('user_role', role);
    } else {
      await _prefs.remove('user_role');
    }

    if (permissions != null) {
      await _prefs.setString('user_permissions', jsonEncode(permissions));
    } else {
      await _prefs.remove('user_permissions');
    }
  }

  static Future<void> clearSession() async {
    await _prefs.setBool('logged_in', false);
    await _prefs.remove('display_name');
    await _prefs.remove('auth_token');
    await _prefs.remove('user_id');
    await _prefs.remove('username');
    await _prefs.remove('user_role');
    await _prefs.remove('user_permissions');
  }

  static List<Map<String, dynamic>> get drafts {
    final raw = _prefs.getString('delivery_drafts');
    if (raw == null) return [];

    try {
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveDraft(
    Map<String, dynamic> draft,
  ) async {
    final items = drafts;
    items.insert(0, draft);
    await _prefs.setString('delivery_drafts', jsonEncode(items));
  }

  static Future<void> removeDraft(int index) async {
    final items = drafts;

    if (index >= 0 && index < items.length) {
      items.removeAt(index);
      await _prefs.setString('delivery_drafts', jsonEncode(items));
    }
  }
}
