import 'package:flutter/material.dart';
import '../models/supplier_models.dart';
import '../services/api_service.dart';
import '../services/contact_actions.dart';
import '../services/live_sync.dart' show suppliersChanged;
import '../services/session_guard.dart';
import 'supplier_form_screen.dart';

/// One supplier: the contact person with Call / Text / Email / Copy, the address with Maps,
/// and the last deliveries. Edit from the app bar.
class SupplierDetailScreen extends StatefulWidget {
  final int supplierId;
  final Supplier? initial;
  const SupplierDetailScreen({super.key, required this.supplierId, this.initial});

  @override
  State<SupplierDetailScreen> createState() => _SupplierDetailScreenState();
}

class _SupplierDetailScreenState extends State<SupplierDetailScreen> {
  SupplierDetail? _detail;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) _detail = SupplierDetail(widget.initial!, const []);
    suppliersChanged.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    suppliersChanged.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await ApiService.getJson('/api/Suppliers/${widget.supplierId}');
      if (!mounted) return;
      setState(() {
        _detail = SupplierDetail.fromJson((data as Map).cast<String, dynamic>());
        _loading = false;
        _error = null;
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

  Future<void> _edit() async {
    final d = _detail;
    if (d == null) return;
    final saved = await Navigator.push<SupplierDetail>(
      context,
      MaterialPageRoute(builder: (_) => SupplierFormScreen(supplier: d.supplier)),
    );
    if (saved == null || !mounted) return;
    setState(() => _detail = saved);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Supplier saved.')));
  }

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    return Scaffold(
      appBar: AppBar(
        title: Text(d?.supplier.companyName ?? 'Supplier'),
        actions: [
          if (d != null) IconButton(tooltip: 'Edit', onPressed: _edit, icon: const Icon(Icons.edit_outlined)),
        ],
      ),
      body: d == null
          ? Center(
              child: _loading
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(30),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(_error ?? 'Could not load this supplier.', textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Try again')),
                      ]),
                    ),
            )
          : RefreshIndicator(onRefresh: _load, child: _body(d)),
    );
  }

  Widget _body(SupplierDetail d) {
    final s = d.supplier;
    final maroon = Theme.of(context).colorScheme.primary;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(18),
      children: [
        // ---- contact person
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('CONTACT PERSON', style: TextStyle(fontSize: 11, letterSpacing: .6, color: Color(0xFF6B7785))),
                const SizedBox(height: 6),
                Text(s.contactPerson, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                if (s.hasNumber) ...[
                  const SizedBox(height: 2),
                  Text(formatMobile(s.contactNumber), style: const TextStyle(fontSize: 16)),
                ],
                if (s.hasEmail) ...[
                  const SizedBox(height: 2),
                  Text(s.email!, style: const TextStyle(color: Color(0xFF526579))),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    _action(Icons.call, 'Call', s.hasNumber ? () => ContactActions.call(context, s.contactNumber!) : null),
                    _action(Icons.sms_outlined, 'Text',
                        s.hasNumber
                            ? () => ContactActions.text(context, s.contactNumber!,
                                message: 'Hi ${s.contactPerson}, this is Darwin Trading. ')
                            : null),
                    _action(Icons.email_outlined, 'Email',
                        s.hasEmail ? () => ContactActions.email(context, s.email!, subject: 'Darwin Trading') : null),
                    _action(Icons.copy_rounded, 'Copy no.',
                        s.hasNumber ? () => ContactActions.copy(context, s.contactNumber!, 'Number') : null),
                  ],
                ),
                if (!s.hasEmail)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('No email saved. Add one with Edit to send emails.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF8290A0))),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // ---- address
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            leading: Icon(Icons.place_outlined, color: maroon),
            title: Text(s.address),
            subtitle: Text(s.branches > 1 ? '${s.branches} branches of ${s.companyName}' : 'This branch'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(tooltip: 'Copy address', icon: const Icon(Icons.copy_rounded),
                  onPressed: () => ContactActions.copy(context, s.address, 'Address')),
              IconButton(tooltip: 'Open in Maps', icon: Icon(Icons.map_outlined, color: maroon),
                  onPressed: () => ContactActions.map(context, '${s.companyName}, ${s.address}')),
            ]),
          ),
        ),
        const SizedBox(height: 18),

        // ---- deliveries
        Text(
          s.deliveries == 0
              ? 'No deliveries from this supplier yet'
              : 'Deliveries (${s.deliveries})${s.lastDelivery != null ? ' · last ${formatDay(s.lastDelivery!)}' : ''}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        ...d.recentDeliveries.map((x) => Card(
              child: ListTile(
                leading: Icon(x.status == 'sent' ? Icons.check_circle_outline : Icons.edit_note,
                    color: x.status == 'sent' ? const Color(0xFF159477) : const Color(0xFFD58A20)),
                title: Text(x.batchNo, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('${formatDay(x.deliveryDate)} · ${x.items} item${x.items == 1 ? '' : 's'}'),
                trailing: Text(x.status == 'sent' ? 'Received' : 'Draft',
                    style: TextStyle(color: x.status == 'sent' ? const Color(0xFF159477) : const Color(0xFFD58A20))),
              ),
            )),
      ],
    );
  }

  Widget _action(IconData icon, String label, VoidCallback? onTap) {
    final maroon = Theme.of(context).colorScheme.primary;
    final enabled = onTap != null;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: enabled ? maroon.withAlpha(24) : const Color(0xFFF0F0F2),
              child: Icon(icon, color: enabled ? maroon : const Color(0xFFB5BCC4)),
            ),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(fontSize: 12, color: enabled ? null : const Color(0xFFB5BCC4))),
          ]),
        ),
      ),
    );
  }
}
