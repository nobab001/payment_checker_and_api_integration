import 'package:flutter/foundation.dart';

import '../models/otp_verify_response.dart';
import '../models/user_model.dart';
import 'api_service.dart';

enum OtpError {
  notConfigured,
  rateLimited,
  expired,
  alreadyUsed,
  invalid,
  notFound,
  unknown,
}

class OtpResult {
  final bool success;
  final OtpError? error;
  final String? message;
  final String? token;
  final bool isNewUser;
  final UserModel? user;

  const OtpResult.ok({
    this.token,
    this.isNewUser = false,
    this.user,
  })  : success = true,
        error = null,
        message = null;

  const OtpResult.fail(this.error, this.message)
      : success = false,
        token = null,
        isNewUser = false,
        user = null;
}

class OtpService {
  OtpService._();
  static final instance = OtpService._();

  /// Sends OTP via `/api/send-otp` with body `{ "phone": contact }`.
  /// [contact] is either a Bangladesh mobile number or a `@gmail.com` address (server picks SMS vs Gmail).
  Future<OtpResult> sendOtp(String contact) async {
    try {
      final data = await ApiService.instance.postJson('/api/send-otp', {
        'phone': contact.trim(),
      });
      if (data['success'] == false) {
        final msg = _messageFromBody(data);
        return OtpResult.fail(OtpError.unknown, msg ?? 'OTP পাঠানো যায়নি');
      }
      return const OtpResult.ok();
    } on ApiException catch (e) {
      debugPrint(
        '[OtpService] sendOtp ApiException: status=${e.statusCode} msg=${e.message}',
      );
      return OtpResult.fail(
        _mapHttp(e.statusCode),
        _friendlyServerMessage(e.message, _bengaliForSend(e.statusCode)),
      );
    } catch (e) {
      debugPrint('[OtpService] sendOtp unknown error: $e');
      return const OtpResult.fail(OtpError.unknown, 'কিছু একটা সমস্যা হয়েছে');
    }
  }

  /// Verifies with `{ "phone": contact, "code": code }` (same [contact] as send).
  Future<OtpResult> verifyOtp(String contact, String code) async {
    try {
      final data = await ApiService.instance.postJson('/api/verify-otp', {
        'phone': contact.trim(),
        'code': code.trim(),
      });
      final parsed = OtpVerifyResponse.fromJson(data);
      if (!parsed.success) {
        final msg = parsed.message ?? 'যাচাই ব্যর্থ হয়েছে';
        return OtpResult.fail(OtpError.invalid, msg);
      }
      final token = parsed.token;
      if (token == null || token.isEmpty) {
        return const OtpResult.fail(OtpError.unknown, 'সার্ভার টোকেন পাঠায়নি');
      }
      return OtpResult.ok(
        token: token,
        isNewUser: parsed.isNewUser,
        user: parsed.user,
      );
    } on ApiException catch (e) {
      debugPrint(
        '[OtpService] verifyOtp ApiException: status=${e.statusCode} msg=${e.message}',
      );
      return OtpResult.fail(
        _mapHttp(e.statusCode),
        _friendlyServerMessage(e.message, _bengaliForOtp(e.statusCode)),
      );
    } catch (e) {
      debugPrint('[OtpService] verifyOtp unknown error: $e');
      return const OtpResult.fail(OtpError.unknown, 'কিছু একটা সমস্যা হয়েছে');
    }
  }

  OtpError _mapHttp(int? status) => switch (status) {
        400 => OtpError.invalid,
        404 => OtpError.notFound,
        409 => OtpError.alreadyUsed,
        410 => OtpError.expired,
        429 => OtpError.rateLimited,
        500 => OtpError.unknown,
        503 => OtpError.notConfigured,
        _ => OtpError.unknown,
      };

  String? _messageFromBody(Map<String, dynamic> data) {
    final m = data['message'] as String?;
    if (m != null && m.isNotEmpty) return m;
    final e = data['error'] as String?;
    if (e != null && e.isNotEmpty) return e;
    return null;
  }

  /// Prefer a short server [apiMessage] when it looks user-facing; else [fallback].
  String _friendlyServerMessage(String apiMessage, String fallback) {
    final t = apiMessage.trim();
    if (t.isEmpty || t == 'Request failed') return fallback;
    if (t.length > 200) return fallback;
    return t;
  }

  String _bengaliForSend(int? status) => switch (status) {
        400 => 'অনুরোধ গ্রহণযোগ্য নয় — নম্বর বা তথ্য পরীক্ষা করুন',
        429 => '৬০ সেকেন্ড পরে আবার চেষ্টা করুন',
        500 => 'সার্ভারে সমস্যা হয়েছে। কিছুক্ষণ পর আবার চেষ্টা করুন',
        503 => 'SMS বা ইমেইল OTP সার্ভারে চালু নেই',
        _ => 'কিছু একটা সমস্যা হয়েছে',
      };

  String _bengaliForOtp(int? status) => switch (status) {
        400 => 'কোড ভুল বা অনুরোধ সঠিক নয় — আবার চেষ্টা করুন',
        404 => 'OTP পাওয়া যায়নি',
        409 => 'এই কোড আগেই ব্যবহার করা হয়েছে',
        410 => 'কোড মেয়াদ উত্তীর্ণ — নতুন কোড নিন',
        429 => '৬০ সেকেন্ড পরে আবার চেষ্টা করুন',
        500 => 'সার্ভারে সমস্যা হয়েছে। কিছুক্ষণ পর আবার চেষ্টা করুন',
        503 => 'SMS বা ইমেইল OTP সার্ভারে চালু নেই',
        _ => 'কিছু একটা সমস্যা হয়েছে',
      };
}
