import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/local_store.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}
class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _url = TextEditingController(text: ApiService.baseUrl);
  @override
  void dispose() { _url.dispose(); super.dispose(); }

  Future<void> _saveUrl() async {
    await ApiService.setBaseUrl(_url.text);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('API address saved.')));
  }
  Future<void> _logout() async {
    await LocalStore.clearSession();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w800))),
    body: ListView(padding: const EdgeInsets.all(18), children: [
      Card(child: ListTile(
        leading: const CircleAvatar(backgroundColor: Color(0xFFEAF3FB), child: Icon(Icons.person_outline, color: Color(0xFF1769AA))),
        title: Text(LocalStore.displayName, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: const Text('Mobile app preview account'),
      )),
      const SizedBox(height: 18),
      const Text('API connection', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: Color(0xFF142D4E))),
      const SizedBox(height: 8),
      const Text('Android emulator default: http://10.0.2.2:5159. For a physical phone, use your PC LAN or Tailscale address and configure HTTPS.', style: TextStyle(color: Color(0xFF718096), fontSize: 12)),
      const SizedBox(height: 12),
      TextField(controller: _url, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'API base URL', prefixIcon: Icon(Icons.link))),
      const SizedBox(height: 10),
      FilledButton(onPressed: _saveUrl, child: const Text('Save API address')),
      const SizedBox(height: 24),
      const Text('About', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: Color(0xFF142D4E))),
      const SizedBox(height: 8),
      const Card(child: Padding(padding: EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Darwin Trading Mobile', style: TextStyle(fontWeight: FontWeight.w700)),
        SizedBox(height: 5),
        Text('Milestone 1 UI starter. Sample catalogue and dashboard figures are placeholders until the existing DTSIMS2 database API is connected.', style: TextStyle(color: Color(0xFF718096), fontSize: 12)),
      ]))),
      const SizedBox(height: 20),
      OutlinedButton.icon(onPressed: _logout, icon: const Icon(Icons.logout), label: const Text('Sign out')),
    ]),
  );
}
