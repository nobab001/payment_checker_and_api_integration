import 'user_model.dart';

/// Parsed body from [POST /api/verify-otp] on HTTP 2xx.
///
/// Server shape: `{ "success": true, "token": "...", "user": { ... } }`.
class OtpVerifyResponse {
  final bool success;
  final String? message;
  final String? token;
  final UserModel? user;
  final bool isNewUser;

  const OtpVerifyResponse({
    required this.success,
    this.message,
    this.token,
    this.user,
    this.isNewUser = false,
  });

  factory OtpVerifyResponse.fromJson(Map<String, dynamic> json) {
    final rawUser = json['user'];
    UserModel? user;
    if (rawUser is Map<String, dynamic>) {
      user = UserModel.fromJson(rawUser);
    }

    final token = json['token'];
    return OtpVerifyResponse(
      success: json['success'] == true,
      message: json['message'] as String? ?? json['error'] as String?,
      token: token is String ? token : null,
      user: user,
      isNewUser: json['isNewUser'] == true || json['is_new_user'] == true,
    );
  }
}
