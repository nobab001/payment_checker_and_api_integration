import 'package:flutter/services.dart';

/// Bangladesh mobile helpers — strip formatting, keep `01XXXXXXXXX` (11 digits).
class BdPhoneUtils {
  BdPhoneUtils._();

  static const bdPrefixes = ['013', '014', '015', '016', '017', '018', '019'];

  static final RegExp _national11 = RegExp(r'01\d{9}');

  /// Strips `+88` / `880`, spaces, `-`, `.` and keeps `01XXXXXXXXX` (11 digits).
  ///
  /// Examples: `+880 1712-345678` → `01712345678`, `8801712345678` → `01712345678`.
  static String sanitize(String input) {
    var s = input.replaceAll(RegExp(r'[^\d]'), '');
    if (s.isEmpty) return '';

    // যেকোনো জায়গায় 01XXXXXXXXX খুঁজে নেয় (+880 / 880 / স্পেস সহ পেস্ট)
    final direct = _national11.firstMatch(s);
    if (direct != null) return direct.group(0)!;

    // 880 + ১০ অঙ্ক (১ দিয়ে শুরু) → 0 + ১০ অঙ্ক
    if (s.startsWith('880') && s.length >= 13) {
      final tail = s.substring(3);
      if (tail.startsWith('1')) {
        final national = '0${tail.substring(0, 10)}';
        if (national.length == 11) return national;
      }
    }

    // 88… অতিরিক্ত অঙ্ক — 88 সরিয়ে আবার খোঁজা
    if (s.startsWith('88') && s.length > 11) {
      final after88 = s.substring(2);
      final m = _national11.firstMatch(after88);
      if (m != null) return m.group(0)!;
      if (after88.startsWith('1') && after88.length >= 10) {
        return '0${after88.substring(0, 10)}';
      }
    }

    if (s.length > 11) {
      final idx = s.indexOf('01');
      if (idx >= 0 && s.length >= idx + 11) {
        return s.substring(idx, idx + 11);
      }
    }

    return s.length > 11 ? s.substring(0, 11) : s;
  }

  static bool isValid(String phone) {
    final s = sanitize(phone);
    if (s.length != 11) return false;
    return bdPrefixes.contains(s.substring(0, 3));
  }

  static String? validate(String? value, {bool required = true}) {
    if (value == null || value.trim().isEmpty) {
      return required ? 'মোবাইল নম্বর দিন' : null;
    }
    final s = sanitize(value);
    if (s.length != 11) return 'মোবাইল নম্বর অবশ্যই ১১ সংখ্যার হতে হবে';
    if (!bdPrefixes.contains(s.substring(0, 3))) {
      return 'বাংলাদেশি অপারেটর কোড দিন (013–019)';
    }
    return null;
  }

  /// Paste/type — sanitize আগে; শেষে সর্বোচ্চ ১১ অঙ্ক।
  static TextInputFormatter get formatter => TextInputFormatter.withFunction(
        (old, next) {
          final cleaned = sanitize(next.text);
          return TextEditingValue(
            text: cleaned,
            selection: TextSelection.collapsed(offset: cleaned.length),
          );
        },
      );
}
