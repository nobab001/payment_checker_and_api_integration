import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/app_config.dart';
import '../models/payment_settings.dart';
import '../models/sms_gateway.dart';
import '../services/config_service.dart';

class ConfigProvider extends ChangeNotifier {
  final _svc = ConfigService.instance;

  GlobalConfig _global = const GlobalConfig();
  ApiKeys _apiKeys = const ApiKeys();
  SocialLinks _socialLinks = const SocialLinks();
  EmailConfig _emailConfig = const EmailConfig();
  List<EmailAccount> _emailAccounts = [];
  PaymentSettings _paymentSettings = const PaymentSettings();
  List<AppUser> _users = [];
  List<SmsGateway> _smsGateways = [];
  bool _saving = false;
  String? _saveError;

  GlobalConfig get global => _global;
  ApiKeys get apiKeys => _apiKeys;
  SocialLinks get socialLinks => _socialLinks;
  EmailConfig get emailConfig => _emailConfig;
  List<EmailAccount> get emailAccounts => _emailAccounts;
  PaymentSettings get paymentSettings => _paymentSettings;
  List<AppUser> get users => _users;
  List<SmsGateway> get smsGateways => _smsGateways;
  bool get saving => _saving;
  String? get saveError => _saveError;

  final List<StreamSubscription> _subs = [];

  void startListening() {
    _subs.add(
      _svc.globalConfigStream().listen((v) {
        _global = v;
        notifyListeners();
      }),
    );
    _subs.add(
      _svc.apiKeysStream().listen((v) {
        _apiKeys = v;
        notifyListeners();
      }),
    );
    _subs.add(
      _svc.socialLinksStream().listen((v) {
        _socialLinks = v;
        notifyListeners();
      }),
    );
    _subs.add(
      _svc.emailConfigStream().listen((v) {
        _emailConfig = v;
        notifyListeners();
      }),
    );
    _subs.add(
      _svc.emailAccountsStream().listen((v) {
        _emailAccounts = v;
        notifyListeners();
      }),
    );
    _subs.add(
      _svc.paymentSettingsStream().listen((v) {
        _paymentSettings = v;
        notifyListeners();
      }),
    );
    _subs.add(
      _svc.usersStream().listen((v) {
        _users = v;
        notifyListeners();
      }),
    );
    _subs.add(
      _svc.smsGatewaysStream().listen((v) {
        _smsGateways = v;
        notifyListeners();
      }),
    );
  }

  void stopListening() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }

  @override
  void dispose() {
    stopListening();
    super.dispose();
  }

  Future<bool> saveGlobal(GlobalConfig cfg) =>
      _save(() => _svc.saveGlobalConfig(cfg));
  Future<bool> saveApiKeys(ApiKeys keys) => _save(() => _svc.saveApiKeys(keys));
  Future<bool> saveSocialLinks(SocialLinks l) =>
      _save(() => _svc.saveSocialLinks(l));
  Future<bool> saveEmailConfig(EmailConfig c) =>
      _save(() => _svc.saveEmailConfig(c));

  Future<bool> addEmailAccount(EmailAccount a) =>
      _save(() => _svc.addEmailAccount(a));
  Future<bool> updateEmailAccount(EmailAccount a) =>
      _save(() => _svc.updateEmailAccount(a));
  Future<bool> deleteEmailAccount(String id) =>
      _save(() => _svc.deleteEmailAccount(id));
  Future<bool> activateEmailAccount(String id) =>
      _save(() => _svc.activateEmailAccount(id));
  Future<bool> deactivateEmailAccount(String id) =>
      _save(() => _svc.deactivateEmailAccount(id));

  Future<bool> savePaymentSettings(PaymentSettings p) =>
      _save(() => _svc.savePaymentSettings(p));

  Future<bool> _save(Future<void> Function() fn) async {
    _saving = true;
    _saveError = null;
    notifyListeners();
    try {
      await fn();
      return true;
    } catch (e) {
      _saveError = e.toString();
      return false;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  Future<bool> addSmsGateway(SmsGateway gw) =>
      _save(() => _svc.addSmsGateway(gw));
  Future<bool> updateSmsGateway(SmsGateway gw) =>
      _save(() => _svc.updateSmsGateway(gw));
  Future<bool> deleteSmsGateway(String id) =>
      _save(() => _svc.deleteSmsGateway(id));
  Future<bool> activateSmsGateway(String id) =>
      _save(() => _svc.activateSmsGateway(id));
  Future<bool> deactivateSmsGateway(String id) =>
      _save(() => _svc.deactivateSmsGateway(id));

  Future<String> loadSmsOtpTemplate() async {
    try {
      return await _svc.getSmsOtpTemplate();
    } catch (e) {
      return '';
    }
  }

  Future<bool> saveSmsOtpTemplate(String template) =>
      _save(() => _svc.setSmsOtpTemplate(template));

  Future<void> blockUser(String uid, bool blocked) =>
      _svc.blockUser(uid, blocked);

  Future<void> setUserPermissions(
    String uid, {
    bool? smsEnabled,
    bool? gmailEnabled,
  }) => _svc.setUserPermissions(
    uid,
    smsEnabled: smsEnabled,
    gmailEnabled: gmailEnabled,
  );
}
