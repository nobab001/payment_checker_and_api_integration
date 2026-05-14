import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';

/// Optional override for API / SMS-forward base URL (e.g. ngrok or LAN IP).
class ApiBaseUrlPrefs {
  static const _key = 'api_base_url_override';

  /// Trailing slashes stripped. Falls back to [kDefaultApiBaseUrl] when unset/blank.
  static Future<String> getEffectiveBaseUrl() async {
    final p = await SharedPreferences.getInstance();
    final o = p.getString(_key);
    if (o != null && o.trim().isNotEmpty) {
      return normalizeApiBaseUrl(o);
    }
    return normalizeApiBaseUrl(kDefaultApiBaseUrl);
  }

  static Future<String?> getOverrideRaw() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_key);
  }

  static Future<void> setOverride(String? url) async {
    final p = await SharedPreferences.getInstance();
    if (url == null || url.trim().isEmpty) {
      await p.remove(_key);
    } else {
      await p.setString(_key, normalizeApiBaseUrl(url));
    }
  }
}
