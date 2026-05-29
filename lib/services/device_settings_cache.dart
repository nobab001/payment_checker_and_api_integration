import '../models/device_model.dart' show SimSettings;
import '../repositories/sim_filter_local_repository.dart';
import 'sim_sms_filter.dart';

/// Bridge for SMS handlers — delegates to [SimFilterLocalRepository] + [SimSmsFilter].
class DeviceSettingsCache {
  /// Background / foreground SMS: strict SIM + sender rules from local storage.
  static Future<bool> shouldSyncSms({
    required String deviceId,
    required int simSlot,
    required String smsBody,
    String? senderAddress,
  }) async {
    // [deviceId] kept for API compatibility; filters are per-handset local keys.
    return SimSmsFilter.shouldProcessIncomingSmsFromStorage(
      subscriptionId: simSlot,
      senderAddress: senderAddress,
    );
  }

  /// When server sync runs, merge without replacing local lists with empty server arrays.
  static Future<void> saveFromSimSettings(
    String hardwareDeviceId,
    SimSettings sims,
  ) async {
    await SimFilterLocalRepository.instance.mergeFromSimSettings(
      sim1Active: sims.sim1.isEnabled,
      sim1Filters: sims.sim1.filters,
      sim2Active: sims.sim2.isEnabled,
      sim2Filters: sims.sim2.filters,
    );
  }
}
