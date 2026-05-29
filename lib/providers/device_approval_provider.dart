import 'dart:async';

import 'package:android_id/android_id.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import '../models/device_model.dart';
import '../services/api_service.dart';
import '../services/device_approval_bridge.dart';
import '../services/device_session_bridge.dart';

/// Parent–child approval via VPS REST only (polling, no Firebase).
class DeviceApprovalProvider extends ChangeNotifier {
  static const _pollInterval = Duration(seconds: 12);
  static const _androidIdTimeout = Duration(seconds: 8);
  static const _initTimeout = Duration(seconds: 45);

  String? _hardwareDeviceId;
  DeviceModel? _thisDevice;
  List<DeviceModel> _pendingRequests = [];
  Timer? _pollTimer;
  bool _initialized = false;
  Future<void>? _initFuture;
  bool _rejected = false;
  bool _serverMaintenance = false;
  bool _statusRefreshing = false;
  String? _statusMessage;

  String? get hardwareDeviceId => _hardwareDeviceId;
  DeviceModel? get thisDevice => _thisDevice;
  List<DeviceModel> get pendingRequests => _pendingRequests;

  bool get isAwaitingApproval =>
      _thisDevice != null &&
      !_thisDevice!.isParent &&
      _thisDevice!.isPending &&
      !_rejected;

  bool get isParent =>
      _thisDevice != null &&
      _thisDevice!.isParent &&
      _thisDevice!.isActiveDevice;

  bool get registrationRejected => _rejected;
  bool get serverMaintenance => _serverMaintenance;
  bool get statusRefreshing => _statusRefreshing;
  String? get statusMessage => _statusMessage;

  bool get hasSession => _thisDevice != null;

  Future<void> ingestLoginDevice(String hardwareId, DeviceModel device) async {
    _hardwareDeviceId = hardwareId;
    _thisDevice = device;
    _rejected = false;
    _serverMaintenance = false;
    _initialized = true;
    ApiService.instance.setHardwareDeviceId(hardwareId);
    _startPollingIfPending();
    notifyListeners();
  }

  Future<void> ensureInitialized() async {
    if (_initialized && _hardwareDeviceId != null) return;
    if (_initFuture != null) return _initFuture!;
    if (kIsWeb) {
      _initialized = true;
      notifyListeners();
      return;
    }
    _initFuture = _runInitializeWithTimeout();
    return _initFuture!;
  }

  Future<String?> _readHardwareId() async {
    try {
      return await const AndroidId()
          .getId()
          .timeout(_androidIdTimeout);
    } catch (_) {
      return null;
    }
  }

  Future<void> _runInitializeWithTimeout() async {
    try {
      await _runInitialize().timeout(_initTimeout);
    } on TimeoutException {
      debugPrint('[DeviceApproval] init timed out after $_initTimeout');
      _initialized = true;
    }
  }

  Future<void> _runInitialize() async {
    notifyListeners();
    try {
      final token = ApiService.instance.authToken;
      if (token == null || token.isEmpty) {
        _initialized = true;
        return;
      }
      final hw = await _readHardwareId();
      if (hw == null || hw.isEmpty) {
        _initialized = true;
        return;
      }
      if (_hardwareDeviceId == hw && _thisDevice != null) {
        _initialized = true;
        _startPollingIfPending();
        return;
      }
      _hardwareDeviceId = hw;
      ApiService.instance.setHardwareDeviceId(hw);
      final model = await _fetchDeviceModelString();
      var device = await ApiService.instance.fetchDeviceSelf(hw);
      device ??= await ApiService.instance.registerDevice(
        hw,
        'My Phone',
        deviceModel: model,
      );
      _thisDevice = device;
      _rejected = false;
      _serverMaintenance = false;
      await ApiService.instance.syncDeviceSettingsToCache(hardwareDeviceId: hw);
      _initialized = true;
      _startPollingIfPending();
    } catch (e, st) {
      debugPrint('[DeviceApproval] init failed: $e');
      debugPrint('$st');
      _serverMaintenance = _looksLikeServerDown(e);
      _initialized = true;
    } finally {
      notifyListeners();
    }
  }

