import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/device_approval_provider.dart';
import '../services/api_service.dart';
import '../utils/constants.dart';
import '../utils/pin_validation.dart';
import '../screens/pin_settings_screen.dart';
import '../screens/splash_screen.dart';

/// Blocks the main app until the account security PIN is verified on non-parent devices.
class DeviceSecurityPinGate extends StatefulWidget {
  final Widget child;

  const DeviceSecurityPinGate({super.key, required this.child});

  @override
  State<DeviceSecurityPinGate> createState() => _DeviceSecurityPinGateState();
}

class _DeviceSecurityPinGateState extends State<DeviceSecurityPinGate> {
  bool? _needsPin;
  bool _checking = true;
  final _pinCtrl = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _pinCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    _evaluate();
  }

  bool get _canSubmitPin => canSubmitSecurityPin(_pinCtrl.text);

  @override
  void dispose() {
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _evaluate() async {
    final auth = context.read<AuthProvider>();
    if (auth.devicePinVerifiedThisSession) {
      if (mounted) {
        setState(() {
          _needsPin = false;
          _checking = false;
        });
      }
      return;
    }

    final dev = context.read<DeviceApprovalProvider>();
    if (dev.isParent) {
      if (mounted) {
        setState(() {
          _needsPin = false;
          _checking = false;
        });
      }
      return;
    }

    try {
      final access = await ApiService.instance
          .fetchDeviceAccess()
          .timeout(const Duration(seconds: 20));
      final needs = access['requiresSecurityPin'] == true;
      final serverParent = access['isParent'] == true;
      if (mounted) {
        setState(() {
          _needsPin = needs && !serverParent;
          _checking = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _needsPin = auth.pendingDevicePinRequired && !dev.isParent;
          _checking = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    final pin = _pinCtrl.text.trim();
    final pinErr = validateSecurityPin(pin);
    if (pinErr != null) {
      setState(() => _error = pinErr);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ApiService.instance.verifyDevicePin(pin);
      if (!mounted) return;
      await context.read<AuthProvider>().markDevicePinVerified();
      setState(() {
        _needsPin = false;
        _submitting = false;
      });
    } catch (e) {
      if (!mounted) return;
      var msg = ApiService.friendlyErrorMessage(e);
      if (e is ApiException && e.code == 'PIN_STORAGE_CORRUPT') {
        msg =
            'ডাটাবেসে পিন ঠিকমতো সেভ হয়নি। সার্ভার আপডেট করে OTP দিয়ে পিন আবার সেট করুন।';
      }
      setState(() {
        _submitting = false;
        _error = msg;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking || _needsPin == null) {
      return const SplashScreen();
    }
    if (_needsPin != true) {
      return widget.child;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              Icon(Icons.lock_outline, size: 64, color: AppColors.primary),
              const SizedBox(height: 16),
              Text(
                'নিরাপত্তা পিন',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                'এই ডিভাইস প্যারেন্ট নয়। নতুন লগইনে একবার পিন দিন — পরে অ্যাপ খুললে আর লাগবে না (সাইন আউট পরে আবার লাগবে)।',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, height: 1.45, color: Colors.grey.shade800),
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _pinCtrl,
                obscureText: _obscure,
                keyboardType: TextInputType.number,
                maxLength: 7,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Security PIN',
                  counterText: '',
                  helperText: securityPinLengthHint(_pinCtrl.text),
                  helperStyle: TextStyle(
                    color: securityPinDigitCount(_pinCtrl.text) > 6
                        ? Colors.red
                        : Colors.green.shade700,
                    fontSize: 12,
                  ),
                  errorText: _error,
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                onSubmitted: (_) {
                  if (_canSubmitPin) _submit();
                },
              ),
              const Spacer(),
              FilledButton(
                onPressed: (_submitting || !_canSubmitPin) ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _submitting
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('যাচাই করুন', style: TextStyle(fontSize: 16)),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PinSettingsScreen(),
                    ),
                  ).then((_) {
                    if (!context.mounted) return;
                    if (context.read<AuthProvider>().devicePinVerifiedThisSession) {
                      setState(() => _needsPin = false);
                    }
                  });
                },
                child: const Text('পিন ভুলে গেছেন? OTP দিয়ে রিসেট'),
              ),
              TextButton(
                onPressed: () => context.read<AuthProvider>().signOut(),
                child: const Text('সাইন আউট'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
