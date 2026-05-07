import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_config.dart';
import '../providers/config_provider.dart';

class UserManagementScreen extends StatelessWidget {
  const UserManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cfg = context.watch<ConfigProvider>();
    final users = cfg.users;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      appBar: AppBar(
        title: const Text('User Management'),
        backgroundColor: const Color(0xFF0D1B2A),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: users.isEmpty
          ? const Center(
              child: Text('No users found',
                  style: TextStyle(color: Colors.white38)))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: users.length,
              itemBuilder: (_, i) => _UserTile(user: users[i]),
            ),
    );
  }
}

class _UserTile extends StatelessWidget {
  final AppUser user;
  const _UserTile({required this.user});

  @override
  Widget build(BuildContext context) {
    final cfg = context.read<ConfigProvider>();
    return Card(
      color: const Color(0xFF1A2E42),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: user.blocked
                      ? Colors.red.shade900
                      : const Color(0xFF4FC3F7).withAlpha(40),
                  child: Text(
                    user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                    style: TextStyle(
                      color: user.blocked
                          ? Colors.red.shade300
                          : const Color(0xFF4FC3F7),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.name.isNotEmpty ? user.name : '(no name)',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 15),
                      ),
                      Text(user.email,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12)),
                      if (user.phone.isNotEmpty)
                        Text(user.phone,
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 12)),
                    ],
                  ),
                ),
                _RoleBadge(role: user.role),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _PermSwitch(
                  label: 'SMS',
                  value: user.smsEnabled,
                  onChanged: (v) =>
                      cfg.setUserPermissions(user.uid, smsEnabled: v),
                ),
                const SizedBox(width: 12),
                _PermSwitch(
                  label: 'Gmail',
                  value: user.gmailEnabled,
                  onChanged: (v) =>
                      cfg.setUserPermissions(user.uid, gmailEnabled: v),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _confirmToggleBlock(context, cfg),
                  icon: Icon(
                    user.blocked ? Icons.lock_open : Icons.block,
                    size: 16,
                    color: user.blocked
                        ? Colors.greenAccent
                        : Colors.redAccent,
                  ),
                  label: Text(
                    user.blocked ? 'Unblock' : 'Block',
                    style: TextStyle(
                        color: user.blocked
                            ? Colors.greenAccent
                            : Colors.redAccent,
                        fontSize: 13),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmToggleBlock(
      BuildContext context, ConfigProvider cfg) async {
    final action = user.blocked ? 'unblock' : 'block';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A2E42),
        title: Text('Confirm $action',
            style: const TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to $action "${user.name}"?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.white38))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action.toUpperCase(),
                  style: TextStyle(
                      color: user.blocked
                          ? Colors.greenAccent
                          : Colors.redAccent))),
        ],
      ),
    );
    if (confirmed == true) {
      await cfg.blockUser(user.uid, !user.blocked);
    }
  }
}

class _PermSwitch extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _PermSwitch(
      {required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white60, fontSize: 12)),
        const SizedBox(width: 4),
        Transform.scale(
          scale: 0.8,
          child: Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: const Color(0xFF4FC3F7),
            inactiveThumbColor: Colors.white38,
            inactiveTrackColor: Colors.white12,
          ),
        ),
      ],
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final String role;
  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    final isAdmin = role == 'admin';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isAdmin
            ? const Color(0xFF4FC3F7).withAlpha(30)
            : Colors.white.withAlpha(10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isAdmin ? const Color(0xFF4FC3F7) : Colors.white24,
        ),
      ),
      child: Text(
        role.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: isAdmin ? const Color(0xFF4FC3F7) : Colors.white38,
        ),
      ),
    );
  }
}
