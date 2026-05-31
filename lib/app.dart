/// Shared bootstrap for the User App.
///
/// Both [lib/main.dart] (default Flutter entry) and [lib/main_user.dart]
/// (targeted entry for Cursor / flutter run -t) call [bootUserApp].
library;

import 'dart:async';

import 'package:android_id/android_id.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:provider/provider.dart';
import 'package:workmanager/workmanager.dart';

import 'providers/auth_provider.dart';
import 'providers/device_approval_provider.dart';
import 'providers/remote_config_provider.dart';
import 'providers/sms_provider.dart';
import 'providers/sync_provider.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/splash_screen.dart';
import 'repositories/sim_filter_local_repository.dart';
import 'services/api_service.dart';
import 'services/device_approval_bridge.dart';
import 'services/device_session_bridge.dart';
import 'services/sms_service_state_prefs.dart';
import 'services/sms_sync_foreground_service.dart';
import 'sync/sync_worker.dart';
import 'utils/app_crash_logger.dart';
import 'utils/constants.dart';
import 'widgets/device_security_pin_gate.dart';
import 'widgets/sms_permission_gate.dart';

/// Sync engine, session restore, and User App widget tree.
Future<void> bootUserApp() async {
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await SimFilterLocalRepository.instance.ensureDefaults();
      await AppCrashLogger.install();
      if (!kIsWeb) {
        FlutterForegroundTask.initCommunicationPort();
      }

      final auth = AuthProvider();
      await auth.restoreSession();
      await ApiService.instance.syncBaseUrlFromPrefs();

      final deviceApproval = DeviceApprovalProvider();
      DeviceApprovalProvider.wireSignOutBridge(deviceApproval);
      DeviceApprovalBridge.onRejectedMustSignOut = () => auth.signOut();

      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await SmsSyncForegroundService.configurePlugin();
        DeviceSessionBridge.registerOnSignOut(() {
          unawaited(SmsSyncForegroundService.stop());
          unawaited(SmsServiceStatePrefs.deactivateService());
        });
      }

      // Sync engine is Android-only (sqflite + workmanager have no web support).
      final syncProvider = SyncProvider();
      if (!kIsWeb) {
        await Workmanager().initialize(workManagerCallbackDispatcher);
        await syncProvider.init();
      }

      runApp(
        MultiProvider(
          providers: [
            /// Required for [DeviceManagerPage], [DeviceSettingsPage], etc. (`context.read<ApiService>()`).
            /// [DeviceManagerPage] also uses [ApiService.instance] so the screen works even if this is omitted.
            Provider<ApiService>.value(value: ApiService.instance),
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
            ChangeNotifierProvider<DeviceApprovalProvider>.value(
              value: deviceApproval,
            ),
            ChangeNotifierProvider(create: (_) => SmsProvider()),
            ChangeNotifierProvider(
              create: (_) => RemoteConfigProvider()..startListening(),
            ),
            ChangeNotifierProvider(create: (_) => syncProvider),
          ],
          child: const UserApp(),
        ),
      );
    },
    (error, stack) {
      AppCrashLogger.log('zone', error, stack);
    },
  );
}

// ── Root widget ───────────────────────────────────────────────────────────────

class UserApp extends StatelessWidget {
  const UserApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.background,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey.shade50,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
      home: const AppErrorBoundary(child: _AuthGate()),
    );
  }
}

// ── Auth gate ─────────────────────────────────────────────────────────────────

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.restoring) {
      return const SplashScreen();
    }
    if (auth.isLoggedIn) {
      return const _HomeLoader();
    }
    return const LoginScreen();
  }
}

// ── Home loader ───────────────────────────────────────────────────────────────

class _HomeLoader extends StatefulWidget {
  const _HomeLoader();

  @override
  State<_HomeLoader> createState() => _HomeLoaderState();
}

class _HomeLoaderState extends State<_HomeLoader> {
  bool _ready = false;
  bool _needsSetup = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final auth = context.read<AuthProvider>();
    final userModel = auth.user;
    if (!mounted) return;

    if (userModel == null) {
      await auth.signOut();
      return;
    }

    if (userModel.blocked) {
      await auth.signOut();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('আপনার অ্যাকাউন্ট ব্লক করা হয়েছে'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Email/phone OTP is already done on LoginScreen — do not send a second OTP here.

    if (userModel.needsProfileCompletion) {
      setState(() {
        _needsSetup = true;
        _ready = true;
      });
      return;
    }

    if (!mounted) return;
    try {
      if (!kIsWeb) {
        try {
          final hw = await const AndroidId().getId().timeout(
            const Duration(seconds: 8),
          );
          if (hw != null && hw.isNotEmpty) {
            ApiService.instance.setHardwareDeviceId(hw);
          }
        } catch (_) {}
      }
      if (!mounted) return;
      final dev = context.read<DeviceApprovalProvider>();
      await dev.ensureInitialized();
      if (!auth.pendingDevicePinRequired && !dev.isParent) {
        await auth.markDevicePinVerified();
      }
    } catch (e, st) {
      debugPrint('[_HomeLoader] init error: $e');
      debugPrint('$st');
    } finally {
      if (mounted) {
        setState(() => _ready = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SplashScreen();
    if (_needsSetup) {
      return SignupScreen(
        onComplete: () {
          setState(() {
            _needsSetup = false;
            _ready = false;
          });
          _init();
        },
      );
    }
    return const DeviceSecurityPinGate(
      child: SmsPermissionGate(child: HomeScreen()),
    );
  }
}
