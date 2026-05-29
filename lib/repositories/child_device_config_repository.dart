import '../models/child_device_remote_config.dart';
import '../models/device_model.dart';
import '../services/api_service.dart';
/// Loads and saves per-child SIM configuration for the parent device.
class ChildDeviceConfigRepository {
  ChildDeviceConfigRepository({ApiService? api})
      : _api = api ?? ApiService.instance;

  final ApiService _api;

  Future<ChildDeviceRemoteConfig> fetchForChild(DeviceModel device) async {
    final data = await _api.getJson(
      '/api/devices/${device.id}/settings',
      auth: true,
    );
    if (data['success'] == true && data['config'] is Map<String, dynamic>) {
      return ChildDeviceRemoteConfig.fromJson(
        data['config'] as Map<String, dynamic>,
        childDeviceRowId: device.id,
        childHardwareDeviceId: device.deviceId,
      );
    }
    return ChildDeviceRemoteConfig.fromDevice(device);
  }

  Future<DeviceModel> save(ChildDeviceRemoteConfig config) async {
    final data = await _api.putJson(
      '/api/devices/${config.childDeviceRowId}/settings',
      config.toApiBody(),
      auth: true,
    );
    if (data['success'] == true && data['device'] is Map<String, dynamic>) {
      return DeviceModel.fromJson(data['device'] as Map<String, dynamic>);
    }
    throw Exception(data['message']?.toString() ?? 'Save failed');
  }

  /// Child handset: pull server config into local prefs for the SMS background handler.
  Future<void> syncLocalCacheForThisDevice(String hardwareDeviceId) async {
    await _api.syncDeviceSettingsToCache(hardwareDeviceId: hardwareDeviceId);
  }
}
