import 'dart:async';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:android_id/android_id.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/auth_provider.dart';
import '../providers/device_approval_provider.dart';
import '../providers/remote_config_provider.dart';
import '../services/api_service.dart';
import '../services/otp_service.dart';
import '../utils/bd_phone_utils.dart';
import '../utils/constants.dart';
import '../utils/gmail_input_utils.dart';
import '../widgets/custom_login_contact_field.dart';
import '../widgets/custom_otp_field.dart';
import '../widgets/device_bound_dialog.dart';

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
    if (CustomLoginContactField.looksLikeEmail(v)) {
      return GmailInputUtils.validate(v);
    }
    return BdPhoneUtils.validate(v);
  }

  bool _isPhone(String s) =>
      !CustomLoginContactField.looksLikeEmail(s) && BdPhoneUtils.isValid(s);

  String get _contactForApi =>
      CustomLoginContactField.readApiValue(_emailCtrl);

  String _connectivityMessage(ApiException e) {
    // Server's own message for business errors (wrong OTP, account exists, etc.).
    // All transport / infra failures collapse to one professional line.
    switch (e.code) {
      case 'connection_failed':
      case 'network_refused':
      case 'network_dns':
      case 'network_routing':
      case 'network':
      case 'timeout':
        return 'Server unreachable';
      default:
        final t = e.message.trim();
        if (t.isEmpty || t == 'Request failed' || t.length > 200) {
          return 'Server unreachable';
        }
        return t;
    }
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<String?> _readHardwareDeviceId() async {
    if (kIsWeb) return null;
    try {
      return await const AndroidId().getId();
    } catch (_) {
      return null;
    }
  }

  /// Device lock before OTP — same policy as verify-otp, runs on "যাচাই করুন".
  Future<bool> _ensureDeviceAllowsLogin(String contact) async {
    final hwId = await _readHardwareDeviceId();
    if (hwId == null || hwId.isEmpty) return true;

    final check = await ApiService.instance.checkDeviceLoginEligibility(
      contact,
      deviceId: hwId,
    );
    if (check.allowed) return true;

    if (mounted) {
      _showDeviceBoundDialog(
        phones: check.boundPhones,
        emails: check.boundEmails,
      );
    }
    return false;
  }

  bool _isDeviceBoundMessage(String? message) {
    final m = message ?? '';
    return m.contains('ডিভাইসটি') ||
        m.contains('লিংক করা রয়েছে') ||
        m.contains('DEVICE_BOUND');
  }

  void _showDeviceBoundDialog({
    List<String> phones = const [],
    List<String> emails = const [],
  }) {
    if (!mounted) return;
    DeviceBoundDialog.show(
      context,
      phones: phones,
      emails: emails,
    );
  }

  void _showDeviceBoundMessage(String message) {
    final phones = <String>[];
    final emails = <String>[];
    final match = RegExp(r'\(([^)]+)\)').firstMatch(message);
    if (match != null) {
      for (final part in match.group(1)!.split(',')) {
        final s = part.trim();
        if (s.isEmpty) continue;
        if (s.contains('@')) {
          emails.add(s);
        } else {
          phones.add(s);
        }
      }
    }
    _showDeviceBoundDialog(phones: phones, emails: emails);
  }

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
          _showSnackbar('No internet connection', Colors.red[700]!);
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
      _showConnectivitySnack(e);
      return;
    }

    // 2. Device binding (before OTP is sent)
    try {
      if (!await _ensureDeviceAllowsLogin(input)) {
        if (!mounted) return;
        setState(() => _sendingOtp = false);
        return;
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _sendingOtp = false);
      _showConnectivitySnack(e);
      return;
    }

    // 3. Check whether account exists
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
        _showConnectivitySnack(e);
      }
    } on Exception catch (_) {
      // Connection errors (SocketException, timeout, etc.) → show error message
      if (!mounted) return;
      setState(() => _sendingOtp = false);
      _showSnackbar('Server unreachable', Colors.red[700]!);
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
    final hwId = await _readHardwareDeviceId();
    final result = await OtpService.instance.sendOtp(
      _contactForApi,
      deviceId: hwId,
    );
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
      } else if (_isDeviceBoundMessage(result.message)) {
        _showDeviceBoundMessage(result.message!);
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
    try {
      if (!await _ensureDeviceAllowsLogin(_contactForApi)) {
        if (!mounted) return;
        setState(() {
          _sendingOtp = false;
          _isNewUser = false;
        });
        return;
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _sendingOtp = false;
        _isNewUser = false;
      });
      _showConnectivitySnack(e);
      return;
    }
    final hwId = await _readHardwareDeviceId();
    final result = await OtpService.instance.sendOtpNew(
      _contactForApi,
      deviceId: hwId,
    );
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
      } else if (_isDeviceBoundMessage(result.message)) {
        _showDeviceBoundMessage(result.message!);
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
    String? hwId;
    String deviceModel = '';
    if (!kIsWeb) {
      try {
        hwId = await const AndroidId().getId();
        final android = await DeviceInfoPlugin().androidInfo;
        final brand = android.brand.trim();
        final model = android.model.trim();
        deviceModel = brand.isNotEmpty && model.isNotEmpty
            ? '$brand $model'
            : (model.isNotEmpty ? model : android.device.trim());
      } catch (_) {}
    }
    final result = await OtpService.instance.verifyOtp(
      input,
      code,
      deviceId: hwId,
      deviceModel: deviceModel.isNotEmpty ? deviceModel : null,
    );
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
      } else if (ok) {
        auth.setPendingDevicePinRequired(result.requiresSecurityPin);
        if (hwId != null && hwId.isNotEmpty && result.device != null) {
          if (!mounted) return;
          final devProv = context.read<DeviceApprovalProvider>();
          await devProv.ingestLoginDevice(
            hwId,
            result.device!,
          );
        }
        if (mounted) setState(() => _verifying = false);
      }
      // On success _AuthGate routes; device init runs in _HomeLoader
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

  void _showConnectivitySnack(ApiException e) {
    _showSnackbar(
      _connectivityMessage(e),
      Colors.red[700]!,
    );
  }

  void _showSnackbar(String msg, Color bg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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

  static const _hPad = 24.0;
  static const _alertToOtpGap = 18.0;
  /// OTP বক্স–লগইন বাটনের মাঝের ফাঁক; টাইমার মাঝখানে (আগের ফাঁক − ৭dp)।
  static const _otpToLoginBridgeHeight = 40.0;
  static const _loginToSocialGap = 20.0;

  InputDecoration get _contactDecoration => InputDecoration(
        labelText: 'মোবাইল নম্বর অথবা Gmail এড্রেস',
        labelStyle: const TextStyle(fontSize: 13),
        prefixIcon: const Icon(Icons.person_outline),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
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
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      );

  Widget _buildMaintenanceBanner() {
    return Container(
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
    );
  }

  Widget _buildHeader() {
    return Column(
      children: const [
        Icon(Icons.account_balance_wallet, size: 64, color: AppColors.primary),
        SizedBox(height: 12),
        Text(
          AppStrings.appName,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        ),
        SizedBox(height: 6),
        Text(
          'SMS পেমেন্ট ট্র্যাকার',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildOtpSentBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _isNewUser ? Colors.green.shade50 : Colors.blue.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _isNewUser ? Colors.green.shade200 : Colors.blue.shade200,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _isNewUser ? Icons.person_add_outlined : Icons.sms_outlined,
            color: _isNewUser ? Colors.green.shade700 : Colors.blue.shade700,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _isNewUser
                  ? '${_emailCtrl.text.trim()}-এ নিশ্চিতকরণ কোড পাঠানো হয়েছে'
                  : '${_emailCtrl.text.trim()}-এ ৬ সংখ্যার কোড পাঠানো হয়েছে',
              style: TextStyle(
                color: _isNewUser ? Colors.green.shade800 : Colors.blue.shade800,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOtpResendLine({required bool busy}) {
    if (_cooldown > 0) {
      return Text(
        '${_cooldown}s পরে আবার পাঠান',
        style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
      );
    }
    return TextButton(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      onPressed: busy ? null : (_isNewUser ? _sendOtpNew : _sendOtp),
      child: const Text(
        'কোড আবার পাঠান',
        style: TextStyle(color: AppColors.primary, fontSize: 13),
      ),
    );
  }

  Widget _buildOtpSection({required bool busy, required bool rateLimited}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildOtpSentBanner(),
        const SizedBox(height: _alertToOtpGap),
        CustomOtpField(
          controllers: _otpCtrl,
          focusNodes: _otpFocus,
          enabled: !busy && !rateLimited,
          onAutoSubmit: (_) async {
            if (!_verifying && mounted) await _onLoginWithOtp();
          },
        ),
      ],
    );
  }

  Widget _buildRateLimitBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Row(
        children: [
          Icon(Icons.hourglass_top_rounded, color: Colors.amber.shade800, size: 22),
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
                  style: TextStyle(color: Colors.amber.shade800, fontSize: 12),
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
              border: Border.all(color: Colors.amber.shade400, width: 2),
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
    );
  }

  Widget _buildLoginButton({
    required bool busy,
    required bool appDisabled,
    required bool rateLimited,
  }) {
    return ElevatedButton(
      onPressed: busy || appDisabled || rateLimited
          ? null
          : (_showOtp ? _onLoginWithOtp : _onVerify),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: Colors.grey.shade400,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                        ? (_isNewUser ? 'নিশ্চিত করুন' : 'লগইন করুন')
                        : 'যাচাই করুন'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
    );
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: _hPad),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Align(
                  alignment: const Alignment(0, -0.1),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (appDisabled) ...[
                          _buildMaintenanceBanner(),
                          const SizedBox(height: 16),
                        ],
                        _buildHeader(),
                        const SizedBox(height: 32),
                        CustomLoginContactField(
                          controller: _emailCtrl,
                          enabled: !_showOtp,
                          onContactChanged: () {
                            if (_showOtp) {
                              setState(() {
                                _showOtp = false;
                                _isNewUser = false;
                                _clearOtp();
                              });
                            }
                          },
                          decoration: _contactDecoration,
                          validator: _validateContact,
                        ),
                        if (_showOtp) ...[
                          const SizedBox(height: 16),
                          _buildOtpSection(
                            busy: busy,
                            rateLimited: rateLimited,
                          ),
                          SizedBox(
                            height: _otpToLoginBridgeHeight,
                            child: Center(
                              child: _buildOtpResendLine(busy: busy),
                            ),
                          ),
                        ],
                        if (rateLimited) ...[
                          SizedBox(height: _showOtp ? 12 : 10),
                          _buildRateLimitBanner(),
                        ],
                        if (!_showOtp) const SizedBox(height: 16),
                        _buildLoginButton(
                          busy: busy,
                          appDisabled: appDisabled,
                          rateLimited: rateLimited,
                        ),
                        const SizedBox(height: _loginToSocialGap),
                        _LoginSocialFooter(
                          onLaunch: _launch,
                          whatsapp: rc.whatsapp,
                          facebook: rc.facebook,
                          telegram: rc.telegram,
                          youtube: rc.youtube,
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Social links directly under the primary login / verify button.
class _LoginSocialFooter extends StatelessWidget {
  final void Function(String url) onLaunch;
  final String whatsapp;
  final String facebook;
  final String telegram;
  final String youtube;

  const _LoginSocialFooter({
    required this.onLaunch,
    required this.whatsapp,
    required this.facebook,
    required this.telegram,
    required this.youtube,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(child: Divider(color: Colors.grey.shade300)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'আমাদের সাথে থাকুন',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
              ),
            ),
            Expanded(child: Divider(color: Colors.grey.shade300)),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _SocialBtn(
              icon: FontAwesomeIcons.whatsapp,
              color: const Color(0xFF25D366),
              label: 'WhatsApp',
              onTap: () => onLaunch(whatsapp),
            ),
            _SocialBtn(
              icon: FontAwesomeIcons.facebook,
              color: const Color(0xFF1877F2),
              label: 'Facebook',
              onTap: () => onLaunch(facebook),
            ),
            _SocialBtn(
              icon: FontAwesomeIcons.telegram,
              color: const Color(0xFF229ED9),
              label: 'Telegram',
              onTap: () => onLaunch(telegram),
            ),
            _SocialBtn(
              icon: FontAwesomeIcons.youtube,
              color: const Color(0xFFFF0000),
              label: 'YouTube',
              onTap: () => onLaunch(youtube),
            ),
          ],
        ),
      ],
    );
  }
}

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
