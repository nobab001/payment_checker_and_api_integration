import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/device_model.dart';
import '../providers/device_approval_provider.dart';
import '../services/api_service.dart';
import '../utils/constants.dart';
import 'device_settings_page.dart';

class DeviceManagerPage extends StatefulWidget {
  const DeviceManagerPage({super.key});

  @override
  State<DeviceManagerPage> createState() => _DeviceManagerPageState();
}

class _DeviceManagerPageState extends State<DeviceManagerPage> {
  List<DeviceModel> _devices = [];
  bool _loading = true;
  String? _error;
  DeviceApprovalProvider? _deviceApproval;
  late void Function() _approvalListener;

  @override
  void initState() {
    super.initState();
    _approvalListener = () {
      if (mounted) _loadDevices();
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _deviceApproval = context.read<DeviceApprovalProvider>();
      _deviceApproval!.addListener(_approvalListener);
    });
    _loadDevices();
  }

  @override
  void dispose() {
    _deviceApproval?.removeListener(_approvalListener);
    super.dispose();
  }

  Future<void> _loadDevices() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<ApiService>();
      final res = await api.getJson('/api/devices', auth: true);
      if (res['success'] == true) {
        _devices = (res['devices'] as List)
            .map((d) => DeviceModel.fromJson(d as Map<String, dynamic>))
            .toList();
      } else {
        _error = res['message'] ?? 'Failed to load devices';
      }
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _approve(DeviceModel pending) async {
    final api = context.read<ApiService>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await api.approveDevice(pending.id);
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Device approved')));
      await _loadDevices();
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('Approve failed: $e')));
      }
    }
  }

  Future<void> _reject(DeviceModel pending) async {
    final api = context.read<ApiService>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await api.rejectDevice(pending.id);
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Device rejected')));
      await _loadDevices();
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('Reject failed: $e')));
      }
    }
  }

  Future<void> _transferParent(DeviceModel target) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Transfer parent role'),
        content: Text(
          'Make "${target.displayDeviceName}" the parent device? You will lose parent-only actions on this phone until it is transferred back.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Transfer')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final api = context.read<ApiService>();
    final devProv = context.read<DeviceApprovalProvider>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await api.transferParentRole(target.id);
      if (!mounted) return;
      await devProv.refreshThisDeviceFromServer();
      messenger.showSnackBar(const SnackBar(content: Text('Parent role updated')));
      await _loadDevices();
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('Transfer failed: $e')));
      }
    }
  }

  Future<void> _renameDevice(DeviceModel device) async {
    final controller = TextEditingController(text: device.displayDeviceName);
    String? submitted;
    try {
      submitted = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.edit_outlined, size: 22),
              SizedBox(width: 8),
              Expanded(child: Text('Rename device')),
            ],
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 255,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Display name',
              hintText: 'Leave empty to use model name',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => Navigator.pop(ctx, controller.text.trim()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
    if (!mounted || submitted == null) return;
    final api = context.read<ApiService>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await api.updateDeviceName(deviceId: device.id, newName: submitted);
      if (!mounted) return;
      if (res['success'] == true && res['device'] is Map<String, dynamic>) {
        final updated = DeviceModel.fromJson(res['device'] as Map<String, dynamic>);
        setState(() {
          final ix = _devices.indexWhere((e) => e.id == updated.id);
          if (ix >= 0) _devices[ix] = updated;
        });
        messenger.showSnackBar(
          const SnackBar(content: Text('Device name updated')),
        );
      } else {
        final msg = res['message']?.toString() ?? 'Update failed';
        messenger.showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('Update failed: $e')));
      }
    }
  }

  Future<void> _deleteDevice(DeviceModel device) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Device'),
        content: Text('Remove "${device.displayDeviceName}" from your account?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm == true && mounted) {
      try {
        final api = context.read<ApiService>();
        await api.deleteJson('/api/devices/${device.id}', auth: true);
        _loadDevices();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final devProv = context.watch<DeviceApprovalProvider>();
    final myHw = devProv.hardwareDeviceId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Devices'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _devices.isEmpty
                  ? const Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.devices, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('No devices registered', style: TextStyle(fontSize: 16, color: Colors.grey)),
                      ]),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadDevices,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _devices.length,
                        itemBuilder: (ctx, i) {
                          final d = _devices[i];
                          final isSelf = myHw != null && d.deviceId == myHw;
                          final showParentActions = devProv.isParent && d.isPending;
                          final showTransfer =
                              devProv.isParent &&
                              d.isActiveDevice &&
                              !d.isParent &&
                              !isSelf;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              leading: CircleAvatar(
                                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                                child: Icon(
                                  d.isPending ? Icons.hourglass_top : Icons.phone_android,
                                  color: d.isPending ? Colors.orange : AppColors.primary,
                                ),
                              ),
                              title: Row(children: [
                                Expanded(
                                  child: Text(
                                    d.displayDeviceName,
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                ),
                                if (d.isParent)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 4),
                                    child: Icon(Icons.shield, size: 18, color: Colors.amber.shade800),
                                  ),
                                if (d.isActiveDevice)
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined, size: 22),
                                    onPressed: () => _renameDevice(d),
                                    tooltip: 'Edit name',
                                  ),
                              ]),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: [
                                      _buildChip('Status', d.isPending ? 'Pending' : 'Active',
                                          color: d.isPending ? Colors.orange : Colors.green),
                                      if (d.isParent) _buildChip('Role', 'Parent', color: Colors.amber.shade800),
                                    ],
                                  ),
                                  if (d.deviceModel.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Row(children: [
                                      Icon(Icons.phone_iphone, size: 16, color: Colors.grey[600]),
                                      const SizedBox(width: 4),
                                      Text(d.deviceModel),
                                    ]),
                                  ],
                                  if (d.sim1Number != null && d.sim1Number!.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Row(children: [
                                      Icon(Icons.sim_card, size: 16, color: Colors.grey[600]),
                                      const SizedBox(width: 4),
                                      Text('SIM1: ${d.sim1Number} (${d.sim1Operator ?? "?"})'),
                                    ]),
                                  ],
                                  if (d.sim2Number != null && d.sim2Number!.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Row(children: [
                                      Icon(Icons.sim_card_outlined, size: 16, color: Colors.grey[600]),
                                      const SizedBox(width: 4),
                                      Text('SIM2: ${d.sim2Number} (${d.sim2Operator ?? "?"})'),
                                    ]),
                                  ],
                                  if (showParentActions) ...[
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        FilledButton(
                                          onPressed: () => _approve(d),
                                          child: const Text('Accept'),
                                        ),
                                        const SizedBox(width: 10),
                                        OutlinedButton(
                                          onPressed: () => _reject(d),
                                          child: const Text('Reject'),
                                        ),
                                      ],
                                    ),
                                  ],
                                  if (showTransfer) ...[
                                    const SizedBox(height: 10),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: TextButton.icon(
                                        onPressed: () => _transferParent(d),
                                        icon: const Icon(Icons.swap_horiz, size: 18),
                                        label: const Text('Transfer parent role here'),
                                      ),
                                    ),
                                  ],
                                  if (d.isActiveDevice) ...[
                                    const SizedBox(height: 8),
                                    Row(children: [
                                      _buildChip('Filter', d.smsFilterEnabled ? 'On' : 'Off',
                                          color: d.smsFilterEnabled ? Colors.green : Colors.grey),
                                      const SizedBox(width: 8),
                                      _buildChip('Block Unknown', d.blockUnknown ? 'On' : 'Off',
                                          color: d.blockUnknown ? Colors.green : Colors.grey),
                                      const SizedBox(width: 8),
                                      _buildChip('Block Incoming', d.blockIncoming ? 'On' : 'Off',
                                          color: d.blockIncoming ? Colors.green : Colors.grey),
                                    ]),
                                  ],
                                ],
                              ),
                              trailing: d.isActiveDevice
                                  ? IconButton(
                                      icon: const Icon(Icons.settings),
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => DeviceSettingsPage(device: d, onSaved: _loadDevices),
                                          ),
                                        );
                                      },
                                    )
                                  : null,
                              onLongPress: d.isActiveDevice ? () => _deleteDevice(d) : null,
                            ),
                          );
                        },
                      ),
                    ),
    );
  }

  Widget _buildChip(String label, String value, {required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500),
      ),
    );
  }
}
