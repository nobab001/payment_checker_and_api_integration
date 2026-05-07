import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_checker_admin/firebase_options.dart';
import 'package:payment_checker_admin/providers/auth_provider.dart';
import 'package:payment_checker_admin/providers/config_provider.dart';
import 'package:payment_checker_admin/screens/admin_login_screen.dart';
import 'package:provider/provider.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    setupFirebaseCoreMocks();
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } on FirebaseException catch (e) {
      if (e.code != 'duplicate-app') rethrow;
    }
  });

  testWidgets('Admin login screen shows title and email field', (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AdminAuthProvider()),
          ChangeNotifierProvider(create: (_) => ConfigProvider()),
        ],
        child: const MaterialApp(
          home: AdminLoginScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Admin Panel'), findsOneWidget);
    expect(find.byType(TextFormField), findsWidgets);
  });
}
