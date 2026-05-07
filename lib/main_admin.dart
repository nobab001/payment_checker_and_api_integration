// ── Admin App entry point ─────────────────────────────────────────────────────
//
// Run from Android Studio: open [admin/] as a separate project, or from repo root:
//   flutter run -t lib/main_admin.dart --flavor admin
// NEVER omit `--flavor admin` on Android from root — Gradle would build the `user`
// variant and replace the User App on the device.
//
// Android applicationId: com.yourdomain.adminapp (root `admin` flavor OR admin/android)
//
// Firebase project : payment-checker-4049e  (shared with User App)
// ─────────────────────────────────────────────────────────────────────────────

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Admin package — added as a path dependency in root pubspec.yaml
import 'package:payment_checker_admin/firebase_options.dart'
    as admin_fb;
import 'package:payment_checker_admin/providers/auth_provider.dart';
import 'package:payment_checker_admin/providers/config_provider.dart';
import 'package:payment_checker_admin/screens/admin_dashboard_screen.dart';
import 'package:payment_checker_admin/screens/admin_login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Use admin's own FirebaseOptions (same project, different Android app ID).
  await Firebase.initializeApp(
    options: admin_fb.DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const AdminEntryApp());
}

class AdminEntryApp extends StatelessWidget {
  const AdminEntryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AdminAuthProvider()),
        ChangeNotifierProvider(create: (_) => ConfigProvider()),
      ],
      child: MaterialApp(
        title: 'Payment Checker Admin',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: const Color(0xFF0D1B2A),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF4FC3F7),
            surface: Color(0xFF1A2E42),
          ),
        ),
        home: const _AdminAuthGate(),
      ),
    );
  }
}

class _AdminAuthGate extends StatelessWidget {
  const _AdminAuthGate();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AdminAuthProvider>();
    return auth.isAuthenticated
        ? const AdminDashboardScreen()
        : const AdminLoginScreen();
  }
}
