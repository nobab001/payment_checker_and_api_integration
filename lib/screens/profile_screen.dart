import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/device_approval_provider.dart';
import '../services/payment_service.dart';
import '../utils/constants.dart';
import '../utils/parent_recovery.dart';
import '../widgets/profile_credentials_card.dart';
import 'api_integration/api_integration_hub_screen.dart';
import 'sms_filter_forward_settings_page.dart';
import 'pin_settings_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    if (user == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 20),
          CircleAvatar(
            radius: 40,
            backgroundColor: AppColors.primary,
            child: Text(
              user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            user.name,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          Text(
            user.role.toUpperCase(),
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 24),
          const ProfileCredentialsCard(),
          const SizedBox(height: 12),
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: Icon(Icons.hub_outlined, color: AppColors.primary),
              title: const Text(
                'API Integration',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Daraz, Alibaba — একই SIM দিয়ে মাল্টি-সাইট পেমেন্ট গেটওয়ে',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const ApiIntegrationHubScreen(),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: _infoTile(Icons.badge_outlined, 'Role', user.role),
          ),
          const SizedBox(height: 16),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.workspace_premium_outlined,
                          color: AppColors.primary),
                      const SizedBox(width: 8),
                      const Text(
                        'ইতিহাস সেবা (ওয়ালেট থেকে)',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'ওয়ালেট: ৳ ${NumberFormat('#,##0.00', 'en').format(user.balance)}',
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user.historyPremiumUntil != null
                        ? 'প্রিমিয়াম: ${DateFormat('d MMM yyyy').format(user.historyPremiumUntil!)} পর্যন্ত'
                        : 'প্রিমিয়াম সক্রিয় নয়',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'টাকা অ্যাপ ওয়ালেটে থাকতে হবে (ড্যাশবোর্ড → Add Balance)।',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            try {
                              await PaymentService.instance
                                  .purchaseHistorySubscription('history_10d');
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          '১০ দিনের সেবা সক্রিয় হয়েছে')),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('$e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                          child: const Text('১০ দিন'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            try {
                              await PaymentService.instance
                                  .purchaseHistorySubscription('history_15d');
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          '১৫ দিনের সেবা সক্রিয় হয়েছে')),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('$e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                          child: const Text('১৫ দিন'),
                        ),
                      ),
                    ],
                  ),
                  const Text(
                    'মূল্য: ৳১০০ / ৳১৫০ (সার্ভারে নির্ধারিত)',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: Icon(Icons.lock_reset, color: AppColors.primary, size: 26),
              title: const Text(
                'নিরাপত্তা পিন',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                user.pinConfigured
                    ? 'পিন পরিবর্তন বা OTP দিয়ে রিসেট'
                    : 'নতুন পিন সেট করুন',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PinSettingsScreen()),
                );
              },
            ),
          ),
          if (!kIsWeb) ...[
            const SizedBox(height: 12),
            _parentRecoveryTile(context),
          ],
          const SizedBox(height: 12),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: Icon(Icons.filter_alt_outlined, color: AppColors.primary, size: 26),
              title: const Text('SMS filter & forward', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Allowed senders, local server URL'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SmsFilterForwardSettingsPage()),
                );
              },
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _confirmSignOut(context),
              icon: const Icon(Icons.logout, color: Colors.red),
              label: const Text('Sign Out',
                  style: TextStyle(color: Colors.red)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _parentRecoveryTile(BuildContext context) {
    final dev = context.watch<DeviceApprovalProvider>();
    if (dev.isParent) return const SizedBox.shrink();

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(Icons.phonelink_setup, color: Colors.orange.shade800, size: 26),
        title: const Text(
          'Restore parent on this phone',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: const Text(
          'If parent was moved to another device and that phone no longer works',
          style: TextStyle(fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _showParentRecoveryDialog(context),
      ),
    );
  }

  void _showParentRecoveryDialog(BuildContext context) {
    final pinCtrl = TextEditingController();
    final keyCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore parent role'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'এই ফোনটিকে প্যারেন্ট করবে। সাইনআপের Security PIN দিন। '
              'মডেল লিখতে হবে না — অ্যাপ নিজে এই হ্যান্ডসেট চিনবে।',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pinCtrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: 'Account security PIN',
                counterText: '',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: keyCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Recovery key (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final messenger = ScaffoldMessenger.of(context);
              await context.read<DeviceApprovalProvider>().ensureInitialized();
              final err = await recoverParentOnThisDevice(
                accountPin: pinCtrl.text,
                recoveryKey: keyCtrl.text,
              );
              if (!context.mounted) return;
              if (err != null) {
                messenger.showSnackBar(SnackBar(content: Text(err)));
                return;
              }
              await refreshDeviceApprovalAfterRecovery(
                context.read<DeviceApprovalProvider>(),
              );
              messenger.showSnackBar(
                const SnackBar(content: Text('Parent role restored on this account')),
              );
            },
            child: const Text('Restore'),
          ),
        ],
      ),
    );
  }

  Widget _infoTile(IconData icon, String label, String value) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primary, size: 22),
      title: Text(label,
          style: const TextStyle(fontSize: 11, color: Colors.grey)),
      subtitle: Text(value,
          style:
              const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
    );
  }

  void _confirmSignOut(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Sign out of your account?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary),
            onPressed: () {
              Navigator.pop(context);
              context.read<AuthProvider>().signOut();
            },
            child: const Text('Sign Out',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
