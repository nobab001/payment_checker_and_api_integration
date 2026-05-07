import 'package:flutter/material.dart';

import '../models/sms_record.dart';
import '../services/sms_monitoring_prefs.dart';
import '../services/sms_service.dart';
import '../services/sold_out_storage.dart';
import '../services/storage_service.dart';
import '../utils/sms_history_search.dart';

class SmsProvider extends ChangeNotifier {
  List<SmsRecord> _records = [];
  Map<String, int> _counts = {};
  Map<String, double> _balances = {};
  bool _loading = false;
  String _filter = 'All';
  bool _permissionsGranted = false;
  bool _monitoringEnabled = true;

  Set<String> _soldOutKeys = {};
  String _historySearchQuery = '';

  List<SmsRecord> get records {
    if (_filter == 'All') return _records;
    return _records.where((r) => r.s == _filter).toList();
  }

  /// SMS list for History dashboard: operator filter + search query.
  List<SmsRecord> get recordsForHistory {
    final base = records;
    final q = _historySearchQuery;
    if (q.trim().isEmpty) return base;
    return base.where((r) => smsRecordMatchesQuery(r, q)).toList();
  }

  Map<String, int> get counts => _counts;
  Map<String, double> get balances => _balances;
  bool get loading => _loading;
  String get filter => _filter;
  int get total => _records.length;
  bool get permissionsGranted => _permissionsGranted;
  bool get monitoringEnabled => _monitoringEnabled;
  String get historySearchQuery => _historySearchQuery;

  static String recordKey(SmsRecord r) => '${r.t}|${r.s}|${r.m.hashCode}';

  bool isSoldOut(SmsRecord r) => _soldOutKeys.contains(recordKey(r));

  void setHistorySearchQuery(String value) {
    if (_historySearchQuery == value) return;
    _historySearchQuery = value;
    notifyListeners();
  }

  Future<void> toggleSoldOut(SmsRecord r) async {
    final k = recordKey(r);
    if (_soldOutKeys.contains(k)) {
      _soldOutKeys.remove(k);
    } else {
      _soldOutKeys.add(k);
    }
    await SoldOutStorage.instance.writeAll(_soldOutKeys);
    notifyListeners();
  }

  Future<void> _loadSoldOut() async {
    _soldOutKeys = await SoldOutStorage.instance.readAll();
  }

  Future<void> init() async {
    SmsService.instance.onNewSms = _onNewSms;
    _monitoringEnabled = await SmsMonitoringPrefs.isMonitoringEnabled();

    if (_monitoringEnabled) {
      await _requestAndListen();
    } else {
      SmsService.instance.stopListening();
      _permissionsGranted = await SmsService.instance.requestPermissions();
    }

    await load();

    if (_monitoringEnabled &&
        _permissionsGranted &&
        !await SmsMonitoringPrefs.hasInitialInboxImportDone()) {
      await importFromInbox();
      await SmsMonitoringPrefs.setInitialInboxImportDone();
    }
    notifyListeners();
  }

  void _onNewSms(SmsRecord record) {
    _records.insert(0, record);
    _updateStats();
    notifyListeners();
  }

  Future<void> _requestAndListen() async {
    _permissionsGranted = await SmsService.instance.requestPermissions();
    if (_permissionsGranted) {
      await SmsService.instance.restartListeningIfEnabled();
    }
    notifyListeners();
  }

  /// Resume telephony after app was backgrounded / reboot (Dart state reset).
  Future<void> onAppResumed() async {
    if (!await SmsMonitoringPrefs.isMonitoringEnabled()) return;
    if (!_permissionsGranted) return;
    await SmsService.instance.restartListeningIfEnabled();
  }

  /// Dashboard toggle: persists preference, starts/stops listener, imports inbox when turning ON.
  Future<void> setMonitoringEnabled(bool enabled) async {
    await SmsMonitoringPrefs.setMonitoringEnabled(enabled);
    _monitoringEnabled = enabled;
    notifyListeners();

    if (enabled) {
      _permissionsGranted = await SmsService.instance.requestPermissions();
      if (_permissionsGranted) {
        await SmsService.instance.restartListeningIfEnabled();
        await importFromInbox();
        await SmsMonitoringPrefs.setInitialInboxImportDone();
      }
    } else {
      SmsService.instance.stopListening();
    }
    notifyListeners();
  }

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    await _loadSoldOut();
    _records = await StorageService.instance.readAll();
    _updateStats();
    _loading = false;
    notifyListeners();
  }

  void setFilter(String f) {
    _filter = f;
    notifyListeners();
  }

  void _updateStats() {
    _counts = {};
    _balances = {};
    for (final r in _records) {
      _counts[r.s] = (_counts[r.s] ?? 0) + 1;
      _balances[r.s] = double.tryParse(r.b) ?? 0;
    }
  }

  /// Pull existing payment SMS from device inbox into local JSON
  Future<void> importFromInbox() async {
    _loading = true;
    notifyListeners();
    try {
      final inbox = await SmsService.instance.loadInboxHistory();
      final existing = {for (final r in _records) '${r.t}_${r.s}'};
      for (final r in inbox) {
        if (!existing.contains('${r.t}_${r.s}')) {
          await StorageService.instance.appendSms(r);
        }
      }
      await load();
    } catch (_) {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> clearHistory() async {
    await StorageService.instance.clearAll();
    await SoldOutStorage.instance.clear();
    _soldOutKeys = {};
    _records = [];
    _counts = {};
    _balances = {};
    notifyListeners();
  }
}
