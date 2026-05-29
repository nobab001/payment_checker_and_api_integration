import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/constants.dart';
import '../utils/otp_field_metrics.dart';

/// এক বক্স = এক অঙ্ক; পেস্ট ৬ অঙ্ক হলে সব বক্সে ভাগ।
class _OtpSingleDigitFormatter extends TextInputFormatter {
  final void Function(String sixDigits)? onPasteSix;

  _OtpSingleDigitFormatter({this.onPasteSix});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');

    if (digits.length >= OtpFieldMetrics.length) {
      final six = digits.substring(0, OtpFieldMetrics.length);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onPasteSix?.call(six);
      });
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    if (digits.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    final one = digits.substring(digits.length - 1);
    return TextEditingValue(
      text: one,
      selection: const TextSelection.collapsed(offset: 1),
    );
  }
}

/// ৬-অঙ্কের OTP — অ্যাপ জুড়ে একই মাপ ও স্টাইল।
class CustomOtpField extends StatefulWidget {
  final List<TextEditingController>? controllers;
  final List<FocusNode>? focusNodes;
  final Future<void> Function(String code)? onAutoSubmit;
  final bool enabled;
  final void Function(int index, String value)? onChanged;
  final void Function(int index)? onBackspaceOnEmpty;

  const CustomOtpField({
    super.key,
    this.controllers,
    this.focusNodes,
    this.onAutoSubmit,
    this.enabled = true,
    this.onChanged,
    this.onBackspaceOnEmpty,
  });

  @override
  State<CustomOtpField> createState() => _CustomOtpFieldState();
}

class _CustomOtpFieldState extends State<CustomOtpField> {
  static const _length = OtpFieldMetrics.length;

  /// App [ThemeData.inputDecorationTheme] uses filled + vertical padding — breaks
  /// fixed-height OTP cells unless overridden here.
  static final _otpFieldTheme = InputDecorationTheme(
    filled: false,
    fillColor: Colors.transparent,
    isDense: true,
    isCollapsed: true,
    contentPadding: EdgeInsets.zero,
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    disabledBorder: InputBorder.none,
    errorBorder: InputBorder.none,
    focusedErrorBorder: InputBorder.none,
  );

  late final List<TextEditingController> _ctrl;
  late final List<FocusNode> _focus;
  late final bool _ownsControllers;
  bool _submitting = false;
  String _lastSubmitted = '';

  @override
  void initState() {
    super.initState();
    _ownsControllers = widget.controllers == null;
    _ctrl = widget.controllers ??
        List.generate(_length, (_) => TextEditingController());
    _focus = widget.focusNodes ?? List.generate(_length, (_) => FocusNode());
    for (var i = 0; i < _length; i++) {
      _focus[i].addListener(_onFocusChanged);
    }
    for (final c in _ctrl) {
      c.addListener(_onAnyDigitChanged);
    }
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (var i = 0; i < _length; i++) {
      _focus[i].removeListener(_onFocusChanged);
    }
    for (final c in _ctrl) {
      c.removeListener(_onAnyDigitChanged);
    }
    if (_ownsControllers) {
      for (final c in _ctrl) {
        c.dispose();
      }
      for (final f in _focus) {
        f.dispose();
      }
    }
    super.dispose();
  }

  String get code => _ctrl.map((c) => c.text).join();

  void _onAnyDigitChanged() {
    if (code.length < _length) {
      _lastSubmitted = '';
      _submitting = false;
    }
    _tryAutoSubmit();
  }

  Future<void> _tryAutoSubmit() async {
    final c = code;
    if (c.length != _length || !RegExp(r'^\d{6}$').hasMatch(c)) return;
    if (!widget.enabled || widget.onAutoSubmit == null) return;
    if (_submitting || c == _lastSubmitted) return;

    _submitting = true;
    _lastSubmitted = c;
    await widget.onAutoSubmit!(c);
    if (mounted) _submitting = false;
  }

  void _applyPastedCode(String six) {
    for (var j = 0; j < _length; j++) {
      _ctrl[j].value = TextEditingValue(
        text: six[j],
        selection: const TextSelection.collapsed(offset: 1),
      );
    }
    _focus[_length - 1].requestFocus();
    widget.onChanged?.call(_length - 1, six);
    _tryAutoSubmit();
  }

  void _onDigit(int i, String val) {
    widget.onChanged?.call(i, val);
    if (val.length == 1 && i < _length - 1) {
      _focus[i + 1].requestFocus();
    }
    _tryAutoSubmit();
  }

  void _onBackspace(int i) {
    if (i <= 0) return;
    _ctrl[i - 1].clear();
    _focus[i - 1].requestFocus();
    widget.onBackspaceOnEmpty?.call(i);
  }

  InputDecoration _cellDecoration() {
    return const InputDecoration(
      filled: false,
      fillColor: Colors.transparent,
      isDense: true,
      isCollapsed: true,
      counterText: '',
      contentPadding: EdgeInsets.zero,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      focusedErrorBorder: InputBorder.none,
    );
  }

  Widget _digitBox(BuildContext context, int i, double boxW, double boxH) {
    final focused = _focus[i].hasFocus;
    final radius = BorderRadius.circular(OtpFieldMetrics.borderRadius);

    return SizedBox(
      width: boxW,
      height: boxH,
      child: Theme(
        data: Theme.of(context).copyWith(
          inputDecorationTheme: _otpFieldTheme,
          textSelectionTheme: TextSelectionThemeData(
            cursorColor: AppColors.primary,
            selectionColor: AppColors.primary.withValues(alpha: 0.25),
          ),
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: DecoratedBox(
            decoration: OtpFieldMetrics.boxDecoration(
              focused: focused,
              enabled: widget.enabled,
            ),
            child: Center(
              child: Focus(
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.backspace &&
                      _ctrl[i].text.isEmpty) {
                    _onBackspace(i);
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  controller: _ctrl[i],
                  focusNode: _focus[i],
                  enabled: widget.enabled,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  textAlignVertical: TextAlignVertical.center,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    _OtpSingleDigitFormatter(onPasteSix: _applyPastedCode),
                  ],
                  style: const TextStyle(
                    fontSize: OtpFieldMetrics.digitFontSize,
                    fontWeight: FontWeight.bold,
                    height: 1,
                    color: AppColors.primary,
                  ),
                  decoration: _cellDecoration(),
                  onChanged: (v) => _onDigit(i, v),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : OtpFieldMetrics.rowWidth(OtpFieldMetrics.preferredBoxWidth);
        final boxW = OtpFieldMetrics.boxWidthFor(available);
        final boxH = OtpFieldMetrics.preferredBoxHeight;
        final rowW = OtpFieldMetrics.rowWidth(boxW);

        return SizedBox(
          height: boxH,
          child: Align(
            alignment: Alignment.center,
            child: SizedBox(
              width: rowW,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(
                  _length,
                  (i) => _digitBox(context, i, boxW, boxH),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
