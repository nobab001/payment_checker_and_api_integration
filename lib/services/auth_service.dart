import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_model.dart';
import 'api_service.dart';

class AuthService {
  static final AuthService instance = AuthService._();
  AuthService._();

  static const _kToken = 'auth_token';
  static const _kUserJson = 'auth_user_json';

  Future<void> persistSession(String token, UserModel user) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kToken, token);
    await p.setString(_kUserJson, jsonEncode(user.toJson()));
    ApiService.instance.setAuthToken(token);
  }

  Future<void> cacheUser(UserModel user) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kUserJson, jsonEncode(user.toJson()));
  }

  Future<String?> readToken() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kToken);
  }

  Future<UserModel?> readCachedUser() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kUserJson);
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return UserModel.fromJson(m);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearSession() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kToken);
    await p.remove(_kUserJson);
    ApiService.instance.setAuthToken(null);
  }

  /// Apply token + in-memory API client without persisting (optional helper).
  void applyToken(String? token) => ApiService.instance.setAuthToken(token);
}
