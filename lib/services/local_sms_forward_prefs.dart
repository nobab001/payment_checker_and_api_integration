import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../utils/constants.dart';

/// Local SMS → Node forward: enable flag + allowed sender substrings.
class LocalSmsForwardPrefs {
  static const _enabledKey = 'local_sms_forward_enabled';
  static const _allowedKey = 'local_sms_allowed_senders_json';

  static Future<bool> isForwardEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_enabledKey) ?? false;
  }

  static Future<void> setForwardEnabled(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_enabledKey, v);
  }

  static Future<List<String>> loadAllowedSenders() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_allowedKey);
    if (raw == null || raw.trim().isEmpty) {
      return kOperators.map((o) => o.key).toList();
    }
    try {
      final list = jsonDecode(raw);
      if (list is List) {
        return list.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<void> saveAllowedSenders(List<String> items) async {
    final p = await SharedPreferences.getInstance();
    final clean = items.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    await p.setString(_allowedKey, jsonEncode(clean));
  }
}
