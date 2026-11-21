import 'package:flutter/material.dart';
import '../models/inventory_models.dart';
import '../services/api_service.dart';
import '../services/session_guard.dart';

/// Asks for a category name (and optional description), creates it in the
/// shared database and returns it, or null if cancelled.
Future<ProductCategory?> showCreateCategoryDialog(BuildContext context) {
  return showDialog<ProductCategory>(
    context: context,
    builder: (_) => const _CategoryDialog(),
  );
}

class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog();
  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Enter the category name.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final data = await ApiService.postJson('/api/Products/categories', {
        'name': _name.text.trim(),
        'description': _description.text.trim(),
      });
      final created =
          ProductCategory.fromJson((data as Map).cast<String, dynamic>());
      if (mounted) Navigator.pop(context, created);
    } on SessionExpiredException {
      if (mounted) {
        Navigator.pop(context);
        handleSessionExpired(context);
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Something went wrong. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New category'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              maxLength: 100,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Category name',
                prefixIcon: Icon(Icons.category_outlined),
                counterText: '',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _description,
              maxLength: 255,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                counterText: '',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style: const TextStyle(color: Color(0xFFC0392B), fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Create'),
        ),
      ],
    );
  }
}