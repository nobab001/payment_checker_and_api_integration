class UserModel {
  /// Primary key from MySQL (exposed as String in the app).
  final String id;
  final String name;
  final String phone;
  final String role;
  final String email;
  final String pin;
  final bool emailVerified;
  final bool blocked;

  /// App wallet balance (maps to `balance` / `wallet_balance` in JSON).
  final double balance;

  /// Premium history service expiry (wallet purchases extend this).
  final DateTime? historyPremiumUntil;

  const UserModel({
    required this.id,
    required this.name,
    required this.phone,
    required this.role,
    required this.email,
    this.pin = '',
    this.emailVerified = false,
    this.blocked = false,
    this.balance = 0,
    this.historyPremiumUntil,
  });

  /// `true` when the user must finish onboarding (name / profile) in-app.
  bool get needsProfileCompletion => name.trim().isEmpty;

  static String _stringId(dynamic v) {
    if (v == null) return '';
    if (v is String) return v;
    return v.toString();
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  static double _pickBalance(Map<String, dynamic> m) {
    final keys = ['balance', 'wallet_balance', 'walletBalance'];
    for (final k in keys) {
      final v = m[k];
      if (v is num) return v.toDouble();
    }
    return 0;
  }

  factory UserModel.fromJson(Map<String, dynamic> m) {
    final phone = (m['phone'] as String?) ??
        (m['phone_number'] as String?) ??
        (m['phoneNumber'] as String?) ??
        '';
    return UserModel(
      id: _stringId(m['id'] ?? m['user_id']),
      name: (m['name'] as String?) ?? '',
      phone: phone,
      role: (m['role'] as String?) ?? 'user',
      email: (m['email'] as String?) ?? '',
      pin: (m['pin'] as String?) ?? '',
      emailVerified: (m['emailVerified'] as bool?) ??
          (m['email_verified'] as bool?) ??
          false,
      blocked: (m['blocked'] as bool?) ?? (m['is_blocked'] as bool?) ?? false,
      balance: _pickBalance(m),
      historyPremiumUntil: _parseDate(
        m['historyPremiumUntil'] ?? m['history_premium_until'],
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'role': role,
        'email': email,
        'pin': pin,
        'emailVerified': emailVerified,
        'blocked': blocked,
        'balance': balance,
        if (historyPremiumUntil != null)
          'historyPremiumUntil': historyPremiumUntil!.toIso8601String(),
      };
}
