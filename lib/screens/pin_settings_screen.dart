import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../utils/constants.dart';
import '../utils/pin_validation.dart';
import '../widgets/custom_login_contact_field.dart';
import '../widgets/custom_otp_field.dart';

/// Change or reset account security PIN (works on any logged-in device).
class PinSettingsScreen extends StatefulWidget {
  const PinSettingsScreen({super.key});

  @override
  State<PinSettingsScreen> createState() => _PinSettingsScreenState();
}

class _PinSettingsScreenState extends State<PinSettingsScreen> {
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _submitting = false;
  String? _error;

  bool _forgotMode = false;
  List<Map<String, dynamic>> _contacts = [];
  String? _selectedContact;
  bool _loadingContacts = false;
  bool _otpSent = false;
  int _cooldown = 0;
  Timer? _cooldownTimer;
  final List<TextEditingController> _otpCtrl =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFocus = List.generate(6, (_) => FocusNode());
  final _manualContactCtrl = TextEditingController();
  bool _useManualContact = false;

  @override
  void initState() {
    super.initState();
    void refresh() {
      if (mounted) setState(() {});
    }
    _currentCtrl.addListener(refresh);
    _newCtrl.addListener(refresh);
    _confirmCtrl.addListener(refresh);
  }

  bool get _canSubmitChangePin {
    final newP = _newCtrl.text.trim();
    final confirm = _confirmCtrl.text.trim();
    if (!canSubmitSecurityPin(newP) || !canSubmitSecurityPin(confirm)) {
      return false;
    }
    if (newP != confirm) return false;
    if (_pinConfigured && !canSubmitSecurityPin(_currentCtrl.text.trim())) {
      return false;
    }
    return true;
  }

  bool get _canSubmitForgotReset {
    if (_otpCode.length != 6) return false;
    final newP = _newCtrl.text.trim();
    final confirm = _confirmCtrl.text.trim();
    return canSubmitSecurityPin(newP) &&
        canSubmitSecurityPin(confirm) &&
        newP == confirm;
  }

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    _cooldownTimer?.cancel();
    for (final c in _otpCtrl) {
      c.dispose();
    }
    for (final f in _otpFocus) {
      f.dispose();
    }
    _manualContactCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _mergeContacts(
    List<Map<String, dynamic>> api,
    UserModel? user,
  ) {
    final seen = <String>{};
    final out = <Map<String, dynamic>>[];
    void add(String type, String? value) {
      final v = ApiService.normalizeContactForApi(value ?? '');
      if (v.isEmpty || seen.contains(v)) return;
      seen.add(v);
      out.add({'type': type, 'value': v});
    }

    for (final c in api) {
      add(c['type'] as String? ?? 'phone', c['value'] as String?);
    }
    if (user != null) {
      if (user.phone.isNotEmpty) add('phone', user.phone);
      if (user.email.isNotEmpty) add('email', user.email);
    }
    return out;
  }

  bool get _pinConfigured =>
      context.read<AuthProvider>().user?.pinConfigured == true;

