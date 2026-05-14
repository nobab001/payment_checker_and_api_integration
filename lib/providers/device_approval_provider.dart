import 'dart:async';

import 'package:android_id/android_id.dart';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as sio;

import '../models/device_model.dart';
import '../services/api_service.dart';
import '../services/device_session_bridge.dart';

/// Master–slave device flow: first device is parent + active; others start `pending`
/// until the parent approves (REST + Socket.io `device:activated`).
class DeviceApprovalProvider extends ChangeNotifier {
  String? _hardwareDeviceId;
  DeviceModel? _thisDevice;
  sio.Socket? _socket;
  Timer? _pollTimer;
  bool _initializing = false;
  bool _initialized = false;
  bool _rejected = false;

  String? get hardwareDeviceId => _hardwareDeviceId;
  DeviceModel? get thisDevice => _thisDevice;

  bool get isAwaitingApproval =>
      _thisDevice != null && _thisDevice!.isPending && !_rejected;

  bool get isParent =>
      _thisDevice != null &&
      _thisDevice!.isParent &&
      _thisDevice!.isActiveDevice;

  bool get registrationRejected => _rejected;

  bool get hasSession => _thisDevice != null;

  Future<void> ensureInitialized() async {
    if (_initializing || _initialized) return;
    if (kIsWeb) {
      _initialized = true;
      notifyListeners();
      return;
    }
    _initializing = true;
    notifyListeners();
    try {
      final token = ApiService.instance.authToken;
      if (token == null || token.isEmpty) {
        _initialized = true;
        return;
      }
      final hw = await const AndroidId().getId();
      if (hw == null || hw.isEmpty) {
        _initialized = true;
        return;
      }
      _hardwareDeviceId = hw;
      ApiService.instance.setHardwareDeviceId(hw);
      var device = await ApiService.instance.registerDevice(hw, 'My Phone');
      device ??= await ApiService.instance.fetchDeviceSelf(hw);
      _thisDevice = device;
      _rejected = false;
      _connectSocket(token, hw);
      _startPollingIfPending();
      _initialized = true;
    } catch (_) {
      _initialized = true;
    } finally {
      _initializing = false;
      notifyListeners();
    }
  }

  void _startPollingIfPending() {
    _pollTimer?.cancel();
    if (_hardwareDeviceId == null) return;
    if (!isAwaitingApproval) return;
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) => _pollSelf());
  }

  Future<void> _pollSelf() async {
    final hw = _hardwareDeviceId;
    if (hw == null) return;
    try {
      final d = await ApiService.instance.fetchDeviceSelf(hw);
      if (d != null && !d.isPending) {
        _thisDevice = d;
        _pollTimer?.cancel();
        _pollTimer = null;
        notifyListeners();
      }
    } catch (_) {}
  }

  void _connectSocket(String token, String hw) {
    _socket?.disconnect();
    _socket?.dispose();
    final base = ApiService.instance.resolvedApiBase;
    final socket = sio.io(
      base,
      sio.OptionBuilder()
          .setTransports(['websocket'])
          .enableAutoConnect()
          .setAuth({'token': token, 'deviceId': hw})
          .build(),
    );
    _socket = socket;
    socket.on('device:activated', (data) {
      final map = _asStringKeyedMap(data);
      final dev = map?['device'];
      if (dev is Map) {
        final d = DeviceModel.fromJson(Map<String, dynamic>.from(dev));
        if (d.id == _thisDevice?.id) {
          _thisDevice = d;
          _pollTimer?.cancel();
          _pollTimer = null;
          notifyListeners();
        }
      }
    });
    socket.on('device:rejected', (data) {
      final map = _asStringKeyedMap(data);
      final rid = map?['deviceId'];
      final pendingId = rid == null ? null : int.tryParse(rid.toString());
      if (pendingId != null &&
          _thisDevice != null &&
          pendingId == _thisDevice!.id) {
        _rejected = true;
        _pollTimer?.cancel();
        _pollTimer = null;
        notifyListeners();
      }
    });
    socket.on('device:approval_request', (_) => notifyListeners());
    socket.on('device:parent_role_changed', (_) => _refreshSelfQuiet());
  }

  Future<void> _refreshSelfQuiet() async {
    final hw = _hardwareDeviceId;
    if (hw == null) return;
    try {
      final d = await ApiService.instance.fetchDeviceSelf(hw);
      if (d != null) {
        _thisDevice = d;
        notifyListeners();
      }
    } catch (_) {}
  }

  /// After parent transfer (or other server-side role changes), refresh this handset row.
  Future<void> refreshThisDeviceFromServer() async {
    await _refreshSelfQuiet();
  }

  Map<String, dynamic>? _asStringKeyedMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }

  void reset() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _thisDevice = null;
    _hardwareDeviceId = null;
    _rejected = false;
    _initialized = false;
    _initializing = false;
    ApiService.instance.setHardwareDeviceId(null);
    notifyListeners();
  }

  static void wireSignOutBridge(DeviceApprovalProvider p) {
    DeviceSessionBridge.onSignOut = p.reset;
  }
}
