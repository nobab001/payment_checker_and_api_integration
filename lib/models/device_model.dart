/// Per-SIM filter configuration
class SimConfig {
  final bool isEnabled;
  final List<String> filters;

  const SimConfig({this.isEnabled = true, this.filters = const []});

  factory SimConfig.fromJson(Map<String, dynamic> m) {
    final senders = m['allowed_senders'] ?? m['filters'];
    final off =
        m['active'] == false || m['status'] == 'off' || m['isEnabled'] == false;
    final on =
        m['active'] == true ||
        m['isEnabled'] == true ||
        m['enabled'] == true ||
        m['status'] == 'on';
    return SimConfig(
      isEnabled: on || !off,
      filters: senders is List
          ? senders.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList()
          : const [],
    );
  }

  Map<String, dynamic> toJson() => {'isEnabled': isEnabled, 'filters': filters};

  SimConfig copyWith({bool? isEnabled, List<String>? filters}) => SimConfig(
    isEnabled: isEnabled ?? this.isEnabled,
    filters: filters ?? this.filters,
  );
}

/// Combined SIM settings container
class SimSettings {
  final SimConfig sim1;
  final SimConfig sim2;

  const SimSettings({required this.sim1, required this.sim2});

  factory SimSettings.fromJson(Map<String, dynamic> m) {
    return SimSettings(
      sim1: SimConfig.fromJson(m['sim1'] ?? {}),
      sim2: SimConfig.fromJson(m['sim2'] ?? {}),
    );
  }

  Map<String, dynamic> toJson() => {
    'sim1': sim1.toJson(),
    'sim2': sim2.toJson(),
  };

  /// Build from the flat device row (allowed/blocked keyword strings)
  factory SimSettings.fromDeviceRow({
    required bool smsFilterEnabled,
    required bool blockUnknown,
    required bool blockIncoming,
    required String allowedKeywords,
    required String blockedKeywords,
  }) {
    final allowed = allowedKeywords.isEmpty
        ? <String>[]
        : allowedKeywords
              .split(',')
              .map((k) => k.trim())
              .where((k) => k.isNotEmpty)
              .toList();
    final blocked = blockedKeywords.isEmpty
        ? <String>[]
        : blockedKeywords
              .split(',')
              .map((k) => k.trim())
              .where((k) => k.isNotEmpty)
              .toList();
    // Both SIMs share the same filters for now
    return SimSettings(
      sim1: SimConfig(isEnabled: smsFilterEnabled, filters: allowed),
      sim2: SimConfig(isEnabled: smsFilterEnabled, filters: blocked),
    );
  }
}

/// Model for a registered device (matches server's devices table)
class DeviceModel {
  final int id;
  final int userId;
  final String deviceId;
  final String deviceName;
  /// User override from `devices.custom_name`; when empty, [displayDeviceName] uses [deviceModel] then [deviceName].
  final String customName;
  final String deviceModel;
  final String androidVersion;
  final String? sim1Number;
  final String? sim1Operator;
  final String? sim2Number;
  final String? sim2Operator;
  final bool smsFilterEnabled;
  final bool blockUnknown;
  final bool blockIncoming;
  final String allowedKeywords;
  final String blockedKeywords;
  /// Server: `pending` | `active` (master–slave approval).
  final String status;
  /// Account parent device (can approve pending devices and transfer role).
  final bool isParent;
  final SimSettings? simSettings;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  /// Last app presence ping / registration (`devices.last_seen_at`).
  final DateTime? lastSeenAt;
  /// Reported on last heartbeat (`devices.last_battery_percent`), 0–100.
  final int? lastBatteryPercent;

  const DeviceModel({
    required this.id,
    required this.userId,
    required this.deviceId,
    required this.deviceName,
    this.customName = '',
    this.status = 'active',
    this.isParent = false,
    this.deviceModel = '',
    this.androidVersion = '',
    this.sim1Number,
    this.sim1Operator,
    this.sim2Number,
    this.sim2Operator,
    this.smsFilterEnabled = true,
    this.blockUnknown = false,
    this.blockIncoming = false,
    this.allowedKeywords = '',
    this.blockedKeywords = '',
    this.simSettings,
    this.createdAt,
    this.updatedAt,
    this.lastSeenAt,
    this.lastBatteryPercent,
  });

  /// Prefer explicit presence time, else row update time.
  DateTime? get effectiveLastSync => lastSeenAt ?? updatedAt;
  String get displayDeviceName {
    final c = customName.trim();
    if (c.isNotEmpty) return c;
    final m = deviceModel.trim();
    if (m.isNotEmpty) return m;
    final n = deviceName.trim();
    if (n.isNotEmpty) return n;
    return 'Device';
  }

  bool get isPending => status == 'pending';

  bool get isActiveDevice => status == 'active';

