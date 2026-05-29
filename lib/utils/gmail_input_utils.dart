import 'package:flutter/services.dart';

/// Gmail suffix (`@gmail.com`) with natural cursor / selection.
class GmailInputUtils {
  GmailInputUtils._();

  static const suffix = '@gmail.com';
  static const int suffixLength = suffix.length;

  /// শুধু ইউজারনেম অংশ।
  static String sanitizeLocal(String raw) {
    var s = raw.trim().toLowerCase();
    if (s.contains('@')) {
      s = s.split('@').first;
    }
    if (s.endsWith(suffix)) {
      s = s.substring(0, s.length - suffix.length);
    }
    return s.replaceAll(RegExp(r'[^a-z0-9._-]'), '');
  }

  static String composeDisplay(String local) {
    final l = sanitizeLocal(local);
    if (l.isEmpty) return '';
    return '$l$suffix';
  }

  static String toApiValue(String displayOrLocal) {
    final d = displayOrLocal.trim().toLowerCase();
    if (d.isEmpty) return '';
    if (d.endsWith(suffix)) return d;
    final local = sanitizeLocal(d);
    if (local.isEmpty) return '';
    return '$local$suffix';
  }

  static bool isValid(String value) {
    final api = toApiValue(value);
    return RegExp(r'^[^\s@]+@gmail\.com$').hasMatch(api);
  }

  static String? validate(String? value, {bool required = true}) {
    if (value == null || value.trim().isEmpty) {
      return required ? 'জিমেইল দিন' : null;
    }
    if (!isValid(value)) return 'শুধু @gmail.com ঠিকানা গ্রহণযোগ্য';
    return null;
  }

  /// Core: only rewrite when suffix/local invalid; otherwise keep [next] as-is.
  static TextEditingValue formatEditUpdate(
    TextEditingValue old,
    TextEditingValue next,
  ) {
    if (next.text.isEmpty) {
      return next;
    }

    final local = sanitizeLocal(next.text);
    if (local.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    final expected = '$local$suffix';

    // Valid text — preserve cursor, selection, tap position (no forced collapse).
    if (next.text == expected) {
      return next;
    }

    final selection = _repairSelection(
      attempted: next,
      localLength: local.length,
      expectedLength: expected.length,
    );

    return TextEditingValue(text: expected, selection: selection);
  }

  /// Suffix মুছে ফেললে / invalid char সরালে selection যতটা সম্ভব রাখা।
  static TextSelection _repairSelection({
    required TextEditingValue attempted,
    required int localLength,
    required int expectedLength,
  }) {
    final sel = attempted.selection;
    if (!sel.isValid) {
      return TextSelection.collapsed(offset: localLength);
    }

    final at = attempted.text.indexOf('@');
    final localEnd = at >= 0 ? at : attempted.text.length;

    var base = sel.baseOffset;
    var extent = sel.extentOffset;

    // ইউজারনেমের ভিতরে ছিল — সেখানেই রাখি
    if (base <= localEnd) {
      base = base.clamp(0, localLength);
    } else {
      base = localLength;
    }

    if (extent <= localEnd) {
      extent = extent.clamp(0, localLength);
    } else {
      extent = (localLength + suffixLength).clamp(0, expectedLength);
    }

    if (base > extent) {
      final t = base;
      base = extent;
      extent = t;
    }

    return TextSelection(baseOffset: base, extentOffset: extent);
  }
}

/// `TextFormField`-এ ব্যবহার করুন — controller listener লাগে না।
class GmailSuffixInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return GmailInputUtils.formatEditUpdate(oldValue, newValue);
  }
}
