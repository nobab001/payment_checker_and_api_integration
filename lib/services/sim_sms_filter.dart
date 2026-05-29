import 'package:flutter/foundation.dart';

import '../models/sim_filter_preferences.dart';
import '../repositories/sim_filter_local_repository.dart';
import '../utils/sender_match_utils.dart';

/// Strict SMS gate: SIM toggle → allowed sender list (address only).
class SimSmsFilter {
  /// Maps [subscriptionId] from telephony to slot index `0` (SIM 1) or `1` (SIM 2).
  static int normalizeSlot(int? subscriptionId) {
    if (subscriptionId == null) return 0;
    if (subscriptionId <= 0) return 0;
    if (subscriptionId == 1) return 1;
    // Some OEMs use 2+ for the second subscription.
    return 1;
  }

  /// True when [address] matches any entry in [allowedSenders] after normalization.
  static bool senderMatches(String? address, List<String> allowedSenders) =>
      senderAddressMatchesAllowed(address, allowedSenders);

  /// Step 1–4 from product rules using in-memory [prefs].
  static bool shouldProcessIncomingSms({
    required SimFilterPreferences prefs,
    required int subscriptionId,
    required String? senderAddress,
  }) {
    final slot = normalizeSlot(subscriptionId);
    final simActive = slot == 0 ? prefs.sim1Active : prefs.sim2Active;
    if (!simActive) return false;

    final tags = slot == 0 ? prefs.sim1ProviderTags : prefs.sim2ProviderTags;
    if (tags.isNotEmpty) {
      return senderMatches(senderAddress, tags);
    }
    final allowed = slot == 0
        ? prefs.sim1AllowedSenders
        : prefs.sim2AllowedSenders;
    return senderMatches(senderAddress, allowed);
  }

  /// Loads prefs from disk, logs slot in debug, returns whether to process SMS.
  static Future<bool> shouldProcessIncomingSmsFromStorage({
    required int subscriptionId,
    required String? senderAddress,
  }) async {
    final prefs = await SimFilterLocalRepository.instance.ensureDefaults();
    final slot = normalizeSlot(subscriptionId);
    if (kDebugMode) {
      debugPrint(
        '[SimSmsFilter] subscriptionId=$subscriptionId → slot=$slot '
        'sim1=${prefs.sim1Active}/${prefs.sim1AllowedSenders.length} '
        'sim2=${prefs.sim2Active}/${prefs.sim2AllowedSenders.length} '
        'sender="$senderAddress"',
      );
    }
    return shouldProcessIncomingSms(
      prefs: prefs,
      subscriptionId: subscriptionId,
      senderAddress: senderAddress,
    );
  }
}
