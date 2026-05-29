import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/gmail_input_utils.dart';

/// Reusable Gmail field — `@gmail.com` লেগে থাকে; কার্সর/সিলেক্ট/কপি স্বাভাবিক।
class CustomEmailField extends StatefulWidget {
  final TextEditingController controller;
  final String? labelText;
  final String? hintText;
  final IconData? prefixIcon;
  final bool enabled;
  final bool required;
  final String? Function(String?)? validator;
  final InputDecoration? decoration;
  final void Function(String apiEmail)? onChanged;

  const CustomEmailField({
    super.key,
    required this.controller,
    this.labelText,
    this.hintText,
    this.prefixIcon,
    this.enabled = true,
    this.required = true,
    this.validator,
    this.decoration,
    this.onChanged,
  });

  static String readApiValue(TextEditingController c) =>
      GmailInputUtils.toApiValue(c.text);

  @override
  State<CustomEmailField> createState() => _CustomEmailFieldState();
}

class _CustomEmailFieldState extends State<CustomEmailField> {
  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      enabled: widget.enabled,
      keyboardType: TextInputType.emailAddress,
      autocorrect: false,
      enableSuggestions: false,
      // Listener + forced collapse সরানো — formatter শুধু প্রয়োজন হলে ঠিক করে।
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9._@-]')),
        GmailSuffixInputFormatter(),
      ],
      onChanged: (v) =>
          widget.onChanged?.call(GmailInputUtils.toApiValue(v)),
      validator: widget.validator ??
          (v) => GmailInputUtils.validate(v, required: widget.required),
      decoration: widget.decoration ??
          InputDecoration(
            labelText: widget.labelText ?? 'জিমেইল',
            hintText: widget.hintText ?? 'username',
            prefixIcon: Icon(widget.prefixIcon ?? Icons.email_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
    );
  }
}
