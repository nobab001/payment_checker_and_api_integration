import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/auth_provider.dart';
import '../providers/device_approval_provider.dart';
import '../providers/remote_config_provider.dart';
import '../providers/sms_provider.dart';
import 'device_settings_page.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../widgets/history_list_widgets.dart';
import 'payment_gateway_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final sms = context.read<SmsProvider>();
      if (!sms.statePreloaded) await sms.preloadPersistedState();
      await sms.load();
    });
  }

  Future<void> _openDeviceSettings(BuildContext context) async {
    final device = context.read<DeviceApprovalProvider>().thisDevice;
    if (device == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Device not ready yet. Open the Devices tab and try again.',
          ),
        ),
      );
      return;
    }
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => DeviceSettingsPage(
          device: device,
          onSaved: () {},
        ),
      ),
    );
    if (!context.mounted) return;
    await context.read<SmsProvider>().refreshSetupState();
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Device settings saved. You can start monitoring now.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _handleMonitoringToggle(BuildContext context) async {
    final sms = context.read<SmsProvider>();
    if (!sms.monitoringEnabled) {
      await sms.refreshSetupState();
      if (!sms.deviceConfigured) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Device Settings-এ SIM slot, মোবাইল নম্বর ও Admin Template সেভ করুন।',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        await _openDeviceSettings(context);
        return;
      }
    }
    final ok = await sms.setMonitoringEnabled(!sms.monitoringEnabled);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please configure your SIM slot and select at least one sender first.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      await _openDeviceSettings(context);
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _export(BuildContext context) async {
    try {
      final file = await StorageService.instance.getExportFile();
      if (!file.existsSync()) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No data to export yet')),
          );
        }
        return;
      }
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Payment Checker — SMS History Export',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  void _confirmClear(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear All History'),
        content: const Text(
          'Deletes all saved SMS records from local storage. Cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(context);
              _searchCtrl.clear();
              context.read<SmsProvider>().setHistorySearchQuery('');
              context.read<SmsProvider>().clearHistory();
            },
            child:
                const Text('Delete All', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sms = context.watch<SmsProvider>();
    final rc = context.watch<RemoteConfigProvider>().config;
    final fmt = NumberFormat('#,##0.00', 'en');
    final filtered = sms.recordsForHistory;

    return RefreshIndicator(
      onRefresh: () => context.read<SmsProvider>().load(),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (!rc.smsApiEnabled)
                  _ApiDisabledBanner(
                    icon: Icons.sms_failed_outlined,
                    message: 'SMS ট্র্যাকিং অ্যাডমিন দ্বারা বন্ধ করা আছে',
                  ),
                if (!rc.gmailApiEnabled)
                  _ApiDisabledBanner(
                    icon: Icons.mail_lock_outlined,
                    message: 'Gmail ট্র্যাকিং অ্যাডমিন দ্বারা বন্ধ করা আছে',
                  ),
                _StatusBanner(
                  granted: sms.permissionsGranted,
                  total: sms.total,
                ),
                if (!kIsWeb) ...[
                  const SizedBox(height: 10),
                  _MonitoringCard(
                    enabled: sms.monitoringEnabled,
                    configured: sms.deviceConfigured,
                    restoring: sms.statePreloaded && sms.serviceActivated,
                    loading: sms.loading,
                    total: sms.total,
                    onToggle: () => _handleMonitoringToggle(context),
                    onConfigure: () => _openDeviceSettings(context),
                  ),
                ],
                _WalletTopBar(
                  walletFormatted:
                      fmt.format(context.watch<AuthProvider>().user?.balance ?? 0),
                  onAddBalance: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const PaymentGatewayScreen(),
                      ),
                    );
                  },
                  onMenuSelected: (value) {
                    switch (value) {
                      case 'export':
                        _export(context);
                        break;
                      case 'clear':
                        _confirmClear(context);
                        break;
                    }
                  },
                ),
                const SizedBox(height: 16),
                const Text(
                  'Operators',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
              ]),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 2.15,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final op = kOperators[i];
                  return _CompactOperatorTile(
                    config: op,
                    count: sms.counts[op.key] ?? 0,
                    balance: fmt.format(sms.balances[op.key] ?? 0),
                  );
                },
                childCount: kOperators.length,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Live history',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _searchCtrl,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'খুঁজুন — অঙ্ক, TrxID, টাকার পরিমাণ…',
                      prefixIcon:
                          const Icon(Icons.search, size: 22),
                      suffixIcon: sms.historySearchQuery.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear, size: 20),
                              onPressed: () {
                                _searchCtrl.clear();
                                unawaited(
                                  context
                                      .read<SmsProvider>()
                                      .setHistorySearchQuery(''),
                                );
                              },
                            ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: AppColors.primary,
                          width: 1.5,
                        ),
                      ),
                    ),
                    onChanged: (v) {
                      unawaited(
                        context.read<SmsProvider>().setHistorySearchQuery(v),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        FilterChip(
                          label: const Text('All'),
                          selected: sms.filter == 'All',
                          onSelected: (_) =>
                              context.read<SmsProvider>().setFilter('All'),
                        ),
                        const SizedBox(width: 6),
                        ...kOperators.map(
                          (op) => Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: FilterChip(
                              label: Text(op.key),
                              selected: sms.filter == op.key,
                              onSelected: (_) => context
                                  .read<SmsProvider>()
                                  .setFilter(op.key),
                              selectedColor: op.color.withAlpha(40),
                              checkmarkColor: op.color,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          if (sms.loading || sms.searchingRemote)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (filtered.isEmpty)
            SliverToBoxAdapter(
              child: HistoryListEmptyState(
                hasRecords: sms.records.isNotEmpty,
                monitoringEnabled: sms.monitoringEnabled,
                deviceConfigured: sms.deviceConfigured,
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) =>
                      SmsHistoryListTile(record: filtered[i]),
                  childCount: filtered.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _WalletTopBar extends StatelessWidget {
  final String walletFormatted;
  final VoidCallback onAddBalance;
  final void Function(String) onMenuSelected;

  const _WalletTopBar({
    required this.walletFormatted,
    required this.onAddBalance,
    required this.onMenuSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 1,
      shadowColor: Colors.black12,
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.account_balance_wallet_outlined,
                color: AppColors.primary, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Total wallet balance',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '৳ $walletFormatted',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: Colors.grey.shade700, size: 22),
              itemBuilder: (ctx) => const [
                PopupMenuItem(value: 'export', child: Text('Export JSON')),
                PopupMenuItem(value: 'clear', child: Text('Clear all')),
              ],
              onSelected: onMenuSelected,
            ),
            const SizedBox(width: 4),
            FilledButton(
              onPressed: onAddBalance,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'Add Balance',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactOperatorTile extends StatelessWidget {
  final OperatorConfig config;
  final int count;
  final String balance;

  const _CompactOperatorTile({
    required this.config,
    required this.count,
    required this.balance,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          colors: [config.color, config.color.withAlpha(200)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: config.color.withAlpha(45),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          Icon(config.icon, color: Colors.white.withAlpha(230), size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  config.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '৳ $balance',
                  style: TextStyle(
                    color: Colors.white.withAlpha(230),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '$count tx',
                  style: TextStyle(
                    color: Colors.white.withAlpha(170),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ApiDisabledBanner extends StatelessWidget {
  final IconData icon;
  final String message;
  const _ApiDisabledBanner({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.red.shade600, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: Colors.red.shade700, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonitoringCard extends StatelessWidget {
  final bool enabled;
  final bool configured;
  final bool restoring;
  final bool loading;
  final int total;
  final VoidCallback onToggle;
  final VoidCallback onConfigure;

  const _MonitoringCard({
    required this.enabled,
    required this.configured,
    required this.restoring,
    required this.loading,
    required this.total,
    required this.onToggle,
    required this.onConfigure,
  });

  @override
  Widget build(BuildContext context) {
    final color = enabled
        ? Colors.green
        : configured
            ? Colors.orange
            : Colors.grey;
    final statusText = enabled
        ? 'ACTIVE · Listening · $total records synced'
        : restoring
            ? 'ACTIVE · Restoring background service…'
            : configured
                ? 'Ready — tap Start Service'
                : 'Setup required — configure SIM & Admin Template';
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  enabled ? Icons.sensors : Icons.settings_suggest_outlined,
                  color: color.shade600,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    statusText,
                    style: TextStyle(
                      color: color.shade700,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            if (!configured) ...[
              const SizedBox(height: 8),
              Text(
                'Settings-এ SIM slot, মোবাইল নম্বর ও Admin Template/Center সেভ করুন। তারপর Start Service চালু হবে।',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.35),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: loading
                  ? const Center(
                      child: SizedBox(
                        height: 32,
                        width: 32,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton.icon(
                          onPressed: loading
                              ? null
                              : (!configured && !enabled)
                                  ? null
                                  : (restoring && !enabled)
                                      ? null
                                      : onToggle,
                          icon: Icon(
                            enabled
                                ? Icons.stop_circle_outlined
                                : Icons.play_circle_outlined,
                            size: 18,
                          ),
                          label: Text(
                            enabled
                                ? 'Stop Service'
                                : restoring
                                    ? 'Service Active'
                                    : configured
                                        ? 'Start Service'
                                        : 'Start Service',
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: enabled
                                ? Colors.red.shade600
                                : configured
                                    ? Colors.green.shade600
                                    : Colors.grey.shade500,
                            disabledBackgroundColor: Colors.grey.shade400,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                        if (!configured) ...[
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: onConfigure,
                            icon: const Icon(Icons.tune, size: 18),
                            label: const Text('Device Settings'),
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final bool granted;
  final int total;

  const _StatusBanner({required this.granted, required this.total});

  @override
  Widget build(BuildContext context) {
    final color = granted ? Colors.green : Colors.orange;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.shade300),
      ),
      child: Row(
        children: [
          Icon(
            granted ? Icons.sensors : Icons.sensors_off,
            color: color.shade700,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              granted
                  ? 'Listening for SMS · $total saved'
                  : 'SMS permission not granted — tap to fix',
              style: TextStyle(color: color.shade800, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
