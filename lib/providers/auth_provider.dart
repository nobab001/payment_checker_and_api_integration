import 'package:flutter/material.dart';

import '../models/user_model.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/device_session_bridge.dart';

class AuthProvider extends ChangeNotifier {
  UserModel? _user;
  bool _loading = false;
  bool _restoring = true;
  String? _error;

  // Set during new-user OTP verification; cleared after signup complete
  String? pendingContact;
  bool pendingIsPhone = false;
  bool _devicePinVerifiedThisSession = false;
  bool pendingDevicePinRequired = false;

  bool get devicePinVerifiedThisSession => _devicePinVerifiedThisSession;

  UserModel? get user => _user;
  bool get loading => _loading;
  bool get restoring => _restoring;
  String? get error => _error;
  bool get isLoggedIn => _user != null;

  /// Call once at startup (after [WidgetsFlutterBinding.ensureInitialized]).
  Future<void> restoreSession() async {
    _restoring = true;
    notifyListeners();
    try {
      final token = await AuthService.instance.readToken();
      if (token == null || token.isEmpty) {
        _user = null;
        return;
      }
      AuthService.instance.applyToken(token);
      try {
        final fresh = await ApiService.instance.fetchCurrentUser();
        if (fresh != null) {
          _user = fresh;
          await AuthService.instance.cacheUser(fresh);
        } else {
          _user = await AuthService.instance.readCachedUser();
          if (_user == null) {
            await AuthService.instance.clearSession();
          }
        }
      } catch (_) {
        _user = await AuthService.instance.readCachedUser();
        if (_user == null) {
          await AuthService.instance.clearSession();
        }
      }

      if (_user != null) {
        final pinOk = await AuthService.instance.isDevicePinVerifiedForUser(_user!.id);
        if (pinOk) {
          _devicePinVerifiedThisSession = true;
          pendingDevicePinRequired = false;
        }
        // SIM filter cache sync runs after [DeviceApprovalProvider.ensureInitialized].
      }
    } finally {
      _restoring = false;
      notifyListeners();
    }
  }

  void setUser(UserModel user) {
    _user = user;
    AuthService.instance.cacheUser(user);
    notifyListeners();
  }

  void setPendingContact(String contact, bool isPhone) {
    pendingContact = contact;
    pendingIsPhone = isPhone;
  }

  void clearPendingContact() {
    pendingContact = null;
    pendingIsPhone = false;
  }

  Future<void> markDevicePinVerified() async {
    _devicePinVerifiedThisSession = true;
    pendingDevicePinRequired = false;
    final uid = _user?.id;
    if (uid != null && uid.isNotEmpty) {
      await AuthService.instance.persistDevicePinVerified(uid);
    }
    notifyListeners();
  }

  void setPendingDevicePinRequired(bool value) {
    pendingDevicePinRequired = value;
    notifyListeners();
  }

  /// After OTP verification: store JWT and user from API (or load via `/api/me` if [user] is null).
  Future<bool> signInWithSession(String token, UserModel? user) async {
    _loading = true;
    _error = null;
    _devicePinVerifiedThisSession = false;
    await AuthService.instance.clearDevicePinVerified();
    notifyListeners();
    try {
      ApiService.instance.setAuthToken(token);
      final resolved = user ?? await ApiService.instance.fetchCurrentUser();
      if (resolved == null) {
        await AuthService.instance.clearSession();
        _error = 'প্রোফাইল লোড হয়নি';
        _user = null;
        _loading = false;
        notifyListeners();
        return false;
      }
      await AuthService.instance.persistSession(token, resolved);
      _user = resolved;
      await ApiService.instance.syncBaseUrlFromPrefs();
    } catch (e) {
      await AuthService.instance.clearSession();
      _user = null;
      _error = e.toString();
    }
    _loading = false;
    notifyListeners();
    return _error == null && _user != null;
  }

  /// Refresh profile from [GET /api/me].
  Future<void> refreshUser() async {
    final token = await AuthService.instance.readToken();
    if (token == null || token.isEmpty) return;
    AuthService.instance.applyToken(token);
    try {
      final fresh = await ApiService.instance.fetchCurrentUser();
      if (fresh != null) {
        _user = fresh;
        await AuthService.instance.cacheUser(fresh);
        notifyListeners();
      }
    } catch (_) {
      // keep cached user
    }
  }

  Future<void> signOut() async {
    await AuthService.instance.clearSession();
    _user = null;
    _devicePinVerifiedThisSession = false;
    pendingDevicePinRequired = false;
    clearPendingContact();
    DeviceSessionBridge.notifySignedOut();
    notifyListeners();
  }
}
