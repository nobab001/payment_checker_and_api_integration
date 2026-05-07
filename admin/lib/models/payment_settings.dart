class PaymentSettings {
  final String bkashApiKey;
  final String bkashSecretKey;
  final String bkashAppId;
  final String bkashPassword;
  final bool testMode;
  final String bkashCallbackUrl;

  const PaymentSettings({
    this.bkashApiKey = '',
    this.bkashSecretKey = '',
    this.bkashAppId = '',
    this.bkashPassword = '',
    this.testMode = true,
    this.bkashCallbackUrl = '',
  });

  factory PaymentSettings.fromMap(Map<String, dynamic> m) => PaymentSettings(
        bkashApiKey: m['bkashApiKey'] as String? ?? '',
        bkashSecretKey: m['bkashSecretKey'] as String? ?? '',
        bkashAppId: m['bkashAppId'] as String? ?? '',
        bkashPassword: m['bkashPassword'] as String? ?? '',
        testMode: m['testMode'] as bool? ?? true,
        bkashCallbackUrl: m['bkashCallbackUrl'] as String? ?? '',
      );

  Map<String, dynamic> toMap() => {
        'bkashApiKey': bkashApiKey,
        'bkashSecretKey': bkashSecretKey,
        'bkashAppId': bkashAppId,
        'bkashPassword': bkashPassword,
        'testMode': testMode,
        'bkashCallbackUrl': bkashCallbackUrl,
      };

  bool get hasRequiredBkashFields =>
      bkashApiKey.isNotEmpty &&
      bkashSecretKey.isNotEmpty &&
      bkashAppId.isNotEmpty &&
      bkashPassword.isNotEmpty;
}
