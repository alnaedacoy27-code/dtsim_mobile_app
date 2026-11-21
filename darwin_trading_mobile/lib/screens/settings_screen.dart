import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/local_store.dart';
import 'login_screen.dart';
import 'server_settings_sheet.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _signingOut = false;

  Future<void> _logout() async {
    setState(() => _signingOut = true);
    await ApiService.logout(); // lets the desktop's User Monitoring see you left
    await LocalStore.clearSession();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: const Text('Settings',
                style: TextStyle(fontWeight: FontWeight.w800))),
        body: ListView(padding: const EdgeInsets.all(18), children: [
          Card(
            child: ListTile(
              leading: const CircleAvatar(
                  backgroundColor: Color(0xFFEAF3FB),
                  child: Icon(Icons.person_outline, color: Color(0xFF1769AA))),
              title: Text(LocalStore.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text([
                if (LocalStore.username != null) '@${LocalStore.username}',
                if (LocalStore.role != null) LocalStore.role!,
              ].join('  ·  ')),
            ),
          ),
          const SizedBox(height: 18),
          const Text('Server connection',
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                  color: Color(0xFF142D4E))),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.dns_outlined, color: Color(0xFF1769AA)),
              title: const Text('Connected to',
                  style: TextStyle(fontSize: 12, color: Color(0xFF718096))),
              subtitle: Text(ApiService.baseUrl,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, color: Color(0xFF243B53))),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await showServerSettings(context);
                if (mounted) setState(() {});
              },
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Changing the server takes effect for the next requests. Sign out and in again to start a new session on the other server.',
            style: TextStyle(color: Color(0xFF718096), fontSize: 12),
          ),
          const SizedBox(height: 24),
          const Text('About',
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                  color: Color(0xFF142D4E))),
          const SizedBox(height: 8),
          const Card(
              child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Darwin Trading Mobile',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        SizedBox(height: 5),
                        Text(
                            'Works with the same database as the desktop system. Your sign-ins and changes are recorded in the audit trail.',
                            style: TextStyle(
                                color: Color(0xFF718096), fontSize: 12)),
                      ]))),
          const SizedBox(height: 20),
          OutlinedButton.icon(
              onPressed: _signingOut ? null : _logout,
              icon: const Icon(Icons.logout),
              label: const Text('Sign out')),
        ]),
      );
}