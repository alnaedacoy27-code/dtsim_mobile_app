import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/app_logo.dart';
import '../services/brand.dart';
import 'home_shell.dart';
import 'server_settings_sheet.dart';

/// Log in, looking like the desktop's: the maroon Darwin Trading panel on top, the form below.
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
        icon: const Icon(Icons.lock_outline, size: 36, color: Brand.alert),
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
    final size = MediaQuery.of(context).size;
    final top = MediaQuery.of(context).padding.top;
    final brandHeight = (size.height * 0.36).clamp(250.0, 340.0);

    return Scaffold(
      backgroundColor: Brand.maroon,
      body: SingleChildScrollView(
        child: Column(
          children: [
            // ---- the maroon brand panel, as on the desktop
            SizedBox(
              height: brandHeight + top,
              width: double.infinity,
              child: Stack(
                children: [
                  const Positioned.fill(child: CustomPaint(painter: BrandCircles())),
                  Positioned(
                    top: top + 4,
                    right: 8,
                    child: IconButton(
                      tooltip: 'Server connection',
                      onPressed: _busy ? null : _openServerSettings,
                      icon: const Icon(Icons.settings_ethernet, color: Colors.white70),
                    ),
                  ),
                  Positioned(
                    left: 28,
                    right: 28,
                    bottom: 34,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(45),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.memory(appLogoBytes, width: 66, height: 66, gaplessPlayback: true),
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text('DARWIN',
                            style: TextStyle(color: Colors.white, fontSize: 36, height: 1.0, fontWeight: FontWeight.w800, letterSpacing: 1)),
                        const Text('TRADING',
                            style: TextStyle(color: Colors.white, fontSize: 36, height: 1.05, fontWeight: FontWeight.w800, letterSpacing: 1)),
                        const SizedBox(height: 10),
                        const Text('Sales and Inventory System',
                            style: TextStyle(color: Brand.onMaroonSoft, fontSize: 15, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ---- the white sheet with the form
            Container(
              width: double.infinity,
              constraints: BoxConstraints(minHeight: size.height - brandHeight - top),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: EdgeInsets.fromLTRB(24, 30, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Welcome back',
                          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Brand.maroon)),
                      const SizedBox(height: 6),
                      const Text('Log in with your Darwin Trading account.',
                          style: TextStyle(color: Brand.muted, fontSize: 14.5)),
                      const SizedBox(height: 26),
                      TextField(
                        controller: _username,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.person_outline)),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _password,
                        obscureText: _obscure,
                        onSubmitted: (_) => _apiLogin(),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _obscure ? 'Show password' : 'Hide password',
                            icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      FilledButton(
                        onPressed: _busy ? null : _apiLogin,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(54),
                          backgroundColor: Brand.maroon,
                          disabledBackgroundColor: Brand.maroon.withAlpha(150),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: _busy
                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Log in', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
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
                              const Icon(Icons.dns_outlined, size: 16, color: Brand.muted),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'Server: ${ApiService.baseUrl}',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12, color: Brand.muted),
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Text('Change',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Brand.maroon)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
