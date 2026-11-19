import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class LocalStore {
  static late SharedPreferences _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static bool get isLoggedIn => _prefs.getBool('logged_in') ?? false;
  static String get displayName => _prefs.getString('display_name') ?? 'Darwin Trading User';
  static Future<void> saveSession(String name) async {
    await _prefs.setBool('logged_in', true);
    await _prefs.setString('display_name', name);
  }
  static Future<void> clearSession() async {
    await _prefs.setBool('logged_in', false);
    await _prefs.remove('display_name');
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

  static Future<void> saveDraft(Map<String, dynamic> draft) async {
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
