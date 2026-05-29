import 'package:flutter/material.dart';

import 'custom_otp_field.dart';

/// Legacy name — wraps [CustomOtpField]. Pass [onAutoSubmit] for ৬তম অঙ্কে অটো যাচাই।
class OtpDigitRow extends StatelessWidget {
  final List<TextEditingController> controllers;
  final List<FocusNode> focusNodes;
  final Future<void> Function(String code)? onAutoSubmit;
  final bool enabled;
  final void Function(int index, String value)? onChanged;
  final void Function(int index)? onBackspaceOnEmpty;

  const OtpDigitRow({
    super.key,
    required this.controllers,
    required this.focusNodes,
    this.onAutoSubmit,
    this.enabled = true,
    this.onChanged,
    this.onBackspaceOnEmpty,
  });

  @override
  Widget build(BuildContext context) {
    return CustomOtpField(
      controllers: controllers,
      focusNodes: focusNodes,
      onAutoSubmit: onAutoSubmit,
      enabled: enabled,
      onChanged: onChanged,
      onBackspaceOnEmpty: onBackspaceOnEmpty,
    );
  }
}
