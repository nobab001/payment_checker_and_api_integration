import 'package:flutter/material.dart';

import '../utils/bd_phone_utils.dart';

/// Reusable BD mobile field — auto-strips `+88`, spaces, punctuation; max 11 digits.
class CustomMobileField extends StatelessWidget {
  final TextEditingController controller;
  final String? labelText;
  final String? hintText;
  final IconData? prefixIcon;
  final bool enabled;
  final String? Function(String?)? validator;
  final InputDecoration? decoration;
  final void Function(String sanitized)? onChanged;

  const CustomMobileField({
    super.key,
    required this.controller,
    this.labelText,
    this.hintText,
    this.prefixIcon,
    this.enabled = true,
    this.validator,
    this.decoration,
    this.onChanged,
  });

  void _applySanitize() {
    final cleaned = BdPhoneUtils.sanitize(controller.text);
    if (controller.text != cleaned) {
      controller.value = TextEditingValue(
        text: cleaned,
        selection: TextSelection.collapsed(offset: cleaned.length),
      );
    }
    onChanged?.call(cleaned);
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.phone,
      // digitsOnly + custom sanitize — paste `+880 1712-345 678` ঠিক হয়।
      inputFormatters: [BdPhoneUtils.formatter],
      onChanged: (_) => _applySanitize(),
      validator: validator ?? (v) => BdPhoneUtils.validate(v),
      decoration: decoration ??
          InputDecoration(
            labelText: labelText ?? 'মোবাইল নম্বর',
            hintText: hintText ?? '01XXXXXXXXX',
            prefixIcon: Icon(prefixIcon ?? Icons.phone_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
    );
  }
}
