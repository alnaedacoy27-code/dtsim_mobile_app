import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/local_store.dart';
import '../services/session_guard.dart';
import '../services/live_sync.dart';
import 'deliveries_screen.dart' show createDeliveryDraft;

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  DateTime? _updated;

  @override
  void initState() {
    super.initState();
    deliveriesChanged.addListener(_refreshQuietly);
    productsChanged.addListener(_refreshQuietly);
    _load();
  }

  @override
  void dispose() {
    deliveriesChanged.removeListener(_refreshQuietly);
    productsChanged.removeListener(_refreshQuietly);
    super.dispose();
  }

  void _refreshQuietly() => _load();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await ApiService.getJson('/api/Dashboard/summary');
      if (!mounted) return;
      setState(() {
        _data = (data as Map).cast<String, dynamic>();
        _updated = DateTime.now();
        _loading = false;
      });
    } on SessionExpiredException {
      if (mounted) handleSessionExpired(context);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Something went wrong. Please try again.';
      });
    }
  }

  String _value(String key) =>
      _data == null ? '–' : '${(_data![key] as num?)?.toInt() ?? 0}';

  String _time(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final failed = _error != null;
    final statusText = failed
        ? _error!
        : (_loading && _data == null)
            ? 'Connecting to live inventory…'
            : 'Live data · updated ${_updated == null ? '' : _time(_updated!)}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF153B63), Color(0xFF1769AA)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('GOOD DAY', style: TextStyle(color: Color(0xFFB8D7F3), fontSize: 11, letterSpacing: 1.8, fontWeight: FontWeight.w700)),
                const SizedBox(height: 7),
                Text(LocalStore.displayName, style: const TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                const Text('Here is your store activity at a glance.', style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 20),
                Row(children: [
                  Icon(failed ? Icons.cloud_off_outlined : Icons.cloud_done_outlined, color: Colors.white70, size: 17),
                  const SizedBox(width: 7),
                  Expanded(child: Text(statusText, style: const TextStyle(color: Colors.white70, fontSize: 12))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: Colors.white.withAlpha(40), borderRadius: BorderRadius.circular(30)),
                    child: Text(failed ? 'OFFLINE' : 'LIVE', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ]),
              ]),
            ),
            const SizedBox(height: 20),
            const Text('Overview', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF142D4E))),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.55,
              children: [
                _MetricCard(title: 'Products', value: _value('products'), icon: Icons.inventory_2_outlined, tint: const Color(0xFFE8F2FC), color: const Color(0xFF1769AA)),
                _MetricCard(title: 'Low stock', value: _value('lowStock'), icon: Icons.warning_amber_rounded, tint: const Color(0xFFFFF4E5), color: const Color(0xFFE59A25)),
                _MetricCard(title: 'Deliveries today', value: _value('deliveriesToday'), icon: Icons.local_shipping_outlined, tint: const Color(0xFFE7F7F4), color: const Color(0xFF149A87)),
                _MetricCard(title: 'Delivery drafts', value: _value('drafts'), icon: Icons.save_outlined, tint: const Color(0xFFF0ECFF), color: const Color(0xFF7657C8)),
              ],
            ),
            const SizedBox(height: 22),
            const Text('Quick actions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF142D4E))),
            const SizedBox(height: 12),
            _ActionTile(icon: Icons.add_box_outlined, title: 'Create delivery draft', subtitle: 'Record incoming items', onTap: () => createDeliveryDraft(context)),
            const SizedBox(height: 10),
            const _ActionTile(icon: Icons.qr_code_scanner, title: 'Scan a barcode', subtitle: 'Use the scan button on the Inventory tab', onTap: null),
            const SizedBox(height: 10),
            _ActionTile(icon: Icons.sync_rounded, title: 'Sync status', subtitle: failed ? 'Last attempt failed. Tap to retry' : 'Tap to refresh now', onTap: _load),
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title, value;
  final IconData icon;
  final Color tint, color;
  const _MetricCard({required this.title, required this.value, required this.icon, required this.tint, required this.color});
  @override
  Widget build(BuildContext context) => Card(child: Padding(
    padding: const EdgeInsets.all(15),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Container(width: 34, height: 34, decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: color, size: 19)),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800, color: Color(0xFF142D4E))),
        Text(title, style: const TextStyle(fontSize: 12, color: Color(0xFF718096))),
      ]),
    ]),
  ));
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final VoidCallback? onTap;
  const _ActionTile({required this.icon, required this.title, required this.subtitle, required this.onTap});
  @override
  Widget build(BuildContext context) => Card(child: ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 7),
    leading: Container(width: 42, height: 42, decoration: BoxDecoration(color: const Color(0xFFEAF3FB), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: const Color(0xFF1769AA))),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF243B53))),
    subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
    trailing: const Icon(Icons.chevron_right, color: Color(0xFF9AA7B5)),
    onTap: onTap,
  ));
}