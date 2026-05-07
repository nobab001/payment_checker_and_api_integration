import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/sync_provider.dart';
import '../sync/sync_config.dart';
import '../utils/constants.dart';

class SyncSettingsScreen extends StatefulWidget {
  const SyncSettingsScreen({super.key});

  @override
  State<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends State<SyncSettingsScreen> {
  final _ipController = TextEditingController();
  final _portController = TextEditingController();
  bool _ipDirty = false;
  bool _portDirty = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadValues());
  }

  void _loadValues() {
    final cfg = context.read<SyncProvider>().config;
    _ipController.text = cfg.mainDeviceIp;
    _portController.text = cfg.port.toString();
    setState(() {
      _ipDirty = false;
      _portDirty = false;
    });
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Future<void> _saveIp() async {
    await context.read<SyncProvider>().setMainIp(_ipController.text.trim());
    setState(() => _ipDirty = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('IP ঠিকানা সেভ হয়েছে')),
      );
    }
  }

  Future<void> _savePort() async {
    final port = int.tryParse(_portController.text.trim());
    if (port == null || port < 1024 || port > 65535) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('পোর্ট 1024–65535 এর মধ্যে হতে হবে'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    await context.read<SyncProvider>().setPort(port);
    setState(() => _portDirty = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('পোর্ট $port সেভ হয়েছে')),
      );
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncProvider>();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('SMS Sync সেটিংস'),
        actions: [
          // Network indicator chip
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Center(
              child: _NetworkChip(available: sync.networkAvailable),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => sync.refresh(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _InfoBanner(),
            const SizedBox(height: 16),
            _ModeSelector(
              current: sync.config.mode,
              onChange: (m) {
                sync.setMode(m);
                _loadValues();
              },
            ),
            const SizedBox(height: 20),
            if (sync.config.mode == DeviceMode.main) ...[
              _MainDevicePanel(sync: sync),
            ] else if (sync.config.mode == DeviceMode.sub) ...[
              _SubDevicePanel(
                sync: sync,
                ipController: _ipController,
                portController: _portController,
                ipDirty: _ipDirty,
                portDirty: _portDirty,
                onIpChanged: () => setState(() => _ipDirty = true),
                onPortChanged: () => setState(() => _portDirty = true),
                onSaveIp: _saveIp,
                onSavePort: _savePort,
              ),
            ] else ...[
              _DisabledPanel(),
            ],
            if (sync.statusMessage.isNotEmpty) ...[
              const SizedBox(height: 20),
              _StatusMessage(message: sync.statusMessage),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Info Banner ───────────────────────────────────────────────────────────────

class _InfoBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withAlpha(15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withAlpha(60)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.sync_alt, color: AppColors.primary, size: 22),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'এই ফিচারটি একটি মেইন ডিভাইস (Parent) এবং একাধিক সাব-ডিভাইস (Sub) এর মধ্যে '
              'SMS স্বয়ংক্রিয়ভাবে সিঙ্ক করে। সাব-ডিভাইস SMS রিসিভ করলে তাৎক্ষণিকভাবে '
              'মেইন ডিভাইসে পাঠায়। পাঠাতে ব্যর্থ হলে লোকাল কিউতে জমা রাখে এবং '
              'পরবর্তী সুযোগে সব একসাথে পাঠায়।',
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.primary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Mode Selector ─────────────────────────────────────────────────────────────

class _ModeSelector extends StatelessWidget {
  final DeviceMode current;
  final void Function(DeviceMode) onChange;

  const _ModeSelector({required this.current, required this.onChange});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ডিভাইস মোড নির্বাচন করুন',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _ModeCard(
                mode: DeviceMode.none,
                icon: Icons.block_outlined,
                label: 'বন্ধ',
                subtitle: 'Sync নেই',
                selected: current == DeviceMode.none,
                color: Colors.grey,
                onTap: () => onChange(DeviceMode.none),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ModeCard(
                mode: DeviceMode.main,
                icon: Icons.hub_outlined,
                label: 'মেইন',
                subtitle: 'Parent device',
                selected: current == DeviceMode.main,
                color: AppColors.primary,
                onTap: () => onChange(DeviceMode.main),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ModeCard(
                mode: DeviceMode.sub,
                icon: Icons.smartphone_outlined,
                label: 'সাব',
                subtitle: 'Child device',
                selected: current == DeviceMode.sub,
                color: Colors.teal,
                onTap: () => onChange(DeviceMode.sub),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ModeCard extends StatelessWidget {
  final DeviceMode mode;
  final IconData icon;
  final String label;
  final String subtitle;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _ModeCard({
    required this.mode,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? color : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? color : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                      color: color.withAlpha(60),
                      blurRadius: 8,
                      offset: const Offset(0, 3))
                ]
              : [],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: selected ? Colors.white : color, size: 26),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.black87,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(
                color: selected ? Colors.white70 : Colors.grey,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Main Device Panel ─────────────────────────────────────────────────────────

class _MainDevicePanel extends StatelessWidget {
  final SyncProvider sync;
  const _MainDevicePanel({required this.sync});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          icon: Icons.hub,
          label: 'মেইন ডিভাইস কনফিগারেশন',
          color: AppColors.primary,
        ),
        const SizedBox(height: 12),

        // Local IP
        _InfoRow(
          icon: Icons.wifi,
          label: 'এই ডিভাইসের IP',
          value: sync.localIp.isNotEmpty ? sync.localIp : 'অজানা',
          onCopy: sync.localIp.isNotEmpty
              ? () {
                  Clipboard.setData(ClipboardData(text: sync.localIp));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${sync.localIp} কপি হয়েছে')),
                  );
                }
              : null,
        ),
        const SizedBox(height: 8),

        // Port
        _InfoRow(
          icon: Icons.settings_ethernet,
          label: 'পোর্ট',
          value: sync.config.port.toString(),
        ),
        const SizedBox(height: 8),

        // Server status
        _ServerStatusRow(
          running: sync.serverRunning,
          isBusy: sync.isBusy,
          onRestart: () => sync.restartServer(),
        ),
        const SizedBox(height: 16),

        // Instructions
        _HintBox(
          icon: Icons.info_outline,
          color: Colors.blue,
          text: 'সাব-ডিভাইসগুলোকে এই IP ও পোর্ট দিন:\n'
              '${sync.localIp.isNotEmpty ? sync.localIp : "<আপনার IP>"} : ${sync.config.port}\n\n'
              'উভয় ডিভাইস একই Wi-Fi/LAN নেটওয়ার্কে থাকতে হবে।',
        ),
      ],
    );
  }
}

// ── Sub-device Panel ──────────────────────────────────────────────────────────

class _SubDevicePanel extends StatelessWidget {
  final SyncProvider sync;
  final TextEditingController ipController;
  final TextEditingController portController;
  final bool ipDirty;
  final bool portDirty;
  final VoidCallback onIpChanged;
  final VoidCallback onPortChanged;
  final VoidCallback onSaveIp;
  final VoidCallback onSavePort;

  const _SubDevicePanel({
    required this.sync,
    required this.ipController,
    required this.portController,
    required this.ipDirty,
    required this.portDirty,
    required this.onIpChanged,
    required this.onPortChanged,
    required this.onSaveIp,
    required this.onSavePort,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          icon: Icons.smartphone,
          label: 'সাব-ডিভাইস কনফিগারেশন',
          color: Colors.teal,
        ),
        const SizedBox(height: 12),

        // Pending badge
        _PendingBadge(count: sync.pendingCount),
        const SizedBox(height: 8),

        // WorkManager status
        const _WorkManagerBadge(),
        const SizedBox(height: 16),

        // Main IP input
        _InputRow(
          controller: ipController,
          label: 'মেইন ডিভাইসের IP ঠিকানা',
          hint: 'যেমন: 192.168.1.100',
          icon: Icons.router_outlined,
          isDirty: ipDirty,
          onChanged: (_) => onIpChanged(),
          onSave: onSaveIp,
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 12),

        // Port input
        _InputRow(
          controller: portController,
          label: 'পোর্ট নম্বর',
          hint: '7890',
          icon: Icons.settings_ethernet,
          isDirty: portDirty,
          onChanged: (_) => onPortChanged(),
          onSave: onSavePort,
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 20),

        // Action buttons
        Row(
          children: [
            Expanded(
              child: _ActionButton(
                label: 'কানেকশন টেস্ট',
                icon: Icons.network_ping,
                color: AppColors.primary,
                loading: sync.isBusy,
                onPressed: () => sync.testConnection(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ActionButton(
                label: 'এখনই পাঠাও',
                icon: Icons.send_outlined,
                color: Colors.teal,
                loading: sync.isBusy,
                onPressed: sync.pendingCount > 0 ? () => sync.flushNow() : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _HintBox(
          icon: Icons.info_outline,
          color: Colors.teal,
          text: 'প্রতিটি নতুন SMS আসার সময় এই ডিভাইস স্বয়ংক্রিয়ভাবে মেইন ডিভাইসে '
              'পাঠানোর চেষ্টা করবে। ব্যর্থ হলে কিউতে জমা রাখবে এবং পরের বার সব একসাথে পাঠাবে।',
        ),
      ],
    );
  }
}

// ── Disabled Panel ────────────────────────────────────────────────────────────

class _DisabledPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 20),
          Icon(Icons.sync_disabled, size: 60, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            'SMS Sync বন্ধ আছে',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600),
          ),
          const SizedBox(height: 6),
          Text(
            'উপরে মোড নির্বাচন করে শুরু করুন',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ── Reusable Sub-widgets ──────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _SectionTitle(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onCopy;
  const _InfoRow(
      {required this.icon,
      required this.label,
      required this.value,
      this.onCopy});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(fontSize: 10, color: Colors.grey)),
                Text(value,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          if (onCopy != null)
            IconButton(
              icon: const Icon(Icons.copy, size: 18),
              color: Colors.grey.shade600,
              tooltip: 'কপি করুন',
              onPressed: onCopy,
            ),
        ],
      ),
    );
  }
}

class _ServerStatusRow extends StatelessWidget {
  final bool running;
  final bool isBusy;
  final VoidCallback onRestart;
  const _ServerStatusRow(
      {required this.running,
      required this.isBusy,
      required this.onRestart});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: running ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: running ? Colors.green.shade200 : Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(
            running ? Icons.check_circle_outline : Icons.cancel_outlined,
            color: running ? Colors.green.shade700 : Colors.red.shade700,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              running ? 'সার্ভার চলছে ✓' : 'সার্ভার বন্ধ আছে',
              style: TextStyle(
                color: running ? Colors.green.shade800 : Colors.red.shade800,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: isBusy ? null : onRestart,
            icon: const Icon(Icons.restart_alt, size: 16),
            label: const Text('রিস্টার্ট'),
          ),
        ],
      ),
    );
  }
}

