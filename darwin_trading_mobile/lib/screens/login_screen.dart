import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/app_logo.dart';
import 'home_shell.dart';
import 'server_settings_sheet.dart';

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

  Future<void> _apiLogin() async {
    if (_username.text.trim().isEmpty || _password.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter your username and password.')));
      return;
    }
    setState(() => _busy = true);
    try {
      await ApiService.login(_username.text.trim(), _password.text);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeShell()));
    } on AuthException catch (e) {
      if (!mounted) return;
      if (e.type == AuthFailure.noAccess) {
        await _showAccessDenied(e.message);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.message),
          duration: const Duration(seconds: 5),
          action: e.type == AuthFailure.network
              ? SnackBarAction(label: 'Server', onPressed: _openServerSettings)
              : null,
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Something went wrong. Please try again.'),
          duration: Duration(seconds: 5),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openServerSettings() async {
    await showServerSettings(context);
    if (mounted) setState(() {}); // show the server that is now selected
  }

  Future<void> _showAccessDenied(String message) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.lock_outline, size: 36, color: Color(0xFFB3261E)),
        title: const Text('Access Denied'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
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
        child: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 28),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Image.memory(appLogoBytes, width: 84, height: 84, gaplessPlayback: true),
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
                      const SizedBox(height: 18),
                      InkWell(
                        onTap: _busy ? null : _openServerSettings,
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.dns_outlined, size: 16, color: Color(0xFF69788A)),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'Server: ${ApiService.baseUrl}',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF69788A)),
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Text('Change', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1769AA))),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 8,
              child: IconButton(
                tooltip: 'Server connection',
                onPressed: _busy ? null : _openServerSettings,
                icon: const Icon(Icons.settings_ethernet, color: Color(0xFF69788A)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}