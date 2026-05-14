import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/device_model.dart';
import '../models/remote_config.dart';
import '../models/user_model.dart';
import 'api_base_url_prefs.dart';

/// Central HTTP client for the Node API.
///
/// Default base URL: [kDefaultApiBaseUrl] in `lib/config/api_config.dart` (overridable via prefs).
/// `user`, `message`, `exists`, `isNewUser` as produced by `server/app.js`.
///
/// Auth: call [setAuthToken] after login; authenticated requests send
/// `Authorization: Bearer <token>`.
///
/// **Login / connectivity:** [ensureServerReachable] runs `GET /health` before OTP.
/// Socket/HTTP failures are turned into [ApiException] with `code` set for UI mapping:
/// `connection_failed` (after 3 transport retries), `network_refused`, `network_dns`,
/// `network_routing`, generic `network`, and `timeout`.
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
  String? _hardwareDeviceId;
  String _apiBase = normalizeApiBaseUrl(kDefaultApiBaseUrl);

  /// Current API origin (after [syncBaseUrlFromPrefs]); for Socket.io, logs, toasts.
  String get resolvedApiBase => _apiBase;

  void setAuthToken(String? token) {
    _authToken = token?.isEmpty == true ? null : token;
  }

  void setHardwareDeviceId(String? id) {
    _hardwareDeviceId = id?.isEmpty == true ? null : id;
  }

  String? get authToken => _authToken;

  /// Reload API host from SharedPreferences (call after changing base URL in settings).
  Future<void> syncBaseUrlFromPrefs() async {
    final b = await ApiBaseUrlPrefs.getEffectiveBaseUrl();
    _apiBase = normalizeApiBaseUrl(b);
  }

  Uri _uri(String path) {
    final base = _apiBase;
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
    if (auth && _hardwareDeviceId != null) {
      h['X-Device-Id'] = _hardwareDeviceId!;
    }
    return h;
  }

  Map<String, dynamic> _decodeBody(String body) {
    if (body.isEmpty) return {};
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    return {};
  }

  /// Normalize contact: trim, lowercase for email, digits-only for phone.
  static String normalizeContactForApi(String contact) {
    final c = contact.trim();
    if (c.contains('@')) return c.toLowerCase();
    return c.replaceAll(RegExp(r'[^\d+]'), '');
  }

  /// Quick reachability check before login / OTP (`GET /health` on current [\_apiBase]).
  ///
  /// On failure the app shows Bengali hints; see [LoginScreen._connectivityMessage].
  /// Typical fixes: run Node on port 3000, `adb reverse tcp:3000 tcp:3000` for
  /// `127.0.0.1`, or set API URL under Profile → SMS filter & forward.
  Future<void> ensureServerReachable() async {
    await getJson('/health');
  }

  static const Duration _kTimeout = Duration(seconds: 15);
  static const int _connectionAttempts = 3;
  static const Duration _retryDelay = Duration(milliseconds: 450);

  /// Retries transient transport failures up to [_connectionAttempts] times.
  Future<http.Response> _sendWithConnectionRetries(
    Future<http.Response> Function() send,
  ) async {
    for (var attempt = 0; attempt < _connectionAttempts; attempt++) {
      try {
        return await send().timeout(_kTimeout);
      } on TimeoutException {
        if (attempt >= _connectionAttempts - 1) break;
      } on SocketException {
        if (attempt >= _connectionAttempts - 1) break;
      } on HttpException {
        if (attempt >= _connectionAttempts - 1) break;
      } on TlsException {
        if (attempt >= _connectionAttempts - 1) break;
      }
      await Future<void>.delayed(_retryDelay);
    }
    throw ApiException(
      message:
          'Connection failed to $_apiBase. Please check if the server is running.',
      code: 'connection_failed',
    );
  }

  Never _wrapNetworkError(Object e) {
    if (e is TimeoutException) {
      throw const ApiException(message: 'সার্ভার রেসপন্স দেরি করছে', code: 'timeout');
    }
    if (e is SocketException) {
      final lower = e.message.toLowerCase();
      final errno = e.osError?.errorCode;
      // Linux/Android: 111 = connection refused; Windows uses different numbers — also match text.
      if (lower.contains('connection refused') || errno == 111) {
        throw const ApiException(
          message: 'সার্ভার চালু নেই বা পোর্ট বন্ধ — Node API চালু আছে কিনা দেখুন',
          code: 'network_refused',
        );
      }
      if (lower.contains('failed host lookup') ||
          lower.contains('name or service not known') ||
          lower.contains('no address associated with hostname')) {
        throw const ApiException(
          message: 'সার্ভার ঠিকানা খুঁজে পাওয়া যায়নি — URL বা DNS পরীক্ষা করুন',
          code: 'network_dns',
        );
      }
      if (lower.contains('network is unreachable') ||
          lower.contains('no route to host') ||
          errno == 101 ||
          errno == 113) {
        throw const ApiException(
          message: 'নেটওয়ার্ক রুট নেই — Wi‑Fi/মোবাইল ডেটা বা VPN পরীক্ষা করুন',
          code: 'network_routing',
        );
      }
      throw const ApiException(message: 'ইন্টারনেট বা সার্ভার কানেকশন নেই', code: 'network');
    }
    if (e is HttpException) {
      throw const ApiException(message: 'ইন্টারনেট বা সার্ভার কানেকশন নেই', code: 'network');
    }
    throw ApiException(message: e.toString());
  }

  /// POST JSON; returns parsed object on 2xx. Throws [ApiException] otherwise.
  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body, {
    bool auth = false,
  }) async {
    try {
      final res = await _sendWithConnectionRetries(
        () => http.post(
          _uri(path),
          headers: _headers(auth: auth),
          body: jsonEncode(body),
        ),
      );
      final data = _decodeBody(res.body);
      if (res.statusCode >= 200 && res.statusCode < 300) return data;
      final msg =
          data['message'] as String? ??
          data['error'] as String? ??
          (res.body.isNotEmpty ? res.body : 'Request failed');
      throw ApiException(
        statusCode: res.statusCode,
        message: msg,
        code: data['code'] as String?,
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      _wrapNetworkError(e);
    }
  }

  Future<Map<String, dynamic>> getJson(String path, {bool auth = false}) async {
    try {
      final res = await _sendWithConnectionRetries(
        () => http.get(_uri(path), headers: _headers(auth: auth)),
      );
      final data = _decodeBody(res.body);
      if (res.statusCode >= 200 && res.statusCode < 300) return data;
      final msg =
          data['message'] as String? ??
          data['error'] as String? ??
          (res.body.isNotEmpty ? res.body : 'Request failed');
      throw ApiException(
        statusCode: res.statusCode,
        message: msg,
        code: data['code'] as String?,
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      _wrapNetworkError(e);
    }
  }

  /// PUT JSON; returns parsed object on 2xx. Throws [ApiException] otherwise.
  Future<Map<String, dynamic>> putJson(
    String path,
    Map<String, dynamic> body, {
    bool auth = false,
  }) async {
    try {
      final res = await _sendWithConnectionRetries(
        () => http.put(
          _uri(path),
          headers: _headers(auth: auth),
          body: jsonEncode(body),
        ),
      );
      final data = _decodeBody(res.body);
      if (res.statusCode >= 200 && res.statusCode < 300) return data;
      final msg =
          data['message'] as String? ??
          data['error'] as String? ??
          (res.body.isNotEmpty ? res.body : 'Request failed');
      throw ApiException(
        statusCode: res.statusCode,
        message: msg,
        code: data['code'] as String?,
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      _wrapNetworkError(e);
    }
  }

  /// DELETE request; returns parsed object on 2xx. Throws [ApiException] otherwise.
  Future<Map<String, dynamic>> deleteJson(
    String path, {
    bool auth = false,
  }) async {
    try {
      final res = await _sendWithConnectionRetries(
        () => http.delete(_uri(path), headers: _headers(auth: auth)),
      );
      final data = _decodeBody(res.body);
      if (res.statusCode >= 200 && res.statusCode < 300) return data;
      final msg =
          data['message'] as String? ??
          data['error'] as String? ??
          (res.body.isNotEmpty ? res.body : 'Request failed');
      throw ApiException(
        statusCode: res.statusCode,
        message: msg,
        code: data['code'] as String?,
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      _wrapNetworkError(e);
    }
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
    } on ApiException {
      // Server-side error → treat as "account may exist" to avoid blocking login
      return true;
    } catch (_) {
      // Any other unexpected error → let it propagate for proper handling
      rethrow;
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
    final data = await postJson('/api/complete-profile', {
      'name': name,
      'pin': pin,
      'phone': phone,
      'email': email,
    }, auth: true);
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
    await postJson('/api/wallet/complete-top-up', {
      'pendingId': pendingId,
      'paymentID': paymentID,
    }, auth: true);
  }

  Future<void> purchaseHistorySubscription(String planId) async {
    await postJson('/api/wallet/purchase-history-subscription', {
      'planId': planId,
    }, auth: true);
  }

  // —— Devices —— //

  /// Syncs device settings from server to local cache for background filtering.
  Future<void> syncDeviceSettingsToCache() async {
    // Device filter settings are fetched and cached locally
  }

  /// Registers this hardware device; returns server row (status / is_parent).
  Future<DeviceModel?> registerDevice(
    String deviceId,
    String deviceName, {
    String deviceModel = '',
  }) async {
    final body = <String, dynamic>{
      'deviceId': deviceId,
      'deviceName': deviceName,
      if (deviceModel.isNotEmpty) 'deviceModel': deviceModel,
    };
    final data = await postJson('/api/devices', body, auth: true);
    if (data['success'] == true && data['device'] is Map<String, dynamic>) {
      return DeviceModel.fromJson(data['device'] as Map<String, dynamic>);
    }
    return null;
  }

  Future<DeviceModel?> fetchDeviceSelf(String hardwareDeviceId) async {
    final q = Uri.encodeQueryComponent(hardwareDeviceId);
    final data = await getJson('/api/devices/self?deviceId=$q', auth: true);
    if (data['success'] == true && data['device'] is Map<String, dynamic>) {
      return DeviceModel.fromJson(data['device'] as Map<String, dynamic>);
    }
    return null;
  }

  Future<Map<String, dynamic>> approveDevice(int pendingDeviceRowId) {
    return postJson('/api/devices/$pendingDeviceRowId/approve', {}, auth: true);
  }

  Future<Map<String, dynamic>> rejectDevice(int pendingDeviceRowId) {
    return postJson('/api/devices/$pendingDeviceRowId/reject', {}, auth: true);
  }

  Future<Map<String, dynamic>> transferParentRole(int targetDeviceRowId) {
    return postJson('/api/devices/transfer-parent', {
      'target_device_id': targetDeviceRowId,
    }, auth: true);
  }

  /// Sets `custom_name` (empty string clears override → UI uses device model).
  Future<Map<String, dynamic>> updateDeviceName({
    required int deviceId,
    required String newName,
  }) {
    return postJson('/api/update-device-name', {
      'device_id': deviceId,
      'new_name': newName,
    }, auth: true);
  }
}
