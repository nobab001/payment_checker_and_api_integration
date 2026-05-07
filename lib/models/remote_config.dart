class RemoteConfig {
  final bool appEnabled;
  final bool smsApiEnabled;
  final bool gmailApiEnabled;
  final bool userRegistrationEnabled;
  final bool smsGatewayActive;
  final bool smsGatewayChecked;
  final String whatsapp;
  final String facebook;
  final String telegram;
  final String youtube;

  const RemoteConfig({
    this.appEnabled = true,
    this.smsApiEnabled = true,
    this.gmailApiEnabled = true,
    this.userRegistrationEnabled = true,
    this.smsGatewayActive = false,
    this.smsGatewayChecked = false,
    this.whatsapp = '',
    this.facebook = '',
    this.telegram = '',
    this.youtube = '',
  });

  factory RemoteConfig.fromJson(Map<String, dynamic> j) {
    bool? b(String k) => j[k] as bool?;
    String? s(String k) => j[k] as String?;
    return RemoteConfig(
      appEnabled: b('appEnabled') ?? true,
      smsApiEnabled: b('smsApiEnabled') ?? true,
      gmailApiEnabled: b('gmailApiEnabled') ?? true,
      userRegistrationEnabled: b('userRegistrationEnabled') ?? true,
      smsGatewayActive: b('smsGatewayActive') ?? false,
      smsGatewayChecked: b('smsGatewayChecked') ?? true,
      whatsapp: s('whatsapp') ?? '',
      facebook: s('facebook') ?? '',
      telegram: s('telegram') ?? '',
      youtube: s('youtube') ?? '',
    );
  }
}
