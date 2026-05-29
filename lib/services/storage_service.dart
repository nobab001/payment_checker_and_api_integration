import 'dart:io';

import '../models/sms_record.dart';
import 'sms_history_database.dart';

/// Local-first SMS history — SQLite with B-tree indexes ([SmsHistoryDatabase]).
class StorageService {
  static final StorageService instance = StorageService._();
  StorageService._();

  final _db = SmsHistoryDatabase.instance;

  Future<List<SmsRecord>> readAll({int limit = 2000}) =>
      _db.readRecent(limit: limit);

  Future<List<SmsRecord>> searchLocal(
    String query, {
    String? operatorKey,
    int limit = 200,
  }) =>
      _db.searchLocal(query, operatorKey: operatorKey, limit: limit);

  Future<void> appendSms(SmsRecord record, {bool synced = false}) =>
      _db.append(record, synced: synced);

  Future<void> appendSmsBatch(
    List<SmsRecord> incoming, {
    bool synced = false,
  }) =>
      _db.appendBatch(incoming, synced: synced);

  Future<void> markSynced(String dedupeKey) => _db.markSynced(dedupeKey);

  Future<File> getExportFile() => _db.writeExportJson();

  Future<Map<String, dynamic>> getStats() async {
    final records = await readAll(limit: 5000);
    final counts = <String, int>{};
    final balances = <String, double>{};
    for (final r in records) {
      counts[r.s] = (counts[r.s] ?? 0) + 1;
      balances[r.s] = double.tryParse(r.b) ?? 0;
    }
    return {'counts': counts, 'balances': balances, 'total': records.length};
  }

  Future<void> clearAll() => _db.clearAll();
}
