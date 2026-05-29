import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telephony/telephony.dart';

import 'api_service.dart';

import '../models/payment_sms_ingest_payload.dart';
import '../models/sms_template.dart';
import '../models/sms_record.dart';
import '../models/sim_filter_preferences.dart';
import '../repositories/sim_filter_local_repository.dart';
import '../utils/dynamic_sms_template_parser.dart';
import '../utils/sender_match_utils.dart';
import '../utils/sms_parser.dart';
import 'background_payment_api_client.dart';
import 'sms_history_database.dart';
import 'sim_sms_filter.dart';
import 'sms_automation_prefs.dart';
import 'sms_template_cache.dart';

/// SIM/sender gate → admin template regex OR custom-sender fallback → API.
class PaymentSmsProcessor {
  PaymentSmsProcessor._();
  static final PaymentSmsProcessor instance = PaymentSmsProcessor._();

  final _templateCache = SmsTemplateCache.instance;

  /// Background isolate: load templates from disk + auth for optional refresh.
  static Future<void> bootstrapForBackground() async {
    await SmsTemplateCache.instance.ensureLoaded();
    if (!SmsTemplateCache.instance.hasTemplates) {
      try {
        final sp = await SharedPreferences.getInstance();
        final token = sp.getString('auth_token')?.trim();
        if (token != null && token.isNotEmpty) {
          ApiService.instance.setAuthToken(token);
          await ApiService.instance.syncBaseUrlFromPrefs();
          await SmsTemplateCache.instance.refreshFromServer(force: true);
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[PaymentSmsProcessor] template bootstrap: $e');
        }
      }
    }
  }

  Future<ProcessedPaymentSms?> processIncoming(SmsMessage message) async {
    if (!await SmsAutomationPrefs.isAutomationConfigured()) {
      if (kDebugMode) {
        debugPrint('[PaymentSmsProcessor] skip — device settings not saved');
      }
      return null;
    }

    await bootstrapForBackground();

    final prefs = await SimFilterLocalRepository.instance.loadSettings();
    final detectedSlot = _resolveSlot(message);
    final slot = _effectiveSlot(prefs, detectedSlot);
    if (!_slotActive(prefs, slot)) {
      if (kDebugMode) {
        debugPrint(
          '[PaymentSmsProcessor] skip — SIM ${slot + 1} not active (detected=$detectedSlot)',
        );
      }
      return null;
    }

    final address = message.address ?? '';
    final body = message.body ?? '';
    if (body.trim().isEmpty) return null;

    final ts = message.date != null
        ? DateFormat('yyyy-MM-dd HH:mm:ss')
            .format(DateTime.fromMillisecondsSinceEpoch(message.date!))
        : DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());

    if (!_templateCache.hasTemplates) {
      if (kDebugMode) {
        debugPrint(
          '[PaymentSmsProcessor] skip — no admin templates (open app once after login)',
        );
      }
      return null;
    }

    // Admin template: strict regex only (no catch-all fallback).
    final tpl = _matchAdminTemplate(prefs, slot, address);
    ParsedPaymentSms? parsed;

    if (tpl == null) {
      if (kDebugMode) {
        debugPrint(
          '[PaymentSmsProcessor] sender/slot/template mismatch slot=$slot from="$address"',
        );
      }
      return null;
    }

    parsed = DynamicSmsTemplateParser.parseTemplate(
      smsBody: body,
      template: tpl,
      fallbackTimestamp: ts,
    );
    if (parsed == null) {
      if (kDebugMode) {
        debugPrint(
          '[PaymentSmsProcessor] regex miss slot=$slot template="${tpl.customerPreview}"',
        );
      }
      return null;
    }

    if (kDebugMode) {
      debugPrint(
        '[PaymentSmsProcessor] parsed trx=${parsed.trxId} amount=${parsed.amount} '
        'tag=${tpl.customerPreview}',
      );
    }

