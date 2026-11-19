import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static late SharedPreferences _prefs;
  static const _defaultUrl = 'http://10.0.2.2:5159';

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static String get baseUrl => _prefs.getString('api_base_url') ?? _defaultUrl;
  static Future<void> setBaseUrl(String value) async {
    await _prefs.setString('api_base_url', value.trim().replaceAll(RegExp(r'/$'), ''));
  }

  // Update this route and response parsing to match your API's actual login endpoint.
  static Future<bool> login(String username, String password) async {
    final uri = Uri.parse('$baseUrl/api/auth/login');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    ).timeout(const Duration(seconds: 12));
    if (response.statusCode >= 200 && response.statusCode < 300) return true;
    throw Exception('Login endpoint returned ${response.statusCode}. Confirm the API route and request format.');
  }
}
