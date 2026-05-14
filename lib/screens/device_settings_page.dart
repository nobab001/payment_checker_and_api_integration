import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/device_model.dart';
import '../services/api_service.dart';
import '../utils/constants.dart';

class DeviceSettingsPage extends StatefulWidget {
  final DeviceModel device;
  final VoidCallback? onSaved;

  const DeviceSettingsPage({super.key, required this.device, this.onSaved});

  @override
  State<DeviceSettingsPage> createState() => _DeviceSettingsPageState();
}

class _DeviceSettingsPageState extends State<DeviceSettingsPage> {
  late bool _sim1On;
  late List<String> _sim1Filters;
  late bool _sim2On;
  late List<String> _sim2Filters;
  final _filterController = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final sims =
        widget.device.simSettings ??
        SimSettings(
          sim1: SimConfig(isEnabled: widget.device.smsFilterEnabled),
          sim2: SimConfig(isEnabled: widget.device.smsFilterEnabled),
        );
    _sim1On = sims.sim1.isEnabled;
    _sim1Filters = List.from(sims.sim1.filters);
    _sim2On = sims.sim2.isEnabled;
    _sim2Filters = List.from(sims.sim2.filters);
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  void _addFilter(bool isSim1) {
    final text = _filterController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      if (isSim1) {
        if (!_sim1Filters.contains(text)) _sim1Filters.add(text);
      } else {
        if (!_sim2Filters.contains(text)) _sim2Filters.add(text);
      }
      _filterController.clear();
    });
  }

  void _removeFilter(bool isSim1, String filter) {
    setState(() {
      if (isSim1) {
        _sim1Filters.remove(filter);
      } else {
        _sim2Filters.remove(filter);
      }
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final api = context.read<ApiService>();
      await api.putJson('/api/devices/${widget.device.id}/settings', {
        'sim1': {'status': _sim1On ? 'on' : 'off', 'filters': _sim1Filters},
        'sim2': {'status': _sim2On ? 'on' : 'off', 'filters': _sim2Filters},
      }, auth: true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Settings saved'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onSaved?.call();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.device.displayDeviceName),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Save',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSimCard(
            title: 'SIM 1',
            icon: Icons.sim_card,
            isOn: _sim1On,
            filters: _sim1Filters,
            onToggle: (v) => setState(() => _sim1On = v),
            onAdd: (f) => _addFilter(true),
            onRemove: (f) => _removeFilter(true, f),
          ),
          const SizedBox(height: 16),
          _buildSimCard(
            title: 'SIM 2',
            icon: Icons.sim_card_outlined,
            isOn: _sim2On,
            filters: _sim2Filters,
            onToggle: (v) => setState(() => _sim2On = v),
            onAdd: (f) => _addFilter(false),
            onRemove: (f) => _removeFilter(false, f),
          ),
          const SizedBox(height: 24),
          Card(
            color: Colors.blue.shade50,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'SMS will only be backed up if:\n'
                      '• The SIM is enabled (toggle ON)\n'
                      '• The SMS contains at least one filter keyword\n'
                      '• Leave filters empty to backup ALL SMS from that SIM',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimCard({
    required String title,
    required IconData icon,
    required bool isOn,
    required List<String> filters,
    required ValueChanged<bool> onToggle,
    required ValueChanged<String> onAdd,
    required ValueChanged<String> onRemove,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppColors.primary),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Switch(
                  value: isOn,
                  onChanged: onToggle,
                  activeThumbColor: AppColors.primary,
                ),
                Text(
                  isOn ? 'ON' : 'OFF',
                  style: TextStyle(
                    color: isOn ? Colors.green : Colors.grey,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            if (isOn) ...[
              const Divider(height: 24),
              const Text(
                'Filter Keywords (match SMS body)',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: filters
                    .map(
                      (f) => Chip(
                        label: Text(f, style: const TextStyle(fontSize: 13)),
                        onDeleted: () => onRemove(f),
                        deleteIconColor: Colors.red,
                        backgroundColor: Colors.green.shade50,
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _filterController,
                      decoration: const InputDecoration(
                        hintText: 'e.g. bKash, Nagad, Rocket',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        isDense: true,
                      ),
                      onSubmitted: (_) => onAdd(_filterController.text.trim()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: () => onAdd(_filterController.text.trim()),
                    icon: const Icon(Icons.add),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
