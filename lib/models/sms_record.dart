class SmsRecord {
  final String t;  // timestamp ISO8601
  final String s;  // sender (bKash/Nagad/Rocket/Upay)
  final String m;  // raw message body
  final String b;  // balance after transaction
  final String tp; // type: recv/send/out/in/req/txn
  final double am; // transaction amount

  const SmsRecord({
    required this.t,
    required this.s,
    required this.m,
    required this.b,
    required this.tp,
    required this.am,
  });

  factory SmsRecord.fromJson(Map<String, dynamic> j) => SmsRecord(
        t: (j['t'] as String?) ?? DateTime.now().toIso8601String(),
        s: (j['s'] as String?) ?? '',
        m: (j['m'] as String?) ?? '',
        b: (j['b'] as String?) ?? '0',
        tp: (j['tp'] as String?) ?? 'txn',
        am: ((j['am'] as num?) ?? 0).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        't': t,
        's': s,
        'm': m,
        'b': b,
        'tp': tp,
        'am': am,
      };

  DateTime get time => DateTime.tryParse(t) ?? DateTime.now();
}