class _PendingBadge extends StatelessWidget {
  final int count;
  const _PendingBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final color = count > 0 ? Colors.orange : Colors.green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.shade200),
      ),
      child: Row(
        children: [
          Icon(
            count > 0 ? Icons.hourglass_bottom : Icons.check_circle_outline,
            color: color.shade700,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              count > 0
                  ? '$count টি SMS পেন্ডিং কিউতে আছে'
                  : 'পেন্ডিং কিউ খালি ✓',
              style: TextStyle(
                  color: color.shade800, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _InputRow extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool isDirty;
  final void Function(String) onChanged;
  final VoidCallback onSave;
  final TextInputType? keyboardType;

  const _InputRow({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    required this.isDirty,
    required this.onChanged,
    required this.onSave,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType: keyboardType,
                onChanged: onChanged,
                decoration: InputDecoration(
                  hintText: hint,
                  prefixIcon: Icon(icon, size: 20),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                ),
              ),
            ),
            if (isDirty) ...[
              const SizedBox(width: 8),
              FilledButton(
                onPressed: onSave,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 14),
                ),
                child: const Text('সেভ'),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool loading;
  final VoidCallback? onPressed;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.loading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: loading ? null : onPressed,
      icon: loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            )
          : Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 13)),
      style: FilledButton.styleFrom(
        backgroundColor: onPressed == null ? Colors.grey.shade300 : color,
        foregroundColor:
            onPressed == null ? Colors.grey.shade600 : Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

class _HintBox extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _HintBox(
      {required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                  fontSize: 12, color: color.withAlpha(220), height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusMessage extends StatelessWidget {
  final String message;
  const _StatusMessage({required this.message});

  @override
  Widget build(BuildContext context) {
    final isError =
        message.contains('ব্যর্থ') || message.contains('✗') || message.contains('না');
    final color = isError ? Colors.red : Colors.green;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.shade200),
      ),
      child: Text(
        message,
        style: TextStyle(color: color.shade800, fontSize: 13),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// ── Network chip (AppBar indicator) ──────────────────────────────────────────

class _NetworkChip extends StatelessWidget {
  final bool available;
  const _NetworkChip({required this.available});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: available
            ? Colors.green.withAlpha(50)
            : Colors.red.withAlpha(50),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: available ? Colors.green.shade300 : Colors.red.shade300,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            available ? Icons.wifi : Icons.wifi_off,
            size: 13,
            color: available ? Colors.green.shade200 : Colors.red.shade200,
          ),
          const SizedBox(width: 4),
          Text(
            available ? 'Online' : 'Offline',
            style: TextStyle(
              fontSize: 11,
              color: available ? Colors.green.shade100 : Colors.red.shade100,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── WorkManager info row ──────────────────────────────────────────────────────

class _WorkManagerBadge extends StatelessWidget {
  const _WorkManagerBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.purple.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.purple.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule, color: Colors.purple.shade700, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'WorkManager চালু আছে',
                  style: TextStyle(
                    color: Colors.purple.shade800,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'প্রতি ১৫ মিনিটে পেন্ডিং SMS পাঠানোর চেষ্টা করবে — অ্যাপ বন্ধ থাকলেও',
                  style: TextStyle(
                      color: Colors.purple.shade600, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
