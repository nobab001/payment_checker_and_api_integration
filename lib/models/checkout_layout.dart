import '../constants/checkout_blocks.dart';

class CheckoutNumberSlot {
  final int simSlot;
  final String phone;
  final bool enabled;
  final int position;
  final String? bankName;
  final String? accountName;
  final String? branch;
  final String? accountNumber;

  const CheckoutNumberSlot({
    required this.simSlot,
    required this.phone,
    this.enabled = true,
    this.position = 1,
    this.bankName,
    this.accountName,
    this.branch,
    this.accountNumber,
  });

  factory CheckoutNumberSlot.fromJson(Map<String, dynamic> j) =>
      CheckoutNumberSlot(
        simSlot: (j['simSlot'] as num?)?.toInt() ?? 1,
        phone: j['phone']?.toString() ?? '',
        enabled: j['enabled'] != false,
        position: (j['position'] as num?)?.toInt() ?? 1,
        bankName: j['bankName']?.toString(),
        accountName: j['accountName']?.toString(),
        branch: j['branch']?.toString(),
        accountNumber: j['accountNumber']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'simSlot': simSlot,
        'phone': phone,
        'enabled': enabled,
        'position': position,
        if (bankName != null) 'bankName': bankName,
        if (accountName != null) 'accountName': accountName,
        if (branch != null) 'branch': branch,
        if (accountNumber != null) 'accountNumber': accountNumber,
      };

  CheckoutNumberSlot copyWith({
    bool? enabled,
    int? position,
    String? bankName,
    String? accountName,
    String? branch,
  }) =>
      CheckoutNumberSlot(
        simSlot: simSlot,
        phone: phone,
        enabled: enabled ?? this.enabled,
        position: position ?? this.position,
        bankName: bankName ?? this.bankName,
        accountName: accountName ?? this.accountName,
        branch: branch ?? this.branch,
        accountNumber: accountNumber,
      );
}

class CheckoutBlockConfig {
  final String id;
  final String title;
  final List<CheckoutNumberSlot> numbers;
  final bool enabled;

  const CheckoutBlockConfig({
    required this.id,
    required this.title,
    required this.numbers,
    this.enabled = true,
  });

  factory CheckoutBlockConfig.fromJson(String id, Map<String, dynamic> j) =>
      CheckoutBlockConfig(
        id: id,
        title: j['title']?.toString() ?? CheckoutBlocks.titles[id] ?? id,
        numbers: (j['numbers'] as List<dynamic>? ?? [])
            .map((e) => CheckoutNumberSlot.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList(),
        enabled: j['enabled'] != false,
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'numbers': numbers.map((n) => n.toJson()).toList(),
        'enabled': enabled,
      };

  CheckoutBlockConfig copyWith({
    String? title,
    List<CheckoutNumberSlot>? numbers,
    bool? enabled,
  }) =>
      CheckoutBlockConfig(
        id: id,
        title: title ?? this.title,
        numbers: numbers ?? this.numbers,
        enabled: enabled ?? this.enabled,
      );
}

class CheckoutLayout {
  final int version;
  final List<String> blockOrder;
  final Map<String, CheckoutBlockConfig> blocks;

  const CheckoutLayout({
    this.version = 1,
    required this.blockOrder,
    required this.blocks,
  });

  factory CheckoutLayout.empty() => CheckoutLayout(
        blockOrder: List<String>.from(CheckoutBlocks.defaultOrder),
        blocks: {
          for (final id in CheckoutBlocks.defaultOrder)
            id: CheckoutBlockConfig(
              id: id,
              title: CheckoutBlocks.titles[id]!,
              numbers: [],
            ),
        },
      );

  factory CheckoutLayout.fromJson(Map<String, dynamic>? j) {
    if (j == null || j.isEmpty) return CheckoutLayout.empty();
    final order = (j['blockOrder'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        List<String>.from(CheckoutBlocks.defaultOrder);
    final rawBlocks = j['blocks'] as Map<String, dynamic>? ?? {};
    final blocks = <String, CheckoutBlockConfig>{};
    for (final id in order) {
      final raw = rawBlocks[id] as Map<String, dynamic>?;
      blocks[id] = raw != null
          ? CheckoutBlockConfig.fromJson(id, raw)
          : CheckoutBlockConfig(
              id: id,
              title: CheckoutBlocks.titles[id] ?? id,
              numbers: [],
            );
    }
    return CheckoutLayout(
      version: (j['version'] as num?)?.toInt() ?? 1,
      blockOrder: order,
      blocks: blocks,
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'blockOrder': blockOrder,
        'blocks': {
          for (final e in blocks.entries) e.key: e.value.toJson(),
        },
      };
}
