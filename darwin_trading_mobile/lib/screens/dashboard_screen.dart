import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/brand.dart';
import '../services/local_store.dart';
import '../services/session_guard.dart';
import '../services/live_sync.dart';
import 'deliveries_screen.dart' show createDeliveryDraft;

/// Home: the same look as the desktop's (maroon, "Welcome back", role and date), with the live figures.
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

  int _n(String key) => (_data?[key] as num?)?.toInt() ?? 0;
  String _value(String key) => _data == null ? '–' : '${_n(key)}';

  static String _time(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
  }

  static String _greeting(DateTime d) =>
      d.hour < 12 ? 'GOOD MORNING' : (d.hour < 18 ? 'GOOD AFTERNOON' : 'GOOD EVENING');

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final failed = _error != null;
    final statusText = failed
        ? _error!
        : (_loading && _data == null)
            ? 'Connecting to the system…'
            : 'Live from the system · updated ${_updated == null ? '' : _time(_updated!)}';
    final role = Brand.roleText(LocalStore.role);
    final low = _n('lowStock');

    return Scaffold(
      backgroundColor: Brand.background,
      appBar: AppBar(
        title: const Text('Dashboard', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [IconButton(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: RefreshIndicator(
        color: Brand.maroon,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
          children: [
            // ---- welcome card, like the desktop's maroon panel
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Brand.maroon, Brand.maroonLight],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(children: [
                  const Positioned.fill(child: CustomPaint(painter: BrandCircles())),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_greeting(now),
                          style: const TextStyle(color: Brand.onMaroonSoft, fontSize: 11, letterSpacing: 1.8, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text('Welcome back, ${LocalStore.displayName}',
                          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Text(role.isEmpty ? Brand.longDate(now) : '$role  |  ${Brand.longDate(now)}',
                          style: const TextStyle(color: Brand.onMaroonSoft, fontSize: 13)),
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                        decoration: BoxDecoration(color: Colors.black.withAlpha(30), borderRadius: BorderRadius.circular(12)),
                        child: Row(children: [
                          Icon(failed ? Icons.cloud_off_outlined : Icons.cloud_done_outlined, color: Colors.white70, size: 17),
                          const SizedBox(width: 7),
                          Expanded(child: Text(statusText, style: const TextStyle(color: Colors.white70, fontSize: 12))),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: failed ? Colors.white.withAlpha(40) : Colors.white,
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              if (!failed) ...[
                                Container(width: 6, height: 6, decoration: const BoxDecoration(color: Brand.green, shape: BoxShape.circle)),
                                const SizedBox(width: 5),
                              ],
                              Text(failed ? 'OFFLINE' : 'LIVE',
                                  style: TextStyle(
                                      color: failed ? Colors.white : Brand.maroon, fontSize: 10, fontWeight: FontWeight.w800)),
                            ]),
                          ),
                        ]),
                      ),
                    ]),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 22),
            const _SectionTitle('Overview'),
            const SizedBox(height: 10),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.5,
              children: [
                _MetricCard(title: 'Products', value: _value('products'), icon: Icons.inventory_2_outlined,
                    tint: Brand.maroonTint, color: Brand.maroon),
                _MetricCard(title: 'Low stock', value: _value('lowStock'), icon: Icons.warning_amber_rounded,
                    tint: low > 0 ? Brand.alertBack : const Color(0xFFF1F1F2),
                    color: low > 0 ? Brand.alert : Brand.muted,
                    note: _data == null ? null : (low > 0 ? 'Restock' : 'All good')),
                _MetricCard(title: 'Deliveries today', value: _value('deliveriesToday'), icon: Icons.local_shipping_outlined,
                    tint: const Color(0xFFE9F5EE), color: Brand.green),
                _MetricCard(title: 'Delivery drafts', value: _value('drafts'), icon: Icons.edit_note_rounded,
                    tint: const Color(0xFFFFF4E5), color: const Color(0xFFB7791F),
                    note: _data == null || _n('drafts') == 0 ? null : 'Not sent yet'),
              ],
            ),
            const SizedBox(height: 22),
            const _SectionTitle('Quick actions'),
            const SizedBox(height: 10),
            _ActionTile(icon: Icons.add_box_outlined, title: 'Create delivery draft', subtitle: 'Record the items a supplier brought',
                onTap: () => createDeliveryDraft(context)),
            const SizedBox(height: 10),
            const _ActionTile(icon: Icons.qr_code_scanner, title: 'Scan a barcode', subtitle: 'Use the scan button on the Products tab', onTap: null),
            const SizedBox(height: 10),
            _ActionTile(icon: Icons.sync_rounded, title: 'Sync status',
                subtitle: failed ? 'Last attempt failed. Tap to retry' : 'Tap to refresh now', onTap: _load),
          ],
        ),
      ),
    );
  }
}

/// A section title in maroon, like the group headers on the desktop's home screen.
class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Row(children: [
        Container(width: 4, height: 18, decoration: BoxDecoration(color: Brand.maroon, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Brand.maroon)),
      ]);
}

class _MetricCard extends StatelessWidget {
  final String title, value;
  final String? note;
  final IconData icon;
  final Color tint, color;
  const _MetricCard({required this.title, required this.value, required this.icon, required this.tint, required this.color, this.note});
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(children: [
              Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, color: color, size: 19)),
              const Spacer(),
              if (note != null)
                Flexible(
                  child: Text(note!,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10.5, color: color, fontWeight: FontWeight.w600)),
                ),
            ]),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Brand.ink)),
              Text(title, style: const TextStyle(fontSize: 12, color: Brand.muted)),
            ]),
          ]),
        ),
      );
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final VoidCallback? onTap;
  const _ActionTile({required this.icon, required this.title, required this.subtitle, required this.onTap});
  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 7),
          leading: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: Brand.maroonTint, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: Brand.maroon)),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: Brand.ink)),
          subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: Brand.muted)),
          trailing: onTap == null ? null : const Icon(Icons.chevron_right, color: Color(0xFFB0B4B8)),
          onTap: onTap,
        ),
      );
}
