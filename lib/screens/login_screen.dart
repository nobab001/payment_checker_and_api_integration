import 'dart:async';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
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
  final _formKey   = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();

  final List<TextEditingController> _otpCtrl =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFocus =
      List.generate(6, (_) => FocusNode());

  bool _showOtp    = false;
  bool _sendingOtp = false;
  bool _verifying  = false;
  int  _cooldown   = 0;
  Timer? _timer;

  @override
  void dispose() {
    _emailCtrl.dispose();
    for (final c in _otpCtrl) { c.dispose(); }
    for (final f in _otpFocus) { f.dispose(); }
    _timer?.cancel();
    super.dispose();
  }

  // ── validation ───────────────────────────────────────────────────────────

  String? _validateEmail(String? v) {
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
      if (!s.contains('@gmail.com')) return 'শুধু @gmail.com ঠিকানা গ্রহণযোগ্য';
      return null;
    }
    return 'সঠিক মোবাইল নম্বর অথবা Gmail দিন';
  }

  bool _isPhone(String s) => RegExp(r'^\d+$').hasMatch(s);

  // ── actions ──────────────────────────────────────────────────────────────

  Future<void> _onVerify() async {
    if (!_formKey.currentState!.validate()) return;
    final input = _emailCtrl.text.trim();
    final isPhone = _isPhone(input);

    debugPrint('[LoginScreen] _onVerify input="$input" isPhone=$isPhone');

    // Check user existence
    setState(() => _sendingOtp = true);
    final exists = await ApiService.instance.checkContactExists(input);
    if (!mounted) return;
    setState(() => _sendingOtp = false);

    if (exists) {
      // Old user - send OTP directly
      await _sendOtp(isNewUser: false);
    } else {
      // New user - show dialog
      await _showNewUserDialog(input, isPhone);
    }
  }

  Future<void> _showNewUserDialog(String input, bool isPhone) async {
    final typeText = isPhone ? 'নম্বরে' : 'জিমেইলে';
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'অ্যাকাউন্ট পাওয়া যায়নি',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'আপনার এই $typeText কোনো অ্যাকাউন্ট নেই। পেমেন্ট চেকারের সাথে যুক্ত হতে এই $typeText একটি ওটিপি (OTP) পাঠানো হবে। আপনি কি নতুন অ্যাকাউন্ট তৈরি করতে চান?',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'নাম্বারটি পরিবর্তন করব',
              style: TextStyle(color: Colors.grey),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('নতুন একাউন্ট করব'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _sendOtp(isNewUser: true);
    }
  }

  Future<void> _sendOtp({bool isNewUser = false}) async {
    setState(() => _sendingOtp = true);
    final result = await OtpService.instance.sendOtp(_emailCtrl.text.trim());
    if (!mounted) return;
    if (result.success) {
      setState(() {
        _showOtp    = true;
        _sendingOtp = false;
      });
      _startCooldown();
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) _otpFocus[0].requestFocus();
      });
    } else {
      setState(() => _sendingOtp = false);
      _showSnackbar(result.message ?? 'OTP পাঠানো যায়নি', Colors.red[700]!);
    }
  }

  Future<void> _onLoginWithOtp() async {
    final code = _otpCtrl.map((c) => c.text).join();
    if (code.length != 6) {
      _showSnackbar('৬ সংখ্যার কোড দিন', Colors.orange);
      return;
    }
    setState(() => _verifying = true);
    final input = _emailCtrl.text.trim();
    final result = await OtpService.instance.verifyOtp(input, code);
    if (!mounted) return;
    if (result.success && result.token != null) {
      final auth = context.read<AuthProvider>();
      if (result.isNewUser) {
        auth.setPendingContact(input, _isPhone(input));
      }
      final ok = await auth.signInWithSession(result.token!, result.user);
      if (!ok && mounted && auth.error != null) {
        setState(() => _verifying = false);
        _showSnackbar(auth.error!, Colors.red[700]!);
      }
      // On success: _AuthGate routes to _HomeLoader which handles new/existing user
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
    for (final c in _otpCtrl) { c.clear(); }
    _otpFocus[0].requestFocus();
  }

  void _startCooldown() {
    _cooldown = 60;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        _cooldown--;
        if (_cooldown <= 0) t.cancel();
      });
    });
  }

  void _onOtpDigit(int i, String val) {
    if (val.length == 6) {
      for (int j = 0; j < 6; j++) { _otpCtrl[j].text = val[j]; }
      _otpFocus[5].requestFocus();
      _onLoginWithOtp();
      return;
    }
    if (val.isNotEmpty && i < 5) _otpFocus[i + 1].requestFocus();
    if (val.isEmpty && i > 0)    _otpFocus[i - 1].requestFocus();
  }

  void _showSnackbar(String msg, Color bg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: bg));
  }

  Future<void> _launch(String url) async {
    if (url.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('শীঘ্রই আসছে — আমাদের সাথেই থাকুন!'),
          backgroundColor: const Color(0xFF37474F),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          duration: const Duration(milliseconds: 750),
        ));
      }
      return;
    }
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('শীঘ্রই আসছে — আমাদের সাথেই থাকুন!'),
          backgroundColor: const Color(0xFF37474F),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          duration: const Duration(milliseconds: 750),
        ));
      }
    }
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final rc   = context.watch<RemoteConfigProvider>().config;
    final busy = _sendingOtp || _verifying || auth.loading;
    final appDisabled = !rc.appEnabled;

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
                  if (appDisabled) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.orange.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.construction, color: Colors.orange.shade700, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'অ্যাপটি সাময়িকভাবে রক্ষণাবেক্ষণের জন্য বন্ধ আছে',
                              style: TextStyle(color: Colors.orange.shade800, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  const Icon(Icons.account_balance_wallet,
                      size: 64, color: AppColors.primary),
                  const SizedBox(height: 12),
                  const Text(
                    AppStrings.appName,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'SMS পেমেন্ট ট্র্যাকার',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 40),

                  // ── email field ────────────────────────────────────────
                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    enabled: !_showOtp,
                    onChanged: (_) {
                      if (_showOtp) {
                        setState(() {
                          _showOtp = false;
                          _clearOtp();
                        });
                      }
                    },
                    decoration: InputDecoration(
                      labelText: 'আপনার মোবাইল নম্বর অথবা জিমেইল এড্রেস দিন',
                      labelStyle: const TextStyle(fontSize: 13),
                      prefixIcon: const Icon(Icons.person_outline),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
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
                            color: AppColors.primary, width: 2),
                      ),
                    ),
                    validator: _validateEmail,
                  ),
                  const SizedBox(height: 16),

                  // ── OTP boxes ──────────────────────────────────────────
                  if (_showOtp) ...[
                    Text(
                      '${_emailCtrl.text.trim()}-এ ৬ সংখ্যার কোড পাঠানো হয়েছে (SMS বা ইমেইল)',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.grey.shade600, fontSize: 12),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(6, (i) => _OtpBox(
                        controller: _otpCtrl[i],
                        focusNode: _otpFocus[i],
                        onChanged: (v) => _onOtpDigit(i, v),
                      )),
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: _cooldown > 0
                          ? Text(
                              '${_cooldown}s পরে আবার পাঠান',
                              style: TextStyle(
                                  color: Colors.grey.shade500, fontSize: 12),
                            )
                          : TextButton(
                              onPressed: busy ? null : _sendOtp,
                              child: const Text('কোড আবার পাঠান',
                                  style:
                                      TextStyle(color: AppColors.primary)),
                            ),
                    ),
                    const SizedBox(height: 6),
                  ],

                  // ── main button ────────────────────────────────────────
                  ElevatedButton(
                    onPressed: busy || appDisabled
                        ? null
                        : (_showOtp ? _onLoginWithOtp : _onVerify),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      elevation: 2,
                    ),
                    child: busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : Text(
                            _showOtp ? 'লগিন করুন' : 'যাচাই করুন',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),
                  const SizedBox(height: 44),

                  // ── social row ─────────────────────────────────────────
                  Row(
                    children: [
                      Expanded(child: Divider(color: Colors.grey.shade300)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('আমাদের সাথে থাকুন',
                            style: TextStyle(
                                color: Colors.grey.shade500, fontSize: 12)),
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

// ── OTP single box ────────────────────────────────────────────────────────────

class _OtpBox extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 54,
      child: TextFormField(
        controller: controller,
        focusNode: focusNode,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 6,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppColors.primary),
        decoration: InputDecoration(
          counterText: '',
          contentPadding: EdgeInsets.zero,
          filled: true,
          fillColor: Colors.grey.shade100,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  const BorderSide(color: AppColors.primary, width: 2)),
        ),
        onChanged: onChanged,
      ),
    );
  }
}

// ── Social button ─────────────────────────────────────────────────────────────

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
          Text(label,
              style:
                  TextStyle(fontSize: 10, color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}
