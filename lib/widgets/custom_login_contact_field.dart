import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/bd_phone_utils.dart';
import '../utils/gmail_input_utils.dart';

/// Login: মোবাইল **অথবা** Gmail — অক্ষর দিলে Gmail মোড, নম্বর দিলে মোবাইল মোড।
class CustomLoginContactField extends StatefulWidget {
  final TextEditingController controller;
  final bool enabled;
  final String? Function(String?)? validator;
  final InputDecoration? decoration;
  final VoidCallback? onContactChanged;

  const CustomLoginContactField({
    super.key,
    required this.controller,
    this.enabled = true,
    this.validator,
    this.decoration,
    this.onContactChanged,
  });

  static bool looksLikeEmail(String text) =>
      RegExp(r'[a-zA-Z@]').hasMatch(text);

  static String readApiValue(TextEditingController c) {
    final t = c.text.trim();
    if (looksLikeEmail(t)) return GmailInputUtils.toApiValue(t);
    return BdPhoneUtils.sanitize(t);
  }

  @override
  State<CustomLoginContactField> createState() =>
      _CustomLoginContactFieldState();
}

class _CustomLoginContactFieldState extends State<CustomLoginContactField> {
  bool _emailMode = false;
  bool _syncing = false;

  /// খালি থাকলে true — তখন অক্ষর+সংখ্যা উভয় কিবোর্ড (Gmail বা 01… লিখতে)।
  bool get _isEmpty => widget.controller.text.isEmpty;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    _onTextChanged();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    if (_syncing) return;
    final raw = widget.controller.text;
    final wantEmail = raw.isNotEmpty && CustomLoginContactField.looksLikeEmail(raw);

    if (wantEmail != _emailMode) {
      setState(() => _emailMode = wantEmail);
    }

    _syncing = true;
    // ইমেইল: GmailSuffixInputFormatter ঠিক করে — listener দিয়ে আবার লিখলে কার্সর আটকে যেত।
    if (!_emailMode) {
      final cleaned = BdPhoneUtils.sanitize(raw);
      if (widget.controller.text != cleaned) {
        widget.controller.value = TextEditingValue(
          text: cleaned,
          selection: TextSelection.collapsed(offset: cleaned.length),
        );
      }
    }
    _syncing = false;
    widget.onContactChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    // খালি/ইমেইল: টেক্সট কিবোর্ড — আগে digitsOnly থাকায় Gmail অক্ষর লেখা যেত না।
    final keyboardType = _emailMode || _isEmpty
        ? TextInputType.emailAddress
        : TextInputType.phone;

    final List<TextInputFormatter> formatters;
    if (_emailMode) {
      formatters = [
        FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9._@-]')),
        GmailSuffixInputFormatter(),
      ];
    } else if (_isEmpty) {
      // মোবাইল বা Gmail — প্রথম ট্যাপে যেকোনো অক্ষর/সংখ্যা।
      formatters = [
        FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9+.\s\-_,@]')),
      ];
    } else {
      formatters = [BdPhoneUtils.formatter];
    }

    return TextFormField(
      controller: widget.controller,
      enabled: widget.enabled,
      keyboardType: keyboardType,
      textCapitalization: TextCapitalization.none,
      autocorrect: false,
      enableSuggestions: false,
      inputFormatters: formatters,
      onChanged: (_) => _onTextChanged(),
      validator: widget.validator,
      decoration: widget.decoration,
    );
  }
}
