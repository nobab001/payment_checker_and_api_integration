import 'package:flutter/foundation.dart';
import '../services/auth_service.dart';

class AdminAuthProvider extends ChangeNotifier {
  final _svc = AdminAuthService.instance;

  AdminUser? _user;
  bool _loading = false;
  String? _error;

  AdminUser? get user => _user;
  bool get loading => _loading;
  String? get error => _error;
  bool get isAuthenticated => _user != null;

  AdminAuthProvider() {
    _svc.authStateChanges.listen((u) {
      _user = u;
      notifyListeners();
    });
    _user = _svc.currentUser;
  }

  Future<bool> signIn(String email, String password) async {
    _loading = true;
    _error = null;
    notifyListeners();
    _error = await _svc.signIn(email, password);
    _loading = false;
    notifyListeners();
    return _error == null;
  }

  Future<void> signOut() async {
    await _svc.signOut();
  }
}
