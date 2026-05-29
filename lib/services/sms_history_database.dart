import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/sms_record.dart';
import '../utils/constants.dart';

/// SQLite local cache — indexed for fast search at scale (sqflite, not JSON).
class SmsHistoryDatabase {
  SmsHistoryDatabase._();
  static final SmsHistoryDatabase instance = SmsHistoryDatabase._();

  static const _dbName = 'sms_history.db';
  static const _table = 'sms_history';
  static const _dbVersion = 2;

  Database? _db;
  final List<SmsRecord> _webCache = [];

  Future<Database?> get _database async {
    if (kIsWeb) return null;
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = p.join(await getDatabasesPath(), _dbName);
    return openDatabase(
      dbPath,
      version: _dbVersion,
      onCreate: (db, _) async {
        await _createSchema(db);
        await _migrateFromJsonFile(db);
      },
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 2) await _upgradeToV2(db);
        await _migrateFromJsonFile(db);
      },
      onOpen: (db) => _migrateFromJsonFile(db),
    );
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE $_table (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        t             TEXT    NOT NULL,
        s             TEXT    NOT NULL,
        m             TEXT    NOT NULL,
        b             TEXT    NOT NULL DEFAULT '0',
        tp            TEXT    NOT NULL DEFAULT 'txn',
        am            REAL    NOT NULL DEFAULT 0,
        trx_id        TEXT,
        sim_slot      INTEGER,
        sim_number    TEXT,
        provider_tag  TEXT,
        sender_number TEXT,
        dedupe_key    TEXT    NOT NULL UNIQUE,
        is_synced     INTEGER NOT NULL DEFAULT 0,
        server_id     INTEGER,
        created_at    INTEGER NOT NULL
      )
    ''');
    await _createIndexes(db);
  }

  Future<void> _upgradeToV2(Database db) async {
    await db.execute(
      'ALTER TABLE $_table ADD COLUMN is_synced INTEGER NOT NULL DEFAULT 1',
    );
    await db.execute('ALTER TABLE $_table ADD COLUMN server_id INTEGER');
    await _createIndexes(db);
  }

  Future<void> _createIndexes(Database db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sms_history_t ON $_table (t DESC, id DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sms_trx_id ON $_table (trx_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sms_sender_number ON $_table (sender_number)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sms_sim_number ON $_table (sim_number)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sms_amount ON $_table (am)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sms_is_synced ON $_table (is_synced)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sms_search_compound ON $_table (trx_id, sender_number, sim_number, t DESC)',
    );
  }

  static String dedupeKey(SmsRecord r) => '${r.t}|${r.s}|${r.m.hashCode}';

  Map<String, Object?> _toRow(SmsRecord r, {bool synced = false, int? serverId}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return {
      't': r.t,
      's': r.s,
      'm': r.m,
      'b': r.b,
      'tp': r.tp,
      'am': r.am,
      'trx_id': r.trxId,
      'sim_slot': r.simSlot,
      'sim_number': r.simNumber,
      'provider_tag': r.providerTag,
      'sender_number': r.senderNumber,
      'dedupe_key': dedupeKey(r),
      'is_synced': synced ? 1 : 0,
      'server_id': serverId,
      'created_at': now,
    };
  }

  SmsRecord _fromRow(Map<String, Object?> row) => SmsRecord(
        t: row['t'] as String,
        s: row['s'] as String,
        m: row['m'] as String,
        b: row['b'] as String? ?? '0',
        tp: row['tp'] as String? ?? 'txn',
        am: (row['am'] as num?)?.toDouble() ?? 0,
        trxId: row['trx_id'] as String?,
        simSlot: row['sim_slot'] as int?,
        simNumber: row['sim_number'] as String?,
        providerTag: row['provider_tag'] as String?,
        senderNumber: row['sender_number'] as String?,
      );

  Future<File> _legacyJsonFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/${AppStrings.historyFile}');
  }

  Future<void> _migrateFromJsonFile(Database db) async {
    final count = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM $_table'),
        ) ??
        0;

    final file = await _legacyJsonFile();
    if (!file.existsSync()) return;

    if (count > 0) {
      await _archiveLegacyJson(file);
      return;
    }

    try {
      final raw = file.readAsStringSync().trim();
      if (raw.isEmpty) {
        await _archiveLegacyJson(file);
        return;
      }

      final list = jsonDecode(raw) as List<dynamic>;
      final records = list
          .map((e) => SmsRecord.fromJson(e as Map<String, dynamic>))
          .toList();

      if (records.isEmpty) {
        await _archiveLegacyJson(file);
        return;
      }

      await db.transaction((txn) async {
        for (final r in records) {
          await txn.insert(
            _table,
            _toRow(r, synced: true),
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      });

      await _archiveLegacyJson(file);
      if (kDebugMode) {
        debugPrint(
          '[SmsHistoryDatabase] migrated ${records.length} record(s) from JSON',
        );
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[SmsHistoryDatabase] JSON migration failed: $e');
        debugPrint('$st');
      }
    }
  }

  Future<void> _archiveLegacyJson(File file) async {
    if (!file.existsSync()) return;
    final archived = File('${file.path}.migrated');
    if (archived.existsSync()) {
      file.deleteSync();
      return;
    }
    await file.rename(archived.path);
  }

  Future<List<SmsRecord>> readAll({int limit = 2000}) => readRecent(limit: limit);

  Future<List<SmsRecord>> readRecent({int limit = 500}) async {
    if (kIsWeb) {
      return _webCache.take(limit).toList();
    }
    final db = await _database;
    if (db == null) return [];

    final rows = await db.query(
      _table,
      orderBy: 't DESC, id DESC',
      limit: limit,
    );
    return rows.map(_fromRow).toList();
  }

  /// Indexed SQL search — TrxID, amount, phone (last digits), message.
  Future<List<SmsRecord>> searchLocal(
    String query, {
    String? operatorKey,
    int limit = 200,
  }) async {
    final q = query.trim();
    if (q.isEmpty) {
      return readRecent(limit: limit);
    }

    if (kIsWeb) {
      return _webCache
          .where((r) => _matchesQuery(r, q, operatorKey))
          .take(limit)
          .toList();
    }

    final db = await _database;
    if (db == null) return [];

    final like = '%$q%';
    final digits = q.replaceAll(RegExp(r'[^\d]'), '');
    final where = <String>[];
    final args = <Object?>[];

    if (operatorKey != null && operatorKey != 'All') {
      where.add('(s = ? OR provider_tag LIKE ?)');
      args.addAll([operatorKey, '%$operatorKey%']);
    }

    final searchParts = <String>[
      'trx_id LIKE ?',
      'sender_number LIKE ?',
      'sim_number LIKE ?',
      'm LIKE ?',
      'CAST(am AS TEXT) LIKE ?',
      'provider_tag LIKE ?',
    ];
    final searchArgs = [like, like, like, like, like, like];
    if (digits.length >= 2) {
      searchParts.add('sender_number LIKE ?');
      searchParts.add('sim_number LIKE ?');
      searchParts.add('m LIKE ?');
      searchArgs.addAll(['%$digits%', '%$digits%', '%$digits%']);
    }
    where.add('(${searchParts.join(' OR ')})');
    args.addAll(searchArgs);

    final rows = await db.query(
      _table,
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 't DESC, id DESC',
      limit: limit,
    );
    return rows.map(_fromRow).toList();
  }

  bool _matchesQuery(SmsRecord r, String q, String? operatorKey) {
    if (operatorKey != null && operatorKey != 'All') {
      if (r.s != operatorKey && !(r.providerTag?.contains(operatorKey) ?? false)) {
        return false;
      }
    }
    final lower = q.toLowerCase();
    final hay = '${r.m} ${r.s} ${r.trxId} ${r.senderNumber} ${r.simNumber} ${r.am}'
        .toLowerCase();
    return hay.contains(lower);
  }

  Future<void> append(SmsRecord record, {bool synced = false}) =>
      appendBatch([record], synced: synced);

  Future<void> appendBatch(
    List<SmsRecord> incoming, {
    bool synced = false,
  }) async {
    if (incoming.isEmpty) return;

    if (kIsWeb) {
      final existing = {for (final r in _webCache) dedupeKey(r)};
      for (final r in incoming.reversed) {
        if (existing.add(dedupeKey(r))) {
          _webCache.insert(0, r);
        }
      }
      return;
    }

    final db = await _database;
    if (db == null) return;

    await db.transaction((txn) async {
      for (final r in incoming.reversed) {
        await txn.insert(
          _table,
          _toRow(r, synced: synced),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  Future<void> markSynced(String dedupeKey) async {
    if (kIsWeb) return;
    final db = await _database;
    if (db == null) return;
    await db.update(
      _table,
      {'is_synced': 1},
      where: 'dedupe_key = ?',
      whereArgs: [dedupeKey],
    );
  }

  Future<List<SmsRecord>> listUnsynced({int limit = 50}) async {
    if (kIsWeb) return [];
    final db = await _database;
    if (db == null) return [];
    final rows = await db.query(
      _table,
      where: 'is_synced = 0',
      orderBy: 'created_at ASC',
      limit: limit,
    );
    return rows.map(_fromRow).toList();
  }

  Future<void> clearAll() async {
    if (kIsWeb) {
      _webCache.clear();
      return;
    }
    final db = await _database;
    if (db == null) return;
    await db.delete(_table);
  }

  Future<File> writeExportJson() async {
    final records = await readAll(limit: 10000);
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/sms_history_export.json');
    await file.writeAsString(
      jsonEncode(records.map((r) => r.toJson()).toList()),
    );
    return file;
  }
}
