import 'dart:async';
import 'package:flutter/foundation.dart';
import 'api_service.dart';

/// Bumped when products, categories or stock change in the system.
final ValueNotifier<int> productsChanged = ValueNotifier<int>(0);

/// Bumped when delivery batches or their items change in the system.
final ValueNotifier<int> deliveriesChanged = ValueNotifier<int>(0);

/// Bumped when suppliers are added or edited (on the phone or the desktop).
final ValueNotifier<int> suppliersChanged = ValueNotifier<int>(0);

/// Asks the server every few seconds whether anything changed (for example
/// something done on the desktop) and tells the screens to reload only then.
class LiveSync {
  static const _interval = Duration(seconds: 5);

  static Timer? _timer;
  static String? _products;
  static String? _deliveries;
  static String? _suppliers;
  static bool _busy = false;
  static VoidCallback? _onSessionExpired;

  static void start({required VoidCallback onSessionExpired}) {
    _onSessionExpired = onSessionExpired;
    _timer?.cancel();
    _poll();
    _timer = Timer.periodic(_interval, (_) => _poll());
  }

  /// Pause (app in the background). Keeps the last stamp so changes that
  /// happened meanwhile are noticed when polling resumes.
  static void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Stop and forget everything (sign out).
  static void reset() {
    stop();
    _products = null;
    _deliveries = null;
    _suppliers = null;
  }

  static Future<void> _poll() async {
    if (_busy) return;
    _busy = true;
    try {
      final data = await ApiService.getJson('/api/Live/stamp') as Map;
      final p = data['products']?.toString();
      final d = data['deliveries']?.toString();
      final s = data['suppliers']?.toString();

      if (_products != null && p != _products) productsChanged.value++;
      if (_deliveries != null && d != _deliveries) deliveriesChanged.value++;
      if (_suppliers != null && s != _suppliers) suppliersChanged.value++;

      _products = p;
      _deliveries = d;
      _suppliers = s;
    } on SessionExpiredException {
      stop();
      _onSessionExpired?.call();
    } catch (_) {
      // Offline or server busy: try again at the next tick.
    } finally {
      _busy = false;
    }
  }
}