    return _buildProcessed(
      parsed: parsed,
      prefs: prefs,
      slot: slot,
      address: address,
      ts: ts,
      providerTagDisplay: tpl.customerPreview,
    );
  }

  /// When telephony reports wrong slot, use the only active SIM.
  int _effectiveSlot(SimFilterPreferences prefs, int detected) {
    if (_slotActive(prefs, detected)) return detected;
    if (prefs.sim1Active && !prefs.sim2Active) return 0;
    if (prefs.sim2Active && !prefs.sim1Active) return 1;
    return detected;
  }

  ProcessedPaymentSms _buildProcessed({
    required ParsedPaymentSms parsed,
    required SimFilterPreferences prefs,
    required int slot,
    required String address,
    required String ts,
    String? providerTagDisplay,
  }) {
    final simNumber = slot == 0 ? prefs.sim1Number : prefs.sim2Number;
    final record = _toSmsRecord(
      parsed,
      address,
      ts,
      simSlot: slot + 1,
      simNumber: simNumber,
    );

    final payload = PaymentSmsIngestPayload.fromParsed(
      parsed: parsed,
      simSlot: slot + 1,
      receiverNumber: simNumber,
      providerTagDisplay: providerTagDisplay,
    );

    return ProcessedPaymentSms(
      record: record,
      ingestPayload: payload.toJson(),
      parsed: parsed,
      simSlotIndex: slot,
    );
  }

  int _resolveSlot(SmsMessage message) {
    if (message.simSlotIndex != null && message.simSlotIndex! >= 0) {
      return message.simSlotIndex!.clamp(0, 1);
    }
    return SimSmsFilter.normalizeSlot(message.subscriptionId);
  }

  bool _slotActive(SimFilterPreferences prefs, int slot) =>
      slot == 0 ? prefs.sim1Active : prefs.sim2Active;

  SmsTemplate? _matchAdminTemplate(
    SimFilterPreferences prefs,
    int slot,
    String address,
  ) {
    final tags = slot == 0 ? prefs.sim1ProviderTags : prefs.sim2ProviderTags;
    if (tags.isEmpty) return null;

    final legacySenders =
        slot == 0 ? prefs.sim1AllowedSenders : prefs.sim2AllowedSenders;

    for (final preview in tags) {
      final tpl = _templateCache.findByCustomerPreview(preview);
      if (tpl == null) continue;
      final allowed = <String>{
        tpl.senderId,
        ...legacySenders,
      }.where((s) => s.trim().isNotEmpty).toList();
      if (senderAddressMatchesAllowed(address, allowed)) {
        return tpl;
      }
    }
    return null;
  }

  SmsRecord _toSmsRecord(
    ParsedPaymentSms p,
    String address,
    String ts, {
    required int simSlot,
    required String simNumber,
  }) {
    final amt = double.tryParse(p.amount) ?? 0.0;
    return SmsRecord(
      t: ts,
      s: p.providerTag.isNotEmpty
          ? p.providerTag
          : SmsParser.detectSender(address),
      m: p.rawBody,
      b: p.balance.isNotEmpty ? p.balance : SmsParser.extractBalance(p.rawBody),
      tp: SmsParser.detectType(p.rawBody),
      am: amt,
      trxId: p.trxId,
      simSlot: simSlot,
      simNumber: simNumber,
      providerTag: p.providerTag,
      senderNumber: p.senderNumber,
    );
  }

  Future<void> syncToServer(ProcessedPaymentSms processed) async {
    final payload =
        PaymentSmsIngestPayload.fromJsonMap(processed.ingestPayload);
    final key = SmsHistoryDatabase.dedupeKey(processed.record);
    await BackgroundPaymentApiClient.instance.ingest(
      payload,
      localDedupeKey: key,
    );
  }
}

class ProcessedPaymentSms {
  final SmsRecord record;
  final Map<String, dynamic> ingestPayload;
  final ParsedPaymentSms parsed;
  final int simSlotIndex;

  const ProcessedPaymentSms({
    required this.record,
    required this.ingestPayload,
    required this.parsed,
    required this.simSlotIndex,
  });
}
