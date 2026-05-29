import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// PC LAN IP when testing on a physical phone over Wi‑Fi (same network as the dev machine).
/// Update if your PC gets a different address (`ipconfig` on Windows).
const String kDevLanHost = '192.168.0.116';

const String kDevPort = '3000';

/// Stale ngrok hosts saved in older builds — cleared from SharedPreferences on startup.
const Set<String> kStaleApiHosts = {
  'drastic-fringe-unlined.ngrok-free.dev',
};

/// Default API origin for [ApiService].
///
/// Build override: `flutter run --dart-define=API_BASE_URL=http://192.168.0.116:3000`
String get kBaseUrl {
  const fromEnv = String.fromEnvironment('API_BASE_URL');
  if (fromEnv.isNotEmpty) return normalizeApiBaseUrl(fromEnv);

  if (kIsWeb) return 'http://127.0.0.1:$kDevPort';

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    return 'http://127.0.0.1:$kDevPort';
  }

  if (Platform.isAndroid) {
    // Phone/emulator: 127.0.0.1 is the device itself, not the PC running Node.
    return 'http://$kDevLanHost:$kDevPort';
  }

  return 'http://127.0.0.1:$kDevPort';
}

/// Alias kept for older references.
String get kDefaultApiBaseUrl => kBaseUrl;

/// Strip trailing slashes for consistent URI joining.
String normalizeApiBaseUrl(String url) =>
    url.trim().replaceAll(RegExp(r'/+$'), '');

bool isStaleApiBaseUrl(String url) {
  try {
    final host = Uri.parse(url.trim()).host.toLowerCase();
    return kStaleApiHosts.contains(host);
  } catch (_) {
    return false;
  }
}
