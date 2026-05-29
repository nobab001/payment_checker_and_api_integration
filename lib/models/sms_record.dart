class SmsRecord {
  final String t;  // timestamp ISO8601
  final String s;  // sender (bKash/Nagad/Rocket/Upay)
  final String m;  // raw message body
  final String b;  // balance after transaction
  final String tp; // type: recv/send/out/in/req/txn
  final double am; // transaction amount
  final String? trxId;
  final int? simSlot;
  final String? simNumber;
  final String? providerTag;
  final String? senderNumber;

  const SmsRecord({
    required this.t,
    required this.s,
    required this.m,
    required this.b,
    required this.tp,
    required this.am,
    this.trxId,
    this.simSlot,
    this.simNumber,
    this.providerTag,
    this.senderNumber,
  });

  factory SmsRecord.fromJson(Map<String, dynamic> j) => SmsRecord(
        t: (j['t'] as String?) ?? DateTime.now().toIso8601String(),
        s: (j['s'] as String?) ?? '',
        m: (j['m'] as String?) ?? '',
        b: (j['b'] as String?) ?? '0',
        tp: (j['tp'] as String?) ?? 'txn',
        am: ((j['am'] as num?) ?? 0).toDouble(),
        trxId: j['trx_id'] as String? ?? j['trxId'] as String?,
        simSlot: (j['sim_slot'] as num?)?.toInt(),
        simNumber: j['sim_number'] as String?,
        providerTag: j['provider_tag'] as String?,
        senderNumber: j['sender_number'] as String?,
      );

  Map<String, dynamic> toJson() => {
        't': t,
        's': s,
        'm': m,
        'b': b,
        'tp': tp,
        'am': am,
        if (trxId != null) 'trx_id': trxId,
        if (simSlot != null) 'sim_slot': simSlot,
        if (simNumber != null) 'sim_number': simNumber,
        if (providerTag != null) 'provider_tag': providerTag,
        if (senderNumber != null) 'sender_number': senderNumber,
      };

  DateTime get time => DateTime.tryParse(t) ?? DateTime.now();
}
