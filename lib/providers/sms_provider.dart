import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/sms_record.dart';
import '../services/sms_persistence_bootstrap.dart';
import '../services/background_payment_api_client.dart';
import '../services/payment_ingest_connectivity_watcher.dart';
import '../services/sms_service_state_prefs.dart';
import '../services/sms_service.dart';
import '../services/sms_sync_foreground_service.dart';
import '../services/sold_out_storage.dart';
import '../repositories/sms_history_local_repository.dart';
import '../services/sms_history_database.dart';
import '../services/payment_search_service.dart';
import '../utils/app_crash_logger.dart';

/// Local-first SMS state: list/search/stats from [SmsHistoryLocalRepository] only.
class SmsProvider extends ChangeNotifier {
  final _localHistory = SmsHistoryLocalRepository.instance;
  List<SmsRecord> _records = [];
  Map<String, int> _counts = {};
  Map<String, double> _balances = {};
  bool _loading = false;
  String _filter = 'All';
  bool _permissionsGranted = false;
  bool _monitoringEnabled = false;
  bool _deviceConfigured = false;
  bool _statePreloaded = false;

  Set<String> _soldOutKeys = {};
  String _historySearchQuery = '';
  List<SmsRecord> _historyDisplay = [];
  bool _searchingRemote = false;

  List<SmsRecord> get records {
    if (_filter == 'All') return _records;
    return _records.where((r) => r.s == _filter).toList();
  }

  /// Home list: SQLite search first; server cascade if local miss.
  List<SmsRecord> get recordsForHistory {
    final q = _historySearchQuery.trim();
    if (q.isEmpty) return records;
    return _historyDisplay;
  }

  bool get searchingRemote => _searchingRemote;

  Map<String, int> get counts => _counts;
  Map<String, double> get balances => _balances;
  bool get loading => _loading;
  String get filter => _filter;
  int get total => _records.length;
  bool get permissionsGranted => _permissionsGranted;
  bool get monitoringEnabled => _monitoringEnabled;
  bool get deviceConfigured => _deviceConfigured;
  bool get serviceActivated => _monitoringEnabled && _deviceConfigured;
  bool get statePreloaded => _statePreloaded;
  String get historySearchQuery => _historySearchQuery;

  static String recordKey(SmsRecord r) => SmsHistoryDatabase.dedupeKey(r);

  bool isSoldOut(SmsRecord r) => _soldOutKeys.contains(recordKey(r));

  Future<void> setHistorySearchQuery(String value) async {
    if (_historySearchQuery == value) return;
    _historySearchQuery = value;
    await _runHistorySearch();
    notifyListeners();
  }

  Future<void> _runHistorySearch() async {
    final q = _historySearchQuery.trim();
    if (q.isEmpty) {
      _historyDisplay = [];
      _searchingRemote = false;
      return;
    }

    final op = _filter == 'All' ? null : _filter;
    var local = await _localHistory.searchLocal(q, operatorKey: op);
    if (local.isNotEmpty) {
      _historyDisplay = local;
      _searchingRemote = false;
      return;
    }

    if (q.length < 3) {
      _historyDisplay = [];
      _searchingRemote = false;
      return;
    }

    _searchingRemote = true;
    notifyListeners();

    _historyDisplay = await PaymentSearchService.instance.searchWithFallback(
      query: q,
      operatorKey: op,
    );
    _searchingRemote = false;
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

  /// Reads disk before first frame so Home can show RUNNING immediately.
  Future<void> preloadPersistedState() async {
    final snap = await SmsPersistenceBootstrap.loadSnapshot();
    _deviceConfigured = snap.deviceConfigured;
    _monitoringEnabled = snap.serviceActivated;
    _statePreloaded = true;
    notifyListeners();
  }

  Future<void> refreshSetupState() async {
    final snap = await SmsPersistenceBootstrap.loadSnapshot();
    _deviceConfigured = snap.deviceConfigured;
    if (_monitoringEnabled && !_deviceConfigured) {
      await SmsServiceStatePrefs.deactivateService();
      _monitoringEnabled = false;
      SmsService.instance.stopListening();
      await SmsSyncForegroundService.stop();
    } else {
      _monitoringEnabled = snap.serviceActivated;
    }
    notifyListeners();
  }

  Future<void> init() async {
    try {
      SmsService.instance.onNewSms = _onNewSms;
      final snap = await SmsPersistenceBootstrap.loadSnapshot();
      _deviceConfigured = snap.deviceConfigured;
      _monitoringEnabled = snap.serviceActivated;
      _statePreloaded = true;

      _permissionsGranted = await SmsService.instance.requestPermissions();

      if (_monitoringEnabled && _deviceConfigured && _permissionsGranted) {
        await SmsService.instance.restartListeningIfEnabled();
        await SmsPersistenceBootstrap.resumeBackgroundPipeline(
          permissionsOk: true,
        );
      } else {
        SmsService.instance.stopListening();
        if (!_monitoringEnabled) {
          await SmsSyncForegroundService.stop();
        }
      }

      if (!kIsWeb && Platform.isAndroid) {
        unawaited(Permission.notification.request());
      }

      await load();
      PaymentIngestConnectivityWatcher.instance.start();
      unawaited(BackgroundPaymentApiClient.instance.flushQueue());

      await _syncForegroundService();
    } catch (e, st) {
      AppCrashLogger.log('SmsProvider.init', e, st);
    } finally {
      notifyListeners();
    }
  }

  Future<void> _syncForegroundService() async {
    try {
      await SmsSyncForegroundService.startIfMonitoringEnabled(
        monitoring: _monitoringEnabled,
        permissionsOk: _permissionsGranted,
      );
    } catch (e, st) {
      AppCrashLogger.log('SmsProvider.foreground', e, st);
    }
  }

  void _onNewSms(SmsRecord record) {
    _records.insert(0, record);
    _updateStats();
    notifyListeners();
  }

  /// Resume telephony after app was backgrounded / reboot (Dart state reset).
  Future<void> onAppResumed() async {
    if (!await SmsServiceStatePrefs.shouldResumeService()) return;
    if (!_permissionsGranted) return;
    await SmsService.instance.restartListeningIfEnabled();
    await _syncForegroundService();
    unawaited(BackgroundPaymentApiClient.instance.flushQueue());
  }

  /// Dashboard toggle: persists preference; starts/stops background SMS listener only.
  Future<bool> setMonitoringEnabled(bool enabled) async {
    if (enabled) {
      final snap = await SmsPersistenceBootstrap.loadSnapshot();
      _deviceConfigured = snap.deviceConfigured;
      if (!_deviceConfigured) {
        notifyListeners();
        return false;
      }
    }

    await SmsServiceStatePrefs.setServiceActivated(enabled);
    _monitoringEnabled = enabled;
    notifyListeners();

    if (enabled) {
      _permissionsGranted = await SmsService.instance.requestPermissions();
      if (_permissionsGranted) {
        await SmsService.instance.restartListeningIfEnabled();
      }
    } else {
      SmsService.instance.disableBackgroundPipeline();
      await SmsSyncForegroundService.stop();
    }
    await _syncForegroundService();
    notifyListeners();
    return true;
  }

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    await _loadSoldOut();
    _records = await _localHistory.loadRecent(limit: 500);
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

  Future<void> clearHistory() async {
    await _localHistory.clearAll();
    await SoldOutStorage.instance.clear();
    _soldOutKeys = {};
    _records = [];
    _counts = {};
    _balances = {};
    notifyListeners();
  }
}
