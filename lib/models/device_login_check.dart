/// Result of POST /api/check-device-login (before OTP is sent).
class DeviceLoginCheck {
  final bool allowed;
  final String? message;
  final String? boundAccountLabel;
  final List<String> boundPhones;
  final List<String> boundEmails;

  const DeviceLoginCheck({
    required this.allowed,
    this.message,
    this.boundAccountLabel,
    this.boundPhones = const [],
    this.boundEmails = const [],
  });

  factory DeviceLoginCheck.allowed() =>
      const DeviceLoginCheck(allowed: true);

  static List<String> _stringList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map((e) => e.toString().trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  factory DeviceLoginCheck.fromJson(Map<String, dynamic> data) {
    return DeviceLoginCheck(
      allowed: data['allowed'] == true,
      message: data['message'] as String?,
      boundAccountLabel: data['boundAccountLabel'] as String?,
      boundPhones: _stringList(data['boundPhones']),
      boundEmails: _stringList(data['boundEmails']),
    );
  }

  factory DeviceLoginCheck.denied(Map<String, dynamic> data) {
    return DeviceLoginCheck(
      allowed: false,
      message: data['message'] as String?,
      boundAccountLabel: data['boundAccountLabel'] as String?,
      boundPhones: _stringList(data['boundPhones']),
      boundEmails: _stringList(data['boundEmails']),
    );
  }
}
