import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/delivery_models.dart';
import '../models/inventory_models.dart';
import '../services/api_service.dart';
import '../services/session_guard.dart';
import '../services/live_sync.dart' show deliveriesChanged;
import 'products_screen.dart' show formatMoney;

const _ink = Color(0xFF181C20);

class DeliveryDetailScreen extends StatefulWidget {
  final int batchId;
  const DeliveryDetailScreen({super.key, required this.batchId});

  @override
  State<DeliveryDetailScreen> createState() => _DeliveryDetailScreenState();
}

class _DeliveryDetailScreenState extends State<DeliveryDetailScreen> {
  BatchDetail? _b;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    deliveriesChanged.addListener(_onRemoteChange);
    _load();
  }

  @override
  void dispose() {
    deliveriesChanged.removeListener(_onRemoteChange);
    super.dispose();
  }

  void _onRemoteChange() {
    if (!_busy) _load(showSpinner: false);
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _load({bool showSpinner = true}) async {
    if (showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final data = await ApiService.getJson('/api/Deliveries/${widget.batchId}');
      if (!mounted) return;
      setState(() {
        _b = BatchDetail.fromJson((data as Map).cast<String, dynamic>());
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

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on SessionExpiredException {
      if (mounted) handleSessionExpired(context);
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String message, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _addItem() async {
    final product = await Navigator.push<Product>(
      context,
      MaterialPageRoute(builder: (_) => const _ProductPickerPage()),
    );
    if (product == null || !mounted) return;

    // Already in this batch? Open that line instead, like the desktop does, so
    // picking the item again never replaces its quantity without showing it.
    final already = _b?.items.where((i) => i.productId == product.id).firstOrNull;
    if (already != null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('This item is already in the batch. Update its line.')));
      return _editItem(already);
    }

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ItemSheet(
        batchId: widget.batchId,
        productId: product.id,
        title: product.measurement.isEmpty
            ? product.name
            : '${product.name} · ${product.measurement}',
        defaultPrice: product.sellingPrice,
      ),
    );
    if (saved == true) {
      deliveriesChanged.value++;
      _load(showSpinner: false);
    }
  }

  Future<void> _editItem(DeliveryItem item) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ItemSheet(
        batchId: widget.batchId,
        productId: item.productId,
        title: item.title,
        existing: item,
      ),
    );
    if (saved == true) {
      deliveriesChanged.value++;
      _load(showSpinner: false);
    }
  }

  Future<void> _removeItem(DeliveryItem item) async {
    if (!await _confirm('Remove item', 'Remove ${item.title} from this batch?',
        'Remove')) {
      return;
    }
    await _run(() async {
      await ApiService.deleteJson(
          '/api/Deliveries/${widget.batchId}/items/${item.id}');
      deliveriesChanged.value++;
      await _load(showSpinner: false);
    });
  }

  Future<void> _send() async {
    final b = _b!;
    if (!await _confirm(
      'Send to inventory',
      'This adds ${b.items.length} item${b.items.length == 1 ? '' : 's'} '
          'to your stock and locks the batch. This cannot be undone.',
      'Send',
    )) {
      return;
    }
    await _run(() async {
      await ApiService.postJson('/api/Deliveries/${widget.batchId}/send');
      deliveriesChanged.value++;
      _toast('Batch sent to inventory.');
      await _load(showSpinner: false);
    });
  }

  Future<void> _deleteDraft() async {
    if (!await _confirm('Delete draft',
        'Delete this draft batch and everything in it?', 'Delete')) {
      return;
    }
    await _run(() async {
      await ApiService.deleteJson('/api/Deliveries/${widget.batchId}');
      deliveriesChanged.value++;
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final b = _b;

    return Scaffold(
      appBar: AppBar(
        title: Text(b?.batchNo ?? 'Delivery'),
        actions: [
          if (b != null && b.isDraft)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'delete') _deleteDraft();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'delete', child: Text('Delete draft')),
              ],
            ),
        ],
      ),
      bottomNavigationBar: (b != null && b.isDraft)
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _addItem,
                      icon: const Icon(Icons.add),
                      label: const Text('Add item'),
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: (_busy || b.items.isEmpty) ? null : _send,
                      icon: const Icon(Icons.send_outlined),
                      label: const Text('Send'),
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50)),
                    ),
                  ),
                ]),
              ),
            )
          : null,
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null || _b == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error ?? 'Batch not found.', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ]),
        ),
      );
    }

    final b = _b!;
    final color = b.isDraft ? const Color(0xFFD58A20) : const Color(0xFF159477);

    return RefreshIndicator(
      onRefresh: () => _load(showSpinner: false),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(18),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(b.companyName,
                          style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: _ink)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: color.withAlpha(30),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(b.isDraft ? 'DRAFT' : 'SENT',
                          style: TextStyle(
                              color: color,
                              fontSize: 10,
                              fontWeight: FontWeight.w800)),
                    ),
                  ]),
                  if (b.companyAddress.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(b.companyAddress,
                        style: const TextStyle(color: Color(0xFF69788A))),
                  ],
                  const Divider(height: 26),
                  _row('Delivery date', fmtDate(b.deliveryDate)),
                  _row('Contact', b.contact),
                  if (b.createdBy != null) _row('Created by', b.createdBy!),
                  if (b.sentBy != null) _row('Sent by', b.sentBy!),
                  const Divider(height: 26),
                  _row('Total cost', '₱${formatMoney(b.totalCost)}'),
                  _row('Expected profit', '₱${formatMoney(b.expectedProfit)}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text('Items (${b.items.length})',
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800, color: _ink)),
          const SizedBox(height: 8),
          if (b.items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(30),
              child: Text(
                b.isDraft
                    ? 'No items yet. Tap “Add item” to scan or search a product.'
                    : 'This batch has no items.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF8290A0)),
              ),
            )
          else
            ...b.items.map(_itemCard),
        ],
      ),
    );
  }

  Widget _itemCard(DeliveryItem i) {
    final b = _b!;
    final qtyText = i.byPack
        ? '${i.enteredQty} pack${i.enteredQty == 1 ? '' : 's'} × ${i.packSize} pcs = ${i.qty} pcs'
        : '${i.qty} pcs';
    final costText = i.byPack
        ? '₱${formatMoney(i.enteredCost)} per pack'
        : '₱${formatMoney(i.enteredCost)} per piece';

    return Card(
      child: ListTile(
        onTap: b.isDraft ? () => _editItem(i) : null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        title: Text(i.title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          '$qtyText\nCost $costText  ·  Sells ₱${formatMoney(i.sellingPrice)}\n'
          'Line ₱${formatMoney(i.lineCost)}  ·  Profit ₱${formatMoney(i.expectedProfit)}',
        ),
        isThreeLine: true,
        trailing: b.isDraft
            ? IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: _busy ? null : () => _removeItem(i),
              )
            : null,
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Color(0xFF69788A))),
            const SizedBox(width: 16),
            Flexible(
              child: Text(value,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}

// ---------------------------------------------------------------------------
// Product picker: search by name / barcode / size, or scan
// ---------------------------------------------------------------------------
class _ProductPickerPage extends StatefulWidget {
  const _ProductPickerPage();
  @override
  State<_ProductPickerPage> createState() => _ProductPickerPageState();
}

class _ProductPickerPageState extends State<_ProductPickerPage> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<Product> _items = [];
  bool _loading = true;
  String? _error;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _query('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _query(String text, {bool autoPick = false}) async {
    final id = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await ApiService.getJson('/api/Products', query: {
        if (text.isNotEmpty) 'search': text,
        'stock': 'all',
        'page': '1',
        'pageSize': '40',
      });
      final page = ProductPage.fromJson((data as Map).cast<String, dynamic>());
      if (!mounted || id != _requestId) return;

      if (autoPick && page.items.length == 1) {
        Navigator.pop(context, page.items.first);
        return;
      }
      setState(() {
        _items = page.items;
        _loading = false;
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

  Future<void> _scan() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const _ScanPage()),
    );
    if (code != null && mounted) {
      _search.text = code;
      _query(code, autoPick: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose product'),
        actions: [
          IconButton(onPressed: _scan, icon: const Icon(Icons.qr_code_scanner)),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
            child: TextField(
              controller: _search,
              autofocus: false,
              onChanged: (v) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 400),
                    () => _query(v.trim()));
              },
              decoration: const InputDecoration(
                hintText: 'Search name, barcode or size',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!, textAlign: TextAlign.center))
                    : _items.isEmpty
                        ? const Center(child: Text('No products match.'))
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
                            itemCount: _items.length,
                            itemBuilder: (_, i) {
                              final p = _items[i];
                              return Card(
                                child: ListTile(
                                  onTap: () => Navigator.pop(context, p),
                                  title: Text(
                                    p.measurement.isEmpty
                                        ? p.name
                                        : '${p.name} · ${p.measurement}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700),
                                  ),
                                  subtitle: Text(
                                      '${p.categoryName}  ·  ${p.barcode}\nOn hand: ${p.qtyOnHand}'),
                                  isThreeLine: true,
                                  trailing: const Icon(Icons.add_circle_outline),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

class _ScanPage extends StatelessWidget {
  const _ScanPage();
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Scan barcode')),
        body: MobileScanner(onDetect: (capture) {
          final code = capture.barcodes.firstOrNull?.rawValue;
          if (code != null && code.isNotEmpty) Navigator.pop(context, code);
        }),
      );
}

// ---------------------------------------------------------------------------
// Item sheet: quantity, cost (per piece or per pack) and selling price
// ---------------------------------------------------------------------------
class _ItemSheet extends StatefulWidget {
  final int batchId;
  final int productId;
  final String title;
  final double? defaultPrice;
  final DeliveryItem? existing;

  const _ItemSheet({
    required this.batchId,
    required this.productId,
    required this.title,
    this.defaultPrice,
    this.existing,
  });

  @override
  State<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<_ItemSheet> {
  // The same limits as the desktop delivery screen.
  static const _maxQty = 999999;
  static const _maxPack = 100000;
  static const _maxMoney = 9999999.99;

  final _qty = TextEditingController();
  final _pack = TextEditingController();
  final _cost = TextEditingController();
  final _price = TextEditingController();

  bool _byPack = false;
  bool _saving = false;
  LastPrice? _last;

  /// Like the desktop: the cost is locked to what this supplier charged last
  /// time, until the user says the supplier really changed its price.
  bool _unlocked = false;
  bool get _locked => _last != null && !_unlocked;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _byPack = e.byPack;
      _qty.text = '${e.enteredQty}';
      if (e.byPack) _pack.text = '${e.packSize}';
      _cost.text = _num(e.enteredCost);
      _price.text = _num(e.sellingPrice);
    } else if (widget.defaultPrice != null && widget.defaultPrice! > 0) {
      _price.text = _num(widget.defaultPrice!);
    }
    _loadLastPrice();
  }

  @override
  void dispose() {
    _qty.dispose();
    _pack.dispose();
    _cost.dispose();
    _price.dispose();
    super.dispose();
  }

  String _num(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  // per-piece cost keeps up to 4 decimals (at least 2), like the desktop
  static String _cost4(double v) {
    var t = v.toStringAsFixed(4);
    while (t.endsWith('0') && t.split('.')[1].length > 2) {
      t = t.substring(0, t.length - 1);
    }
    final parts = t.split('.');
    final whole = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
    return '₱$whole.${parts[1]}';
  }

  static String _describe(bool byPack, int pack, double entered, double perPiece) => byPack
      ? '₱${formatMoney(entered)} per pack of $pack (${_cost4(perPiece)} per piece)'
      : '${_cost4(perPiece)} per piece';

  String _lastText(LastPrice l) =>
      _describe(l.costMode == 'pack', l.packSize, l.enteredCost, l.costPrice);

  Future<void> _loadLastPrice() async {
    try {
      final data = await ApiService.getJson(
          '/api/Deliveries/${widget.batchId}/last-price/${widget.productId}');
      final map = (data as Map).cast<String, dynamic>();
      if (map['found'] == false || !mounted) return;
      final last = LastPrice.fromJson(map);
      setState(() {
        _last = last;
        final e = widget.existing;
        if (e == null) {
          // Start from what this supplier charged last time.
          _byPack = last.costMode == 'pack';
          _pack.text = _byPack && last.packSize > 1 ? '${last.packSize}' : '';
          _cost.text = _num(last.enteredCost);
          if (last.sellingPrice > 0) _price.text = _num(last.sellingPrice);
        } else if ((e.costPrice - last.costPrice).abs() > 0.00005) {
          // this line was already saved with a changed price
          _unlocked = true;
        }
      });
    } catch (_) {
      // The hint is optional; saving still works without it.
    }
  }

  Future<void> _unlock() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Supplier's price changed?"),
        content: const Text(
            'Only unlock the cost if the supplier really changed its price. '
            'The change is recorded in the audit trail with your name.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Unlock cost')),
        ],
      ),
    );
    if (ok == true && mounted) setState(() => _unlocked = true);
  }

  int get _q => int.tryParse(_qty.text) ?? 0;
  int get _k => _byPack ? (int.tryParse(_pack.text) ?? 0) : 1;
  double get _c => double.tryParse(_cost.text) ?? 0;
  double get _p => double.tryParse(_price.text) ?? 0;

  // cost of ONE piece, rounded to 4 decimals like the server
  double get _unit =>
      _byPack && _k > 0 ? (_c / _k * 10000).roundToDouble() / 10000 : _c;

  String? _validate() {
    if (_q <= 0) {
      return _byPack ? 'Enter the number of packs.' : 'Enter a quantity greater than zero.';
    }
    if (_q > _maxQty) return 'The quantity can be at most 999,999.';
    if (_byPack && _k < 2) return 'Enter how many pieces are in one pack (2 or more).';
    if (_byPack && _k > _maxPack) return 'A pack can hold at most 100,000 pieces.';
    if (_c <= 0) return _byPack ? 'Enter the cost of one pack.' : 'Enter the cost of one piece.';
    if (_p <= 0) return 'Enter the selling price per piece.';
    if (_c > _maxMoney || _p > _maxMoney) return 'Prices can be at most ₱9,999,999.99.';
    if (_unit < 0.0001) return 'The cost per piece is too small. Check the pieces in 1 pack.';
    return null;
  }

  Future<void> _save({bool confirmed = false, bool lowPriceOk = false}) async {
    final problem = _validate();
    if (problem != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem)));
      return;
    }

    // Same check as the desktop: selling at or below cost needs a yes.
    if (!lowPriceOk && _p <= _unit) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Price not above cost'),
          content: Text('The selling price per piece (₱${formatMoney(_p)}) is not higher '
              'than the cost per piece (${_cost4(_unit)}). Add it anyway?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add anyway')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }

    setState(() => _saving = true);
    try {
      await ApiService.postJson('/api/Deliveries/${widget.batchId}/items', {
        'productId': widget.productId,
        'quantity': _q,
        'costMode': _byPack ? 'pack' : 'piece',
        'packSize': _k,
        'enteredCost': _c,
        'price': _p,
        'costChangeConfirmed': confirmed || _unlocked,
      });
      if (mounted) Navigator.pop(context, true);
    } on SessionExpiredException {
      if (mounted) {
        Navigator.pop(context);
        handleSessionExpired(context);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);

      if (e.code == 'PRICE_LOCKED') {
        // The supplier's price was recorded meanwhile (for example on the desktop).
        final last = _last;
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Supplier price changed'),
            content: Text(
              last == null
                  ? e.message
                  : 'This supplier last charged ${_lastText(last)} (${last.batchNo}). '
                      'The cost you entered is different. Use the new cost?',
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Use new cost')),
            ],
          ),
        );
        if (ok == true && mounted) _save(confirmed: true, lowPriceOk: true);
        return;
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Something went wrong. Please try again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pieces = _q * _k;
    final lineCost =
        ((_byPack ? _q * _c : pieces * _c) * 100).roundToDouble() / 100;
    final profit = pieces * _p - lineCost;
    final margin = _p > 0 ? (_p - _unit) / _p * 100 : 0.0;
    final showPreview =
        _q > 0 && _c > 0 && _p > 0 && (!_byPack || _k >= 2);
    final last = _last;

    final money = [
      FilteringTextInputFormatter.allow(RegExp(r'^\d{0,7}(\.\d{0,2})?')),
    ];
    final digits = [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(6),
    ];

    final String lockText;
    if (last == null) {
      lockText = 'First delivery of this item from this supplier: '
          'enter its cost (per piece, or per pack / box).';
    } else if (_locked) {
      lockText = 'Cost is locked at ${_lastText(last)}: '
          'what this supplier charged (${last.batchNo}).';
    } else {
      lockText = 'Cost unlocked. This supplier charged ${_lastText(last)} before. '
          'A change is recorded in the audit trail.';
    }

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          20, 4, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800, color: _ink)),
          const SizedBox(height: 8),
          // cost lock note, worded like the desktop
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
            decoration: BoxDecoration(
              color: _locked ? const Color(0xFFFFF6E5) : const Color(0xFFF2F5F8),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              Icon(
                  _locked
                      ? Icons.lock_outline
                      : (last == null ? Icons.info_outline : Icons.lock_open),
                  size: 18,
                  color: _locked ? const Color(0xFFB7791F) : const Color(0xFF718096)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(lockText,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF4A5568))),
              ),
              if (_locked)
                TextButton(onPressed: _unlock, child: const Text('Price changed?')),
            ]),
          ),
          const SizedBox(height: 14),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Per piece')),
              ButtonSegment(value: true, label: Text('Per pack / box')),
            ],
            selected: {_byPack},
            onSelectionChanged:
                _locked ? null : (s) => setState(() => _byPack = s.first),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _qty,
            keyboardType: TextInputType.number,
            inputFormatters: digits,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
                labelText: _byPack ? 'Quantity (packs)' : 'Quantity (pieces)'),
          ),
          if (_byPack) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _pack,
              readOnly: _locked,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Pieces in 1 pack',
                suffixIcon: _locked ? const Icon(Icons.lock_outline, size: 18) : null,
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _cost,
            readOnly: _locked,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: money,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: _byPack ? 'Cost price (per pack)' : 'Cost price (per piece)',
              prefixText: '₱ ',
              suffixIcon: _locked ? const Icon(Icons.lock_outline, size: 18) : null,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: money,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Selling price per piece (VAT included)',
              prefixText: '₱ ',
            ),
          ),
          if (showPreview) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFCF2F2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(children: [
                _previewRow('Pieces into stock',
                    _byPack ? '$_q × $_k = $pieces' : '$pieces'),
                if (_byPack) _previewRow('Each piece costs', _cost4(_unit)),
                _previewRow('Line cost', '₱${formatMoney(lineCost)}'),
                _previewRow('Expected profit',
                    '₱${formatMoney(profit)}  (${margin.toStringAsFixed(1)}% margin)'),
              ]),
            ),
            if (profit < 0)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('The selling price is lower than the cost.',
                    style: TextStyle(color: Color(0xFFC0392B), fontSize: 12)),
              ),
          ],
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _saving ? null : () => _save(),
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check),
            label: Text(widget.existing == null ? 'Add to batch' : 'Update item'),
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
        ],
      ),
    );
  }

  Widget _previewRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Color(0xFF586068))),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      );
}