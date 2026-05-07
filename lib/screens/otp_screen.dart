import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/otp_service.dart';
import '../utils/constants.dart';

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

  void _onDigitEntered(int index, String value) {
    if (value.length == 6) {
      for (int i = 0; i < 6; i++) {
        _ctrl[i].text = value[i];
      }
      _focus[5].requestFocus();
      _verify();
      return;
    }
    if (value.isNotEmpty && index < 5) {
      _focus[index + 1].requestFocus();
    }
    if (value.isEmpty && index > 0) {
      _focus[index - 1].requestFocus();
    }
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(6, (i) => _OtpBox(
                      controller: _ctrl[i],
                      focusNode: _focus[i],
                      onChanged: (v) => _onDigitEntered(i, v),
                    )),
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
            fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.primary),
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
              borderSide: const BorderSide(color: AppColors.primary, width: 2)),
        ),
        onChanged: onChanged,
      ),
    );
  }
}
