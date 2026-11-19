import 'package:flutter/material.dart';
import '../services/local_store.dart';
import '../services/api_service.dart';
import 'home_shell.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;

  Future<void> _demoLogin() async {
    final name = _username.text.trim().isEmpty ? 'Darwin Trading User' : _username.text.trim();
    await LocalStore.saveSession(name);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeShell()));
  }

  Future<void> _apiLogin() async {
    if (_username.text.trim().isEmpty || _password.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter your username and password.')));
      return;
    }
    setState(() => _busy = true);
    try {
      await ApiService.login(_username.text.trim(), _password.text);
      await LocalStore.saveSession(_username.text.trim());
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeShell()));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not sign in: $e'),
          duration: const Duration(seconds: 5),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 28),
                  Container(
                    width: 78, height: 78,
                    decoration: BoxDecoration(color: const Color(0xFFE8F2FC), borderRadius: BorderRadius.circular(24)),
                    child: const Icon(Icons.inventory_2_rounded, size: 40, color: Color(0xFF1769AA)),
                  ),
                  const SizedBox(height: 28),
                  const Text('DARWIN TRADING', style: TextStyle(fontSize: 13, letterSpacing: 2.2, fontWeight: FontWeight.w800, color: Color(0xFF1769AA))),
                  const SizedBox(height: 8),
                  const Text('Welcome back', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: Color(0xFF142D4E))),
                  const SizedBox(height: 8),
                  const Text('Sign in to manage deliveries and inventory.', style: TextStyle(color: Color(0xFF69788A), fontSize: 15)),
                  const SizedBox(height: 30),
                  TextField(controller: _username, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.person_outline))),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _password, obscureText: _obscure,
                    onSubmitted: (_) => _apiLogin(),
                    decoration: InputDecoration(
                      labelText: 'Password', prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined), onPressed: () => setState(() => _obscure = !_obscure)),
                    ),
                  ),
                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed: _busy ? null : _apiLogin,
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    child: _busy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Sign in', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _busy ? null : _demoLogin,
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    child: const Text('Preview app (demo mode)'),
                  ),
                  const SizedBox(height: 14),
                  const Text('Demo mode uses sample data only. API sign-in requires the backend login endpoint to be configured.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Color(0xFF8290A0))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
