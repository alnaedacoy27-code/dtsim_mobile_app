import 'package:flutter/material.dart';
import '../models/inventory_models.dart';
import '../services/api_service.dart';
import '../services/session_guard.dart';
import '../services/live_sync.dart' show productsChanged;
import 'product_form_screen.dart';
import 'products_screen.dart' show formatMoney;

class ProductDetailScreen extends StatefulWidget {
  final Product product;
  const ProductDetailScreen({super.key, required this.product});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  late Product _product;
  List<StockMovement> _movements = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _product = widget.product;
    productsChanged.addListener(_onRemoteChange);
    _load();
  }

  @override
  void dispose() {
    productsChanged.removeListener(_onRemoteChange);
    super.dispose();
  }

  void _onRemoteChange() => _load(showSpinner: false);

  Future<void> _load({bool showSpinner = true}) async {
    if (showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final data = await ApiService.getJson('/api/Products/${_product.id}');
      final map = (data as Map).cast<String, dynamic>();
      if (!mounted) return;
      setState(() {
        _product =
            Product.fromJson((map['product'] as Map).cast<String, dynamic>());
        _movements = ((map['movements'] as List?) ?? [])
            .map((e) =>
                StockMovement.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
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

  Future<void> _edit() async {
    final saved = await Navigator.push<Product>(
      context,
      MaterialPageRoute(builder: (_) => ProductFormScreen(product: _product)),
    );
    if (saved == null || !mounted) return;

    setState(() => _product = saved);
    productsChanged.value++; // refresh the dashboard numbers
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Product updated.')));
    _load();
  }

  Color get _statusColor {
    switch (_product.status) {
      case 'out':
        return const Color(0xFFC0392B);
      case 'low':
        return const Color(0xFFD58A20);
      default:
        return const Color(0xFF159477);
    }
  }

  String get _statusLabel {
    switch (_product.status) {
      case 'out':
        return 'Out of stock';
      case 'low':
        return 'Low stock';
      default:
        return 'In stock';
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _product;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Product details'),
        actions: [
          IconButton(
            tooltip: 'Edit product',
            onPressed: _edit,
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
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
                    Text(p.name,
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF181C20))),
                    if (p.measurement.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(p.measurement,
                          style: const TextStyle(color: Color(0xFF69788A))),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('${p.qtyOnHand}',
                            style: TextStyle(
                                fontSize: 38,
                                fontWeight: FontWeight.w800,
                                color: _statusColor)),
                        const SizedBox(width: 8),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text('on hand · $_statusLabel',
                              style: TextStyle(
                                  color: _statusColor,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                    const Divider(height: 28),
                    _row('Category', p.categoryName),
                    _row('Barcode', p.barcode),
                    _row('Selling price', formatMoney(p.sellingPrice)),
                    _row('Low stock alert at', '${p.lowStockThreshold}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text('Stock movements',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF181C20))),
            const SizedBox(height: 4),
            const Text('Latest 30 changes to this item',
                style: TextStyle(fontSize: 12, color: Color(0xFF8290A0))),
            const SizedBox(height: 10),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(30),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Column(children: [
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ])
            else if (_movements.isEmpty)
              const Padding(
                padding: EdgeInsets.all(30),
                child: Text('No stock movements recorded yet.',
                    textAlign: TextAlign.center),
              )
            else
              ..._movements.map(_movementTile),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
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

  Widget _movementTile(StockMovement m) {
    late final String label;
    late final IconData icon;

    switch (m.type) {
      case 'delivery_in':
        label = 'Delivery received';
        icon = Icons.local_shipping_outlined;
        break;
      case 'sale_out':
        label = 'Sale';
        icon = Icons.point_of_sale;
        break;
      case 'loss_out':
        label = 'Loss';
        icon = Icons.report_gmailerrorred_outlined;
        break;
      default:
        label = 'Adjustment';
        icon = Icons.tune;
    }

    final positive = m.qtyChange >= 0;
    final color =
        positive ? const Color(0xFF159477) : const Color(0xFFC0392B);

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withAlpha(30),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          '${_formatDate(m.createdAt)}${m.user == null ? '' : '  ·  ${m.user}'}',
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('${positive ? '+' : ''}${m.qtyChange}',
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w800, color: color)),
            Text('bal. ${m.balanceAfter}',
                style: const TextStyle(fontSize: 10, color: Color(0xFF8290A0))),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }
}