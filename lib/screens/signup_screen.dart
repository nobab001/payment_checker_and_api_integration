import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../utils/constants.dart';

const _bdPrefixes = ['013', '014', '015', '016', '017', '018', '019'];

class SignupScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const SignupScreen({super.key, required this.onComplete});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey      = GlobalKey<FormState>();
  final _nameCtrl     = TextEditingController();
  final _pinCtrl      = TextEditingController();
  final _optionalCtrl = TextEditingController();
  bool _saving        = false;
  bool _pinVisible    = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pinCtrl.dispose();
    _optionalCtrl.dispose();
    super.dispose();
  }

  String? _validateName(String? v) {
    if (v == null || v.trim().isEmpty) return 'নাম দিন';
    if (v.trim().length < 2) return 'কমপক্ষে ২ অক্ষর দিন';
    return null;
  }

  String? _validatePin(String? v) {
    if (v == null || v.trim().isEmpty) return 'পিন দিন';
    if (v.length != 4 && v.length != 6) return 'পিন অবশ্যই ৪ বা ৬ ডিজিটের হতে হবে';
    return null;
  }

  String? _validatePhone(String? v) {
    if (v == null || v.trim().isEmpty) return 'মোবাইল নম্বর দিন';
    final s = v.trim();
    if (s.length != 11) return 'মোবাইল নম্বর অবশ্যই ১১ সংখ্যার হতে হবে';
    if (!_bdPrefixes.contains(s.substring(0, 3))) {
      return 'বাংলাদেশি অপারেটর কোড দিন (013–019)';
    }
    return null;
  }

  String? _validateEmail(String? v) {
    if (v == null || v.trim().isEmpty) return null; // optional
    final s = v.trim();
    if (!RegExp(r'^[^\s@]+@gmail\.com$', caseSensitive: false).hasMatch(s)) {
      return 'শুধু @gmail.com ঠিকানা গ্রহণযোগ্য';
    }
    return null;
  }

  Future<void> _submit(bool isPhone, String contact) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final name = _nameCtrl.text.trim();
    final pin  = _pinCtrl.text.trim();
    final opt  = _optionalCtrl.text.trim();

    final String phone;
    final String email;
    if (isPhone) {
      phone = ApiService.normalizeContactForApi(contact);
      email = opt.isEmpty ? '' : ApiService.normalizeContactForApi(opt);
    } else {
      email = ApiService.normalizeContactForApi(contact);
      phone = opt.isEmpty ? '' : ApiService.normalizeContactForApi(opt);
    }

    try {
      final updated = await ApiService.instance.completeProfile(
        name: name,
        pin: pin,
        phone: phone,
        email: email,
      );
      if (!mounted) return;
      context.read<AuthProvider>().setUser(updated);
      context.read<AuthProvider>().clearPendingContact();
      widget.onComplete();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('সংরক্ষণ ব্যর্থ হয়েছে — আবার চেষ্টা করুন'),
        backgroundColor: Colors.red[700],
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth      = context.watch<AuthProvider>();
    final contact   = auth.pendingContact ?? '';
    final isPhone   = auth.pendingIsPhone;
    final typeLabel = isPhone ? 'মোবাইল নম্বর' : 'জিমেইল';

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
                  const Icon(Icons.account_circle_outlined,
                      size: 64, color: AppColors.primary),
                  const SizedBox(height: 12),
                  const Text(
                    'নতুন অ্যাকাউন্ট',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$typeLabel: $contact',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                  const SizedBox(height: 32),

                  // ── Name ──────────────────────────────────────────────────
                  _buildField(
                    controller: _nameCtrl,
                    label: 'আপনার নাম',
                    icon: Icons.person_outline,
                    validator: _validateName,
                  ),
                  const SizedBox(height: 14),

                  // ── PIN ───────────────────────────────────────────────────
                  TextFormField(
                    controller: _pinCtrl,
                    obscureText: !_pinVisible,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: 'একটি ৪ বা ৬ ডিজিটের পিন',
                      labelStyle: const TextStyle(fontSize: 13),
                      prefixIcon: const Icon(Icons.lock_outline),
                      counterText: '',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                            color: AppColors.primary, width: 2),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(_pinVisible
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined),
                        onPressed: () =>
                            setState(() => _pinVisible = !_pinVisible),
                      ),
                    ),
                    validator: _validatePin,
                  ),
                  const SizedBox(height: 14),

                  // ── Optional / Required contact ───────────────────────────
                  if (isPhone) ...[
                    _buildField(
                      controller: _optionalCtrl,
                      label: 'আপনার জিমেইল এড্রেস (ঐচ্ছিক)',
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                      validator: _validateEmail,
                    ),
                  ] else ...[
                    _buildField(
                      controller: _optionalCtrl,
                      label: 'আপনার মোবাইল নাম্বার',
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: _validatePhone,
                    ),
                  ],
                  const SizedBox(height: 28),

                  // ── Submit ────────────────────────────────────────────────
                  ElevatedButton(
                    onPressed: _saving ? null : () => _submit(isPhone, contact),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      elevation: 2,
                    ),
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Text(
                            'অ্যাকাউন্ট তৈরি করুন',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 13),
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
      validator: validator,
    );
  }
}
