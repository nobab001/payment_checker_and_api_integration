import 'dart:async';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/auth_provider.dart';
import '../providers/remote_config_provider.dart';
import '../services/api_service.dart';
import '../services/otp_service.dart';
import '../utils/constants.dart';

const _bdPrefixes = ['013', '014', '015', '016', '017', '018', '019'];

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();

  final List<TextEditingController> _otpCtrl = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _otpFocus = List.generate(6, (_) => FocusNode());

  bool _showOtp = false;
  bool _isNewUser = false; // true when coming from "Create Account" flow
  bool _sendingOtp = false;
  bool _verifying = false;
  int _cooldown = 0;
  Timer? _timer;

  // Server-rate-limit cooldown: shown when backend returns 429 (Too Many Requests).
  // Disables the Verify button + shows a banner with countdown.
  int _serverCooldown = 0;
  Timer? _serverCooldownTimer;

  @override
  void dispose() {
    _emailCtrl.dispose();
    for (final c in _otpCtrl) {
      c.dispose();
    }
    for (final f in _otpFocus) {
      f.dispose();
    }
    _timer?.cancel();
    _serverCooldownTimer?.cancel();
    super.dispose();
  }

  /// Start the "Too Many Requests" countdown.
  /// [seconds] = how long to keep the Verify button disabled.
  void _startServerCooldown([int seconds = 10]) {
    _serverCooldownTimer?.cancel();
    setState(() => _serverCooldown = seconds);
    _serverCooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _serverCooldown--;
        if (_serverCooldown <= 0) t.cancel();
      });
    });
  }

  // ── Validation ────────────────────────────────────────────────────────────

  String? _validateContact(String? v) {
    if (v == null || v.trim().isEmpty) return 'এই ঘর পূরণ করুন';
    final s = v.trim();
    if (_isPhone(s)) {
      if (s.length != 11) return 'মোবাইল নম্বর অবশ্যই ১১ সংখ্যার হতে হবে';
      if (!_bdPrefixes.contains(s.substring(0, 3))) {
        return 'বাংলাদেশি অপারেটর কোড দিন (013–019)';
      }
      return null;
    }
    if (s.contains('@')) {
      if (!RegExp(r'^[^\s@]+@gmail\.com$', caseSensitive: false).hasMatch(s)) {
        return 'শুধু @gmail.com ঠিকানা গ্রহণযোগ্য';
      }
      return null;
    }
    return 'সঠিক মোবাইল নম্বর অথবা Gmail দিন';
  }

  bool _isPhone(String s) => RegExp(r'^\d+$').hasMatch(s);

  String get _contactForApi =>
      ApiService.normalizeContactForApi(_emailCtrl.text);

  String _connectivityMessage(ApiException e) {
    const tip = '\n\nটিপ: API ঠিকানা বদলাতে Profile → SMS filter & forward। USB তে adb reverse tcp:3000 tcp:3000';
    switch (e.code) {
      case 'connection_failed':
        return e.message;
      case 'network_refused':
        return 'সার্ভার চালু নেই বা পোর্ট বন্ধ — Node API চালু আছে কিনা দেখুন$tip';
      case 'network_dns':
        return 'সার্ভার ঠিকানা খুঁজে পাওয়া যায়নি — URL বা DNS পরীক্ষা করুন$tip';
      case 'network_routing':
        return 'নেটওয়ার্ক রুট নেই — কানেকশন বা VPN পরীক্ষা করুন$tip';
      case 'network':
        return 'ইন্টারনেট বা সার্ভার কানেকশন নেই — পরে আবার চেষ্টা করুন$tip';
      case 'timeout':
        return 'সার্ভার রেসপন্স দেরি করছে — কিছুক্ষণ পর আবার চেষ্টা করুন$tip';
      case 'bad_response':
        return 'সার্ভার থেকে সঠিক ডেটা পাওয়া যায়নি';
      default:
        final t = e.message.trim();
        if (t.isEmpty || t == 'Request failed' || t.length > 120) {
          return 'সার্ভারে সমস্যা — আবার চেষ্টা করুন';
        }
        return t;
    }
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  /// Called when user taps "যাচাই করুন" (Verify button).
  Future<void> _onVerify() async {
    if (!_formKey.currentState!.validate()) return;
    final input = _contactForApi;

    setState(() => _sendingOtp = true);

    if (!kIsWeb) {
      try {
        final results = await Connectivity().checkConnectivity();
        final online = results.any((r) => r != ConnectivityResult.none);
        if (!online) {
          if (!mounted) return;
          setState(() => _sendingOtp = false);
          _showSnackbar(
            'কোনো ইন্টারনেট কানেকশন নেই — Wi‑Fi বা মোবাইল ডেটা চালু করুন',
            Colors.red[700]!,
          );
          return;
        }
      } catch (_) {
        // If connectivity check fails, continue to HTTP health check.
      }
    }

    // 1. Check server reachability
    try {
      await ApiService.instance.ensureServerReachable();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _sendingOtp = false);
      _showSnackbar(_connectivityMessage(e), Colors.red[700]!);
      return;
    }

    // 2. Check whether account exists
    try {
      final exists = await ApiService.instance.checkContactExists(input);
      if (!mounted) return;
      setState(() => _sendingOtp = false);

      if (exists) {
        // Existing user → send OTP and show OTP boxes
        await _sendOtp();
      } else {
        // No account → show popup with Create / Cancel options
        _showAccountNotFoundDialog(input);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _sendingOtp = false);
      if (e.statusCode == 429) {
        _startServerCooldown(10);
      } else {
        _showSnackbar(_connectivityMessage(e), Colors.red[700]!);
      }
    } on Exception catch (_) {
      // Connection errors (SocketException, timeout, etc.) → show error message
      if (!mounted) return;
      setState(() => _sendingOtp = false);
      _showSnackbar('সংযোগ ব্যর্থ হয়েছে — আবার চেষ্টা করুন', Colors.red[700]!);
    }
  }

  /// Show popup: "Account not found" with Create / Cancel buttons.
  void _showAccountNotFoundDialog(String contact) {
    final isPhone = _isPhone(contact);
    final label = isPhone ? 'মোবাইল নম্বর' : 'জিমেইল';

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              Icons.person_search_outlined,
              color: Colors.orange.shade700,
              size: 26,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'অ্যাকাউন্ট পাওয়া যায়নি',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade700,
                  height: 1.5,
                ),
                children: [
                  TextSpan(text: '$label '),
                  TextSpan(
                    text: contact,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const TextSpan(text: ' দিয়ে কোনো অ্যাকাউন্ট নেই।'),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'নতুন অ্যাকাউন্ট তৈরি করতে নিচের বাটনে ক্লিক করুন।',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          // Cancel
          OutlinedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.grey.shade700,
              side: BorderSide(color: Colors.grey.shade300),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            child: const Text('বাতিল করুন'),
          ),
          const SizedBox(width: 8),
          // Create account
          ElevatedButton.icon(
            icon: const Icon(Icons.person_add_outlined, size: 18),
            label: const Text('নতুন অ্যাকাউন্ট তৈরি'),
            onPressed: () {
              Navigator.of(ctx).pop();
              _sendOtpNew();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  /// Send OTP to EXISTING user via /api/send-otp
  Future<void> _sendOtp() async {
    setState(() {
      _sendingOtp = true;
      _isNewUser = false;
    });
    final result = await OtpService.instance.sendOtp(_contactForApi);
    if (!mounted) return;
    if (result.success) {
      setState(() {
        _showOtp = true;
        _sendingOtp = false;
      });
      _startCooldown();
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) _otpFocus[0].requestFocus();
      });
    } else {
      setState(() => _sendingOtp = false);
      if (result.error == OtpError.rateLimited) {
        _startServerCooldown(10);
      } else {
        _showSnackbar(result.message ?? 'OTP পাঠানো যায়নি', Colors.red[700]!);
      }
    }
  }

  /// Create new account + send OTP via /api/send-otp-new
  Future<void> _sendOtpNew() async {
    setState(() {
      _sendingOtp = true;
      _isNewUser = true;
    });
    final result = await OtpService.instance.sendOtpNew(_contactForApi);
    if (!mounted) return;
    if (result.success) {
      setState(() {
        _showOtp = true;
        _sendingOtp = false;
      });
      _startCooldown();
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) _otpFocus[0].requestFocus();
      });
    } else {
      setState(() {
        _sendingOtp = false;
        _isNewUser = false;
      });
      // If the account already exists (race condition), switch to normal OTP flow
      if (result.error == OtpError.alreadyUsed) {
        _showSnackbar(
          'এই নম্বরে অ্যাকাউন্ট আছে — OTP পাঠানো হচ্ছে',
          Colors.blue.shade700,
        );
        await _sendOtp();
      } else if (result.error == OtpError.rateLimited) {
        _startServerCooldown(10);
      } else {
        _showSnackbar(result.message ?? 'OTP পাঠানো যায়নি', Colors.red[700]!);
      }
    }
  }

  /// Verify OTP code, log in (or route to signup for new users)
  Future<void> _onLoginWithOtp() async {
    final code = _otpCtrl.map((c) => c.text).join();
    if (code.length != 6) {
      _showSnackbar('৬ সংখ্যার কোড দিন', Colors.orange);
      return;
    }
    setState(() => _verifying = true);
    final input = _contactForApi;
    final result = await OtpService.instance.verifyOtp(input, code);
    if (!mounted) return;
    if (result.success && result.token != null) {
      final auth = context.read<AuthProvider>();
      // isNewUser from server (profile_complete = 0) means route to SignupScreen
      if (result.isNewUser) {
        auth.setPendingContact(input, _isPhone(input));
      }
      final ok = await auth.signInWithSession(result.token!, result.user);
      if (!ok && mounted && auth.error != null) {
        setState(() => _verifying = false);
        _showSnackbar(auth.error!, Colors.red[700]!);
      }
      // On success _AuthGate routes automatically
    } else {
      setState(() => _verifying = false);
      _showSnackbar(result.message ?? 'যাচাই ব্যর্থ হয়েছে', Colors.red[700]!);
      if (result.error == OtpError.expired ||
          result.error == OtpError.alreadyUsed) {
        _clearOtp();
      }
    }
  }

  void _clearOtp() {
    for (final c in _otpCtrl) {
      c.clear();
    }
    _otpFocus[0].requestFocus();
  }

  void _startCooldown() {
    _cooldown = 60;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _cooldown--;
        if (_cooldown <= 0) t.cancel();
      });
    });
  }

  void _onOtpDigit(int i, String val) {
    // ── 1. Full 6-digit paste into any box → distribute and auto-verify ──
    if (val.length == 6 && RegExp(r'^\d{6}$').hasMatch(val)) {
      for (int j = 0; j < 6; j++) {
        _otpCtrl[j].value = TextEditingValue(text: val[j]);
      }
      _onLoginWithOtp();
      return;
    }

    // Keep only the LAST typed digit (overwrite behavior).
    if (val.length > 1) {
      final keep = val.substring(val.length - 1);
      _otpCtrl[i].value = TextEditingValue(
        text: keep,
        selection: TextSelection.collapsed(offset: keep.length),
      );
      if (i < 5) _otpFocus[i + 1].requestFocus();
      return;
    }

    // ── 3. Single digit typed normally ──
    if (val.length == 1 && i < 5) {
      _otpFocus[i + 1].requestFocus();
    }
    // ── 4. Box was cleared (backspace on a filled box) → stay here, do nothing.
    //      Backspace on an EMPTY box is handled in _onOtpBackspace below.
  }

  /// Called when the user presses backspace AND the current box is already empty.
  /// Behaviour: move to the previous box AND clear its digit.
  void _onOtpBackspace(int i) {
    if (i <= 0) return;
    _otpCtrl[i - 1].clear();
    _otpFocus[i - 1].requestFocus();
  }

  void _showSnackbar(String msg, Color bg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  Future<void> _launch(String url) async {
    if (url.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('শীঘ্রই আসছে — আমাদের সাথেই থাকুন!'),
            backgroundColor: const Color(0xFF37474F),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            duration: const Duration(milliseconds: 750),
          ),
        );
      }
      return;
    }
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('লিংক খোলা যায়নি'),
            backgroundColor: const Color(0xFF37474F),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final rc = context.watch<RemoteConfigProvider>().config;
    final busy = _sendingOtp || _verifying || auth.loading;
    final appDisabled = !rc.appEnabled;
    final rateLimited = _serverCooldown > 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Maintenance banner ─────────────────────────────────
                  if (appDisabled) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.orange.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.construction,
                            color: Colors.orange.shade700,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'অ্যাপটি সাময়িকভাবে রক্ষণাবেক্ষণের জন্য বন্ধ আছে',
                              style: TextStyle(
                                color: Colors.orange.shade800,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // ── Logo / title ───────────────────────────────────────
                  const Icon(
                    Icons.account_balance_wallet,
                    size: 64,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    AppStrings.appName,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'SMS পেমেন্ট ট্র্যাকার',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 40),

                  // ── Contact input ──────────────────────────────────────
                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    enabled: !_showOtp,
                    onChanged: (_) {
                      if (_showOtp) {
                        setState(() {
                          _showOtp = false;
                          _isNewUser = false;
                          _clearOtp();
                        });
                      }
                    },
                    decoration: InputDecoration(
                      labelText: 'মোবাইল নম্বর অথবা Gmail এড্রেস',
                      labelStyle: const TextStyle(fontSize: 13),
                      prefixIcon: const Icon(Icons.person_outline),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      disabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: AppColors.primary,
                          width: 2,
                        ),
                      ),
                    ),
                    validator: _validateContact,
                  ),
                  const SizedBox(height: 16),

                  // ── OTP boxes (shown after OTP sent) ───────────────────
                  if (_showOtp) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: _isNewUser
                            ? Colors.green.shade50
                            : Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _isNewUser
                              ? Colors.green.shade200
                              : Colors.blue.shade200,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _isNewUser
                                ? Icons.person_add_outlined
                                : Icons.sms_outlined,
                            color: _isNewUser
                                ? Colors.green.shade700
                                : Colors.blue.shade700,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _isNewUser
                                  ? '${_emailCtrl.text.trim()}-এ নিশ্চিতকরণ কোড পাঠানো হয়েছে'
                                  : '${_emailCtrl.text.trim()}-এ ৬ সংখ্যার কোড পাঠানো হয়েছে',
                              style: TextStyle(
                                color: _isNewUser
                                    ? Colors.green.shade800
                                    : Colors.blue.shade800,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(
                        6,
                        (i) => _OtpBox(
                          controller: _otpCtrl[i],
                          focusNode: _otpFocus[i],
                          onChanged: (v) => _onOtpDigit(i, v),
                          onBackspaceOnEmpty: () => _onOtpBackspace(i),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: _cooldown > 0
                          ? Text(
                              '${_cooldown}s পরে আবার পাঠান',
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 12,
                              ),
                            )
                          : TextButton(
                              onPressed: busy
                                  ? null
                                  : (_isNewUser ? _sendOtpNew : _sendOtp),
                              child: const Text(
                                'কোড আবার পাঠান',
                                style: TextStyle(color: AppColors.primary),
                              ),
                            ),
                    ),
                    const SizedBox(height: 6),
                  ],

                  // ── Server rate-limit banner (Too Many Requests) ───────
                  if (rateLimited) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.amber.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.hourglass_top_rounded,
                            color: Colors.amber.shade800,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'অনেকবার চেষ্টা করা হয়েছে',
                                  style: TextStyle(
                                    color: Colors.amber.shade900,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  'অনুগ্রহ করে $_serverCooldown সেকেন্ড অপেক্ষা করুন',
                                  style: TextStyle(
                                    color: Colors.amber.shade800,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.amber.shade100,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.amber.shade400,
                                width: 2,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '$_serverCooldown',
                              style: TextStyle(
                                color: Colors.amber.shade900,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // ── Main action button ─────────────────────────────────
                  ElevatedButton(
                    onPressed: busy || appDisabled || rateLimited
                        ? null
                        : (_showOtp ? _onLoginWithOtp : _onVerify),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade400,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 2,
                    ),
                    child: busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            rateLimited
                                ? '$_serverCooldown সেকেন্ড অপেক্ষা করুন'
                                : (_showOtp
                                      ? (_isNewUser
                                            ? 'নিশ্চিত করুন'
                                            : 'লগইন করুন')
                                      : 'যাচাই করুন'),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                  const SizedBox(height: 44),

                  // ── Social row ─────────────────────────────────────────
                  Row(
                    children: [
                      Expanded(child: Divider(color: Colors.grey.shade300)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'আমাদের সাথে থাকুন',
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Expanded(child: Divider(color: Colors.grey.shade300)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _SocialBtn(
                        icon: FontAwesomeIcons.whatsapp,
                        color: const Color(0xFF25D366),
                        label: 'WhatsApp',
                        onTap: () => _launch(rc.whatsapp),
                      ),
                      _SocialBtn(
                        icon: FontAwesomeIcons.facebook,
                        color: const Color(0xFF1877F2),
                        label: 'Facebook',
                        onTap: () => _launch(rc.facebook),
                      ),
                      _SocialBtn(
                        icon: FontAwesomeIcons.telegram,
                        color: const Color(0xFF229ED9),
                        label: 'Telegram',
                        onTap: () => _launch(rc.telegram),
                      ),
                      _SocialBtn(
                        icon: FontAwesomeIcons.youtube,
                        color: const Color(0xFFFF0000),
                        label: 'YouTube',
                        onTap: () => _launch(rc.youtube),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── OTP single digit box ──────────────────────────────────────────────────────
//
// • Accepts only ONE digit per box (auto-truncates if user types more).
// • Auto-advances forward when a digit is entered.
// • Detects a 6-digit paste in any single box and fans it out (handled by parent).
// • Detects backspace on an already-empty box and notifies the parent so it can
//   clear the previous box and move focus back.

class _OtpBox extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onBackspaceOnEmpty;

  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onBackspaceOnEmpty,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 54,
      // Focus wraps the TextField so we can observe key events that the
      // TextField itself didn't consume (notably "backspace on empty box").
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.backspace &&
              controller.text.isEmpty) {
            onBackspaceOnEmpty();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: TextFormField(
          controller: controller,
          focusNode: focusNode,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          // maxLength: 6 lets us detect a full 6-digit paste; we truncate
          // anything else down to 1 char inside the parent's onChanged.
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
          decoration: InputDecoration(
            counterText: '',
            contentPadding: EdgeInsets.zero,
            filled: true,
            fillColor: Colors.grey.shade100,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.primary, width: 2),
            ),
          ),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// ── Helper end ────────────────────────────────────────────────────────────────

// ── Social link button ────────────────────────────────────────────────────────

class _SocialBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _SocialBtn({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color.withAlpha(20),
              shape: BoxShape.circle,
              border: Border.all(color: color.withAlpha(60)),
            ),
            child: Center(child: FaIcon(icon, color: color, size: 24)),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}
