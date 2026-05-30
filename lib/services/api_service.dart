import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../models/account_credentials.dart';
import '../models/device_login_check.dart';
import '../utils/bd_phone_utils.dart';
import '../utils/gmail_input_utils.dart';
import '../models/device_model.dart';
import '../models/device_status_result.dart';
import 'device_settings_cache.dart';
import '../models/remote_config.dart';
import '../models/sms_template.dart';
import '../models/checkout_layout.dart';
import '../models/merchant_site.dart';
import '../models/payment_sms_ingest_payload.dart';
import '../models/sms_record.dart';
import '../models/user_model.dart';
import 'background_payment_api_client.dart';

/// Central HTTP client for the Payment Checker API.
///
/// Base URL: [kBaseUrl] (see `lib/config/api_config.dart`).
/// Auth: call [setAuthToken] after login; authenticated requests send
/// `Authorization: Bearer <token>`.
/// Connectivity: [ensureServerReachable] runs `GET /health` before OTP.
class ApiException implements Exception {
  final int? statusCode;
  final String message;
  final String? code;
  final Map<String, dynamic>? details;

  const ApiException({
    this.statusCode,
    required this.message,
    this.code,
    this.details,
  });

  @override
  String toString() => 'ApiException($statusCode: $message)';
}

class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  static const String _apiBasePrefKey = 'pcu_api_base_v1';

  String? _authToken;
  String? _hardwareDeviceId;
  String _apiBase = normalizeApiBaseUrl(kBaseUrl);

  /// Active API origin ([kBaseUrl] or value saved in SharedPreferences).
  String get resolvedApiBase => _apiBase;

  void setAuthToken(String? token) {
    _authToken = token?.isEmpty == true ? null : token;
  }

  void setHardwareDeviceId(String? id) {
    _hardwareDeviceId = id?.isEmpty == true ? null : id;
    _persistHardwareDeviceId(_hardwareDeviceId);
  }

  Future<void> _persistHardwareDeviceId(String? id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (id == null || id.isEmpty) {
        await prefs.remove('pcu_hw_device_id_v1');
      } else {
        await prefs.setString('pcu_hw_device_id_v1', id);
      }
    } catch (_) {}
  }

  String? get authToken => _authToken;

  String? get hardwareDeviceId => _hardwareDeviceId;

  /// Loads optional dev override from SharedPreferences (set via [setApiBaseUrl]).
  Future<void> syncBaseUrlFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_apiBasePrefKey)?.trim();
      if (saved != null && saved.isNotEmpty && !isStaleApiBaseUrl(saved)) {
        _apiBase = normalizeApiBaseUrl(saved);
        return;
      }
      if (saved != null && saved.isNotEmpty && isStaleApiBaseUrl(saved)) {
        await prefs.remove(_apiBasePrefKey);
      }
      _apiBase = normalizeApiBaseUrl(kBaseUrl);
    } catch (_) {
      _apiBase = normalizeApiBaseUrl(kBaseUrl);
    }
  }

  /// Save API base (e.g. new ngrok URL) without rebuilding the app.
  Future<void> setApiBaseUrl(String url) async {
    final normalized = normalizeApiBaseUrl(url);
    _apiBase = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiBasePrefKey, normalized);
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
      // Required by ngrok free tier to bypass the browser-warning interstitial.
      'ngrok-skip-browser-warning': 'true',
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
    if (c.contains('@') || RegExp(r'[a-zA-Z]').hasMatch(c)) {
      return GmailInputUtils.toApiValue(c);
    }
    return BdPhoneUtils.sanitize(c);
  }

  /// Quick reachability check before login / OTP (`GET /health`).
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
      } on http.ClientException {
        if (attempt >= _connectionAttempts - 1) break;
      }
      await Future<void>.delayed(_retryDelay);
    }
    throw const ApiException(
      message: 'Server unreachable',
      code: 'connection_failed',
    );
  }

  Never _wrapNetworkError(Object e) {
    if (e is TimeoutException) {
      throw const ApiException(message: 'Server unreachable', code: 'timeout');
    }
    // All socket / HTTP transport errors → single friendly message.
    throw const ApiException(message: 'Server unreachable', code: 'network');
  }

  /// POST JSON; returns parsed object on 2xx. Throws [ApiException] otherwise.
  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body, {
    bool auth = false,
    Map<String, String>? extraHeaders,
  }) async {
    try {
      final headers = _headers(auth: auth);
      if (extraHeaders != null) {
        headers.addAll(extraHeaders);
      }
      final res = await _sendWithConnectionRetries(
        () => http.post(_uri(path), headers: headers, body: jsonEncode(body)),
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
        details: data,
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

  Future<Map<String, dynamic>> patchJson(
    String path,
    Map<String, dynamic> body, {
    bool auth = false,
  }) async {
    try {
      final res = await _sendWithConnectionRetries(
        () => http.patch(
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

  /// Device lock check before OTP — same rules as verify-otp, earlier in the flow.
  Future<DeviceLoginCheck> checkDeviceLoginEligibility(
    String contact, {
    String? deviceId,
  }) async {
    final body = <String, dynamic>{'contact': normalizeContactForApi(contact)};
    final hw = deviceId?.trim();
    if (hw != null && hw.isNotEmpty) {
      body['deviceId'] = hw;
    }
    try {
      final data = await postJson('/api/check-device-login', body);
      return DeviceLoginCheck.fromJson(data);
    } on ApiException catch (e) {
      if (e.statusCode == 403 && e.code == 'DEVICE_BOUND') {
        return DeviceLoginCheck.denied(e.details ?? {'message': e.message});
      }
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

  /// Syncs this handset's SIM filters from the server into [DeviceSettingsCache].
  Future<void> syncDeviceSettingsToCache({String? hardwareDeviceId}) async {
    final hw = hardwareDeviceId?.trim();
    if (hw == null || hw.isEmpty) return;
    final device = await fetchDeviceSelf(hw);
    if (device == null) return;
    final sims =
        device.simSettings ??
        SimSettings.fromDeviceRow(
          smsFilterEnabled: device.smsFilterEnabled,
          blockUnknown: device.blockUnknown,
          blockIncoming: device.blockIncoming,
          allowedKeywords: device.allowedKeywords,
          blockedKeywords: device.blockedKeywords,
        );
    await DeviceSettingsCache.saveFromSimSettings(
      hw,
      sims,
    ); // → sim_1_* / sim_2_* keys
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

  /// Updates presence time and optional battery for [X-Device-Id] on the server.
  Future<void> postDeviceHeartbeat({int? batteryPercent}) async {
    final body = <String, dynamic>{};
    if (batteryPercent != null) body['batteryPercent'] = batteryPercent;
    await postJson('/api/devices/self/heartbeat', body, auth: true);
  }

  /// VPS polling: child checks if parent approved this handset.
  Future<DeviceStatusResult> checkDeviceStatus(String hardwareDeviceId) async {
    final q = Uri.encodeQueryComponent(hardwareDeviceId);
    try {
      final data = await getJson(
        '/api/check-device-status?deviceId=$q',
        auth: true,
      );
      final status = (data['status'] as String? ?? 'unknown').toLowerCase();
      DeviceModel? device;
      final raw = data['device'];
      if (raw is Map<String, dynamic>) {
        device = DeviceModel.fromJson(raw);
      } else if (raw is Map) {
        device = DeviceModel.fromJson(Map<String, dynamic>.from(raw));
      }
      return DeviceStatusResult(
        success: data['success'] == true,
        status: status,
        device: device,
        message: data['message'] as String?,
      );
    } on ApiException catch (e) {
      final down =
          e.code == 'connection_failed' ||
          e.code == 'network' ||
          e.code == 'timeout';
      if (down) {
        return const DeviceStatusResult(
          success: false,
          status: 'unknown',
          serverMaintenance: true,
          message: 'Server Under Maintenance',
        );
      }
      rethrow;
    } catch (_) {
      return const DeviceStatusResult(
        success: false,
        status: 'unknown',
        serverMaintenance: true,
        message: 'Server Under Maintenance',
      );
    }
  }

  /// Parent: pending child devices from VPS.
  Future<List<DeviceModel>> fetchPendingRequests() async {
    try {
      final data = await getJson('/api/get-pending-requests', auth: true);
      if (data['success'] != true) return [];
      final raw = data['devices'];
      if (raw is! List) return [];
      final list = <DeviceModel>[];
      for (final d in raw) {
        if (d is Map<String, dynamic>) {
          list.add(DeviceModel.fromJson(d));
        } else if (d is Map) {
          list.add(DeviceModel.fromJson(Map<String, dynamic>.from(d)));
        }
      }
      return list;
    } on ApiException catch (e) {
      final down =
          e.code == 'connection_failed' ||
          e.code == 'network' ||
          e.code == 'timeout';
      if (down) return [];
      rethrow;
    }
  }

  Future<Map<String, dynamic>> approveDevice(
    int pendingDeviceRowId, {
    String? securityPin,
  }) {
    final body = <String, dynamic>{};
    final headers = <String, String>{};
    if (securityPin != null && securityPin.trim().isNotEmpty) {
      final p = securityPin.trim();
      body['pin'] = p;
      headers['X-Device-Approval-Pin'] = p;
    }
    return postJson(
      '/api/devices/$pendingDeviceRowId/approve',
      body,
      auth: true,
      extraHeaders: headers.isEmpty ? null : headers,
    );
  }

  Future<Map<String, dynamic>> rejectDevice(
    int pendingDeviceRowId, {
    String? securityPin,
  }) {
    final body = <String, dynamic>{};
    final headers = <String, String>{};
    if (securityPin != null && securityPin.trim().isNotEmpty) {
      final p = securityPin.trim();
      body['pin'] = p;
      headers['X-Device-Approval-Pin'] = p;
    }
    return postJson(
      '/api/devices/$pendingDeviceRowId/reject',
      body,
      auth: true,
      extraHeaders: headers.isEmpty ? null : headers,
    );
  }

  Future<Map<String, dynamic>> transferParentRole(int targetDeviceRowId) {
    return postJson('/api/devices/transfer-parent', {
      'target_device_id': targetDeviceRowId,
    }, auth: true);
  }

  Future<Map<String, dynamic>> verifyDevicePin(String pin) {
    return postJson('/api/auth/verify-device-pin', {'pin': pin}, auth: true);
  }

  Future<List<Map<String, dynamic>>> fetchPinContacts() async {
    final data = await getJson('/api/auth/pin-contacts', auth: true);
    final raw = data['contacts'];
    if (raw is! List) return [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<UserModel> changePin({
    String? currentPin,
    required String newPin,
  }) async {
    final body = <String, dynamic>{'newPin': newPin};
    if (currentPin != null && currentPin.isNotEmpty) {
      body['currentPin'] = currentPin;
    }
    final data = await postJson('/api/auth/change-pin', body, auth: true);
    final u = data['user'] as Map<String, dynamic>? ?? data;
    return UserModel.fromJson(u);
  }

  Future<void> sendForgotPinOtp(String contact) async {
    final c = normalizeContactForApi(contact);
    await postJson('/api/auth/forgot-pin/send-otp', {'contact': c}, auth: true);
  }

  Future<AccountCredentials> fetchAccountCredentials() async {
    final data = await getJson('/api/credentials', auth: true);
    return AccountCredentials.fromJson(data);
  }

  Future<void> sendCredentialLinkOtp(String contact) async {
    final c = normalizeContactForApi(contact);
    await postJson('/api/credentials/send-otp', {'contact': c}, auth: true);
  }

  Future<({AccountCredentials credentials, UserModel? user})>
  verifyAndLinkCredential({
    required String contact,
    required String code,
  }) async {
    final data = await postJson('/api/credentials/verify', {
      'contact': normalizeContactForApi(contact),
      'code': code.trim(),
    }, auth: true);
    final creds = AccountCredentials.fromJson(data);
    final u = data['user'];
    final user = u is Map<String, dynamic> ? UserModel.fromJson(u) : null;
    return (credentials: creds, user: user);
  }

  Future<UserModel> resetPinWithOtp({
    required String contact,
    required String code,
    required String newPin,
  }) async {
    final data = await postJson('/api/auth/forgot-pin/reset', {
      'contact': normalizeContactForApi(contact),
      'code': code,
      'newPin': newPin,
    }, auth: true);
    final u = data['user'] as Map<String, dynamic>? ?? data;
    return UserModel.fromJson(u);
  }

  Future<Map<String, dynamic>> fetchDeviceAccess() {
    return getJson('/api/auth/device-access', auth: true);
  }

  /// Reassign parent: account security PIN and/or server recovery key.
  Future<Map<String, dynamic>> reassignParentEmergency({
    required Map<String, dynamic> body,
    String? recoveryKey,
    String? accountPin,
  }) {
    final headers = <String, String>{};
    if (recoveryKey != null && recoveryKey.trim().isNotEmpty) {
      headers['X-Parent-Recovery-Key'] = recoveryKey.trim();
    }
    final payload = Map<String, dynamic>.from(body);
    if (accountPin != null && accountPin.trim().isNotEmpty) {
      payload['pin'] = accountPin.trim();
    }
    return postJson(
      '/api/devices/reassign-parent',
      payload,
      auth: true,
      extraHeaders: headers.isEmpty ? null : headers,
    );
  }

  // —— SMS sync —— //

  /// Push one SMS record to the server. Fire-and-forget; all errors swallowed.
  Future<void> ingestSms(SmsRecord record) async {
    if (_authToken == null) return;
    try {
      await postJson('/api/sms-ingest', record.toJson(), auth: true);
    } catch (_) {}
  }

  /// Admin-defined SMS templates for dynamic regex parsing.
  Future<List<SmsTemplate>> fetchSmsTemplates() async {
    final result = await fetchSmsTemplatesWithRevision();
    return result.templates;
  }

  /// Templates plus server revision (changes when admin edits any template).
  Future<({List<SmsTemplate> templates, String revision})>
  fetchSmsTemplatesWithRevision() async {
    final data = await getJson('/api/sms-templates', auth: true);
    final list = data['templates'] as List<dynamic>? ?? [];
    final templates = list
        .map((e) => SmsTemplate.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final revision = (data['revision'] as String?)?.trim() ?? '';
    return (templates: templates, revision: revision);
  }

  /// @deprecated Use [fetchSmsTemplates].
  Future<List<SmsTemplate>> fetchSenderTemplates() => fetchSmsTemplates();

  /// Structured payment SMS — delegates to background-safe client (logs + queue).
  Future<void> ingestPaymentSms(Map<String, dynamic> payload) async {
    if (_authToken == null) {
      final prefs = await SharedPreferences.getInstance();
      final t = prefs.getString('pcu_auth_token_v1');
      if (t != null && t.isNotEmpty) setAuthToken(t);
    }
    final model = PaymentSmsIngestPayload.fromJsonMap(payload);
    await BackgroundPaymentApiClient.instance.ingest(model);
  }

  /// Account devices for Device Manager (parent + children).
  Future<Map<String, dynamic>> fetchDevices() async {
    try {
      return await getJson('/api/devices', auth: true);
    } on ApiException catch (e) {
      final transient =
          e.code == 'connection_failed' ||
          e.code == 'network' ||
          e.code == 'timeout';
      if (!transient) rethrow;
    }
    return getJson('/api/get-devices', auth: true);
  }

  /// User-facing message for device / network errors.
  static String friendlyErrorMessage(Object error) {
    if (error is ApiException) {
      switch (error.code) {
        case 'connection_failed':
        case 'network':
        case 'timeout':
          return 'সার্ভারের সাথে সংযোগ হচ্ছে না। PC-তে START-SERVER.bat চালু আছে কিনা দেখুন (একই Wi‑Fi)।';
        default:
          final msg = error.message.trim();
          if (error.statusCode == 503) {
            return 'সার্ভার ডাটাবেস প্রস্তুত নয়। PC-তে MySQL (XAMPP) ও API '
                '(START-SERVER.bat) চালু করে আবার চেষ্টা করুন।';
          }
          if (error.statusCode == 401 || error.statusCode == 403) {
            return 'সেশন শেষ হয়েছে। আবার লগইন করুন।';
          }
          if (msg.isNotEmpty && msg != 'Request failed') {
            final ml = msg.toLowerCase();
            if ((ml.contains('only') &&
                    ml.contains('parent') &&
                    (ml.contains('approve') || ml.contains('authority'))) ||
                ml == 'only the parent device can approve') {
              return 'এই ফিচারের জন্য VPS এ লেটেস্ট API দরকার। নতুন server কোড আপডেট করে Node রিস্টার্ট করুন; '
                  'তবেই অন্য ডিভাইস থেকে পিন দিয়ে অনুমোদন কাজ করবে। ';
            }
            return msg;
          }
          if (error.statusCode != null) {
            return 'সার্ভার ত্রুটি (${error.statusCode})';
          }
      }
    }
    return 'ডিভাইস তালিকা লোড করা যায়নি।';
  }

  // —— Multi-merchant B2B API —— //

  Future<List<MerchantSite>> fetchMerchants() async {
    final data = await getJson('/api/merchants', auth: true);
    final list = data['merchants'] as List<dynamic>? ?? [];
    return list
        .map((e) => MerchantSite.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<MerchantSite> createMerchant({
    required String siteName,
    required String domainAddress,
  }) async {
    final data = await postJson('/api/merchants', {
      'site_name': siteName,
      'domain_address': domainAddress,
    }, auth: true);
    return MerchantSite.fromJson(
      Map<String, dynamic>.from(data['merchant'] as Map),
    );
  }

  Future<Map<String, dynamic>> fetchMerchantDetail(int id) async {
    return getJson('/api/merchants/$id', auth: true);
  }

  Future<void> patchMerchant({
    required int id,
    bool? isActive,
    String? domainAddress,
    String? siteName,
  }) async {
    await patchJson('/api/merchants/$id', {
      'is_active': ?isActive,
      'domain_address': ?domainAddress,
      'site_name': ?siteName,
    }, auth: true);
  }

  Future<void> saveMerchantCheckoutLayout(int id, CheckoutLayout layout) async {
    await putJson(
      '/api/merchants/$id/checkout-layout',
      layout.toJson(),
      auth: true,
    );
  }

  Future<({String apiKeyId, String apiSecret})> regenerateMerchantApiKey({
    required int id,
    required String pin,
  }) async {
    final data = await postJson('/api/merchants/$id/regenerate-key', {
      'pin': pin,
    }, auth: true);
    return (
      apiKeyId: data['api_key_id']?.toString() ?? '',
      apiSecret: data['api_secret']?.toString() ?? '',
    );
  }

  /// Sets `custom_name` (empty string clears override → UI uses device model).
  Future<Map<String, dynamic>> updateDeviceName({
    required int deviceId,
    required String newName,
  }) async {
    final body = {'device_id': deviceId, 'new_name': newName};
    try {
      return await postJson('/api/rename-device', body, auth: true);
    } catch (_) {
      return postJson('/api/update-device-name', body, auth: true);
    }
  }
}
