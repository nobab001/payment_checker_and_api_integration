import 'dart:async';
import 'package:flutter/material.dart';
import '../services/otp_service.dart';
import '../utils/constants.dart';
import '../widgets/custom_otp_field.dart';

class OtpScreen extends StatefulWidget {
  /// Phone (11-digit) or @gmail.com — same as `/api/send-otp` body field `phone`.
  final String contact;
  final VoidCallback onVerified;

  const OtpScreen({super.key, required this.contact, required this.onVerified});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final List<TextEditingController> _ctrl =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focus = List.generate(6, (_) => FocusNode());

  bool _sending = false;
  bool _verifying = false;
  bool _sent = false;
  int _resendCooldown = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _send();
  }

  @override
  void dispose() {
    for (final c in _ctrl) { c.dispose(); }
    for (final f in _focus) { f.dispose(); }
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending || _resendCooldown > 0) return;
    setState(() => _sending = true);
    final result = await OtpService.instance.sendOtp(widget.contact);
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (result.success) {
        _sent = true;
        _startCooldown();
      }
    });
    if (!result.success) {
      _showError(result.message ?? 'OTP পাঠানো যায়নি');
    }
  }

  void _startCooldown() {
    _resendCooldown = 60;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        _resendCooldown--;
        if (_resendCooldown <= 0) t.cancel();
      });
    });
  }

  Future<void> _verify() async {
    final code = _ctrl.map((c) => c.text).join();
    if (code.length != 6) {
      _showError('৬ সংখ্যার কোড দিন');
      return;
    }
    setState(() => _verifying = true);
    final result = await OtpService.instance.verifyOtp(widget.contact, code);
    if (!mounted) return;
    setState(() => _verifying = false);
    if (result.success) {
      widget.onVerified();
    } else {
      _showError(result.message ?? 'যাচাই ব্যর্থ হয়েছে');
      if (result.error == OtpError.expired || result.error == OtpError.alreadyUsed) {
        _clearBoxes();
      }
    }
  }

  void _clearBoxes() {
    for (final c in _ctrl) { c.clear(); }
    _focus[0].requestFocus();
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red[700]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: const BackButton(color: AppColors.primary),
        title: const Text('কোড যাচাই',
            style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  widget.contact.contains('@')
                      ? Icons.mark_email_read_outlined
                      : Icons.sms_outlined,
                  size: 64,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 16),
                const Text(
                  'OTP কোড পাঠানো হয়েছে',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary),
                ),
                const SizedBox(height: 8),
                Text(
                  '${widget.contact}-এ ৬ সংখ্যার কোড পাঠানো হয়েছে',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
                const SizedBox(height: 36),
                if (_sending && !_sent)
                  const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                else ...[
                  CustomOtpField(
                    controllers: _ctrl,
                    focusNodes: _focus,
                    enabled: !_verifying,
                    onAutoSubmit: (_) async {
                      if (!_verifying && mounted) await _verify();
                    },
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: _verifying ? null : _verify,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _verifying
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Text('যাচাই করুন',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: _resendCooldown > 0
                        ? Text(
                            '${_resendCooldown}s পরে আবার পাঠান',
                            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                          )
                        : TextButton(
                            onPressed: _sending ? null : _send,
                            child: const Text('কোড আবার পাঠান',
                                style: TextStyle(color: AppColors.primary)),
                          ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
