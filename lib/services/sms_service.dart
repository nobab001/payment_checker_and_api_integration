import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:telephony/telephony.dart';

import '../models/sms_record.dart';
import '../sync/sync_service.dart';
import '../utils/sms_parser.dart';
import 'sms_monitoring_prefs.dart';
import 'storage_service.dart';

// Top-level function required by telephony for background isolate.
// WidgetsFlutterBinding init is required so path_provider can use
// platform channels from the background engine.
@pragma('vm:entry-point')
Future<void> onBackgroundSms(SmsMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!await SmsMonitoringPrefs.isMonitoringEnabled()) return;
  final address = message.address ?? '';
  if (!SmsParser.isValidSender(address)) return;
  final record = _buildRecord(message);
  await StorageService.instance.appendSms(record);
  await syncInBackground(record);
}

SmsRecord _buildRecord(SmsMessage msg) {
  final body = msg.body ?? '';
  final ts = msg.date != null
      ? DateTime.fromMillisecondsSinceEpoch(msg.date!).toIso8601String()
      : DateTime.now().toIso8601String();
  return SmsRecord(
    t: ts,
    s: SmsParser.detectSender(msg.address ?? ''),
    m: body,
    b: SmsParser.extractBalance(body),
    tp: SmsParser.detectType(body),
    am: SmsParser.extractAmount(body),
  );
}

class SmsService {
  static final SmsService instance = SmsService._();
  SmsService._();

  final _telephony = Telephony.instance;
  bool _listening = false;

  void Function(SmsRecord)? onNewSms;

  Future<bool> requestPermissions() async {
    if (kIsWeb) return false;
    return await _telephony.requestPhoneAndSmsPermissions ?? false;
  }

  void startListening() {
    if (kIsWeb || _listening) return;
    _listening = true;
    _telephony.listenIncomingSms(
      onNewMessage: (SmsMessage message) {
        SmsMonitoringPrefs.isMonitoringEnabled().then((enabled) {
          if (!enabled) return;
          final address = message.address ?? '';
          if (!SmsParser.isValidSender(address)) return;
          final record = _buildRecord(message);
          StorageService.instance.appendSms(record).then((_) async {
            await SyncService.instance.onNewSms(record);
            onNewSms?.call(record);
          });
        });
      },
      onBackgroundMessage: onBackgroundSms,
      listenInBackground: true,
    );
  }

  /// Stops telephony background SMS delivery to Dart (sets native `disable_background`).
  void stopListening() {
    if (kIsWeb || !_listening) return;
    _telephony.listenIncomingSms(
      onNewMessage: (_) {},
      listenInBackground: false,
    );
    _listening = false;
  }

  /// Re-register listener after reboot or if native state was lost.
  Future<void> restartListeningIfEnabled() async {
    if (kIsWeb) return;
    if (!await SmsMonitoringPrefs.isMonitoringEnabled()) return;
    if (_listening) {
      _telephony.listenIncomingSms(
        onNewMessage: (_) {},
        listenInBackground: false,
      );
      _listening = false;
    }
    startListening();
  }

  /// Import existing payment SMS from device inbox
  Future<List<SmsRecord>> loadInboxHistory() async {
    if (kIsWeb) return [];
    try {
      final messages = await _telephony.getInboxSms(
        columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
      );
      return messages
          .where((m) => SmsParser.isValidSender(m.address ?? ''))
          .map(_buildRecord)
          .toList();
    } catch (_) {
      return [];
    }
  }
}
