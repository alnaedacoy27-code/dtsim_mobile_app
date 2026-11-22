import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/inventory_models.dart';
import '../services/api_service.dart';
import '../services/session_guard.dart';
import 'category_dialog.dart';
import '../services/live_sync.dart' show productsChanged;
import 'product_detail_screen.dart';
import 'product_form_screen.dart';

const _statusColors = {
  'in': Color(0xFF159477),
  'low': Color(0xFFD58A20),
  'out': Color(0xFFC0392B),
};

const _statusLabels = {
  'in': 'In stock',
  'low': 'Low stock',
  'out': 'Out of stock',
};

String formatMoney(double value) {
  final fixed = value.toStringAsFixed(2);
  final parts = fixed.split('.');
  final whole = parts[0].replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (m) => ',',
  );
  return '$whole.${parts[1]}';
}

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});
  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  static const _pageSize = 50;

  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  final List<Product> _items = [];
  List<ProductCategory> _categories = [];
  StockSummary _summary = const StockSummary(0, 0, 0);
  int _total = 0;
  int _page = 1;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  String _query = '';
  int? _categoryId;
  String _stock = 'all'; // all | low | out
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.hasClients &&
          _scroll.position.pixels >= _scroll.position.maxScrollExtent - 300) {
        _loadMore();
      }
    });
    productsChanged.addListener(_onRemoteChange);
    _loadCategories();
    _reload();
  }

  // Something changed in the system (e.g. on the desktop): refresh quietly.
  void _onRemoteChange() {
    _loadCategories();
    _reload(showSpinner: false, keepPaging: true);
  }

  @override
  void dispose() {
    productsChanged.removeListener(_onRemoteChange);
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<ProductPage> _fetch(int page, {int? size}) async {
    final data = await ApiService.getJson('/api/Products', query: {
      if (_query.isNotEmpty) 'search': _query,
      if (_categoryId != null) 'categoryId': '$_categoryId',
      'stock': _stock,
      'page': '$page',
      'pageSize': '${size ?? _pageSize}',
    });
    return ProductPage.fromJson((data as Map).cast<String, dynamic>());
  }

  Future<void> _loadCategories() async {
    try {
      final data = await ApiService.getJson('/api/Products/categories');
      if (!mounted) return;
      setState(() {
        _categories = (data as List)
            .map((e) =>
                ProductCategory.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
      });
    } on SessionExpiredException {
      if (mounted) handleSessionExpired(context);
    } catch (_) {
      // The category filter is optional; the list still works without it.
    }
  }

  Future<void> _reload({bool showSpinner = true, bool keepPaging = false}) async {
    final id = ++_requestId;
    // keep what the user already scrolled through (the API serves up to 100 at once)
    final pages = keepPaging ? (_page < 2 ? 1 : 2) : 1;
    if (showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final result = await _fetch(1, size: pages * _pageSize);
      if (!mounted || id != _requestId) return;
      setState(() {
        _items
          ..clear()
          ..addAll(result.items);
        _summary = result.summary;
        _total = result.total;
        _page = pages;
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

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || _items.length >= _total) return;

    final id = _requestId;
    setState(() => _loadingMore = true);

    try {
      final result = await _fetch(_page + 1);
      if (!mounted || id != _requestId) return;
      setState(() {
        _items.addAll(result.items);
        _page += 1;
        _total = result.total;
      });
    } on SessionExpiredException {
      if (mounted) handleSessionExpired(context);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load more products.')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _query = value.trim();
      _reload();
    });
  }

  void _setStock(String value) {
    if (_stock == value) return;
    _stock = value;
    _reload();
  }

  void _setCategory(int? value) {
    if (_categoryId == value) return;
    setState(() => _categoryId = value);
    _reload();
  }

  Future<void> _scan() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const _ScannerPage()),
    );
    if (code != null && mounted) {
      _search.text = code;
      _query = code;
      _reload();
    }
  }

  Future<void> _addProduct() async {
    final saved = await Navigator.push<Product>(
      context,
      MaterialPageRoute(builder: (_) => const ProductFormScreen()),
    );
    if (saved == null || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Product added · barcode ${saved.barcode}'),
      duration: const Duration(seconds: 5),
    ));
    productsChanged.value++; // also refreshes the dashboard numbers
    _loadCategories();
    _reload(showSpinner: false);
  }

  Future<void> _addCategory() async {
    final created = await showCreateCategoryDialog(context);
    if (created == null || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Category "${created.name}" added.')),
    );
    _loadCategories();
  }

  Future<void> _openProduct(Product p) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProductDetailScreen(product: p)),
    );
    if (mounted) {
      _loadCategories();
      _reload(showSpinner: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory',
            style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(onPressed: _scan, icon: const Icon(Icons.qr_code_scanner)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addProduct,
        icon: const Icon(Icons.add),
        label: const Text('New product'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
            child: TextField(
              controller: _search,
              onChanged: (value) {
                setState(() {});
                _onSearchChanged(value);
              },
              decoration: InputDecoration(
                hintText: 'Search name, barcode or size',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _search.clear();
                          _query = '';
                          _reload();
                          setState(() {});
                        },
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              children: [
                _chip('All (${_summary.total})', _stock == 'all',
                    () => _setStock('all')),
                _chip('Low stock (${_summary.low})', _stock == 'low',
                    () => _setStock('low')),
                _chip('Out of stock (${_summary.out})', _stock == 'out',
                    () => _setStock('out')),
              ],
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              children: [
                _chip('All categories', _categoryId == null,
                    () => _setCategory(null)),
                ..._categories.map((c) => _chip(
                      c.name,
                      _categoryId == c.id,
                      () => _setCategory(c.id),
                    )),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    avatar: const Icon(Icons.add, size: 18),
                    label: const Text('New category'),
                    onPressed: _addCategory,
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => onTap(),
        ),
      );

  Widget _buildList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

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
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await _reload(showSpinner: false);
        await _loadCategories();
      },
      child: _items.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                Padding(
                  padding: EdgeInsets.all(40),
                  child: Text('No products match your search.',
                      textAlign: TextAlign.center),
                ),
              ],
            )
          : ListView.builder(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 90),
              itemCount: _items.length + 1,
              itemBuilder: (context, index) {
                if (index == _items.length) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Center(
                      child: _loadingMore
                          ? const CircularProgressIndicator(strokeWidth: 2)
                          : Text('${_items.length} of $_total products',
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFF8290A0))),
                    ),
                  );
                }
                return _productCard(_items[index]);
              },
            ),
    );
  }

  Widget _productCard(Product p) {
    final color = _statusColors[p.status] ?? _statusColors['in']!;

    return Card(
      child: ListTile(
        onTap: () => _openProduct(p),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withAlpha(30),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.inventory_2_outlined, color: color),
        ),
        title: Text(
          p.measurement.isEmpty ? p.name : '${p.name} · ${p.measurement}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${p.categoryName}  ·  ${p.barcode}\n${formatMoney(p.sellingPrice)}',
        ),
        isThreeLine: true,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('${p.qtyOnHand}',
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF181C20))),
            Text(_statusLabels[p.status] ?? '',
                style: TextStyle(fontSize: 10, color: color)),
          ],
        ),
      ),
    );
  }
}

class _ScannerPage extends StatelessWidget {
  const _ScannerPage();
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Scan barcode')),
        body: MobileScanner(onDetect: (capture) {
          final code = capture.barcodes.firstOrNull?.rawValue;
          if (code != null && code.isNotEmpty) Navigator.pop(context, code);
        }),
      );
}