  void _startCooldown([int sec = 60]) {
    _cooldownTimer?.cancel();
    setState(() => _cooldown = sec);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
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

  Future<void> _loadContacts() async {
    setState(() {
      _loadingContacts = true;
      _error = null;
    });
    try {
      final user = context.read<AuthProvider>().user;
      final list = await ApiService.instance.fetchPinContacts();
      final merged = _mergeContacts(list, user);
      if (!mounted) return;
      setState(() {
        _contacts = merged;
        _useManualContact = merged.isEmpty;
        if (merged.isNotEmpty) {
          _selectedContact = merged.first['value'] as String?;
        }
        _loadingContacts = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingContacts = false;
        _error = ApiService.friendlyErrorMessage(e);
      });
    }
  }

  void _enterForgotMode() {
    setState(() {
      _forgotMode = true;
      _otpSent = false;
      _error = null;
    });
    _loadContacts();
  }

  void _exitForgotMode() {
    setState(() {
      _forgotMode = false;
      _otpSent = false;
      _error = null;
    });
    for (final c in _otpCtrl) {
      c.clear();
    }
  }

  String get _otpCode => _otpCtrl.map((c) => c.text).join();

  Future<void> _changePin() async {
    final current = _currentCtrl.text.trim();
    final newPin = _newCtrl.text.trim();
    final confirm = _confirmCtrl.text.trim();

    final pinErr = validateSecurityPin(newPin);
    if (pinErr != null) {
      setState(() => _error = pinErr);
      return;
    }
    if (newPin != confirm) {
      setState(() => _error = 'নতুন পিন মিলছে না');
      return;
    }
    if (_pinConfigured) {
      final curErr = validateSecurityPin(current);
      if (curErr != null) {
        setState(() => _error = curErr);
        return;
      }
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final user = await ApiService.instance.changePin(
        currentPin: _pinConfigured ? current : null,
        newPin: newPin,
      );
      await ApiService.instance.verifyDevicePin(newPin);
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      auth.setUser(user);
      await auth.markDevicePinVerified();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('পিন সফলভাবে পরিবর্তন হয়েছে')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = ApiService.friendlyErrorMessage(e);
      });
    }
  }

  String? get _activeContact {
    if (_useManualContact) {
      return CustomLoginContactField.readApiValue(_manualContactCtrl);
    }
    return _selectedContact;
  }

  Future<void> _sendForgotOtp() async {
    final contact = _activeContact;
    if (contact == null || contact.isEmpty) {
      setState(() => _error = 'ফোন বা Gmail দিন (যেটা দিয়ে লগইন করেন)');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ApiService.instance.sendForgotPinOtp(contact);
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _otpSent = true;
      });
      _startCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('OTP পাঠানো হয়েছে')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = ApiService.friendlyErrorMessage(e);
      });
    }
  }

  Future<void> _resetPinWithOtp() async {
    final contact = _activeContact;
    final code = _otpCode;
    final newPin = _newCtrl.text.trim();
    final confirm = _confirmCtrl.text.trim();

    if (code.length != 6) {
      setState(() => _error = '৬ সংখ্যার OTP দিন');
      return;
    }
    final pinErr = validateSecurityPin(newPin);
    if (pinErr != null) {
      setState(() => _error = pinErr);
      return;
    }
    if (newPin != confirm) {
      setState(() => _error = 'নতুন পিন মিলছে না');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final user = await ApiService.instance.resetPinWithOtp(
        contact: contact!,
        code: code,
        newPin: newPin,
      );
      await ApiService.instance.verifyDevicePin(newPin);
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      auth.setUser(user);
      await auth.markDevicePinVerified();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('নতুন পিন সেট হয়েছে')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = ApiService.friendlyErrorMessage(e);
      });
    }
  }

  Widget _pinField({
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required VoidCallback toggle,
  }) {
    final hint = securityPinLengthHint(controller.text);
    final tooLong = securityPinDigitCount(controller.text) > 6;
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: TextInputType.number,
      maxLength: 7,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        helperText: hint,
        helperStyle: TextStyle(
          color: tooLong ? Colors.red : Colors.green.shade700,
          fontSize: 12,
        ),
        counterText: '',
        suffixIcon: IconButton(
          icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
          onPressed: toggle,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _buildChangePin() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _pinConfigured
              ? 'বর্তমান পিন দিয়ে নতুন পিন সেট করুন।'
              : 'এখনও পিন সেট নেই — নতুন পিন দিন।',
          style: TextStyle(fontSize: 14, height: 1.4, color: Colors.grey.shade800),
        ),
        const SizedBox(height: 20),
        if (_pinConfigured) ...[
          _pinField(
            controller: _currentCtrl,
            label: 'বর্তমান পিন',
            obscure: _obscureCurrent,
            toggle: () => setState(() => _obscureCurrent = !_obscureCurrent),
          ),
          const SizedBox(height: 12),
        ],
        _pinField(
          controller: _newCtrl,
          label: 'নতুন পিন',
          obscure: _obscureNew,
          toggle: () => setState(() => _obscureNew = !_obscureNew),
        ),
        const SizedBox(height: 12),
        _pinField(
          controller: _confirmCtrl,
          label: 'নতুন পিন আবার',
          obscure: _obscureConfirm,
          toggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: (_submitting || !_canSubmitChangePin) ? null : _changePin,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: _submitting
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('পিন পরিবর্তন করুন'),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: _enterForgotMode,
          child: const Text('পিন ভুলে গেছেন? OTP দিয়ে রিসেট করুন'),
        ),
      ],
    );
  }

  Widget _otpBoxes() {
    return CustomOtpField(
      controllers: _otpCtrl,
      focusNodes: _otpFocus,
      enabled: !_submitting,
      onChanged: (index, value) => setState(() {}),
    );
  }

  Widget _buildForgotPin() {
    if (_loadingContacts) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _contacts.isEmpty
              ? 'পুরনো অ্যাকাউন্ট: যে মোবাইল বা Gmail দিয়ে লগইন করেন সেটি লিখুন। OTP যাবে সেখানেই।'
              : 'লিংক করা নাম্বার বা Gmail-এ OTP পাঠানো হবে।',
          style: const TextStyle(fontSize: 14, height: 1.4),
        ),
        const SizedBox(height: 16),
        if (_contacts.isEmpty)
          CustomLoginContactField(
            controller: _manualContactCtrl,
            decoration: const InputDecoration(
              labelText: 'মোবাইল (01…) বা Gmail',
              border: OutlineInputBorder(),
            ),
          )
        else
          RadioGroup<String>(
            groupValue: _selectedContact,
            onChanged: (val) => setState(() => _selectedContact = val),
            child: Column(
              children: _contacts.map((c) {
                final v = c['value'] as String? ?? '';
                final type = c['type'] == 'email' ? 'Gmail' : 'মোবাইল';
                return RadioListTile<String>(
                  title: Text('$type: $v'),
                  value: v,
                );
              }).toList(),
            ),
          ),
        const SizedBox(height: 16),
        if (!_otpSent) ...[
          FilledButton(
            onPressed: (_submitting || _cooldown > 0) ? null : _sendForgotOtp,
            child: Text(_cooldown > 0 ? 'আবার পাঠান ($_cooldown)' : 'OTP পাঠান'),
          ),
        ] else ...[
          const Text('৬ সংখ্যার OTP', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          _otpBoxes(),
          const SizedBox(height: 16),
          _pinField(
            controller: _newCtrl,
            label: 'নতুন পিন',
            obscure: _obscureNew,
            toggle: () => setState(() => _obscureNew = !_obscureNew),
          ),
          const SizedBox(height: 12),
          _pinField(
            controller: _confirmCtrl,
            label: 'নতুন পিন আবার',
            obscure: _obscureConfirm,
            toggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: (_submitting || _cooldown > 0) ? null : _sendForgotOtp,
            child: Text(_cooldown > 0 ? 'পুনরায় পাঠান ($_cooldown)' : 'OTP আবার পাঠান'),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
        ],
        if (_otpSent) ...[
          const SizedBox(height: 16),
          FilledButton(
            onPressed: (_submitting || !_canSubmitForgotReset) ? null : _resetPinWithOtp,
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: _submitting
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('নতুন পিন সেট করুন'),
          ),
        ],
        const SizedBox(height: 8),
        TextButton(
          onPressed: _exitForgotMode,
          child: const Text('পিন জানা আছে? পরিবর্তন করুন'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('নিরাপত্তা পিন'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: _forgotMode ? _buildForgotPin() : _buildChangePin(),
        ),
      ),
    );
  }
}
