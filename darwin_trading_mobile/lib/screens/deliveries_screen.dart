import 'package:flutter/material.dart';
import '../services/local_store.dart';

class DeliveriesScreen extends StatefulWidget {
  const DeliveriesScreen({super.key});
  @override
  State<DeliveriesScreen> createState() => _DeliveriesScreenState();
}
class _DeliveriesScreenState extends State<DeliveriesScreen> {
  Future<void> _newDraft() async {
    final supplier = TextEditingController();
    final ref = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('New delivery draft'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: supplier, decoration: const InputDecoration(labelText: 'Supplier')),
        const SizedBox(height: 10),
        TextField(controller: ref, decoration: const InputDecoration(labelText: 'Invoice / reference')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save draft'))],
    ));
    if (ok == true && supplier.text.trim().isNotEmpty) {
      await LocalStore.saveDraft({'supplier': supplier.text.trim(), 'reference': ref.text.trim(), 'createdAt': DateTime.now().toIso8601String(), 'status': 'Draft'});
      if (mounted) setState(() {});
    }
    supplier.dispose(); ref.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final drafts = LocalStore.drafts;
    return Scaffold(
      appBar: AppBar(title: const Text('Deliveries', style: TextStyle(fontWeight: FontWeight.w800))),
      floatingActionButton: FloatingActionButton.extended(onPressed: _newDraft, icon: const Icon(Icons.add), label: const Text('New draft')),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFFEAF3FB), borderRadius: BorderRadius.circular(16)), child: const Row(children: [
          Icon(Icons.offline_pin_outlined, color: Color(0xFF1769AA), size: 28), SizedBox(width: 12),
          Expanded(child: Text('Drafts are stored on this device. Posting to inventory will require a live API connection.', style: TextStyle(color: Color(0xFF34516D), fontSize: 13))),
        ])),
        const SizedBox(height: 20),
        const Text('Saved drafts', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Color(0xFF142D4E))),
        const SizedBox(height: 10),
        if (drafts.isEmpty)
          const Padding(padding: EdgeInsets.only(top: 42), child: Column(children: [Icon(Icons.inventory_outlined, size: 48, color: Color(0xFFB5C0CC)), SizedBox(height: 12), Text('No delivery drafts yet', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF526579))), SizedBox(height: 5), Text('Tap “New draft” to record an incoming delivery.', style: TextStyle(color: Color(0xFF8290A0), fontSize: 12))]))
        else
          ...drafts.asMap().entries.map((entry) {
            final d = entry.value;
            return Card(child: ListTile(
              leading: const CircleAvatar(backgroundColor: Color(0xFFEAF3FB), child: Icon(Icons.local_shipping_outlined, color: Color(0xFF1769AA))),
              title: Text((d['supplier'] ?? 'Supplier').toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('Ref: ${(d['reference'] ?? '—')}  ·  ${(d['createdAt'] ?? '').toString().split('T').first}'),
              trailing: PopupMenuButton<String>(onSelected: (v) async { if (v == 'delete') { await LocalStore.removeDraft(entry.key); setState(() {}); } }, itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Delete draft'))]),
            ));
          }),
      ]),
    );
  }
}
