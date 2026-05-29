import 'dart:async';
import 'api_service.dart';

class AdminUser {
  final String email;
  const AdminUser({required this.email});
}

class AdminAuthService {
  AdminAuthService._();
  static final instance = AdminAuthService._();

  final _api = ApiService.instance;
  final _authController = StreamController<AdminUser?>.broadcast();

  AdminUser? get currentUser => _api.isAuthenticated ? const AdminUser(email: 'admin@example.com') : null;
  Stream<AdminUser?> get authStateChanges => _authController.stream;

  Future<void> init() async {
    _authController.add(currentUser);
  }

  Future<String?> signIn(String email, String password) async {
    final ok = await _api.login(email, password);
    if (ok) {
      _authController.add(currentUser);
      return null;
    }
    return 'ইমেইল বা পাসওয়ার্ড ভুল';
  }

  Future<void> signOut() async {
    await _api.logout();
    _authController.add(null);
  }
}
