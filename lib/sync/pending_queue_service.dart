import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/sms_record.dart';

/// Persists SMS records that failed to reach the main device.
/// Acts as a durable queue: records are only removed after a confirmed push.
class PendingQueueService {
  static final PendingQueueService instance = PendingQueueService._();
  PendingQueueService._();

  Database? _db;
  // In-memory fallback used on platforms where sqflite is unavailable (web).
  final List<Map<String, dynamic>> _webQueue = [];

  Future<Database> get _database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = p.join(await getDatabasesPath(), 'pending_sms.db');
    return openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, _) => db.execute('''
        CREATE TABLE pending_sms (
          id       INTEGER PRIMARY KEY AUTOINCREMENT,
          data     TEXT    NOT NULL,
          added_at INTEGER NOT NULL
        )
      '''),
    );
  }

  /// Add a single record to the queue.
  Future<void> enqueue(SmsRecord record) async {
    if (kIsWeb) {
      _webQueue.add(record.toJson());
      return;
    }
    final db = await _database;
    await db.insert('pending_sms', {
      'data': jsonEncode(record.toJson()),
      'added_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Retrieve all queued records ordered oldest-first.
  Future<List<SmsRecord>> getAll() async {
    if (kIsWeb) {
      return _webQueue
          .map((e) => SmsRecord.fromJson(e))
          .toList();
    }
    final db = await _database;
    final rows = await db.query('pending_sms', orderBy: 'added_at ASC');
    return rows.map((r) {
      final json = jsonDecode(r['data'] as String) as Map<String, dynamic>;
      return SmsRecord.fromJson(json);
    }).toList();
  }

  /// How many records are currently pending.
  Future<int> count() async {
    if (kIsWeb) return _webQueue.length;
    final db = await _database;
    final result = await db.rawQuery('SELECT COUNT(*) as c FROM pending_sms');
    return (result.first['c'] as int?) ?? 0;
  }

  /// Remove all records (call only after confirmed delivery to main device).
  Future<void> clearAll() async {
    if (kIsWeb) {
      _webQueue.clear();
      return;
    }
    final db = await _database;
    await db.delete('pending_sms');
  }
}
