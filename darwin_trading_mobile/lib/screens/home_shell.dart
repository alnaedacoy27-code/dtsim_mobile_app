import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/live_sync.dart';
import '../services/local_store.dart';
import '../services/session_guard.dart';
import 'dashboard_screen.dart';
import 'deliveries_screen.dart';
import 'products_screen.dart';
import 'settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _Tab {
  final String key; // sent to the server so the desktop shows where the user is
  final Widget page;
  final NavigationDestination destination;
  const _Tab(this.key, this.page, this.destination);
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;
  Timer? _heartbeat;

  List<_Tab> _tabs() {
    final permissions = LocalStore.permissions;
    final tabs = <_Tab>[];

    if (permissions['dashboard'] == true) {
      tabs.add(const _Tab(
        'dashboard',
        DashboardScreen(),
        NavigationDestination(
          icon: Icon(Icons.dashboard_outlined),
          selectedIcon: Icon(Icons.dashboard),
          label: 'Home',
        ),
      ));
    }

    if (permissions['delivery'] == true) {
      tabs.add(const _Tab(
        'delivery',
        DeliveriesScreen(),
        NavigationDestination(
          icon: Icon(Icons.local_shipping_outlined),
          selectedIcon: Icon(Icons.local_shipping),
          label: 'Deliveries',
        ),
      ));
    }

    if (permissions['products'] == true) {
      tabs.add(const _Tab(
        'products',
        ProductsScreen(),
        NavigationDestination(
          icon: Icon(Icons.inventory_2_outlined),
          selectedIcon: Icon(Icons.inventory_2),
          label: 'Products',
        ),
      ));
    }

    // Settings is always available
    tabs.add(const _Tab(
      'settings',
      SettingsScreen(),
      NavigationDestination(
        icon: Icon(Icons.settings_outlined),
        selectedIcon: Icon(Icons.settings),
        label: 'Settings',
      ),
    ));

    return tabs;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _heartbeat = Timer.periodic(const Duration(seconds: 60), (_) => _ping());
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportCurrent());
    _startLive();
  }

  void _startLive() => LiveSync.start(
        onSessionExpired: () {
          if (mounted) handleSessionExpired(context);
        },
      );

  @override
  void dispose() {
    _heartbeat?.cancel();
    LiveSync.reset();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Coming back to the app: say we are here again and where.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reportCurrent();
      _startLive();
    } else if (state == AppLifecycleState.paused) {
      LiveSync.stop();
    }
  }

  Future<void> _ping() => _safe(ApiService.heartbeat);

  Future<void> _reportCurrent() {
    final tabs = _tabs();
    final i = _index < tabs.length ? _index : 0;
    return _safe(() => ApiService.reportModule(tabs[i].key));
  }

  // Monitoring must never get in the user's way, except to sign them out
  // when an administrator ended their session.
  Future<void> _safe(Future<void> Function() call) async {
    try {
      await call();
    } on SessionExpiredException {
      if (mounted) handleSessionExpired(context);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs();
    final selectedIndex = _index < tabs.length ? _index : 0;

    return Scaffold(
      body: IndexedStack(
        index: selectedIndex,
        children: tabs.map((t) => t.page).toList(),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (value) {
          setState(() => _index = value);
          _safe(() => ApiService.reportModule(tabs[value].key));
        },
        destinations: tabs.map((t) => t.destination).toList(),
      ),
    );
  }
}