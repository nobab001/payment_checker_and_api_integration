import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/app_config.dart';
import '../models/payment_settings.dart';
import '../models/sms_gateway.dart';

class ConfigService {
  ConfigService._();
  static final instance = ConfigService._();

  final _db = FirebaseFirestore.instance;

  // ── streams ──────────────────────────────────────────────
  Stream<GlobalConfig> globalConfigStream() => _db
      .collection('config')
      .doc('global')
      .snapshots()
      .map((s) => s.exists ? GlobalConfig.fromMap(s.data()!) : const GlobalConfig());

  Stream<ApiKeys> apiKeysStream() => _db
      .collection('config')
      .doc('apiKeys')
      .snapshots()
      .map((s) => s.exists ? ApiKeys.fromMap(s.data()!) : const ApiKeys());

  Stream<SocialLinks> socialLinksStream() => _db
      .collection('config')
      .doc('socialLinks')
      .snapshots()
      .map((s) => s.exists ? SocialLinks.fromMap(s.data()!) : const SocialLinks());

  Stream<EmailConfig> emailConfigStream() => _db
      .collection('config')
      .doc('emailConfig')
      .snapshots()
      .map((s) => s.exists ? EmailConfig.fromMap(s.data()!) : const EmailConfig());

  Stream<PaymentSettings> paymentSettingsStream() => _db
      .collection('config')
      .doc('paymentSettings')
      .snapshots()
      .map((s) =>
          s.exists ? PaymentSettings.fromMap(s.data()!) : const PaymentSettings());

  Stream<List<AppUser>> usersStream() => _db
      .collection('users')
      .orderBy('name')
      .snapshots()
      .map((s) => s.docs.map((d) => AppUser.fromMap(d.id, d.data())).toList());

  // ── writes ───────────────────────────────────────────────
  Future<void> saveGlobalConfig(GlobalConfig cfg) => _db
      .collection('config')
      .doc('global')
      .set(cfg.toMap(), SetOptions(merge: true));

  Future<void> saveApiKeys(ApiKeys keys) => _db
      .collection('config')
      .doc('apiKeys')
      .set(keys.toMap(), SetOptions(merge: true));

  Future<void> saveSocialLinks(SocialLinks links) => _db
      .collection('config')
      .doc('socialLinks')
      .set(links.toMap(), SetOptions(merge: true));

  Future<void> saveEmailConfig(EmailConfig cfg) => _db
      .collection('config')
      .doc('emailConfig')
      .set(cfg.toMap(), SetOptions(merge: true));

  Future<void> savePaymentSettings(PaymentSettings cfg) => _db
      .collection('config')
      .doc('paymentSettings')
      .set(cfg.toMap(), SetOptions(merge: true));

  Future<void> updateUser(String uid, Map<String, dynamic> data) =>
      _db.collection('users').doc(uid).update(data);

  Future<void> blockUser(String uid, bool blocked) =>
      updateUser(uid, {'blocked': blocked});

  Future<void> setUserPermissions(
      String uid, {bool? smsEnabled, bool? gmailEnabled}) {
    final data = <String, dynamic>{};
    if (smsEnabled != null) data['smsEnabled'] = smsEnabled;
    if (gmailEnabled != null) data['gmailEnabled'] = gmailEnabled;
    if (data.isEmpty) return Future.value();
    return updateUser(uid, data);
  }

  // ── SMS gateways ───────────────────────────────────────────
  Stream<List<SmsGateway>> smsGatewaysStream() => _db
      .collection('sms_gateways')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) =>
          s.docs.map((d) => SmsGateway.fromMap(d.id, d.data())).toList());

  Future<void> addSmsGateway(SmsGateway gw) => _db
      .collection('sms_gateways')
      .add({...gw.toMap(), 'createdAt': FieldValue.serverTimestamp()});

  Future<void> updateSmsGateway(SmsGateway gw) =>
      _db.collection('sms_gateways').doc(gw.id).update(gw.toMap());

  Future<void> deleteSmsGateway(String id) =>
      _db.collection('sms_gateways').doc(id).delete();

  Future<void> activateSmsGateway(String id) async {
    final batch = _db.batch();
    final snap = await _db
        .collection('sms_gateways')
        .where('isActive', isEqualTo: true)
        .get();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'isActive': false});
    }
    batch.update(
        _db.collection('sms_gateways').doc(id), {'isActive': true});
    await batch.commit();
  }

  Future<void> deactivateSmsGateway(String id) =>
      _db.collection('sms_gateways').doc(id).update({'isActive': false});
}
