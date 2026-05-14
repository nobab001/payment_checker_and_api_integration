import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Caches device filter settings locally so background SMS handler
/// can check filters without network access.
class DeviceSettingsCache {
  static const _key = 'device_filter_settings';
  static SharedPreferences? _prefs;

  /// Returns filter settings for a given device_id.
  /// Returns null if no settings cached.
  static Future<DeviceFilterSettings?> getForDevice(String deviceId) async {
    _prefs ??= await SharedPreferences.getInstance();
    final raw = _prefs!.getString('${_key}_$deviceId');
    if (raw == null) return null;
    try {
      return DeviceFilterSettings.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  /// Saves filter settings for a given device_id.
  static Future<void> saveForDevice(String deviceId, DeviceFilterSettings settings) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString('${_key}_$deviceId', jsonEncode(settings.toJson()));
  }

  /// Checks if an SMS should be synced based on device filter settings.
  /// Returns true if SMS passes filters (or no filter configured = backup all).
  /// simSlot: 0 for SIM1, 1 for SIM2
  static Future<bool> shouldSyncSms({
    required String deviceId,
    required int simSlot,
    required String smsBody,
  }) async {
    final settings = await getForDevice(deviceId);
    if (settings == null) return true; // No settings = backup all

    final simConfig = simSlot == 0 ? settings.sim1 : settings.sim2;
    
    // If SIM is disabled, skip
    if (!simConfig.isEnabled) return false;
    
    // If no filters, backup all SMS from this SIM
    if (simConfig.filters.isEmpty) return true;
    
    // Check if any filter keyword is in SMS body
    final lower = smsBody.toLowerCase();
    return simConfig.filters.any((f) => lower.contains(f.toLowerCase()));
  }
}

class DeviceFilterSettings {
  final SimFilterConfig sim1;
  final SimFilterConfig sim2;

  const DeviceFilterSettings({required this.sim1, required this.sim2});

  factory DeviceFilterSettings.fromJson(Map<String, dynamic> m) {
    return DeviceFilterSettings(
      sim1: SimFilterConfig.fromJson(m['sim1'] ?? {}),
      sim2: SimFilterConfig.fromJson(m['sim2'] ?? {}),
    );
  }

  Map<String, dynamic> toJson() => {
    'sim1': sim1.toJson(),
    'sim2': sim2.toJson(),
  };
}

class SimFilterConfig {
  final bool isEnabled;
  final List<String> filters;

  const SimFilterConfig({required this.isEnabled, required this.filters});

  factory SimFilterConfig.fromJson(Map<String, dynamic> m) {
    return SimFilterConfig(
      isEnabled: m['status'] == 'on',
      filters: (m['filters'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() => {
    'status': isEnabled ? 'on' : 'off',
    'filters': filters,
  };
}