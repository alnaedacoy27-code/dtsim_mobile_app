import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});
  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}
class _ProductsScreenState extends State<ProductsScreen> {
  final _search = TextEditingController();
  final _items = const [
    {'name': 'Sample Product A', 'sku': 'DT-0001', 'stock': '32', 'unit': 'pcs'},
    {'name': 'Sample Product B', 'sku': 'DT-0002', 'stock': '8', 'unit': 'box'},
    {'name': 'Sample Product C', 'sku': 'DT-0003', 'stock': '0', 'unit': 'pcs'},
    {'name': 'Sample Product D', 'sku': 'DT-0004', 'stock': '54', 'unit': 'kg'},
    {'name': 'Sample Product E', 'sku': 'DT-0005', 'stock': '4', 'unit': 'pcs'},
  ];
  String _query = '';
  @override
  void dispose() { _search.dispose(); super.dispose(); }

  Future<void> _scan() async {
    final code = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const _ScannerPage()));
    if (code != null && mounted) {
      _search.text = code;
      setState(() => _query = code);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Scanned barcode: $code. Product lookup will use the API once connected.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _items.where((p) => '${p['name']} ${p['sku']}'.toLowerCase().contains(_query.toLowerCase())).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Products', style: TextStyle(fontWeight: FontWeight.w800)), actions: [IconButton(onPressed: _scan, icon: const Icon(Icons.qr_code_scanner))]),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        TextField(controller: _search, onChanged: (v) => setState(() => _query = v), decoration: InputDecoration(hintText: 'Search product or SKU', prefixIcon: const Icon(Icons.search), suffixIcon: IconButton(onPressed: _scan, icon: const Icon(Icons.qr_code_scanner)))),
        const SizedBox(height: 12),
        const Text('Sample catalogue · replace with live inventory API', style: TextStyle(fontSize: 12, color: Color(0xFF8290A0))),
        const SizedBox(height: 8),
        ...filtered.map((p) {
          final qty = int.tryParse(p['stock']!) ?? 0;
          final low = qty <= 8;
          return Card(child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            leading: Container(width: 44, height: 44, decoration: BoxDecoration(color: const Color(0xFFEAF3FB), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.inventory_2_outlined, color: Color(0xFF1769AA))),
            title: Text(p['name']!, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('SKU: ${p['sku']}  ·  ${p['unit']}'),
            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(p['stock']!, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF142D4E))),
              Text(low ? 'Low stock' : 'In stock', style: TextStyle(fontSize: 10, color: low ? const Color(0xFFD58A20) : const Color(0xFF159477))),
            ]),
          ));
        }),
        if (filtered.isEmpty) const Padding(padding: EdgeInsets.all(30), child: Text('No sample products match your search.', textAlign: TextAlign.center)),
      ]),
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
