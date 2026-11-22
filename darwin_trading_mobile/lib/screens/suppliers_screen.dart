import 'dart:async';
import 'package:flutter/material.dart';
import '../models/supplier_models.dart';
import '../services/api_service.dart';
import '../services/contact_actions.dart';
import '../services/live_sync.dart' show suppliersChanged;
import '../services/session_guard.dart';
import 'supplier_detail_screen.dart';
import 'supplier_form_screen.dart';

/// Suppliers tab: search, call or text the contact person straight from the list, add a supplier.
class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({super.key});
  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<Supplier> _items = [];
  bool _loading = true;
  String? _error;
  String _query = '';
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    suppliersChanged.addListener(_onRemoteChange);
    _reload();
  }

  @override
  void dispose() {
    suppliersChanged.removeListener(_onRemoteChange);
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  // Added or edited on the desktop or another phone: refresh quietly.
  void _onRemoteChange() => _reload(showSpinner: false);

  Future<void> _reload({bool showSpinner = true}) async {
    final id = ++_requestId;
    if (showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final data = await ApiService.getJson('/api/Suppliers', query: {
        if (_query.isNotEmpty) 'search': _query,
      });
      if (!mounted || id != _requestId) return;
      setState(() {
        _items = (data as List).map((e) => Supplier.fromJson((e as Map).cast<String, dynamic>())).toList();
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

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _query = value.trim();
      _reload();
    });
  }

  Future<void> _add() async {
    final saved = await Navigator.push<SupplierDetail>(
      context,
      MaterialPageRoute(builder: (_) => const SupplierFormScreen()),
    );
    if (saved == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Supplier "${saved.supplier.companyName}" added.')),
    );
    _reload(showSpinner: false);
  }

  Future<void> _open(Supplier s) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SupplierDetailScreen(supplierId: s.id, initial: s)),
    );
    if (mounted) _reload(showSpinner: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Suppliers', style: TextStyle(fontWeight: FontWeight.w800))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('New supplier'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
            child: TextField(
              controller: _search,
              onChanged: (v) {
                setState(() {});
                _onSearchChanged(v);
              },
              decoration: InputDecoration(
                hintText: 'Search company, person, number or address',
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
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(30),
        children: [
          const SizedBox(height: 30),
          const Icon(Icons.cloud_off_outlined, size: 48, color: Color(0xFFB5C0CC)),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF526579))),
          const SizedBox(height: 16),
          Center(
            child: OutlinedButton.icon(onPressed: _reload, icon: const Icon(Icons.refresh), label: const Text('Try again')),
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: () => _reload(showSpinner: false),
      child: _items.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                Padding(
                  padding: const EdgeInsets.all(40),
                  child: Text(
                    _query.isEmpty ? 'No suppliers yet. Tap New supplier to add one.' : 'No suppliers match your search.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 90),
              itemCount: _items.length,
              itemBuilder: (context, i) => _card(_items[i]),
            ),
    );
  }

  Widget _card(Supplier s) {
    final maroon = Theme.of(context).colorScheme.primary;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _open(s),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: maroon.withAlpha(24), borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.storefront_outlined, color: maroon),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.companyName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(s.address, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF6B7785))),
                    const SizedBox(height: 4),
                    Text(
                      s.hasNumber ? '${s.contactPerson} · ${formatMobile(s.contactNumber)}' : s.contactPerson,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
              if (s.hasNumber) ...[
                IconButton(
                  tooltip: 'Call ${s.contactPerson}',
                  icon: Icon(Icons.call_outlined, color: maroon),
                  onPressed: () => ContactActions.call(context, s.contactNumber!),
                ),
                IconButton(
                  tooltip: 'Text ${s.contactPerson}',
                  icon: Icon(Icons.sms_outlined, color: maroon),
                  onPressed: () => ContactActions.text(context, s.contactNumber!,
                      message: 'Hi ${s.contactPerson}, this is Darwin Trading. '),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
