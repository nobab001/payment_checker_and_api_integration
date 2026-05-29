import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telephony/telephony.dart';

import 'api_service.dart';
import 'local_sms_forward_service.dart';
import 'payment_sms_processor.dart';
import 'sms_service_state_prefs.dart';
import 'storage_service.dart';
import '../models/sms_record.dart';
import '../sync/sync_service.dart';

// Top-level function required by telephony for background isolate.
@pragma('vm:entry-point')
Future<void> onBackgroundSms(SmsMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalSmsForwardService.instance.tryForwardIncomingSms(message);
  if (!await SmsServiceStatePrefs.shouldResumeService()) return;

  await PaymentSmsProcessor.bootstrapForBackground();
  final processed = await PaymentSmsProcessor.instance.processIncoming(message);
  if (processed == null) return;

  // Local-first: persist on device, then sync to remote DB (background-safe HTTP).
  await StorageService.instance.appendSms(processed.record);
  await PaymentSmsProcessor.instance.syncToServer(processed);
  await _ingestLegacy(processed.record);
}

Future<void> _ingestLegacy(SmsRecord record) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token == null || token.isEmpty) return;
    ApiService.instance.setAuthToken(token);
    await ApiService.instance.ingestSms(record);
  } catch (_) {}
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
      onNewMessage: (SmsMessage message) async {
        await LocalSmsForwardService.instance.tryForwardIncomingSms(message);
        if (!await SmsServiceStatePrefs.shouldResumeService()) return;

        final processed =
            await PaymentSmsProcessor.instance.processIncoming(message);
        if (processed == null) return;

        // Local-first dual-write: disk cache → optional LAN sync → remote API.
        await StorageService.instance.appendSms(processed.record);
        await SyncService.instance.onNewSms(processed.record);
        unawaited(PaymentSmsProcessor.instance.syncToServer(processed));
        unawaited(_ingestLegacy(processed.record));
        onNewSms?.call(processed.record);
      },
      onBackgroundMessage: onBackgroundSms,
      listenInBackground: true,
    );
  }

  void stopListening() {
    if (kIsWeb || !_listening) return;
    // Do not call listenIncomingSms(listenInBackground: false) — that sets
    // telephony disable_background=true and breaks SMS after reboot until UI opens.
    _listening = false;
  }

  /// User tapped Stop on Home — fully disable telephony background isolate.
  void disableBackgroundPipeline() {
    if (kIsWeb) return;
    _telephony.listenIncomingSms(
      onNewMessage: (_) {},
      listenInBackground: false,
    );
    _listening = false;
  }

  Future<void> restartListeningIfEnabled() async {
    if (kIsWeb) return;
    if (!await SmsServiceStatePrefs.shouldResumeService()) return;
    if (_listening) return;
    startListening();
  }

  /// Disabled — app only processes live incoming SMS, never reads device inbox.
  Future<List<SmsRecord>> loadInboxHistory({
    bool paymentSendersOnly = false,
  }) async =>
      [];
}
