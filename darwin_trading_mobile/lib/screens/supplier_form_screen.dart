import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/supplier_models.dart';
import '../services/api_service.dart';
import '../services/session_guard.dart';

/// Add a supplier, or edit one when [supplier] is given. The same rules as the desktop:
/// company, contact person, an 11-digit mobile number starting with 09 and the address are
/// required; email is optional; each branch needs its own address. Pops with the saved supplier.
class SupplierFormScreen extends StatefulWidget {
  final Supplier? supplier;
  const SupplierFormScreen({super.key, this.supplier});

  @override
  State<SupplierFormScreen> createState() => _SupplierFormScreenState();
}

class _SupplierFormScreenState extends State<SupplierFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _company = TextEditingController();
  final _person = TextEditingController();
  final _number = TextEditingController();
  final _address = TextEditingController();
  final _email = TextEditingController();
  bool _saving = false;
  String? _addressError;
  String? _numberError;

  bool get _editing => widget.supplier != null;

  static final _titleRx = RegExp(r"^[\p{L}\p{N} .,#'/()&\-]+$", unicode: true);
  static final _personRx = RegExp(r"^[\p{L} '.\-]+$", unicode: true);
  static final _mobileRx = RegExp(r'^09\d{9}$');
  static final _emailRx = RegExp(
      r'^[A-Za-z0-9_%+\-]+(\.[A-Za-z0-9_%+\-]+)*@([A-Za-z0-9]([A-Za-z0-9\-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,24}$');

  @override
  void initState() {
    super.initState();
    final s = widget.supplier;
    if (s != null) {
      _company.text = s.companyName;
      _person.text = s.contactPerson;
      _number.text = s.contactNumber ?? '';
      _address.text = s.address;
      _email.text = s.email ?? '';
    }
  }

  @override
  void dispose() {
    _company.dispose();
    _person.dispose();
    _number.dispose();
    _address.dispose();
    _email.dispose();
    super.dispose();
  }

  static String _tidy(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');

  String? _checkCompany(String? v) {
    final t = _tidy(v ?? '');
    if (t.isEmpty) return 'Enter the company name.';
    if (t.length < 2) return 'The company name is too short.';
    if (!_titleRx.hasMatch(t)) return "Letters, numbers and . , # ' / ( ) & - only.";
    return null;
  }

  String? _checkPerson(String? v) {
    final t = _tidy(v ?? '');
    if (t.isEmpty) return 'Enter the contact person.';
    if (!_personRx.hasMatch(t) || t.replaceAll(RegExp(r"[^\p{L}]", unicode: true), '').length < 2) {
      return "A name: letters, space, ' . - only.";
    }
    return null;
  }

  String? _checkNumber(String? v) {
    if (_numberError != null) return _numberError;
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'Enter the contact number.';
    if (!_mobileRx.hasMatch(t)) return '11 digits starting with 09, e.g. 09171234567.';
    return null;
  }

  String? _checkAddress(String? v) {
    if (_addressError != null) return _addressError;
    final t = _tidy(v ?? '');
    if (t.isEmpty) return 'Enter the address of this branch.';
    if (t.length < 2) return 'The address is too short.';
    if (!_titleRx.hasMatch(t)) return "Letters, numbers and . , # ' / ( ) & - only.";
    return null;
  }

  String? _checkEmail(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return null;
    if (!_emailRx.hasMatch(t)) return 'Not a valid email, e.g. name@gmail.com.';
    return null;
  }

  Future<void> _save() async {
    setState(() {
      _addressError = null;
      _numberError = null;
    });
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);
    try {
      final body = {
        'companyName': _tidy(_company.text),
        'contactPerson': _tidy(_person.text),
        'contactNumber': _number.text.trim(),
        'address': _tidy(_address.text),
        'email': _email.text.trim().isEmpty ? null : _email.text.trim(),
      };
      final data = _editing
          ? await ApiService.putJson('/api/Suppliers/${widget.supplier!.id}', body)
          : await ApiService.postJson('/api/Suppliers', body);
      final saved = SupplierDetail.fromJson((data as Map).cast<String, dynamic>());
      if (mounted) Navigator.pop(context, saved);
    } on SessionExpiredException {
      if (mounted) handleSessionExpired(context);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      if (e.code == 'DUPLICATE_ADDRESS') {
        // show it on the address field itself
        setState(() => _addressError = e.message);
        _formKey.currentState?.validate();
        return;
      }
      if (e.code == 'NUMBER_TAKEN') {
        // the number is another contact person's: show it on the number field
        setState(() => _numberError = e.message);
        _formKey.currentState?.validate();
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), duration: const Duration(seconds: 5)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Something went wrong. Please try again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Edit supplier' : 'New supplier')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            TextFormField(
              controller: _company,
              maxLength: 100,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Company name',
                prefixIcon: Icon(Icons.storefront_outlined),
                counterText: '',
              ),
              validator: _checkCompany,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _person,
              maxLength: 100,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Contact person',
                prefixIcon: Icon(Icons.person_outline),
                counterText: '',
              ),
              validator: _checkPerson,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _number,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)],
              onChanged: (_) {
                if (_numberError != null) setState(() => _numberError = null);
              },
              decoration: const InputDecoration(
                labelText: 'Mobile number',
                hintText: '09171234567',
                prefixIcon: Icon(Icons.phone_iphone),
              ),
              validator: _checkNumber,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _email,
              maxLength: 100,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email (optional)',
                prefixIcon: Icon(Icons.email_outlined),
                counterText: '',
              ),
              validator: _checkEmail,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _address,
              maxLength: 150,
              minLines: 2,
              maxLines: 3,
              textCapitalization: TextCapitalization.words,
              onChanged: (_) {
                if (_addressError != null) setState(() => _addressError = null);
              },
              decoration: const InputDecoration(
                labelText: 'Address of this branch',
                helperText: 'Each branch of a company is its own supplier with its own address. '
                    'Different companies may share an address.',
                helperMaxLines: 2,
                prefixIcon: Icon(Icons.place_outlined),
                counterText: '',
              ),
              validator: _checkAddress,
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check),
              label: Text(_editing ? 'Save changes' : 'Add supplier'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
            ),
          ],
        ),
      ),
    );
  }
}
