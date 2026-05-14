/// Shared bootstrap for the User App.
///
/// Both [lib/main.dart] (default Flutter entry) and [lib/main_user.dart]
/// (targeted entry for Cursor / flutter run -t) call [bootUserApp].
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
import 'services/api_service.dart';
import 'sync/sync_worker.dart';
import 'utils/constants.dart';
import 'widgets/sms_permission_gate.dart';

/// Sync engine, session restore, and User App widget tree (no Firebase).
Future<void> bootUserApp() async {
  WidgetsFlutterBinding.ensureInitialized();

  final auth = AuthProvider();
  await auth.restoreSession();
  await ApiService.instance.syncBaseUrlFromPrefs();

  final deviceApproval = DeviceApprovalProvider();
  DeviceApprovalProvider.wireSignOutBridge(deviceApproval);

  // Sync engine is Android-only (sqflite + workmanager have no web support).
  final syncProvider = SyncProvider();
  if (!kIsWeb) {
    await Workmanager().initialize(
      workManagerCallbackDispatcher,
    );
    await syncProvider.init();
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<DeviceApprovalProvider>.value(value: deviceApproval),
        ChangeNotifierProvider(create: (_) => SmsProvider()),
        ChangeNotifierProvider(
            create: (_) => RemoteConfigProvider()..startListening()),
        ChangeNotifierProvider(create: (_) => syncProvider),
      ],
      child: const UserApp(),
    ),
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
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
      home: const _AuthGate(),
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

    setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SplashScreen();
    if (_needsSetup) {
      return SignupScreen(onComplete: () {
        setState(() {
          _needsSetup = false;
          _ready = false;
        });
        _init();
      });
    }
    return const SmsPermissionGate(child: HomeScreen());
  }
}