  /// Parent: load pending devices from VPS.
  Future<void> refreshThisDeviceFromServer() async {
    final hw = _hardwareDeviceId;
    if (hw == null) return;
    try {
      final d = await ApiService.instance.fetchDeviceSelf(hw);
      if (d != null) {
        _thisDevice = d;
        _serverMaintenance = false;
        await ApiService.instance.syncDeviceSettingsToCache(hardwareDeviceId: hw);
        notifyListeners();
      }
    } catch (e) {
      _serverMaintenance = _looksLikeServerDown(e);
      notifyListeners();
    }
  }

  Future<void> refreshPendingRequests() async {
    if (!isParent) return;
    try {
      _pendingRequests = await ApiService.instance.fetchPendingRequests();
      _serverMaintenance = false;
      notifyListeners();
    } catch (e) {
      _serverMaintenance = _looksLikeServerDown(e);
      notifyListeners();
    }
  }

  /// Manual + periodic status check for child devices waiting on parent.
  Future<void> refreshStatusNow() async {
    final hw = _hardwareDeviceId;
    if (hw == null || hw.isEmpty) return;
    _statusRefreshing = true;
    notifyListeners();
    try {
      await _pollDeviceStatus(hw);
    } finally {
      _statusRefreshing = false;
      notifyListeners();
    }
  }

  void _startPollingIfPending() {
    _pollTimer?.cancel();
    if (_hardwareDeviceId == null) return;
    if (!isAwaitingApproval) return;
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      unawaited(refreshStatusNow());
    });
    unawaited(refreshStatusNow());
  }

  Future<void> _pollDeviceStatus(String hw) async {
    try {
      final result = await ApiService.instance.checkDeviceStatus(hw);
      if (result.serverMaintenance) {
        _serverMaintenance = true;
        _statusMessage = 'Server Under Maintenance';
        return;
      }
      _serverMaintenance = false;
      _statusMessage = null;

      if (result.isRejected) {
        _rejected = true;
        _pollTimer?.cancel();
        _pollTimer = null;
        notifyListeners();
        DeviceApprovalBridge.onRejectedMustSignOut?.call();
        return;
      }

      if (result.isApproved && result.device != null) {
        _thisDevice = result.device;
        _rejected = false;
        _pollTimer?.cancel();
        _pollTimer = null;
        await ApiService.instance.syncDeviceSettingsToCache(hardwareDeviceId: hw);
        notifyListeners();
        return;
      }

      if (result.isPending && result.device != null) {
        _thisDevice = result.device;
        notifyListeners();
      }
    } catch (e) {
      if (_looksLikeServerDown(e)) {
        _serverMaintenance = true;
        _statusMessage = 'Server Under Maintenance';
      }
    }
  }

  bool _looksLikeServerDown(Object e) {
    if (e is ApiException) {
      return e.code == 'connection_failed' ||
          e.code == 'network' ||
          e.code == 'timeout';
    }
    return false;
  }

  Future<String> _fetchDeviceModelString() async {
    try {
      final info = DeviceInfoPlugin();
      final android = await info.androidInfo;
      final brand = android.brand.trim();
      final model = android.model.trim();
      if (brand.isNotEmpty && model.isNotEmpty) return '$brand $model';
      if (model.isNotEmpty) return model;
      return android.device.trim();
    } catch (_) {
      return '';
    }
  }

  void reset() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _thisDevice = null;
    _pendingRequests = [];
    _hardwareDeviceId = null;
    _rejected = false;
    _serverMaintenance = false;
    _statusMessage = null;
    _initialized = false;
    _initFuture = null;
    ApiService.instance.setHardwareDeviceId(null);
    notifyListeners();
  }

  static void wireSignOutBridge(DeviceApprovalProvider p) {
    DeviceSessionBridge.registerOnSignOut(p.reset);
  }
}
