import '../models/sim_filter_preferences.dart';
import 'bd_phone_utils.dart';

/// Validates per-SIM setup before monitoring can start.
/// Requires: active slot, valid BD mobile, and at least one Admin Template or Custom Sender.
class DeviceSetupValidator {
  DeviceSetupValidator._();

  static bool slotHasAdminTemplate(List<String> providerTags) =>
      providerTags.isNotEmpty;

  static bool slotHasCustomSender(List<String> customSenders) =>
      customSenders.isNotEmpty;

  static bool slotReady({
    required String phone,
    required List<String> providerTags,
    List<String> customSenders = const [],
  }) =>
      BdPhoneUtils.isValid(phone) &&
      (slotHasAdminTemplate(providerTags) || slotHasCustomSender(customSenders));

  /// `null` when valid; otherwise a user-facing error message.
  static String? validatePreferences(SimFilterPreferences prefs) {
    if (!prefs.sim1Active && !prefs.sim2Active) {
      return 'কমপক্ষে একটি SIM slot ON করুন';
    }
    if (prefs.sim1Active &&
        !slotReady(
          phone: prefs.sim1Number,
          providerTags: prefs.sim1ProviderTags,
          customSenders: prefs.sim1CustomSenders,
        )) {
      return 'SIM 1: বৈধ মোবাইল নম্বর এবং Option A অথবা Option B বাছুন';
    }
    if (prefs.sim2Active &&
        !slotReady(
          phone: prefs.sim2Number,
          providerTags: prefs.sim2ProviderTags,
          customSenders: prefs.sim2CustomSenders,
        )) {
      return 'SIM 2: বৈধ মোবাইল নম্বর এবং Option A অথবা Option B বাছুন';
    }
    return null;
  }

  static bool isDeviceConfigured(SimFilterPreferences prefs) =>
      validatePreferences(prefs) == null;
}
