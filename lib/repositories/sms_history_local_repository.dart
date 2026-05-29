import '../models/sms_record.dart';
import '../services/storage_service.dart';
import '../utils/sms_history_search.dart';

/// Local-first repository — SQLite only for UI; server sync is separate.
class SmsHistoryLocalRepository {
  SmsHistoryLocalRepository._();
  static final SmsHistoryLocalRepository instance = SmsHistoryLocalRepository._();

  Future<List<SmsRecord>> loadRecent({int limit = 500}) =>
      StorageService.instance.readAll(limit: limit);

  Future<List<SmsRecord>> searchLocal(
    String query, {
    String? operatorKey,
    int limit = 200,
  }) =>
      StorageService.instance.searchLocal(
        query,
        operatorKey: operatorKey,
        limit: limit,
      );

  Future<void> append(SmsRecord record, {bool synced = false}) =>
      StorageService.instance.appendSms(record, synced: synced);

  Future<void> appendBatch(List<SmsRecord> records, {bool synced = false}) =>
      StorageService.instance.appendSmsBatch(records, synced: synced);

  Future<void> markSynced(String dedupeKey) =>
      StorageService.instance.markSynced(dedupeKey);

  Future<void> cacheFromServer(List<SmsRecord> records) =>
      appendBatch(records, synced: true);

  Future<void> clearAll() => StorageService.instance.clearAll();

  /// In-memory filter fallback (web / tests).
  List<SmsRecord> filterByQuery(List<SmsRecord> source, String query) {
    final q = query.trim();
    if (q.isEmpty) return source;
    return source.where((r) => smsRecordMatchesQuery(r, q)).toList();
  }
}
