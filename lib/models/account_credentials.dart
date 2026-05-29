class AccountCredentials {
  final List<String> phones;
  final List<String> emails;
  final int maxPerType;

  const AccountCredentials({
    this.phones = const [],
    this.emails = const [],
    this.maxPerType = 5,
  });

  factory AccountCredentials.fromJson(Map<String, dynamic> m) {
    List<String> list(dynamic raw) {
      if (raw is! List) return [];
      return raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    }

    return AccountCredentials(
      phones: list(m['phones']),
      emails: list(m['emails']),
      maxPerType: (m['maxPerType'] as int?) ?? (m['max_per_type'] as int?) ?? 5,
    );
  }
}
