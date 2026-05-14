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

  // ── Send OTP to an EXISTING user ──────────────────────────────────────────
  // Calls POST /api/send-otp  with body  { "phone": "<phone or email>" }
  Future<OtpResult> sendOtp(String contact) async {
    try {
      final c    = ApiService.normalizeContactForApi(contact);
      final data = await ApiService.instance.postJson('/api/send-otp', {'phone': c});
      if (data['success'] == false) {
        return OtpResult.fail(OtpError.unknown, _messageFromBody(data) ?? 'OTP পাঠানো যায়নি');
      }
      return const OtpResult.ok();
    } on ApiException catch (e) {
      debugPrint('[OtpService] sendOtp ApiException: status=${e.statusCode} msg=${e.message}');
      return OtpResult.fail(_mapHttp(e.statusCode), _friendlyFromException(e, _bengaliForSend(e.statusCode)));
    } catch (e) {
      debugPrint('[OtpService] sendOtp unknown error: $e');
      return const OtpResult.fail(OtpError.unknown, 'কিছু একটা সমস্যা হয়েছে');
    }
  }

  // ── Send OTP to a NEW user (creates account first) ────────────────────────
  // Calls POST /api/send-otp-new  with body  { "phone": "<phone or email>" }
  Future<OtpResult> sendOtpNew(String contact) async {
    try {
      final c    = ApiService.normalizeContactForApi(contact);
      final data = await ApiService.instance.postJson('/api/send-otp-new', {'phone': c});
      if (data['success'] == false) {
        final errCode = data['error'] as String?;
        if (errCode == 'ALREADY_EXISTS') {
          // Account was created between the check and now → treat as existing user
          return OtpResult.fail(OtpError.alreadyUsed, 'এই নম্বর/ইমেইলে ইতিমধ্যে একটি অ্যাকাউন্ট আছে');
        }
        return OtpResult.fail(OtpError.unknown, _messageFromBody(data) ?? 'OTP পাঠানো যায়নি');
      }
      return const OtpResult.ok(isNewUser: true);
    } on ApiException catch (e) {
      debugPrint('[OtpService] sendOtpNew ApiException: status=${e.statusCode} msg=${e.message}');
      return OtpResult.fail(_mapHttp(e.statusCode), _friendlyFromException(e, _bengaliForSend(e.statusCode)));
    } catch (e) {
      debugPrint('[OtpService] sendOtpNew unknown error: $e');
      return const OtpResult.fail(OtpError.unknown, 'কিছু একটা সমস্যা হয়েছে');
    }
  }

  // ── Verify OTP code ───────────────────────────────────────────────────────
  // Calls POST /api/verify-otp  with body  { "phone": "...", "code": "123456" }
  Future<OtpResult> verifyOtp(String contact, String code) async {
    try {
      final c    = ApiService.normalizeContactForApi(contact);
      final data = await ApiService.instance.postJson('/api/verify-otp', {
        'phone': c,
        'code': code.trim(),
      });
      final parsed = OtpVerifyResponse.fromJson(data);
      if (!parsed.success) {
        return OtpResult.fail(OtpError.invalid, parsed.message ?? 'যাচাই ব্যর্থ হয়েছে');
      }
      final token = parsed.token;
      if (token == null || token.isEmpty) {
        return const OtpResult.fail(OtpError.unknown, 'সার্ভার টোকেন পাঠায়নি');
      }
      return OtpResult.ok(token: token, isNewUser: parsed.isNewUser, user: parsed.user);
    } on ApiException catch (e) {
      debugPrint('[OtpService] verifyOtp ApiException: status=${e.statusCode} msg=${e.message}');
      return OtpResult.fail(_mapHttp(e.statusCode), _friendlyFromException(e, _bengaliForOtp(e.statusCode)));
    } catch (e) {
      debugPrint('[OtpService] verifyOtp unknown error: $e');
      return const OtpResult.fail(OtpError.unknown, 'কিছু একটা সমস্যা হয়েছে');
    }
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  OtpError _mapHttp(int? status) => switch (status) {
        400 => OtpError.invalid,
        404 => OtpError.notFound,
        409 => OtpError.alreadyUsed,
        410 => OtpError.expired,
        429 => OtpError.rateLimited,
        500 => OtpError.unknown,
        503 => OtpError.notConfigured,
        _   => OtpError.unknown,
      };

  String? _messageFromBody(Map<String, dynamic> data) {
    final m = data['message'] as String?;
    if (m != null && m.isNotEmpty) return m;
    final e = data['error'] as String?;
    if (e != null && e.isNotEmpty) return e;
    return null;
  }

  String _friendlyServerMessage(String apiMessage, String fallback) {
    final t = apiMessage.trim();
    if (t.isEmpty || t == 'Request failed') return fallback;
    if (t.length > 200) return fallback;
    return t;
  }

  String _friendlyFromException(ApiException e, String fallback) {
    const tip = ' API ঠিকানা: Profile → SMS filter & forward।';
    switch (e.code) {
      case 'connection_failed':
        return e.message;
      case 'network_refused':
        return 'সার্ভার চালু নেই বা পোর্ট বন্ধ — Node চালু আছে কিনা দেখুন।$tip';
      case 'network_dns':
        return 'সার্ভার ঠিকানা খুঁজে পাওয়া যায়নি।$tip';
      case 'network_routing':
        return 'নেটওয়ার্ক রুট নেই — কানেকশন পরীক্ষা করুন।$tip';
      case 'network':
        return 'ইন্টারনেট বা সার্ভার কানেকশন সমস্যা — আবার চেষ্টা করুন।$tip';
      case 'timeout':
        return 'সার্ভার রেসপন্স দেরি করছে — কিছুক্ষণ পর আবার চেষ্টা করুন';
      case 'bad_response':
        return 'সার্ভার থেকে সঠিক ডেটা পাওয়া যায়নি';
      default:
        return _friendlyServerMessage(e.message, fallback);
    }
  }

  String _bengaliForSend(int? status) => switch (status) {
        400 => 'অনুরোধ গ্রহণযোগ্য নয় — নম্বর বা তথ্য পরীক্ষা করুন',
        404 => 'এই নামে কোনো অ্যাকাউন্ট খুঁজে পাওয়া যায়নি!',
        409 => 'এই নম্বর/ইমেইলে ইতিমধ্যে একটি অ্যাকাউন্ট আছে',
        429 => '৬০ সেকেন্ড পরে আবার চেষ্টা করুন',
        500 => 'সার্ভারে সমস্যা হয়েছে। কিছুক্ষণ পর আবার চেষ্টা করুন',
        503 => 'SMS বা ইমেইল OTP সার্ভারে চালু নেই',
        _   => 'কিছু একটা সমস্যা হয়েছে',
      };

  String _bengaliForOtp(int? status) => switch (status) {
        400 => 'কোড ভুল বা অনুরোধ সঠিক নয় — আবার চেষ্টা করুন',
        404 => 'OTP পাওয়া যায়নি',
        409 => 'এই কোড আগেই ব্যবহার করা হয়েছে',
        410 => 'কোড মেয়াদ উত্তীর্ণ — নতুন কোড নিন',
        429 => '৬০ সেকেন্ড পরে আবার চেষ্টা করুন',
        500 => 'সার্ভারে সমস্যা হয়েছে। কিছুক্ষণ পর আবার চেষ্টা করুন',
        503 => 'SMS বা ইমেইল OTP সার্ভারে চালু নেই',
        _   => 'কিছু একটা সমস্যা হয়েছে',
      };
}