  factory DeviceModel.fromJson(Map<String, dynamic> m) {
    // Try nested sim_settings first, then flat fields
    SimSettings? sims;
    if (m['sim_settings'] != null) {
      sims = SimSettings.fromJson(m['sim_settings'] as Map<String, dynamic>);
    } else {
      sims = SimSettings.fromDeviceRow(
        smsFilterEnabled:
            m['sms_filter_enabled'] == true ||
            m['smsFilterEnabled'] == true ||
            m['sms_filter_enabled'] == 1,
        blockUnknown:
            m['block_unknown'] == true ||
            m['blockUnknown'] == true ||
            m['block_unknown'] == 1,
        blockIncoming:
            m['block_incoming'] == true ||
            m['blockIncoming'] == true ||
            m['block_incoming'] == 1,
        allowedKeywords:
            (m['allowed_keywords'] ?? m['allowedKeywords'] ?? '') as String,
        blockedKeywords:
            (m['blocked_keywords'] ?? m['blockedKeywords'] ?? '') as String,
      );
    }
    return DeviceModel(
      id: (m['id'] is int) ? m['id'] : int.tryParse('${m['id']}') ?? 0,
      userId: (m['userId'] is int)
          ? m['userId'] as int
          : (m['user_id'] is int)
              ? m['user_id'] as int
              : int.tryParse('${m['userId'] ?? m['user_id']}') ?? 0,
      deviceId: (m['device_id'] ?? m['deviceId'] ?? '').toString(),
      deviceName: (m['device_name'] ?? m['deviceName'] ?? 'My Phone') as String,
      customName: (m['custom_name'] ?? m['customName'] ?? '').toString(),
      status: (m['status'] ?? 'active').toString(),
      isParent:
          m['is_parent'] == true ||
          m['isParent'] == true ||
          m['is_parent'] == 1 ||
          m['isParent'] == 1,
      deviceModel: (m['device_model'] ?? m['deviceModel'] ?? '') as String,
      androidVersion:
          (m['android_version'] ?? m['androidVersion'] ?? '') as String,
      sim1Number: (m['sim1_number'] ?? m['sim1Number'] ?? '') as String?,
      sim1Operator: (m['sim1_operator'] ?? m['sim1Operator'] ?? '') as String?,
      sim2Number: (m['sim2_number'] ?? m['sim2Number'] ?? '') as String?,
      sim2Operator: (m['sim2_operator'] ?? m['sim2Operator'] ?? '') as String?,
      smsFilterEnabled:
          m['sms_filter_enabled'] == true ||
          m['smsFilterEnabled'] == true ||
          m['sms_filter_enabled'] == 1,
      blockUnknown:
          m['block_unknown'] == true ||
          m['blockUnknown'] == true ||
          m['block_unknown'] == 1,
      blockIncoming:
          m['block_incoming'] == true ||
          m['blockIncoming'] == true ||
          m['block_incoming'] == 1,
      allowedKeywords:
          (m['allowed_keywords'] ?? m['allowedKeywords'] ?? '') as String,
      blockedKeywords:
          (m['blocked_keywords'] ?? m['blockedKeywords'] ?? '') as String,
      simSettings: sims,
      createdAt: _parseDate(m['created_at'] ?? m['createdAt']),
      updatedAt: _parseDate(m['updated_at'] ?? m['updatedAt']),
      lastSeenAt: _parseDate(
        m['last_seen_at'] ?? m['lastSeenAt'] ?? m['last_seen'],
      ),
      lastBatteryPercent: _parseBattery(
        m['last_battery_percent'] ?? m['lastBatteryPercent'],
      ),
    );
  }

  static int? _parseBattery(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse(v.toString());
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'userId': userId,
    'deviceId': deviceId,
    'deviceName': deviceName,
    'customName': customName,
    'status': status,
    'isParent': isParent,
    'deviceModel': deviceModel,
    'androidVersion': androidVersion,
    'sim1Number': sim1Number,
    'sim1Operator': sim1Operator,
    'sim2Number': sim2Number,
    'sim2Operator': sim2Operator,
    'smsFilterEnabled': smsFilterEnabled,
    'blockUnknown': blockUnknown,
    'blockIncoming': blockIncoming,
    'allowedKeywords': allowedKeywords,
    'blockedKeywords': blockedKeywords,
    if (lastSeenAt != null) 'lastSeenAt': lastSeenAt!.toIso8601String(),
    if (lastBatteryPercent != null) 'lastBatteryPercent': lastBatteryPercent,
  };
}

/// Filter settings for a single SIM card
class SimFilterSettings {
  final bool smsFilterEnabled;
  final bool blockUnknown;
  final bool blockIncoming;
  final List<String> allowedKeywords;
  final List<String> blockedKeywords;

  const SimFilterSettings({
    this.smsFilterEnabled = true,
    this.blockUnknown = false,
    this.blockIncoming = false,
    this.allowedKeywords = const [],
    this.blockedKeywords = const [],
  });

  factory SimFilterSettings.fromJson(Map<String, dynamic> m) {
    return SimFilterSettings(
      smsFilterEnabled: m['smsFilterEnabled'] ?? true,
      blockUnknown: m['blockUnknown'] ?? false,
      blockIncoming: m['blockIncoming'] ?? false,
      allowedKeywords:
          (m['allowedKeywords'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      blockedKeywords:
          (m['blockedKeywords'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
    'smsFilterEnabled': smsFilterEnabled,
    'blockUnknown': blockUnknown,
    'blockIncoming': blockIncoming,
    'allowedKeywords': allowedKeywords,
    'blockedKeywords': blockedKeywords,
  };

  /// Parse comma-separated keyword strings into lists
  static SimFilterSettings fromKeywordStrings({
    required String allowed,
    required String blocked,
    bool smsFilterEnabled = true,
    bool blockUnknown = false,
    bool blockIncoming = false,
  }) {
    return SimFilterSettings(
      smsFilterEnabled: smsFilterEnabled,
      blockUnknown: blockUnknown,
      blockIncoming: blockIncoming,
      allowedKeywords: allowed.isEmpty
          ? []
          : allowed
                .split(',')
                .map((k) => k.trim())
                .where((k) => k.isNotEmpty)
                .toList(),
      blockedKeywords: blocked.isEmpty
          ? []
          : blocked
                .split(',')
                .map((k) => k.trim())
                .where((k) => k.isNotEmpty)
                .toList(),
    );
  }

  String get allowedKeywordsString => allowedKeywords.join(', ');
  String get blockedKeywordsString => blockedKeywords.join(', ');
}
