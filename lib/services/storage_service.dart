import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/sms_record.dart';
import '../utils/constants.dart';

class StorageService {
  static final StorageService instance = StorageService._();
  StorageService._();

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/${AppStrings.historyFile}');
  }

  Future<List<SmsRecord>> readAll() async {
    try {
      final f = await _file();
      if (!f.existsSync()) return [];
      final raw = f.readAsStringSync().trim();
      if (raw.isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => SmsRecord.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> appendSms(SmsRecord record) async {
    final records = await readAll();
    records.insert(0, record); // newest first
    final f = await _file();
    f.writeAsStringSync(
      jsonEncode(records.map((r) => r.toJson()).toList()),
    );
  }

  Future<File> getExportFile() => _file();

  Future<Map<String, dynamic>> getStats() async {
    final records = await readAll();
    final counts = <String, int>{};
    final balances = <String, double>{};
    for (final r in records) {
      counts[r.s] = (counts[r.s] ?? 0) + 1;
      balances[r.s] = double.tryParse(r.b) ?? 0;
    }
    return {'counts': counts, 'balances': balances, 'total': records.length};
  }

  Future<void> clearAll() async {
    final f = await _file();
    if (f.existsSync()) f.deleteSync();
  }
}
