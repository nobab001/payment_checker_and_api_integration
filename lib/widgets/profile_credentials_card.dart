import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/account_credentials.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../utils/bd_phone_utils.dart';
import '../utils/constants.dart';
import '../utils/gmail_input_utils.dart';
import 'custom_email_field.dart';
import 'custom_mobile_field.dart';
import 'custom_otp_field.dart';

/// Profile: list linked phones / Gmail with OTP add flow.
class ProfileCredentialsCard extends StatefulWidget {
  const ProfileCredentialsCard({super.key});

  @override
  State<ProfileCredentialsCard> createState() => _ProfileCredentialsCardState();
}

class _ProfileCredentialsCardState extends State<ProfileCredentialsCard> {
  AccountCredentials? _creds;
  bool _loading = true;
  String? _error;

  bool _addingPhone = false;
  bool _addingEmail = false;
  bool _phoneOtpSent = false;
  bool _emailOtpSent = false;
  bool _busy = false;
  int _cooldown = 0;
  Timer? _cooldownTimer;
  String? _formError;

  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final List<TextEditingController> _phoneOtpCtrl =
      List.generate(6, (_) => TextEditingController());
  final List<TextEditingController> _emailOtpCtrl =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _phoneOtpFocus = List.generate(6, (_) => FocusNode());
  final List<FocusNode> _emailOtpFocus = List.generate(6, (_) => FocusNode());

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    for (final c in _phoneOtpCtrl) {
      c.dispose();
    }
    for (final c in _emailOtpCtrl) {
      c.dispose();
    }
    for (final f in _phoneOtpFocus) {
      f.dispose();
    }
    for (final f in _emailOtpFocus) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final c = await ApiService.instance.fetchAccountCredentials();
      if (!mounted) return;
      setState(() {
        _creds = c;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ApiService.friendlyErrorMessage(e);
      });
    }
  }

  void _startCooldown([int sec = 60]) {
    _cooldownTimer?.cancel();
    setState(() => _cooldown = sec);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_cooldown <= 1) {
        t.cancel();
        setState(() => _cooldown = 0);
      } else {
        setState(() => _cooldown -= 1);
      }
    });
  }

  String _otpFrom(List<TextEditingController> ctrls) =>
      ctrls.map((c) => c.text).join();

  void _clearOtp(List<TextEditingController> ctrls) {
    for (final c in ctrls) {
      c.clear();
    }
  }

  void _cancelAddPhone() {
    setState(() {
      _addingPhone = false;
      _phoneOtpSent = false;
      _formError = null;
      _phoneCtrl.clear();
      _clearOtp(_phoneOtpCtrl);
    });
  }

  void _cancelAddEmail() {
    setState(() {
      _addingEmail = false;
      _emailOtpSent = false;
      _formError = null;
      _emailCtrl.clear();
      _clearOtp(_emailOtpCtrl);
    });
  }

  Future<void> _sendPhoneOtp() async {
    final err = BdPhoneUtils.validate(_phoneCtrl.text);
    if (err != null) {
      setState(() => _formError = err);
      return;
    }
    final contact = BdPhoneUtils.sanitize(_phoneCtrl.text);
    setState(() {
      _busy = true;
      _formError = null;
    });
    try {
      await ApiService.instance.sendCredentialLinkOtp(contact);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _phoneOtpSent = true;
      });
      _startCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('OTP পাঠানো হয়েছে')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _formError = ApiService.friendlyErrorMessage(e);
      });
    }
  }

  Future<void> _sendEmailOtp() async {
    final err = GmailInputUtils.validate(_emailCtrl.text);
    if (err != null) {
      setState(() => _formError = err);
      return;
    }
    final contact = CustomEmailField.readApiValue(_emailCtrl);
    setState(() {
      _busy = true;
      _formError = null;
    });
    try {
      await ApiService.instance.sendCredentialLinkOtp(contact);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _emailOtpSent = true;
      });
      _startCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('OTP পাঠানো হয়েছে')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _formError = ApiService.friendlyErrorMessage(e);
      });
    }
  }

  Future<void> _verifyPhone() async {
    final contact = BdPhoneUtils.sanitize(_phoneCtrl.text);
    final code = _otpFrom(_phoneOtpCtrl);
    if (code.length != 6) {
      setState(() => _formError = '৬ সংখ্যার OTP দিন');
      return;
    }
    setState(() {
      _busy = true;
      _formError = null;
    });
    try {
      final result = await ApiService.instance.verifyAndLinkCredential(
        contact: contact,
        code: code,
      );
      if (!mounted) return;
      if (result.user != null) {
        context.read<AuthProvider>().setUser(result.user!);
      }
      setState(() {
        _creds = result.credentials;
        _busy = false;
        _addingPhone = false;
        _phoneOtpSent = false;
      });
      _phoneCtrl.clear();
      _clearOtp(_phoneOtpCtrl);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('মোবাইল নম্বর যোগ হয়েছে')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _formError = ApiService.friendlyErrorMessage(e);
      });
    }
  }

  Future<void> _verifyEmail() async {
    final contact = CustomEmailField.readApiValue(_emailCtrl);
    final code = _otpFrom(_emailOtpCtrl);
    if (code.length != 6) {
      setState(() => _formError = '৬ সংখ্যার OTP দিন');
      return;
    }
    setState(() {
      _busy = true;
      _formError = null;
    });
    try {
      final result = await ApiService.instance.verifyAndLinkCredential(
        contact: contact,
        code: code,
      );
      if (!mounted) return;
      if (result.user != null) {
        context.read<AuthProvider>().setUser(result.user!);
      }
      setState(() {
        _creds = result.credentials;
        _busy = false;
        _addingEmail = false;
        _emailOtpSent = false;
      });
      _emailCtrl.clear();
      _clearOtp(_emailOtpCtrl);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('জিমেইল যোগ হয়েছে')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _formError = ApiService.friendlyErrorMessage(e);
      });
    }
  }

  Widget _sectionHeader({
    required String title,
    required IconData icon,
    required bool canAdd,
    required VoidCallback onAdd,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
          if (canAdd)
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              color: AppColors.primary,
              tooltip: 'যোগ করুন',
              onPressed: _busy ? null : onAdd,
            ),
        ],
      ),
    );
  }

  Widget _listedRow(String value, IconData icon) {
    return ListTile(
      dense: true,
      leading: Icon(icon, color: AppColors.primary, size: 20),
      title: Text(
        value,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _buildPhoneAddForm() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: CustomMobileField(
                  controller: _phoneCtrl,
                  enabled: !_phoneOtpSent && !_busy,
                  labelText: 'নতুন মোবাইল নম্বর',
                  decoration: InputDecoration(
                    labelText: 'নতুন মোবাইল নম্বর',
                    counterText: '',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: (_busy || _cooldown > 0) ? null : _sendPhoneOtp,
                child: Text(
                  _cooldown > 0
                      ? '$_cooldown'
                      : (_phoneOtpSent ? 'আবার পাঠান' : 'সেন্ড'),
                ),
              ),
            ],
          ),
          if (_phoneOtpSent) ...[
            const SizedBox(height: 12),
            const Text(
              'OTP কোড দিন',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            CustomOtpField(
              controllers: _phoneOtpCtrl,
              focusNodes: _phoneOtpFocus,
              enabled: !_busy,
              onAutoSubmit: (_) async {
                if (!_busy && mounted) await _verifyPhone();
              },
            ),
          ],
          TextButton(onPressed: _busy ? null : _cancelAddPhone, child: const Text('বাতিল')),
        ],
      ),
    );
  }

  Widget _buildEmailAddForm() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: CustomEmailField(
                  controller: _emailCtrl,
                  enabled: !_emailOtpSent && !_busy,
                  labelText: 'নতুন জিমেইল',
                  decoration: InputDecoration(
                    labelText: 'নতুন জিমেইল',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: (_busy || _cooldown > 0) ? null : _sendEmailOtp,
                child: Text(
                  _cooldown > 0
                      ? '$_cooldown'
                      : (_emailOtpSent ? 'আবার পাঠান' : 'সেন্ড'),
                ),
              ),
            ],
          ),
          if (_emailOtpSent) ...[
            const SizedBox(height: 12),
            const Text(
              'ইমেইলে পাঠানো OTP দিন',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            CustomOtpField(
              controllers: _emailOtpCtrl,
              focusNodes: _emailOtpFocus,
              enabled: !_busy,
              onAutoSubmit: (_) async {
                if (!_busy && mounted) await _verifyEmail();
              },
            ),
          ],
          TextButton(onPressed: _busy ? null : _cancelAddEmail, child: const Text('বাতিল')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_error != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(_error!, style: const TextStyle(color: Colors.red)),
              TextButton(onPressed: _load, child: const Text('আবার চেষ্টা')),
            ],
          ),
        ),
      );
    }

    final creds = _creds!;
    final canAddPhone = creds.phones.length < creds.maxPerType && !_addingPhone;
    final canAddEmail = creds.emails.length < creds.maxPerType && !_addingEmail;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeader(
            title: 'মোবাইল নম্বর',
            icon: Icons.phone_outlined,
            canAdd: canAddPhone,
            onAdd: () {
              _cancelAddEmail();
              setState(() {
                _addingPhone = true;
                _formError = null;
              });
            },
          ),
          if (creds.phones.isEmpty && !_addingPhone)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                'কোনো নম্বর নেই',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ),
          for (final p in creds.phones) _listedRow(p, Icons.phone_android_outlined),
          if (_addingPhone) _buildPhoneAddForm(),
          const Divider(height: 1),
          _sectionHeader(
            title: 'জিমেইল',
            icon: Icons.email_outlined,
            canAdd: canAddEmail,
            onAdd: () {
              _cancelAddPhone();
              setState(() {
                _addingEmail = true;
                _formError = null;
              });
            },
          ),
          if (creds.emails.isEmpty && !_addingEmail)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                'কোনো জিমেইল নেই',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ),
          for (final e in creds.emails) _listedRow(e, Icons.alternate_email),
          if (_addingEmail) _buildEmailAddForm(),
          if (_formError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                _formError!,
                style: TextStyle(color: Colors.red.shade700, fontSize: 13),
              ),
            ),
          if (creds.phones.length >= creds.maxPerType ||
              creds.emails.length >= creds.maxPerType)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                'প্রতি ধরনে সর্বোচ্চ ${creds.maxPerType}টি যোগ করা যায়',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ),
        ],
      ),
    );
  }
}
