import 'package:flutter/material.dart';

import '../services/api_base_url_prefs.dart';
import '../services/api_service.dart';
import '../services/local_sms_forward_prefs.dart';
import '../utils/constants.dart';

/// Allowed senders + optional API base URL override + local SMS forward toggle.
class SmsFilterForwardSettingsPage extends StatefulWidget {
  const SmsFilterForwardSettingsPage({super.key});

  @override
  State<SmsFilterForwardSettingsPage> createState() => _SmsFilterForwardSettingsPageState();
}

class _SmsFilterForwardSettingsPageState extends State<SmsFilterForwardSettingsPage> {
  final _urlController = TextEditingController();
  final _addController = TextEditingController();
  bool _forward = false;
  List<String> _allowed = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final url = await ApiBaseUrlPrefs.getOverrideRaw();
    final fwd = await LocalSmsForwardPrefs.isForwardEnabled();
    final list = await LocalSmsForwardPrefs.loadAllowedSenders();
    if (!mounted) return;
    setState(() {
      _urlController.text = url ?? '';
      _forward = fwd;
      _allowed = List.from(list);
      _loading = false;
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    _addController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await ApiBaseUrlPrefs.setOverride(_urlController.text.trim().isEmpty ? null : _urlController.text.trim());
    await LocalSmsForwardPrefs.setForwardEnabled(_forward);
    await LocalSmsForwardPrefs.saveAllowedSenders(_allowed);
    await ApiService.instance.syncBaseUrlFromPrefs();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved')),
      );
    }
  }

  void _addSender() {
    final t = _addController.text.trim();
    if (t.isEmpty) return;
    if (_allowed.any((e) => e.toLowerCase() == t.toLowerCase())) {
      _addController.clear();
      return;
    }
    setState(() {
      _allowed = [..._allowed, t];
      _addController.clear();
    });
  }

  void _removeAt(int i) {
    setState(() {
      _allowed = [..._allowed]..removeAt(i);
    });
  }

  void _loadOperatorPresets() {
    setState(() {
      _allowed = kOperators.map((o) => o.key).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SMS filter & forward'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: _loading ? null : _save,
            child: const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('API base URL', style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _urlController,
                          decoration: const InputDecoration(
                            hintText: 'Leave empty for default (see constants.dart)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Tips: use adb reverse tcp:3000 tcp:3000 with http://127.0.0.1:3000; '
                          'for another PC on Wi‑Fi use http://192.168.x.x:3000; '
                          'for a stable tunnel use ngrok (https://xxxx.ngrok-free.app). '
                          'Clear the field to use the app default.',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            await ApiBaseUrlPrefs.setOverride(null);
                            _urlController.clear();
                            await ApiService.instance.syncBaseUrlFromPrefs();
                            if (!mounted) return;
                            messenger.showSnackBar(
                              const SnackBar(content: Text('Reset to default URL')),
                            );
                          },
                          icon: const Icon(Icons.restore, size: 18),
                          label: const Text('Use default URL'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: SwitchListTile(
                    title: const Text('Forward matching SMS to local server'),
                    subtitle: const Text('POST /api/local-sms-ingest when sender matches the list below'),
                    value: _forward,
                    onChanged: (v) => setState(() => _forward = v),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text('Allowed senders', style: Theme.of(context).textTheme.titleSmall),
                    const Spacer(),
                    TextButton(
                      onPressed: _loadOperatorPresets,
                      child: const Text('Load BD presets'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'If the SMS address contains any of these strings (case-insensitive), or matches a known operator name, the message is forwarded.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _addController,
                        decoration: const InputDecoration(
                          hintText: 'e.g. bKash, 16247',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        textCapitalization: TextCapitalization.none,
                        onSubmitted: (_) => _addSender(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _addSender,
                      child: const Text('Add'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < _allowed.length; i++)
                      InputChip(
                        label: Text(_allowed[i]),
                        onDeleted: () => _removeAt(i),
                      ),
                  ],
                ),
                if (_allowed.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'No senders yet — nothing will match until you add at least one.',
                      style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                    ),
                  ),
              ],
            ),
    );
  }
}
