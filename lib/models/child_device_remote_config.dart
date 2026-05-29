import 'device_model.dart';

/// Parent → child remote SIM configuration (server canonical schema).
class ChildDeviceRemoteConfig {
  final int childDeviceRowId;
  final String childHardwareDeviceId;
  final SimSlotRemoteConfig sim1;
  final SimSlotRemoteConfig sim2;

  const ChildDeviceRemoteConfig({
    required this.childDeviceRowId,
    required this.childHardwareDeviceId,
    required this.sim1,
    required this.sim2,
  });

  factory ChildDeviceRemoteConfig.fromDevice(DeviceModel device) {
    final sims =
        device.simSettings ??
        SimSettings(
          sim1: SimConfig(isEnabled: device.smsFilterEnabled),
          sim2: SimConfig(isEnabled: device.smsFilterEnabled),
        );
    return ChildDeviceRemoteConfig(
      childDeviceRowId: device.id,
      childHardwareDeviceId: device.deviceId,
      sim1: SimSlotRemoteConfig.fromSimConfig(sims.sim1),
      sim2: SimSlotRemoteConfig.fromSimConfig(sims.sim2),
    );
  }

  factory ChildDeviceRemoteConfig.fromJson(
    Map<String, dynamic> json, {
    required int childDeviceRowId,
    required String childHardwareDeviceId,
  }) {
    final sim = json['sim_settings'] as Map<String, dynamic>? ?? json;
    return ChildDeviceRemoteConfig(
      childDeviceRowId: childDeviceRowId,
      childHardwareDeviceId: childHardwareDeviceId,
      sim1: SimSlotRemoteConfig.fromJson(sim['sim1'] as Map<String, dynamic>? ?? {}),
      sim2: SimSlotRemoteConfig.fromJson(sim['sim2'] as Map<String, dynamic>? ?? {}),
    );
  }

  Map<String, dynamic> toApiBody() => {
    'sim1': sim1.toApiJson(),
    'sim2': sim2.toApiJson(),
  };

  /// Firestore-style document (optional backend).
  Map<String, dynamic> toFirestoreDocument() => {
    'child_device_id': childHardwareDeviceId,
    'child_device_row_id': childDeviceRowId,
    'sim_1_active': sim1.active,
    'sim_1_allowed_senders': sim1.allowedSenders,
    'sim_2_active': sim2.active,
    'sim_2_allowed_senders': sim2.allowedSenders,
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  };

  ChildDeviceRemoteConfig copyWith({
    SimSlotRemoteConfig? sim1,
    SimSlotRemoteConfig? sim2,
  }) =>
      ChildDeviceRemoteConfig(
        childDeviceRowId: childDeviceRowId,
        childHardwareDeviceId: childHardwareDeviceId,
        sim1: sim1 ?? this.sim1,
        sim2: sim2 ?? this.sim2,
      );
}

class SimSlotRemoteConfig {
  final bool active;
  final List<String> allowedSenders;

  const SimSlotRemoteConfig({
    required this.active,
    this.allowedSenders = const [],
  });

  factory SimSlotRemoteConfig.fromSimConfig(SimConfig config) =>
      SimSlotRemoteConfig(
        active: config.isEnabled,
        allowedSenders: List<String>.from(config.filters),
      );

  factory SimSlotRemoteConfig.fromJson(Map<String, dynamic> m) {
    final active =
        m['active'] == true || m['isEnabled'] == true || m['status'] == 'on';
    final senders = m['allowed_senders'] ?? m['filters'];
    return SimSlotRemoteConfig(
      active: active,
      allowedSenders: senders is List
          ? senders.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList()
          : const [],
    );
  }

  Map<String, dynamic> toApiJson() => {
    'active': active,
    'status': active ? 'on' : 'off',
    'allowed_senders': allowedSenders,
    'filters': allowedSenders,
  };
}
