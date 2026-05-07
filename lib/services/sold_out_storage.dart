import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Persists which SMS records are marked "sold out" (by stable key).
class SoldOutStorage {
  static final SoldOutStorage instance = SoldOutStorage._();
  SoldOutStorage._();

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/sms_sold_out.json');
  }

  Future<Set<String>> readAll() async {
    try {
      final f = await _file();
      if (!f.existsSync()) return {};
      final raw = f.readAsStringSync().trim();
      if (raw.isEmpty) return {};
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => e as String).toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> writeAll(Set<String> keys) async {
    final f = await _file();
    f.writeAsStringSync(jsonEncode(keys.toList()));
  }

  Future<void> clear() => writeAll({});
}
