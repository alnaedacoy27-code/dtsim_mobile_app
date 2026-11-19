import 'package:flutter/material.dart';
import '../services/local_store.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final drafts = LocalStore.drafts.length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [IconButton(onPressed: () {}, icon: const Icon(Icons.notifications_none_rounded))],
      ),
      body: ListView(
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
                const Icon(Icons.cloud_off_outlined, color: Colors.white70, size: 17),
                const SizedBox(width: 7),
                const Expanded(child: Text('Preview mode · not connected to live inventory', style: TextStyle(color: Colors.white70, fontSize: 12))),
                Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: Colors.white.withOpacity(.15), borderRadius: BorderRadius.circular(30)), child: const Text('DEMO', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))),
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
              _MetricCard(title: 'Products', value: '248', icon: Icons.inventory_2_outlined, tint: const Color(0xFFE8F2FC), color: const Color(0xFF1769AA)),
              _MetricCard(title: 'Low stock', value: '12', icon: Icons.warning_amber_rounded, tint: const Color(0xFFFFF4E5), color: const Color(0xFFE59A25)),
              _MetricCard(title: 'Deliveries today', value: '6', icon: Icons.local_shipping_outlined, tint: const Color(0xFFE7F7F4), color: const Color(0xFF149A87)),
              _MetricCard(title: 'Saved drafts', value: '$drafts', icon: Icons.save_outlined, tint: const Color(0xFFF0ECFF), color: const Color(0xFF7657C8)),
            ],
          ),
          const SizedBox(height: 22),
          const Text('Quick actions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF142D4E))),
          const SizedBox(height: 12),
          _ActionTile(icon: Icons.add_box_outlined, title: 'Create delivery draft', subtitle: 'Record incoming items offline', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _QuickDraftPage()))),
          const SizedBox(height: 10),
          const _ActionTile(icon: Icons.qr_code_scanner, title: 'Scan a barcode', subtitle: 'Barcode scanning will be enabled in the product workflow', onTap: null),
          const SizedBox(height: 10),
          const _ActionTile(icon: Icons.sync_rounded, title: 'Sync status', subtitle: 'Connect the API to enable synchronization', onTap: null),
        ],
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

class _QuickDraftPage extends StatefulWidget {
  const _QuickDraftPage();
  @override
  State<_QuickDraftPage> createState() => _QuickDraftPageState();
}
class _QuickDraftPageState extends State<_QuickDraftPage> {
  final _supplier = TextEditingController();
  final _reference = TextEditingController();
  @override
  void dispose() { _supplier.dispose(); _reference.dispose(); super.dispose(); }
  Future<void> _save() async {
    if (_supplier.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a supplier name.')));
      return;
    }
    await LocalStore.saveDraft({'supplier': _supplier.text.trim(), 'reference': _reference.text.trim(), 'createdAt': DateTime.now().toIso8601String(), 'status': 'Draft'});
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Delivery draft saved on this device.')));
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('New delivery draft')),
    body: ListView(padding: const EdgeInsets.all(18), children: [
      const Text('Save a draft even when the store connection is unavailable.', style: TextStyle(color: Color(0xFF718096))),
      const SizedBox(height: 18),
      TextField(controller: _supplier, decoration: const InputDecoration(labelText: 'Supplier name', prefixIcon: Icon(Icons.store_outlined))),
      const SizedBox(height: 14),
      TextField(controller: _reference, decoration: const InputDecoration(labelText: 'Invoice / reference number', prefixIcon: Icon(Icons.receipt_long_outlined))),
      const SizedBox(height: 22),
      FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_outlined), label: const Text('Save draft'), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52))),
    ]),
  );
}
