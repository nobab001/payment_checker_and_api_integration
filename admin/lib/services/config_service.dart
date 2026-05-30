import 'dart:async';
import '../models/app_config.dart';
import '../models/payment_settings.dart';
import '../models/sms_gateway.dart';
import 'api_service.dart';

class ConfigService {
  ConfigService._();
  static final instance = ConfigService._();

  final _api = ApiService.instance;

  final _globalController = StreamController<GlobalConfig>.broadcast();
  final _apiKeysController = StreamController<ApiKeys>.broadcast();
  final _socialLinksController = StreamController<SocialLinks>.broadcast();
  final _emailConfigController = StreamController<EmailConfig>.broadcast();
  final _emailAccountsController =
      StreamController<List<EmailAccount>>.broadcast();
  final _paymentSettingsController =
      StreamController<PaymentSettings>.broadcast();
  final _usersController = StreamController<List<AppUser>>.broadcast();
  final _smsGatewaysController = StreamController<List<SmsGateway>>.broadcast();

  Timer? _timer;

  Stream<GlobalConfig> globalConfigStream() {
    _startPollingIfNeeded();
    return _globalController.stream;
  }

  Stream<ApiKeys> apiKeysStream() {
    _startPollingIfNeeded();
    return _apiKeysController.stream;
  }

  Stream<SocialLinks> socialLinksStream() {
    _startPollingIfNeeded();
    return _socialLinksController.stream;
  }

  Stream<EmailConfig> emailConfigStream() {
    _startPollingIfNeeded();
    return _emailConfigController.stream;
  }

  Stream<List<EmailAccount>> emailAccountsStream() {
    _startPollingIfNeeded();
    return _emailAccountsController.stream;
  }

  Stream<PaymentSettings> paymentSettingsStream() {
    _startPollingIfNeeded();
    return _paymentSettingsController.stream;
  }

  Stream<List<AppUser>> usersStream() {
    _startPollingIfNeeded();
    return _usersController.stream;
  }

  Stream<List<SmsGateway>> smsGatewaysStream() {
    _startPollingIfNeeded();
    return _smsGatewaysController.stream;
  }

  void _startPollingIfNeeded() {
    if (_timer != null) return;
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _poll());
    _poll();
  }

  void stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _poll() async {
    if (!_api.isAuthenticated) return;
    try {
      final configRes = await _api.getJson('/api/admin/config');
      if (configRes['success'] == true && configRes['config'] != null) {
        final c = configRes['config'] as Map<String, dynamic>;
        if (c['global'] != null) {
          _globalController.add(GlobalConfig.fromMap(c['global']));
        }
        if (c['apiKeys'] != null) {
          _apiKeysController.add(ApiKeys.fromMap(c['apiKeys']));
        }
        if (c['socialLinks'] != null) {
          _socialLinksController.add(SocialLinks.fromMap(c['socialLinks']));
        }
        if (c['emailConfig'] != null) {
          _emailConfigController.add(EmailConfig.fromMap(c['emailConfig']));
        }
        if (c['emailAccounts'] != null) {
          final raw = c['emailAccounts'] as List;
          _emailAccountsController.add(
            raw
                .map((x) => EmailAccount.fromMap(x as Map<String, dynamic>))
                .toList(),
          );
        }
        if (c['paymentSettings'] != null) {
          _paymentSettingsController.add(
            PaymentSettings.fromMap(c['paymentSettings']),
          );
        }
      }
    } catch (_) {}

    try {
      final gwRes = await _api.getJson('/api/admin/sms-settings');
      if (gwRes['success'] == true && gwRes['settings'] != null) {
        final raw = gwRes['settings'] as List;
        final list = raw.map((x) => SmsGateway.fromMap(x['id'], x)).toList();
        _smsGatewaysController.add(list);
      }
    } catch (_) {}

    try {
      final userRes = await _api.getJson('/api/admin/users');
      if (userRes['success'] == true && userRes['users'] != null) {
        final raw = userRes['users'] as List;
        final list = raw.map((x) => AppUser.fromMap(x['uid'], x)).toList();
        _usersController.add(list);
      }
    } catch (_) {}
  }

  // ── writes ───────────────────────────────────────────────
  Future<void> saveGlobalConfig(GlobalConfig cfg) =>
      _api.putJson('/api/admin/config/global', cfg.toMap());
  Future<void> saveApiKeys(ApiKeys keys) =>
      _api.putJson('/api/admin/config/apiKeys', keys.toMap());
  Future<void> saveSocialLinks(SocialLinks links) =>
      _api.putJson('/api/admin/config/socialLinks', links.toMap());
  Future<void> saveEmailConfig(EmailConfig cfg) =>
      _api.putJson('/api/admin/config/emailConfig', cfg.toMap());
  Future<void> savePaymentSettings(PaymentSettings cfg) =>
      _api.putJson('/api/admin/config/paymentSettings', cfg.toMap());

  Future<void> updateUser(String uid, Map<String, dynamic> data) =>
      _api.putJson('/api/admin/users/$uid', data);
  Future<void> blockUser(String uid, bool blocked) =>
      updateUser(uid, {'blocked': blocked});

  Future<void> setUserPermissions(
    String uid, {
    bool? smsEnabled,
    bool? gmailEnabled,
  }) {
    return _api.putJson('/api/admin/users/$uid/permissions', {
      'smsEnabled': smsEnabled,
      'gmailEnabled': gmailEnabled,
    });
  }

  // ── Email accounts ─────────────────────────────────────────
  Future<void> addEmailAccount(EmailAccount a) =>
      _api.postJson('/api/admin/email-accounts', a.toMap());
  Future<void> updateEmailAccount(EmailAccount a) =>
      _api.putJson('/api/admin/email-accounts/${a.id}', a.toMap());
  Future<void> deleteEmailAccount(String id) =>
      _api.deleteJson('/api/admin/email-accounts/$id');
  Future<void> activateEmailAccount(String id) =>
      _api.postJson('/api/admin/email-accounts/$id/activate', {});
  Future<void> deactivateEmailAccount(String id) =>
      _api.postJson('/api/admin/email-accounts/$id/deactivate', {});

  // ── SMS gateways ───────────────────────────────────────────
  Future<void> addSmsGateway(SmsGateway gw) =>
      _api.postJson('/api/admin/sms-settings', gw.toMap());
  Future<void> updateSmsGateway(SmsGateway gw) =>
      _api.putJson('/api/admin/sms-settings/${gw.id}', gw.toMap());
  Future<void> deleteSmsGateway(String id) =>
      _api.deleteJson('/api/admin/sms-settings/$id');
  Future<void> activateSmsGateway(String id) =>
      _api.postJson('/api/admin/sms-settings/$id/activate', {});
  Future<void> deactivateSmsGateway(String id) =>
      _api.postJson('/api/admin/sms-settings/$id/deactivate', {});
}
