import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'local_store.dart';

class ApiService {
  static late SharedPreferences _prefs;

  static const _defaultUrl = 'http://192.168.1.2:5159';

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static String get baseUrl =>
      _prefs.getString('api_base_url') ?? _defaultUrl;

  static Future<void> setBaseUrl(String value) async {
    await _prefs.setString('api_base_url', normalizeUrl(value));
  }

  /// "100.64.1.2" -> "http://100.64.1.2:5159". Adds http:// and the default
  /// API port when they are missing and removes trailing slashes.
  static String normalizeUrl(String value) {
    var s = value.trim();
    if (s.isEmpty) return s;
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'http://$s';
    }
    s = s.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(s);
    if (uri != null && uri.host.isNotEmpty && !uri.hasPort && uri.scheme == 'http') {
      s = uri.replace(port: 5159).toString().replaceAll(RegExp(r'/+$'), '');
    }
    return s;
  }

  // ---------------- saved servers (office Wi-Fi, Tailscale, ...) ----------------
  static List<SavedServer> get savedServers {
    final raw = _prefs.getString('saved_servers');
    if (raw != null) {
      try {
        final list = (jsonDecode(raw) as List)
            .map((e) => SavedServer.fromJson((e as Map).cast<String, dynamic>()))
            .where((s) => s.url.isNotEmpty)
            .toList();
        if (list.isNotEmpty) return list;
      } catch (_) {}
    }
    return [SavedServer('Main server', baseUrl)];
  }

  static Future<void> saveServers(List<SavedServer> servers) async {
    await _prefs.setString(
      'saved_servers',
      jsonEncode(servers.map((s) => s.toJson()).toList()),
    );
  }

  /// Checks that the API at [url] answers and can reach its database.
  /// Does not need a login.
  static Future<ConnectionTestResult> testConnection(String url) async {
    final base = normalizeUrl(url);
    if (base.isEmpty || Uri.tryParse(base)?.host.isEmpty != false) {
      return ConnectionTestResult(false, 'Enter a valid address.');
    }

    try {
      final response = await http
          .get(Uri.parse('$base/api/diagnostics/database'))
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        return ConnectionTestResult(true, 'Connected to the system.');
      }
      if (response.statusCode == 503) {
        return ConnectionTestResult(
            false, 'Reached the server, but it cannot reach the database.');
      }
      return ConnectionTestResult(
          false, 'The server answered with an error (HTTP ${response.statusCode}).');
    } on TimeoutException {
      return ConnectionTestResult(false,
          'No answer. Check the address, that the system is running, and that both devices are on the same network or Tailscale.');
    } catch (_) {
      return ConnectionTestResult(false,
          'Cannot reach the server. Check the address and your network or Tailscale connection.');
    }
  }

  /// Shown in the desktop's user monitoring, e.g. "Mobile App (Android)".
  static String get _deviceLabel {
    switch (Platform.operatingSystem) {
      case 'android':
        return 'Android';
      case 'ios':
        return 'iPhone';
      case 'windows':
        return 'Windows';
      default:
        return Platform.operatingSystem;
    }
  }

  static Future<bool> login(String username, String password) async {
    final uri = Uri.parse('$baseUrl/api/Auth/login');

    http.Response response;
    try {
      response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'password': password,
          'deviceName': _deviceLabel,
        }),
      ).timeout(const Duration(seconds: 12));
    } on TimeoutException {
      throw AuthException(
        AuthFailure.network,
        'Connection timed out. Please check your connection and try again.',
      );
    } catch (_) {
      throw AuthException(
        AuthFailure.network,
        'Cannot reach the server. Please check your connection and try again.',
      );
    }

    // Decode the body safely. A denied login may come back with an empty
    // body, so never let a parse problem hide the real status code.
    dynamic data;
    final raw = response.body.trim();
    if (raw.isNotEmpty) {
      try {
        data = jsonDecode(raw);
      } catch (_) {
        data = null;
      }
    }
    final serverMessage =
        (data is Map && data['message'] is String) ? data['message'] as String : null;

    // 403 = the user exists but has no permission for this application.
    if (response.statusCode == 403) {
      throw AuthException(
        AuthFailure.noAccess,
        "You don't have access to this application.",
      );
    }

    // 401 = wrong username or password.
    if (response.statusCode == 401) {
      throw AuthException(
        AuthFailure.invalidCredentials,
        serverMessage ?? 'Invalid username or password.',
      );
    }

    if (response.statusCode == 200 && data is Map && data['user'] is Map) {
      final user = data['user'];

      await LocalStore.saveSession(
        user['fullName'] ?? user['username'],
        token: data['token'],
        userId: user['id'],
        username: user['username'],
        role: user['role'],
        permissions: data['permissions'] is Map
            ? Map<String, dynamic>.from(data['permissions'])
            : null,
      );

      return true;
    }

    throw AuthException(
      AuthFailure.server,
      serverMessage ??
          'Something went wrong on the server (HTTP ${response.statusCode}). Please try again.',
    );
  }

  /// Authenticated GET. Returns the decoded JSON body.
  /// Throws [SessionExpiredException] on 401 and [ApiException] otherwise.
  static Future<dynamic> getJson(
    String path, {
    Map<String, String>? query,
  }) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);

    http.Response response;
    try {
      response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer ${LocalStore.token ?? ''}',
        },
      ).timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw ApiException(
          'Connection timed out. Please check your connection and try again.');
    } catch (_) {
      throw ApiException(
          'Cannot reach the server. Please check your connection and try again.');
    }

    if (response.statusCode == 401) {
      throw SessionExpiredException();
    }

    dynamic data;
    final raw = response.body.trim();
    if (raw.isNotEmpty) {
      try {
        data = jsonDecode(raw);
      } catch (_) {
        data = null;
      }
    }

    if (response.statusCode == 403) {
      throw ApiException(
        (data is Map && data['message'] is String)
            ? data['message'] as String
            : "You don't have access to this feature.",
        status: 403,
      );
    }

    if (response.statusCode >= 200 && response.statusCode < 300 && data != null) {
      return data;
    }

    throw ApiException(
      (data is Map && data['message'] is String)
          ? data['message'] as String
          : 'Server error (HTTP ${response.statusCode}). Please try again.',
      status: response.statusCode,
    );
  }

  // ---------------- session tracking (desktop User Monitoring) ----------------

  /// Keeps this device showing as online. Throws [SessionExpiredException] if
  /// the session was ended (for example by an administrator).
  static Future<void> heartbeat() => postJson('/api/Session/heartbeat');

  /// Tells the system which module the user is in: dashboard, delivery,
  /// products or settings.
  static Future<void> reportModule(String module) =>
      postJson('/api/Session/module', {'module': module});

  /// Best effort: closes the session on the server. Never throws.
  static Future<void> logout() async {
    try {
      await postJson('/api/Session/logout').timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  static Future<dynamic> postJson(String path, [Object? body]) =>
      _send('POST', path, body);

  static Future<dynamic> putJson(String path, [Object? body]) =>
      _send('PUT', path, body);

  static Future<dynamic> deleteJson(String path) => _send('DELETE', path, null);

  /// Authenticated POST / PUT / DELETE. Returns the decoded body (or null when
  /// the server sends none). Throws [SessionExpiredException] on 401 and
  /// [ApiException] (with the server's message and optional code) otherwise.
  static Future<dynamic> _send(String method, String path, Object? body) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${LocalStore.token ?? ''}',
    };
    const wait = Duration(seconds: 20);

    http.Response response;
    try {
      switch (method) {
        case 'POST':
          response = await http
              .post(uri, headers: headers, body: body == null ? null : jsonEncode(body))
              .timeout(wait);
          break;
        case 'PUT':
          response = await http
              .put(uri, headers: headers, body: body == null ? null : jsonEncode(body))
              .timeout(wait);
          break;
        default:
          response = await http.delete(uri, headers: headers).timeout(wait);
      }
    } on TimeoutException {
      throw ApiException(
          'Connection timed out. Please check your connection and try again.');
    } catch (_) {
      throw ApiException(
          'Cannot reach the server. Please check your connection and try again.');
    }

    if (response.statusCode == 401) {
      throw SessionExpiredException();
    }

    dynamic data;
    final raw = response.body.trim();
    if (raw.isNotEmpty) {
      try {
        data = jsonDecode(raw);
      } catch (_) {
        data = null;
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }

    throw ApiException(
      (data is Map && data['message'] is String)
          ? data['message'] as String
          : response.statusCode == 403
              ? "You don't have access to this feature."
              : 'Server error (HTTP ${response.statusCode}). Please try again.',
      code: (data is Map && data['code'] is String) ? data['code'] as String : null,
      status: response.statusCode,
    );
  }
}

enum AuthFailure { noAccess, invalidCredentials, network, server }

class AuthException implements Exception {
  final AuthFailure type;
  final String message;
  AuthException(this.type, this.message);

  @override
  String toString() => message;
}

class ApiException implements Exception {
  final String message;
  final String? code;
  final int? status;
  ApiException(this.message, {this.code, this.status});

  @override
  String toString() => message;
}

/// The saved token was rejected (expired or invalid). Sign in again.
class SessionExpiredException implements Exception {
  @override
  String toString() => 'Your session has expired. Please sign in again.';
}


class SavedServer {
  final String name;
  final String url;
  const SavedServer(this.name, this.url);

  factory SavedServer.fromJson(Map<String, dynamic> j) =>
      SavedServer((j['name'] ?? '').toString(), (j['url'] ?? '').toString());

  Map<String, dynamic> toJson() => {'name': name, 'url': url};
}

class ConnectionTestResult {
  final bool ok;
  final String message;
  const ConnectionTestResult(this.ok, this.message);
}