import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/inventory_models.dart';
import '../services/api_service.dart';
import '../services/session_guard.dart';
import 'category_dialog.dart';

/// Add a new product, or edit an existing one when [product] is given.
/// Pops with the saved [Product].
class ProductFormScreen extends StatefulWidget {
  final Product? product;
  const ProductFormScreen({super.key, this.product});

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _measurement = TextEditingController();
  final _barcode = TextEditingController();
  final _threshold = TextEditingController();

  List<ProductCategory> _categories = [];
  int? _categoryId;
  bool _loadingCategories = true;
  String? _categoryError;
  bool _autoBarcode = true;
  bool _saving = false;

  bool get _editing => widget.product != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    if (p != null) {
      _name.text = p.name;
      _measurement.text = p.measurement;
      _barcode.text = p.barcode;
      _threshold.text = '${p.lowStockThreshold}';
      _categoryId = p.categoryId;
      _autoBarcode = false;
    }
    _loadCategories();
  }

  @override
  void dispose() {
    _name.dispose();
    _measurement.dispose();
    _barcode.dispose();
    _threshold.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    setState(() {
      _loadingCategories = true;
      _categoryError = null;
    });
    try {
      final data = await ApiService.getJson('/api/Products/categories');
      if (!mounted) return;
      setState(() {
        _categories = (data as List)
            .map((e) => ProductCategory.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
        _loadingCategories = false;
      });
    } on SessionExpiredException {
      if (mounted) handleSessionExpired(context);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingCategories = false;
        _categoryError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingCategories = false;
        _categoryError = 'Could not load the categories.';
      });
    }
  }

  Future<void> _addCategory() async {
    final created = await showCreateCategoryDialog(context);
    if (created == null || !mounted) return;
    setState(() {
      _categories = [..._categories, created]
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _categoryId = created.id;
      _categoryError = null;
    });
  }

  Future<void> _scan() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const _ScanPage()),
    );
    if (code != null && mounted) {
      setState(() => _barcode.text = code);
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final useAuto = !_editing && _autoBarcode;

    setState(() => _saving = true);
    try {
      final body = {
        'name': _name.text.trim(),
        'categoryId': _categoryId,
        'measurement': _measurement.text.trim(),
        'barcode': useAuto ? null : _barcode.text.trim(),
        'lowStockThreshold': int.parse(_threshold.text),
      };

      final data = _editing
          ? await ApiService.putJson('/api/Products/${widget.product!.id}', body)
          : await ApiService.postJson('/api/Products', body);

      final saved = Product.fromJson((data as Map).cast<String, dynamic>());
      if (mounted) Navigator.pop(context, saved);
    } on SessionExpiredException {
      if (mounted) handleSessionExpired(context);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.message),
        duration: const Duration(seconds: 5),
      ));
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Something went wrong. Please try again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Edit product' : 'New product')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            TextFormField(
              controller: _name,
              maxLength: 150,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Product name',
                prefixIcon: Icon(Icons.inventory_2_outlined),
                counterText: '',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter the product name.' : null,
            ),
            const SizedBox(height: 14),
            if (_loadingCategories)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_categoryError != null)
              Row(children: [
                Expanded(child: Text(_categoryError!)),
                TextButton(onPressed: _loadCategories, child: const Text('Retry')),
              ])
            else if (_categories.isEmpty)
              const Text(
                'No categories yet. Create the first one below.',
                style: TextStyle(color: Color(0xFFC0392B)),
              )
            else
              DropdownButtonFormField<int>(
                value: _categoryId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  prefixIcon: Icon(Icons.category_outlined),
                ),
                items: _categories
                    .map((c) => DropdownMenuItem<int>(
                          value: c.id,
                          child: Text(c.name, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _categoryId = v),
                validator: (v) => v == null ? 'Choose a category.' : null,
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _loadingCategories ? null : _addCategory,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New category'),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _measurement,
              maxLength: 100,
              decoration: const InputDecoration(
                labelText: 'Measurement / size (optional)',
                helperText: 'Each size is its own item, e.g. 10mm x 6m',
                prefixIcon: Icon(Icons.straighten),
                counterText: '',
              ),
            ),
            const SizedBox(height: 18),
            if (!_editing)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Generate the barcode automatically'),
                subtitle: const Text(
                    'Turn off to scan or type the manufacturer barcode instead.'),
                value: _autoBarcode,
                onChanged: (v) => setState(() => _autoBarcode = v),
              ),
            if (_editing || !_autoBarcode) ...[
              const SizedBox(height: 6),
              TextFormField(
                controller: _barcode,
                maxLength: 30,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]')),
                ],
                decoration: InputDecoration(
                  labelText: 'Barcode',
                  prefixIcon: const Icon(Icons.qr_code_2),
                  counterText: '',
                  suffixIcon: IconButton(
                    tooltip: 'Scan',
                    icon: const Icon(Icons.qr_code_scanner),
                    onPressed: _scan,
                  ),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter or scan the barcode.' : null,
              ),
            ],
            const SizedBox(height: 14),
            TextFormField(
              controller: _threshold,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(7),
              ],
              decoration: const InputDecoration(
                labelText: 'Low stock alert at (pieces)',
                helperText: 'You are warned when the stock reaches this number.',
                prefixIcon: Icon(Icons.warning_amber_rounded),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Enter a number (0 for no alert).';
                final n = int.tryParse(v);
                if (n == null || n < 0 || n > 1000000) return 'Enter a number from 0 to 1,000,000.';
                return null;
              },
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: (_saving || _categories.isEmpty) ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check),
              label: Text(_editing ? 'Save changes' : 'Add product'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
            ),
          ],
        ),
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