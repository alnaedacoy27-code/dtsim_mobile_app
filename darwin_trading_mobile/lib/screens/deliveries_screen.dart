import 'package:flutter/material.dart';
import '../models/delivery_models.dart';
import '../services/api_service.dart';
import '../services/live_sync.dart';
import '../services/session_guard.dart';
import 'delivery_detail_screen.dart';
import 'products_screen.dart' show formatMoney;

// deliveriesChanged now lives in live_sync.dart (re-exported so existing imports keep working)
export '../services/live_sync.dart' show deliveriesChanged;

/// Opens the "new draft" sheet, then the batch itself. Used by the Deliveries
/// tab and by the dashboard's quick action.
Future<void> createDeliveryDraft(BuildContext context) async {
  final id = await showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _NewDraftSheet(),
  );
  if (id == null || !context.mounted) return;

  deliveriesChanged.value++;
  await Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => DeliveryDetailScreen(batchId: id)),
  );
  deliveriesChanged.value++;
}

class DeliveriesScreen extends StatefulWidget {
  const DeliveriesScreen({super.key});
  @override
  State<DeliveriesScreen> createState() => _DeliveriesScreenState();
}

class _DeliveriesScreenState extends State<DeliveriesScreen> {
  List<DeliveryBatch> _batches = [];
  bool _loading = true;
  String? _error;
  String _filter = 'all'; // all | draft | sent
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    deliveriesChanged.addListener(_onChanged);
    _load();
  }

  @override
  void dispose() {
    deliveriesChanged.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => _load(showSpinner: false);

  Future<void> _load({bool showSpinner = true}) async {
    final id = ++_requestId;
    if (showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final data =
          await ApiService.getJson('/api/Deliveries', query: {'filter': _filter});
      if (!mounted || id != _requestId) return;
      setState(() {
        _batches = (data as List)
            .map((e) => DeliveryBatch.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
        _loading = false;
        _error = null;
      });
    } on SessionExpiredException {
      if (mounted) handleSessionExpired(context);
    } on ApiException catch (e) {
      if (!mounted || id != _requestId) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted || id != _requestId) return;
      setState(() {
        _loading = false;
        _error = 'Something went wrong. Please try again.';
      });
    }
  }

  void _setFilter(String value) {
    if (_filter == value) return;
    _filter = value;
    _load();
  }

  Future<void> _open(DeliveryBatch b) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DeliveryDetailScreen(batchId: b.id)),
    );
    deliveriesChanged.value++;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Deliveries',
            style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => createDeliveryDraft(context),
        icon: const Icon(Icons.add),
        label: const Text('New draft'),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 4),
              children: [
                _chip('All', 'all'),
                _chip('Drafts', 'draft'),
                _chip('Sent', 'sent'),
              ],
            ),
          ),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _chip(String label, String value) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: _filter == value,
          onSelected: (_) => _setFilter(value),
        ),
      );

  Widget _buildList() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(30),
        children: [
          const SizedBox(height: 30),
          const Icon(Icons.cloud_off_outlined,
              size: 48, color: Color(0xFFB5C0CC)),
          const SizedBox(height: 12),
          Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF526579))),
          const SizedBox(height: 16),
          Center(
            child: OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(showSpinner: false),
      child: _batches.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 60),
                  child: Column(children: [
                    const Icon(Icons.inventory_outlined,
                        size: 48, color: Color(0xFFB5C0CC)),
                    const SizedBox(height: 12),
                    Text(
                      _filter == 'draft'
                          ? 'No delivery drafts yet'
                          : _filter == 'sent'
                              ? 'No sent deliveries yet'
                              : 'No deliveries yet',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF526579)),
                    ),
                    const SizedBox(height: 5),
                    const Text('Tap “New draft” to record an incoming delivery.',
                        style:
                            TextStyle(color: Color(0xFF8290A0), fontSize: 12)),
                  ]),
                ),
              ],
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 90),
              itemCount: _batches.length,
              itemBuilder: (_, i) => _batchCard(_batches[i]),
            ),
    );
  }

  Widget _batchCard(DeliveryBatch b) {
    final color = b.isDraft ? const Color(0xFFD58A20) : const Color(0xFF159477);

    return Card(
      child: ListTile(
        onTap: () => _open(b),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        leading: CircleAvatar(
          backgroundColor: color.withAlpha(30),
          child: Icon(Icons.local_shipping_outlined, color: color),
        ),
        title: Text(b.companyName,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          '${b.batchNo}  ·  ${fmtDate(b.deliveryDate)}\n'
          '${b.itemCount} item${b.itemCount == 1 ? '' : 's'}  ·  ₱${formatMoney(b.totalCost)}',
        ),
        isThreeLine: true,
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withAlpha(30),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(b.isDraft ? 'DRAFT' : 'SENT',
              style: TextStyle(
                  color: color, fontSize: 10, fontWeight: FontWeight.w800)),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// New draft: pick a supplier from the database and a delivery date
// ---------------------------------------------------------------------------
class _NewDraftSheet extends StatefulWidget {
  const _NewDraftSheet();
  @override
  State<_NewDraftSheet> createState() => _NewDraftSheetState();
}

class _NewDraftSheetState extends State<_NewDraftSheet> {
  List<Supplier> _suppliers = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;
  int? _supplierId;
  DateTime _date = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
  }

  Future<void> _loadSuppliers() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await ApiService.getJson('/api/Deliveries/suppliers');
      if (!mounted) return;
      setState(() {
        _suppliers = (data as List)
            .map((e) => Supplier.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
        _loading = false;
      });
    } on SessionExpiredException {
      if (mounted) {
        Navigator.pop(context);
        handleSessionExpired(context);
      }
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

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year, now.month, now.day), // no future dates
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _create() async {
    if (_supplierId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Choose a supplier.')));
      return;
    }

    setState(() => _saving = true);
    try {
      final data = await ApiService.postJson('/api/Deliveries', {
        'supplierId': _supplierId,
        'deliveryDate':
            DateTime(_date.year, _date.month, _date.day).toIso8601String(),
      });
      final id = ((data as Map)['id'] as num).toInt();
      if (mounted) Navigator.pop(context, id);
    } on SessionExpiredException {
      if (mounted) {
        Navigator.pop(context);
        handleSessionExpired(context);
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Something went wrong. Please try again.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 4, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('New delivery draft',
              style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF142D4E))),
          const SizedBox(height: 4),
          const Text('Choose the supplier and the delivery date.',
              style: TextStyle(color: Color(0xFF718096), fontSize: 13)),
          const SizedBox(height: 18),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Column(children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _loadSuppliers,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ])
          else if (_suppliers.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'No suppliers found. Add a supplier in the main system first.',
                textAlign: TextAlign.center,
              ),
            )
          else ...[
            DropdownButtonFormField<int>(
              value: _supplierId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Supplier',
                prefixIcon: Icon(Icons.store_outlined),
              ),
              items: _suppliers
                  .map((s) => DropdownMenuItem<int>(
                        value: s.id,
                        child: Text(s.label, overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _supplierId = v),
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Delivery date',
                  prefixIcon: Icon(Icons.event_outlined),
                ),
                child: Text(fmtDate(_date)),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _saving ? null : _create,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_outlined),
              label: const Text('Create draft'),
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
            ),
          ],
        ],
      ),
    );
  }
}