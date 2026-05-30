import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _adminApiBaseUrl = 'http://127.0.0.1:3000';

String get kAdminApiBaseUrl => _adminApiBaseUrl;

const String kDevLanHost = '192.168.0.116';
const String kDevPort = '3000';

void initAdminApiBaseUrl(SharedPreferences prefs) {
  final saved = prefs.getString('pca_api_base_url_v1')?.trim();
  if (saved != null && saved.isNotEmpty) {
    _adminApiBaseUrl = saved;
    return;
  }

  if (kIsWeb) {
    _adminApiBaseUrl = 'http://127.0.0.1:$kDevPort';
    return;
  }

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    _adminApiBaseUrl = 'http://127.0.0.1:$kDevPort';
    return;
  }

  if (Platform.isAndroid) {
    _adminApiBaseUrl = 'http://$kDevLanHost:$kDevPort';
    return;
  }

  _adminApiBaseUrl = 'http://127.0.0.1:$kDevPort';
}

Future<void> setAdminApiBaseUrl(String url) async {
  final prefs = await SharedPreferences.getInstance();
  final normalized = url.trim().replaceAll(RegExp(r'/+$'), '');
  if (normalized.isNotEmpty) {
    await prefs.setString('pca_api_base_url_v1', normalized);
    _adminApiBaseUrl = normalized;
  } else {
    await prefs.remove('pca_api_base_url_v1');
    initAdminApiBaseUrl(prefs);
  }
}
