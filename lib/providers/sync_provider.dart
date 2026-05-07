import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/sms_record.dart';
import '../sync/sync_api_client.dart';
import '../sync/sync_config.dart';
import '../sync/sync_service.dart';

class SyncProvider extends ChangeNotifier {
  bool _initialized = false;
  int _pendingCount = 0;
  String _localIp = '';
  String _statusMessage = '';
  bool _isBusy = false;
  bool _networkAvailable = true;

  bool get initialized => _initialized;
  int get pendingCount => _pendingCount;
  String get localIp => _localIp;
  String get statusMessage => _statusMessage;
  bool get isBusy => _isBusy;

  /// Whether the device currently has any active network interface.
  /// Updated on every refresh/action — not a live stream.
  bool get networkAvailable => _networkAvailable;

  SyncConfig get config => SyncService.instance.config;
  bool get serverRunning => SyncService.instance.serverRunning;

  Future<void> init() async {
    await SyncService.instance.init();
    SyncService.instance.onRecordsFromSub = _onRecordsFromSub;
    await _refreshState();
    _initialized = true;
    notifyListeners();
  }

  void _onRecordsFromSub(List<SmsRecord> records) {
    _statusMessage = '${records.length}টি রেকর্ড সাব-ডিভাইস থেকে রিসিভ হয়েছে';
    _refreshState();
    notifyListeners();
  }

  Future<void> _refreshState() async {
    _pendingCount = await SyncService.instance.pendingCount();
    _networkAvailable = await SyncApiClient.hasNetwork();
    await _fetchLocalIp();
  }

  Future<void> _fetchLocalIp() async {
    try {
      final interfaces =
          await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) {
            _localIp = addr.address;
            return;
          }
        }
      }
      _localIp = '';
    } catch (_) {
      _localIp = '';
    }
  }

  // ── Config mutations ─────────────────────────────────────────────────────────

  Future<void> setMode(DeviceMode mode) async {
    await SyncService.instance.updateConfig(config.copyWith(mode: mode));
    await _refreshState();
    notifyListeners();
  }

  Future<void> setMainIp(String ip) async {
    await SyncService.instance.updateConfig(config.copyWith(mainDeviceIp: ip));
    notifyListeners();
  }

  Future<void> setPort(int port) async {
    await SyncService.instance.updateConfig(config.copyWith(port: port));
    notifyListeners();
  }

  // ── Actions ──────────────────────────────────────────────────────────────────

  Future<bool> testConnection() async {
    _isBusy = true;
    _statusMessage = '';
    notifyListeners();

    // Re-check network before the ping attempt.
    _networkAvailable = await SyncApiClient.hasNetwork();
    if (!_networkAvailable) {
      _statusMessage = 'নেটওয়ার্ক সংযোগ নেই — পিং বাতিল হয়েছে ✗';
      _isBusy = false;
      notifyListeners();
      return false;
    }

    final ok = await SyncService.instance.testConnection();
    _statusMessage =
        ok ? 'মেইন ডিভাইস রিচেবল ✓' : 'মেইন ডিভাইস রেসপন্ড করছে না ✗';
    _isBusy = false;
    await _refreshState();
    notifyListeners();
    return ok;
  }

  Future<void> flushNow() async {
    _isBusy = true;
    _statusMessage = '';
    notifyListeners();

    _networkAvailable = await SyncApiClient.hasNetwork();
    if (!_networkAvailable) {
      _statusMessage = 'নেটওয়ার্ক নেই — পরে WorkManager পাঠাবে ⏳';
      _isBusy = false;
      await _refreshState();
      notifyListeners();
      return;
    }

    final ok = await SyncService.instance.flushPending();
    _statusMessage = ok
        ? 'সব পেন্ডিং SMS সফলভাবে পাঠানো হয়েছে ✓'
        : 'পাঠানো ব্যর্থ — WorkManager পরে আবার চেষ্টা করবে';
    _isBusy = false;
    await _refreshState();
    notifyListeners();
  }

  Future<void> restartServer() async {
    _isBusy = true;
    notifyListeners();
    await SyncService.instance.restartServer();
    _statusMessage = 'সার্ভার রিস্টার্ট হয়েছে (port ${config.port})';
    _isBusy = false;
    notifyListeners();
  }

  Future<void> refresh() async {
    await _refreshState();
    notifyListeners();
  }
}
