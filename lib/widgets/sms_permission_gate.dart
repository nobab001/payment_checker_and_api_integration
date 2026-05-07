import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../providers/sms_provider.dart';
import '../services/app_permissions_service.dart';
import '../services/sms_service.dart';
import '../utils/constants.dart';
import '../screens/splash_screen.dart';

/// On Android, blocks [child] until SMS permission is granted. Notification is
/// requested once (optional). On web / non-Android, [child] shows immediately.
class SmsPermissionGate extends StatefulWidget {
  final Widget child;

  const SmsPermissionGate({super.key, required this.child});

  @override
  State<SmsPermissionGate> createState() => _SmsPermissionGateState();
}

class _SmsPermissionGateState extends State<SmsPermissionGate>
    with WidgetsBindingObserver {
  bool? _smsOk;
  bool _smsServicesStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _evaluate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _evaluate(fromResume: true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<SmsProvider>().onAppResumed();
      });
    }
  }

  Future<void> _evaluate({bool fromResume = false}) async {
    final svc = AppPermissionsService.instance;
    if (!svc.requiresSmsGate) {
      if (mounted) setState(() => _smsOk = true);
      _startSmsIfNeeded();
      return;
    }

    if (!fromResume && _smsOk == null) {
      await svc.requestNotificationOptionalFirstInstall();
    }

    final ok = await svc.isSmsGranted();
    if (!mounted) return;

    setState(() => _smsOk = ok);
    if (ok) _startSmsIfNeeded();
  }

  void _startSmsIfNeeded() {
    if (_smsServicesStarted) return;
    _smsServicesStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<SmsProvider>().init();
    });
  }

  Future<void> _requestSms() async {
    final raw = await SmsService.instance.requestPermissions();
    final granted = raw == true;
    if (!mounted) return;
    if (granted) {
      setState(() => _smsOk = true);
      _startSmsIfNeeded();
    } else {
      setState(() {});
    }
  }

  Future<void> _openSettings() async {
    await openAppSettings();
  }

  @override
  Widget build(BuildContext context) {
    if (_smsOk == null) {
      return const SplashScreen();
    }
    if (_smsOk == true) {
      return widget.child;
    }
    return _PermissionRequiredScaffold(
      onAllowSms: _requestSms,
      onOpenSettings: _openSettings,
    );
  }
}

class _PermissionRequiredScaffold extends StatelessWidget {
  final VoidCallback onAllowSms;
  final VoidCallback onOpenSettings;

  const _PermissionRequiredScaffold({
    required this.onAllowSms,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Icon(Icons.sms_outlined, size: 64, color: AppColors.primary),
              const SizedBox(height: 20),
              Text(
                'অনুমতি প্রয়োজন',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
              ),
              const SizedBox(height: 16),
              Text(
                'প্রথমবার অ্যাপ খুললে নোটিফিকেশন ও এসএমএসের অনুমতি চাওয়া হয়। '
                'নোটিফিকেশন না দিলেও চলবে। '
                'কিন্তু পেমেন্ট এসএমএস ট্র্যাক করতে হলে এসএমএস পড়ার অনুমতি অবশ্যই দিতে হবে — '
                'না দিলে অ্যাপের ভেতরে যাওয়া যাবে না।',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.45,
                  color: Colors.grey.shade800,
                ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: onAllowSms,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'এসএমএস অনুমতি দিন',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: onOpenSettings,
                child: const Text('সেটিংস খুলুন'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
