import 'package:flutter/material.dart';
import '../services/api_service.dart';

const _ink = Color(0xFF181C20);

/// Lets the user keep several server addresses (office Wi-Fi, Tailscale, ...),
/// test each one, and choose which one the app uses.
Future<void> showServerSettings(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _ServerSettingsSheet(),
  );
}

class _ServerSettingsSheet extends StatefulWidget {
  const _ServerSettingsSheet();
  @override
  State<_ServerSettingsSheet> createState() => _ServerSettingsSheetState();
}

class _ServerSettingsSheetState extends State<_ServerSettingsSheet> {
  late List<SavedServer> _servers;
  late String _active;
  final Map<String, ConnectionTestResult?> _results = {};
  final Set<String> _testing = {};

  final _name = TextEditingController();
  final _url = TextEditingController();
  ConnectionTestResult? _newResult;
  bool _testingNew = false;

  @override
  void initState() {
    super.initState();
    _servers = ApiService.savedServers;
    _active = ApiService.baseUrl;
    if (!_servers.any((s) => s.url == _active)) {
      _servers = [SavedServer('Main server', _active), ..._servers];
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _test(SavedServer s) async {
    setState(() => _testing.add(s.url));
    final result = await ApiService.testConnection(s.url);
    if (!mounted) return;
    setState(() {
      _testing.remove(s.url);
      _results[s.url] = result;
    });
  }

  Future<void> _use(SavedServer s) async {
    await ApiService.setBaseUrl(s.url);
    await ApiService.saveServers(_servers);
    if (!mounted) return;
    setState(() => _active = s.url);
  }

  Future<void> _delete(SavedServer s) async {
    if (_servers.length <= 1 || s.url == _active) return;
    setState(() => _servers.removeWhere((x) => x.url == s.url));
    await ApiService.saveServers(_servers);
  }

  Future<void> _testNew() async {
    setState(() {
      _testingNew = true;
      _newResult = null;
    });
    final result = await ApiService.testConnection(_url.text);
    if (!mounted) return;
    setState(() {
      _testingNew = false;
      _newResult = result;
    });
  }

  Future<void> _addNew({required bool useNow}) async {
    final url = ApiService.normalizeUrl(_url.text);
    final name = _name.text.trim().isEmpty ? url : _name.text.trim();

    if (url.isEmpty || Uri.tryParse(url)?.host.isEmpty != false) {
      setState(() => _newResult = ConnectionTestResult(false, 'Enter a valid address.'));
      return;
    }
    if (_servers.any((s) => s.url == url)) {
      setState(() => _newResult = ConnectionTestResult(false, 'This address is already saved.'));
      return;
    }

    final server = SavedServer(name, url);
    setState(() {
      _servers.add(server);
      _name.clear();
      _url.clear();
      _newResult = null;
    });
    await ApiService.saveServers(_servers);
    if (useNow) await _use(server);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Server connection',
                style: TextStyle(
                    fontSize: 19, fontWeight: FontWeight.w800, color: _ink)),
            const SizedBox(height: 4),
            const Text(
              'Choose which system this app connects to. Use the local address on the same Wi-Fi, or the Tailscale address when you are on a different network.',
              style: TextStyle(color: Color(0xFF718096), fontSize: 12),
            ),
            const SizedBox(height: 14),
            ..._servers.map(_serverTile),
            const Divider(height: 30),
            const Text('Add a server',
                style: TextStyle(fontWeight: FontWeight.w800, color: _ink)),
            const SizedBox(height: 10),
            TextField(
              controller: _name,
              maxLength: 40,
              decoration: const InputDecoration(
                labelText: 'Name (e.g. Tailscale)',
                prefixIcon: Icon(Icons.label_outline),
                counterText: '',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              onChanged: (_) => setState(() => _newResult = null),
              decoration: const InputDecoration(
                labelText: 'Address (e.g. 100.64.1.2 or 192.168.1.2:5159)',
                prefixIcon: Icon(Icons.link),
              ),
            ),
            if (_newResult != null) ...[
              const SizedBox(height: 8),
              _resultLine(_newResult!),
            ],
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _testingNew ? null : _testNew,
                  icon: _testingNew
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.wifi_tethering),
                  label: const Text('Test'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _addNew(useNow: true),
                  icon: const Icon(Icons.check),
                  label: const Text('Save & use'),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _serverTile(SavedServer s) {
    final active = s.url == _active;
    final testing = _testing.contains(s.url);
    final result = _results[s.url];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: active ? const Color(0xFF800000) : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(
                active ? Icons.radio_button_checked : Icons.radio_button_off,
                color: active ? const Color(0xFF800000) : const Color(0xFF9AA7B5),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: active ? null : () => _use(s),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.name,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(s.url,
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF718096))),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Test connection',
                onPressed: testing ? null : () => _test(s),
                icon: testing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.wifi_tethering),
              ),
              if (_servers.length > 1 && !active)
                IconButton(
                  tooltip: 'Remove',
                  onPressed: () => _delete(s),
                  icon: const Icon(Icons.delete_outline),
                ),
            ]),
            if (result != null)
              Padding(
                padding: const EdgeInsets.only(left: 34, top: 4, right: 8),
                child: _resultLine(result),
              ),
          ],
        ),
      ),
    );
  }

  Widget _resultLine(ConnectionTestResult r) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            r.ok ? Icons.check_circle_outline : Icons.error_outline,
            size: 16,
            color: r.ok ? const Color(0xFF159477) : const Color(0xFFC0392B),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              r.message,
              style: TextStyle(
                fontSize: 12,
                color: r.ok ? const Color(0xFF159477) : const Color(0xFFC0392B),
              ),
            ),
          ),
        ],
      );
}