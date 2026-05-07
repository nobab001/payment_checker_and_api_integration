import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/remote_config.dart';
import '../models/user_model.dart';
import '../utils/constants.dart';

/// Central HTTP client for the VPS Node API.
///
/// Base URL: [kVpsApiBaseUrl] (port 3000). JSON responses use `success`, `token`,
/// `user`, `message`, `exists`, `isNewUser` as produced by `server/app.js`.
///
/// Auth: call [setAuthToken] after login; authenticated requests send
/// `Authorization: Bearer <token>`.
class ApiException implements Exception {
  final int? statusCode;
  final String message;
  final String? code;

  const ApiException({this.statusCode, required this.message, this.code});

  @override
  String toString() => 'ApiException($statusCode: $message)';
}

class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  String? _authToken;

  void setAuthToken(String? token) {
    _authToken = token?.isEmpty == true ? null : token;
  }

  String? get authToken => _authToken;

  Uri _uri(String path) {
    final base = kVpsApiBaseUrl.replaceAll(RegExp(r'/+$'), '');
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$p');
  }

  Map<String, String> _headers({bool auth = false}) {
    final h = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (auth && _authToken != null) {
      h['Authorization'] = 'Bearer $_authToken';
    }
    return h;
  }

  Map<String, dynamic> _decodeBody(String body) {
    if (body.isEmpty) return {};
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    return {};
  }

  /// POST JSON; returns parsed object on 2xx. Throws [ApiException] otherwise.
  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body, {
    bool auth = false,
  }) async {
    final res = await http.post(
      _uri(path),
      headers: _headers(auth: auth),
      body: jsonEncode(body),
    );
    final data = _decodeBody(res.body);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return data;
    }
    final msg = data['message'] as String? ??
        data['error'] as String? ??
        (res.body.isNotEmpty ? res.body : 'Request failed');
    throw ApiException(
      statusCode: res.statusCode,
      message: msg,
      code: data['code'] as String?,
    );
  }

  Future<Map<String, dynamic>> getJson(String path, {bool auth = false}) async {
    final res = await http.get(_uri(path), headers: _headers(auth: auth));
    final data = _decodeBody(res.body);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return data;
    }
    final msg = data['message'] as String? ??
        data['error'] as String? ??
        (res.body.isNotEmpty ? res.body : 'Request failed');
    throw ApiException(
      statusCode: res.statusCode,
      message: msg,
      code: data['code'] as String?,
    );
  }

  // —— Auth / user —— //
  //
  // POST /api/send-otp body: `{ "phone": "<BD mobile OR @gmail.com>" }` — server sends SMS or Gmail OTP.

  /// `true` if backend reports an account for [contact] (phone or email).
  /// On network/API failure returns `true` (same as legacy Firestore behavior).
  Future<bool> checkContactExists(String contact) async {
    try {
      final data = await postJson('/api/check-contact', {'contact': contact});
      return data['exists'] == true;
    } catch (_) {
      return true;
    }
  }

  Future<UserModel?> fetchCurrentUser() async {
    try {
      final data = await getJson('/api/me', auth: true);
      final u = data['user'] as Map<String, dynamic>? ?? data;
      if (u.isEmpty) return null;
      return UserModel.fromJson(u);
    } on ApiException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 403) return null;
      rethrow;
    }
  }

  Future<UserModel> completeProfile({
    required String name,
    required String pin,
    required String phone,
    required String email,
  }) async {
    final data = await postJson(
      '/api/complete-profile',
      {
        'name': name,
        'pin': pin,
        'phone': phone,
        'email': email,
      },
      auth: true,
    );
    final u = data['user'] as Map<String, dynamic>? ?? data;
    return UserModel.fromJson(u);
  }

  // —— Remote config —— //

  Future<RemoteConfig> fetchRemoteConfig() async {
    try {
      final data = await getJson('/api/config');
      return RemoteConfig.fromJson(data);
    } catch (_) {
      return const RemoteConfig();
    }
  }

  // —— Wallet / payments —— //

  Future<Map<String, dynamic>> startWalletTopUp(double amount) async {
    return postJson('/api/wallet/start-top-up', {'amount': amount}, auth: true);
  }

  Future<void> completeWalletTopUp({
    required String pendingId,
    required String paymentID,
  }) async {
    await postJson(
      '/api/wallet/complete-top-up',
      {
        'pendingId': pendingId,
        'paymentID': paymentID,
      },
      auth: true,
    );
  }

  Future<void> purchaseHistorySubscription(String planId) async {
    await postJson(
      '/api/wallet/purchase-history-subscription',
      {'planId': planId},
      auth: true,
    );
  }
}
