class GlobalConfig {
  final bool smsApiEnabled;
  final bool gmailApiEnabled;
  final bool userRegistrationEnabled;
  final bool appEnabled;

  const GlobalConfig({
    this.smsApiEnabled = true,
    this.gmailApiEnabled = true,
    this.userRegistrationEnabled = true,
    this.appEnabled = true,
  });

  factory GlobalConfig.fromMap(Map<String, dynamic> m) => GlobalConfig(
    smsApiEnabled: m['smsApiEnabled'] as bool? ?? true,
    gmailApiEnabled: m['gmailApiEnabled'] as bool? ?? true,
    userRegistrationEnabled: m['userRegistrationEnabled'] as bool? ?? true,
    appEnabled: m['appEnabled'] as bool? ?? true,
  );

  Map<String, dynamic> toMap() => {
    'smsApiEnabled': smsApiEnabled,
    'gmailApiEnabled': gmailApiEnabled,
    'userRegistrationEnabled': userRegistrationEnabled,
    'appEnabled': appEnabled,
  };

  GlobalConfig copyWith({
    bool? smsApiEnabled,
    bool? gmailApiEnabled,
    bool? userRegistrationEnabled,
    bool? appEnabled,
  }) => GlobalConfig(
    smsApiEnabled: smsApiEnabled ?? this.smsApiEnabled,
    gmailApiEnabled: gmailApiEnabled ?? this.gmailApiEnabled,
    userRegistrationEnabled:
        userRegistrationEnabled ?? this.userRegistrationEnabled,
    appEnabled: appEnabled ?? this.appEnabled,
  );
}

class ApiKeys {
  final String smsApiKey;
  final String smsApiEndpoint;
  final String gmailApiKey;
  final String gmailApiEndpoint;

  const ApiKeys({
    this.smsApiKey = '',
    this.smsApiEndpoint = '',
    this.gmailApiKey = '',
    this.gmailApiEndpoint = '',
  });

  factory ApiKeys.fromMap(Map<String, dynamic> m) => ApiKeys(
    smsApiKey: m['smsApiKey'] as String? ?? '',
    smsApiEndpoint: m['smsApiEndpoint'] as String? ?? '',
    gmailApiKey: m['gmailApiKey'] as String? ?? '',
    gmailApiEndpoint: m['gmailApiEndpoint'] as String? ?? '',
  );

  Map<String, dynamic> toMap() => {
    'smsApiKey': smsApiKey,
    'smsApiEndpoint': smsApiEndpoint,
    'gmailApiKey': gmailApiKey,
    'gmailApiEndpoint': gmailApiEndpoint,
  };
}

class SocialLinks {
  final String whatsapp;
  final String facebook;
  final String telegram;
  final String youtube;

  const SocialLinks({
    this.whatsapp = '',
    this.facebook = '',
    this.telegram = '',
    this.youtube = '',
  });

  factory SocialLinks.fromMap(Map<String, dynamic> m) => SocialLinks(
    whatsapp: m['whatsapp'] as String? ?? '',
    facebook: m['facebook'] as String? ?? '',
    telegram: m['telegram'] as String? ?? '',
    youtube: m['youtube'] as String? ?? '',
  );

  Map<String, dynamic> toMap() => {
    'whatsapp': whatsapp.isEmpty ? null : whatsapp,
    'facebook': facebook.isEmpty ? null : facebook,
    'telegram': telegram.isEmpty ? null : telegram,
    'youtube': youtube.isEmpty ? null : youtube,
  };
}

class EmailConfig {
  final String gmailAddress;
  final String appPassword;

  const EmailConfig({this.gmailAddress = '', this.appPassword = ''});

  factory EmailConfig.fromMap(Map<String, dynamic> m) {
    String s(String k) => m[k] as String? ?? '';
    return EmailConfig(
      gmailAddress: s('gmailAddress').isNotEmpty
          ? s('gmailAddress')
          : s('gmail_address').isNotEmpty
          ? s('gmail_address')
          : s('email'),
      appPassword: s('appPassword').isNotEmpty
          ? s('appPassword')
          : s('app_password').isNotEmpty
          ? s('app_password')
          : s('password'),
    );
  }

  Map<String, dynamic> toMap() => {
    'gmailAddress': gmailAddress,
    'appPassword': appPassword,
  };

  bool get isConfigured => gmailAddress.isNotEmpty && appPassword.isNotEmpty;
}

/// One Gmail SMTP account for OTP round-robin.
class EmailAccount {
  final String id;
  final String email;
  final String appPassword;
  final int dailyLimit;
  final int sentCount;
  final bool isActive;

  const EmailAccount({
    this.id = '',
    this.email = '',
    this.appPassword = '',
    this.dailyLimit = 500,
    this.sentCount = 0,
    this.isActive = false,
  });

  factory EmailAccount.fromMap(Map<String, dynamic> m) => EmailAccount(
    id: m['id'] as String? ?? '',
    email: m['email'] as String? ?? '',
    appPassword:
        m['appPassword'] as String? ?? m['app_password'] as String? ?? '',
    dailyLimit:
        (m['dailyLimit'] as num?)?.toInt() ??
        (m['daily_limit'] as num?)?.toInt() ??
        500,
    sentCount:
        (m['sentCount'] as num?)?.toInt() ??
        (m['sent_count'] as num?)?.toInt() ??
        0,
    isActive: m['isActive'] as bool? ?? (m['is_active'] as int? ?? 0) == 1,
  );

  Map<String, dynamic> toMap() => {
    'email': email,
    'appPassword': appPassword,
    'dailyLimit': dailyLimit,
    'isActive': isActive,
  };

  EmailAccount copyWith({
    String? id,
    String? email,
    String? appPassword,
    int? dailyLimit,
    int? sentCount,
    bool? isActive,
  }) => EmailAccount(
    id: id ?? this.id,
    email: email ?? this.email,
    appPassword: appPassword ?? this.appPassword,
    dailyLimit: dailyLimit ?? this.dailyLimit,
    sentCount: sentCount ?? this.sentCount,
    isActive: isActive ?? this.isActive,
  );
}

class AppUser {
  final String uid;
  final String name;
  final String email;
  final String phone;
  final String role;
  final bool blocked;
  final bool smsEnabled;
  final bool gmailEnabled;
  final DateTime? createdAt;

  const AppUser({
    required this.uid,
    required this.name,
    required this.email,
    this.phone = '',
    this.role = 'user',
    this.blocked = false,
    this.smsEnabled = true,
    this.gmailEnabled = true,
    this.createdAt,
  });

  factory AppUser.fromMap(String uid, Map<String, dynamic> m) => AppUser(
    uid: uid,
    name: m['name'] as String? ?? '',
    email: m['email'] as String? ?? '',
    phone: m['phone'] as String? ?? '',
    role: m['role'] as String? ?? 'user',
    blocked: m['blocked'] as bool? ?? false,
    smsEnabled: m['smsEnabled'] as bool? ?? true,
    gmailEnabled: m['gmailEnabled'] as bool? ?? true,
    createdAt: m['createdAt'] != null
        ? (m['createdAt'] is String
              ? DateTime.tryParse(m['createdAt'] as String)
              : (m['createdAt'] as dynamic).toDate())
        : null,
  );

  Map<String, dynamic> toMap() => {
    'name': name,
    'email': email,
    'phone': phone,
    'role': role,
    'blocked': blocked,
    'smsEnabled': smsEnabled,
    'gmailEnabled': gmailEnabled,
  };
}
