import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';

class ApiService {
  ApiService._();
  static final instance = ApiService._();

  static const String _tokenKey = 'pca_auth_token_v1';
  String? _token;

  String? get token => _token;
  bool get isAuthenticated => _token != null && _token!.isNotEmpty;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    initAdminApiBaseUrl(prefs);
    _token = prefs.getString(_tokenKey);
  }

  Future<bool> login(String email, String password) async {
    try {
      final res = await http.post(
        Uri.parse('$kAdminApiBaseUrl/api/admin/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['token'] != null) {
          _token = data['token'];
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_tokenKey, _token!);
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> logout() async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  Future<Map<String, dynamic>> getJson(String path) async {
    final res = await _request('GET', path);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return jsonDecode(res.body);
    }
    throw Exception('GET $path failed: ${res.statusCode} ${res.body}');
  }

  Future<Map<String, dynamic>> putJson(String path, dynamic body) async {
    final res = await _request('PUT', path, body: body);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return jsonDecode(res.body);
    }
    throw Exception('PUT $path failed: ${res.statusCode} ${res.body}');
  }

  Future<Map<String, dynamic>> postJson(String path, dynamic body) async {
    final res = await _request('POST', path, body: body);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return jsonDecode(res.body);
    }
    throw Exception('POST $path failed: ${res.statusCode} ${res.body}');
  }

  Future<Map<String, dynamic>> deleteJson(String path) async {
    final res = await _request('DELETE', path);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return jsonDecode(res.body);
    }
    throw Exception('DELETE $path failed: ${res.statusCode} ${res.body}');
  }

  Future<http.Response> _request(
    String method,
    String path, {
    dynamic body,
  }) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (_token != null) {
      headers['x-admin-key'] = _token!;
    }
    final url = Uri.parse('$kAdminApiBaseUrl$path');
    switch (method.toUpperCase()) {
      case 'GET':
        return await http.get(url, headers: headers);
      case 'PUT':
        return await http.put(url, headers: headers, body: jsonEncode(body));
      case 'POST':
        return await http.post(url, headers: headers, body: jsonEncode(body));
      case 'DELETE':
        return await http.delete(url, headers: headers);
      default:
        throw UnsupportedError('Unsupported HTTP method: $method');
    }
  }
}
