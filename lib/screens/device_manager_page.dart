import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:provider/provider.dart';

import '../models/device_model.dart';
import '../providers/device_approval_provider.dart';
import '../providers/remote_config_provider.dart';
import '../services/api_service.dart';
import '../services/device_navigation_bridge.dart';
import '../utils/constants.dart';
import '../widgets/security_pin_dialog.dart';
import 'device_settings_page.dart';

const Duration _kOnlineThreshold = Duration(minutes: 3);

bool deviceAppearsOnline(DeviceModel model) {
  final t = model.effectiveLastSync;
  if (t == null) return false;
  return DateTime.now().difference(t) <= _kOnlineThreshold;
}

bool _modelLooksLikeTablet(String? model) {
  final m = (model ?? '').toLowerCase();
  if (m.isEmpty) return false;
  return m.contains('tablet') ||
      m.contains('ipad') ||
      m.contains('sm-t') ||
      m.contains('sm-p') ||
      m.contains('tab ') ||
      m.contains(' lenovo tab') ||
      m.contains('nexus 7') ||
      m.contains('nexus 9') ||
      m.contains('pixel c') ||
      m.contains(' mediapad');
}

IconData deviceTypeIcon(DeviceModel d) =>
    _modelLooksLikeTablet(d.deviceModel) ? Icons.tablet_android_rounded : Icons.smartphone_rounded;

String formatLastActive(DateTime? t) {
  if (t == null) return 'Last active: unknown';
  final diff = DateTime.now().difference(t);
  if (diff.inSeconds < 45) return 'Last active: just now';
  if (diff.inMinutes < 60) return 'Last active: ${diff.inMinutes} min ago';
  if (diff.inHours < 24) return 'Last active: ${diff.inHours} h ago';
  if (diff.inDays < 14) return 'Last active: ${diff.inDays} d ago';
  return 'Last active: ${t.toLocal().toString().split(' ').first}';
}

String deviceConnectionStatus(DeviceModel d, bool online) {
  if (d.isPending) return 'Pending';
  if (online) return 'Online';
  return 'Offline';
}

Color statusColor(String status) {
  switch (status) {
    case 'Online':
      return Colors.green.shade700;
    case 'Pending':
      return Colors.orange.shade800;
    default:
      return Colors.grey.shade600;
  }
}

class DeviceManagerPage extends StatefulWidget {
  const DeviceManagerPage({super.key});

  @override
  State<DeviceManagerPage> createState() => _DeviceManagerPageState();
}

class _DeviceManagerPageState extends State<DeviceManagerPage> with WidgetsBindingObserver {
  final Battery _battery = Battery();

  List<DeviceModel> _devices = [];
  bool _loading = true;
  String? _error;
  bool _showOfflineBanner = false;
  DeviceApprovalProvider? _deviceApproval;
  late void Function() _approvalListener;

  Timer? _heartbeatTimer;
  Timer? _debouncedReload;
  int? _localBatteryPercent;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _approvalListener = () {
      if (mounted) _scheduleDevicesReload();
    };
    DeviceNavigationBridge.refreshDevicesList = () {
      if (mounted) _loadDevices(showSpinner: false);
    };
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _deviceApproval = context.read<DeviceApprovalProvider>();
      _deviceApproval!.addListener(_approvalListener);
      await _deviceApproval!.ensureInitialized();
      if (!mounted) return;
      unawaited(_deviceApproval!.refreshPendingRequests());
      if (!mounted) return;
      await _loadDevices(showSpinner: true);
      if (!mounted) return;
      _maybeShowPendingRequestSnack();
      if (!mounted) return;
      _startHeartbeat();
      _refreshLocalBattery();
    });
  }

  void _maybeShowPendingRequestSnack() {
    final pending = _deviceApproval?.pendingRequests ?? [];
    if (pending.isEmpty || !(_deviceApproval?.isParent ?? false)) {
      return;
    }
    if (!mounted) return;
    final first = pending.first;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          pending.length == 1
              ? 'নতুন ডিভাইস: ${first.displayDeviceName} — অনুমোদন প্রয়োজন'
              : '${pending.length}টি ডিভাইস অনুমোদনের অপেক্ষায়',
        ),
        action: SnackBarAction(
          label: 'দেখুন',
          onPressed: () => _loadDevices(showSpinner: true),
        ),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  void _scheduleDevicesReload() {
    if (!mounted) return;
    _debouncedReload?.cancel();
    _debouncedReload = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      _loadDevices(showSpinner: false);
      _maybeShowPendingRequestSnack();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heartbeatTimer?.cancel();
    _debouncedReload?.cancel();
    _deviceApproval?.removeListener(_approvalListener);
    if (DeviceNavigationBridge.refreshDevicesList != null) {
      DeviceNavigationBridge.refreshDevicesList = null;
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshLocalBattery();
      _pingHeartbeat();
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 90), (_) => _pingHeartbeat());
    _pingHeartbeat();
  }

  Future<void> _refreshLocalBattery() async {
    if (kIsWeb) return;
    try {
      final level = await _battery.batteryLevel;
      if (mounted) setState(() => _localBatteryPercent = level);
    } catch (_) {}
  }

  Future<void> _pingHeartbeat() async {
    if (!mounted) return;
    final devProv = context.read<DeviceApprovalProvider>();
    final api = ApiService.instance;
    int? bat = _localBatteryPercent;
    if (bat == null && !kIsWeb) {
      try {
        bat = await _battery.batteryLevel;
      } catch (_) {}
    }
    try {
      await api.postDeviceHeartbeat(batteryPercent: bat);
      if (!mounted) return;
      final hw = _myHardwareId(devProv);
      if (hw != null) {
        await api.syncDeviceSettingsToCache(hardwareDeviceId: hw);
      }
      if (mounted) await _loadDevices(showSpinner: false);
    } catch (_) {}
  }

  String? _myHardwareId(DeviceApprovalProvider devProv) {
    final h = devProv.hardwareDeviceId;
    if (h != null && h.isNotEmpty) return h;
    final t = devProv.thisDevice?.deviceId;
    if (t != null && t.isNotEmpty) return t;
    return null;
  }

  bool _isSelf(DeviceModel d, DeviceApprovalProvider devProv) {
    final id = _myHardwareId(devProv);
    return id != null && d.deviceId == id;
  }

  DeviceModel? _parentDevice(List<DeviceModel> list) {
    for (final d in list) {
      if (d.isParent) return d;
    }
    return list.isNotEmpty ? list.first : null;
  }

  List<DeviceModel> _connectedDevices(List<DeviceModel> list, DeviceModel? parent) {
    if (parent == null) return List<DeviceModel>.from(list);
    return list.where((d) => d.id != parent.id).toList();
  }

  /// Ensures [local] from [DeviceApprovalProvider] appears in the server list.
  List<DeviceModel> _mergeLocalDevice(
    List<DeviceModel> serverList,
    DeviceModel? local,
  ) {
    if (local == null || local.deviceId.isEmpty) return serverList;
    final hasLocal = serverList.any((d) => d.deviceId == local.deviceId);
    if (hasLocal) return serverList;
    return [...serverList, local];
  }

  Future<void> _loadDevices({bool showSpinner = false}) async {
    if (!mounted) return;
    if (showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    List<DeviceModel>? nextDevices;
    String? nextError;

    try {
      final res = await ApiService.instance.fetchDevices();
      if (!mounted) return;
      if (res['success'] == true) {
        final raw = res['devices'];
        final list = raw is List ? raw : const <dynamic>[];
        final built = <DeviceModel>[];
        for (final d in list) {
          if (d is Map<String, dynamic>) {
            built.add(DeviceModel.fromJson(d));
          } else if (d is Map) {
            built.add(DeviceModel.fromJson(Map<String, dynamic>.from(d)));
          }
        }
        nextDevices = _mergeLocalDevice(built, _deviceApproval?.thisDevice);
        if (nextDevices.isEmpty && _deviceApproval != null) {
          await _deviceApproval!.ensureInitialized();
          final local = _deviceApproval!.thisDevice;
          if (local != null) {
            nextDevices = [local];
          }
        }
      } else {
        nextError = res['message']?.toString() ?? 'ডিভাইস তালিকা লোড করা যায়নি';
      }
    } catch (e) {
      if (!mounted) return;
      nextError = ApiService.friendlyErrorMessage(e);
      final local = _deviceApproval?.thisDevice;
      if (local != null) {
        nextDevices = [local];
      }
    }

    if (!mounted) return;
    setState(() {
      if (nextDevices != null) {
        _devices = nextDevices;
        if (nextError == null) {
          _error = null;
          _showOfflineBanner = false;
        } else {
          _showOfflineBanner = true;
          _error = nextError;
        }
      } else if (nextError != null) {
        _error = nextError;
        _showOfflineBanner = false;
      }
      if (showSpinner) _loading = false;
    });
  }

  bool _canManagePendingDevices(DeviceApprovalProvider devProv) {
    if (devProv.isParent) return true;
    return devProv.thisDevice != null;
  }

  Future<String?> _securityPinForNonParent(DeviceApprovalProvider devProv) async {
    if (devProv.isParent) return '';
    return promptAccountSecurityPin(
      context,
      title: 'ডিভাইস অনুমোদন',
      message: 'চাইল্ড ডিভাইস থেকে অনুমোদন দিতে অ্যাকাউন্টের Security PIN দিন।',
    );
  }

  Future<void> _approvePending(DeviceModel pending) async {
    final devProv = context.read<DeviceApprovalProvider>();
    if (!_canManagePendingDevices(devProv)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('এই ডিভাইস এখনও অনুমোদিত নয়')),
      );
      return;
    }
    final pin = await _securityPinForNonParent(devProv);
    if (!devProv.isParent && (pin == null || pin.isEmpty)) return;
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ApiService.instance.approveDevice(
        pending.id,
        securityPin: devProv.isParent ? null : pin,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('${pending.displayDeviceName} অনুমোদিত হয়েছে')),
      );
      await _loadDevices(showSpinner: false);
      unawaited(devProv.refreshPendingRequests());
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(ApiService.friendlyErrorMessage(e))),
        );
      }
    }
  }

  Future<void> _rejectPending(DeviceModel pending) async {
    final devProv = context.read<DeviceApprovalProvider>();
    if (!_canManagePendingDevices(devProv)) return;
    final pin = await _securityPinForNonParent(devProv);
    if (!devProv.isParent && (pin == null || pin.isEmpty)) return;
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ApiService.instance.rejectDevice(
        pending.id,
        securityPin: devProv.isParent ? null : pin,
      );
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Device rejected')));
      await _loadDevices(showSpinner: false);
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(ApiService.friendlyErrorMessage(e))),
        );
      }
    }
  }

  Future<void> _transferParent(DeviceModel target) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Transfer parent role'),
        content: Text(
          'Make "${target.displayDeviceName}" the parent device? You will lose parent-only actions on this phone until it is transferred back.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Transfer')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final devProv = context.read<DeviceApprovalProvider>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ApiService.instance.transferParentRole(target.id);
      if (!mounted) return;
      await devProv.refreshThisDeviceFromServer();
      messenger.showSnackBar(const SnackBar(content: Text('Parent role updated')));
      await _loadDevices(showSpinner: false);
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text('Transfer failed: $e')));
    }
  }

  Future<void> _renameDevice(DeviceModel device) async {
    final controller = TextEditingController(text: device.displayDeviceName);
    String? submitted;
    try {
      submitted = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Rename device'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 255,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Display name',
              hintText: 'Leave empty to use model name',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => Navigator.pop(ctx, controller.text.trim()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
    if (!mounted || submitted == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await ApiService.instance.updateDeviceName(deviceId: device.id, newName: submitted);
      if (!mounted) return;
      if (res['success'] == true && res['device'] is Map<String, dynamic>) {
        final updated = DeviceModel.fromJson(res['device'] as Map<String, dynamic>);
        setState(() {
          final ix = _devices.indexWhere((e) => e.id == updated.id);
          if (ix >= 0) _devices[ix] = updated;
        });
        messenger.showSnackBar(const SnackBar(content: Text('Name updated')));
      } else {
        messenger.showSnackBar(SnackBar(content: Text(res['message']?.toString() ?? 'Update failed')));
      }
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text('Update failed: $e')));
    }
  }

  Future<void> _remoteLogoutDevice(DeviceModel device) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out this device?'),
        content: Text(
          '"${device.displayDeviceName}" will be removed from this account. '
          'That phone must sign in again to use the app.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log out device'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ApiService.instance.deleteJson('/api/devices/${device.id}', auth: true);
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Device removed from account')));
      await _loadDevices(showSpinner: false);
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final devProv = context.watch<DeviceApprovalProvider>();
    final rc = context.watch<RemoteConfigProvider>().config;
    final primary = AppColors.primary;

    if (_loading && _devices.isEmpty) {
      return Center(
        child: SpinKitFadingCircle(color: primary, size: 48),
      );
    }

    if (_error != null && _devices.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_off_outlined, size: 48, color: Colors.grey.shade500),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, height: 1.4),
              ),
              const SizedBox(height: 8),
              Text(
                'API: ${ApiService.instance.resolvedApiBase}',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade700, height: 1.35),
              ),
              const SizedBox(height: 6),
              Text(
                '১) START-SERVER.bat চালান (এই উইন্ডো খোলা রাখুন)\n'
                '২) ফোন ও PC একই Wi‑Fi-তে আছে কিনা দেখুন\n'
                '৩) সংযোগ না হলে ALLOW-FIREWALL.bat Administrator হিসেবে চালান',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.35),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _loadDevices(showSpinner: true),
                icon: const Icon(Icons.refresh),
                label: const Text('আবার চেষ্টা করুন'),
              ),
            ],
          ),
        ),
      );
    }

    if (_devices.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.devices, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text('No devices registered', style: TextStyle(fontSize: 16, color: Colors.grey.shade700)),
          ],
        ),
      );
    }

    final parent = _parentDevice(_devices);
    final connected = _connectedDevices(_devices, parent);
    int sortKey(DeviceModel a, DeviceModel b) {
      if (a.isPending != b.isPending) return a.isPending ? -1 : 1;
      return a.displayDeviceName.toLowerCase().compareTo(b.displayDeviceName.toLowerCase());
    }
    connected.sort(sortKey);

    final parentOnline = parent != null && deviceAppearsOnline(parent);
    final canRenameParent = parent != null && (devProv.isParent && _isSelf(parent, devProv));
    final canManagePending = _canManagePendingDevices(devProv);
    final pendingOthers = _devices
        .where((d) => d.isPending && !( _isSelf(d, devProv) && devProv.isAwaitingApproval))
        .toList();

    return Stack(
      children: [
        RefreshIndicator(
          color: primary,
          onRefresh: () async {
            await _refreshLocalBattery();
            await _pingHeartbeat();
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              if (_showOfflineBanner && _error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Material(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.wifi_off_rounded, color: Colors.orange.shade900, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _error!,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.orange.shade900,
                                    height: 1.35,
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => _loadDevices(showSpinner: true),
                                  child: const Text('রিফ্রেশ'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (!devProv.isParent && !rc.childApproveWithPin && pendingOthers.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Material(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Colors.red.shade800, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'আপনার সার্ভারে পুরোনো API চলছে — চাইল্ড ফোন থেকে পিন দিয়ে অনুমোদন কাজ করবে না। '
                              'VPS এ এই প্রজেক্টের সর্বশেষ `server/` ফোল্ডার আপডেট করে Node রিস্টার্ট করুন '
                              '(ফাইল: deviceApprovalAuth.js)।',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.red.shade900,
                                height: 1.38,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (pendingOthers.isNotEmpty && canManagePending) ...[
                _PendingApprovalBanner(
                  pendingDevices: pendingOthers,
                  needsPin: !devProv.isParent,
                  onApprove: _approvePending,
                  onReject: _rejectPending,
                ),
                const SizedBox(height: 16),
              ],
              if (parent != null) ...[
                Text(
                  'Parent Device',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade900,
                      ),
                ),
                const SizedBox(height: 10),
                _ParentDeviceCard(
                  device: parent,
                  isThisPhone: _isSelf(parent, devProv),
                  online: parentOnline,
                  statusLabel: deviceConnectionStatus(parent, parentOnline),
                  lastActiveText: formatLastActive(parent.effectiveLastSync),
                  onRename: canRenameParent ? () => _renameDevice(parent) : null,
                  onSettings: _isSelf(parent, devProv) && parent.isActiveDevice
                      ? () {
                          Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => DeviceSettingsPage(
                                device: parent,
                                onSaved: () => _loadDevices(showSpinner: false),
                              ),
                            ),
                          );
                        }
                      : null,
                ),
              ],
              const SizedBox(height: 24),
              Text(
                'Connected Devices',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade900,
                    ),
              ),
              const SizedBox(height: 10),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade300),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: connected.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
                        child: Row(
                          children: [
                            Icon(Icons.link_off_rounded, color: Colors.grey.shade600),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'No other devices linked to this account.',
                                style: TextStyle(color: Colors.grey.shade700, height: 1.35),
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: connected.length,
                        separatorBuilder: (context, index) =>
                            Divider(height: 1, color: Colors.grey.shade200),
                        itemBuilder: (context, i) {
                          final d = connected[i];
                          final online = deviceAppearsOnline(d);
                          final status = deviceConnectionStatus(d, online);
                          final showApprove = d.isPending &&
                              canManagePending &&
                              !(_isSelf(d, devProv) && devProv.isAwaitingApproval);
                          final showMakeParent =
                              devProv.isParent && !d.isParent && d.isActiveDevice;

                          return _ConnectedDeviceTile(
                            device: d,
                            isThisPhone: _isSelf(d, devProv),
                            statusLabel: status,
                            statusColor: statusColor(status),
                            lastActiveText: formatLastActive(d.effectiveLastSync),
                            batteryText: d.lastBatteryPercent != null ? '${d.lastBatteryPercent}%' : null,
                            onRename: () => _renameDevice(d),
                            onRemoteLogout: !d.isPending && devProv.isParent ? () => _remoteLogoutDevice(d) : null,
                            onStatusTap: showApprove ? () => _approvePending(d) : null,
                            statusTapHint: showApprove
                                ? (devProv.isParent
                                    ? 'ট্যাপ করে অনুমোদন'
                                    : 'ট্যাপ করে পিন দিয়ে অনুমোদন')
                                : null,
                            onApprove: showApprove ? () => _approvePending(d) : null,
                            onReject: showApprove ? () => _rejectPending(d) : null,
                            showMakeParent: showMakeParent,
                            onMakeParent: showMakeParent ? () => _transferParent(d) : null,
                            onSettings: d.isActiveDevice && (_isSelf(d, devProv) || devProv.isParent)
                                ? () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute<void>(
                                        builder: (_) => DeviceSettingsPage(
                                          device: d,
                                          remoteChildMode:
                                              devProv.isParent && !_isSelf(d, devProv),
                                          onSaved: () => _loadDevices(showSpinner: false),
                                        ),
                                      ),
                                    );
                                  }
                                : null,
                            awaitingParentHint: d.isPending && !devProv.isParent,
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        if (_loading && _devices.isNotEmpty)
          Positioned(
            top: 8,
            right: 16,
            child: SpinKitThreeBounce(color: primary, size: 22),
          ),
      ],
    );
  }
}

class _ParentDeviceCard extends StatelessWidget {
  final DeviceModel device;
  final bool isThisPhone;
  final bool online;
  final String statusLabel;
  final String lastActiveText;
  final VoidCallback? onRename;
  final VoidCallback? onSettings;

  const _ParentDeviceCard({
    required this.device,
    required this.isThisPhone,
    required this.online,
    required this.statusLabel,
    required this.lastActiveText,
    this.onRename,
    this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.primary;
    return Card(
      elevation: 4,
      shadowColor: primary.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: primary.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              primary.withValues(alpha: 0.08),
              Colors.white,
            ],
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.verified_user_rounded, color: primary, size: 32),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              device.displayDeviceName,
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                            ),
                          ),
                          _StatusChip(label: statusLabel, color: statusColor(statusLabel)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (device.deviceModel.isNotEmpty)
                        Text(
                          device.deviceModel,
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                        ),
                      if (isThisPhone)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'This phone',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: primary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(lastActiveText, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
            const SizedBox(height: 16),
            Row(
              children: [
                if (onRename != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onRename,
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      label: const Text('Rename'),
                    ),
                  ),
                if (onSettings != null) ...[
                  if (onRename != null) const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onSettings,
                      icon: const Icon(Icons.settings_outlined, size: 20),
                      style: FilledButton.styleFrom(backgroundColor: primary),
                      label: const Text('Settings'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingApprovalBanner extends StatelessWidget {
  final List<DeviceModel> pendingDevices;
  final bool needsPin;
  final void Function(DeviceModel) onApprove;
  final void Function(DeviceModel) onReject;

  const _PendingApprovalBanner({
    required this.pendingDevices,
    required this.needsPin,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.primary;
    return Material(
      color: Colors.orange.shade50,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.pending_actions, color: Colors.orange.shade900),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${pendingDevices.length}টি ডিভাইস অনুমোদনের অপেক্ষায়',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade900,
                    ),
                  ),
                ),
              ],
            ),
            if (needsPin)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'প্যারেন্ট ফোন নয় — Pending এ ট্যাপ করলে Security PIN লাগবে।',
                  style: TextStyle(fontSize: 12, color: Colors.orange.shade900, height: 1.35),
                ),
              ),
            const SizedBox(height: 10),
            ...pendingDevices.map(
              (d) => ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(deviceTypeIcon(d), color: primary),
                title: Text(d.displayDeviceName, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  d.deviceModel.isNotEmpty ? d.deviceModel : d.deviceId,
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: InkWell(
                  onTap: () => onApprove(d),
                  borderRadius: BorderRadius.circular(20),
                  child: _StatusChip(
                    label: 'Pending',
                    color: Colors.orange.shade800,
                    tappable: true,
                  ),
                ),
                onTap: () => onApprove(d),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectedDeviceTile extends StatelessWidget {
  final DeviceModel device;
  final bool isThisPhone;
  final String statusLabel;
  final Color statusColor;
  final String lastActiveText;
  final String? batteryText;
  final VoidCallback onRename;
  final VoidCallback? onRemoteLogout;
  final VoidCallback? onStatusTap;
  final String? statusTapHint;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final bool showMakeParent;
  final VoidCallback? onMakeParent;
  final VoidCallback? onSettings;
  final bool awaitingParentHint;

  const _ConnectedDeviceTile({
    required this.device,
    required this.isThisPhone,
    required this.statusLabel,
    required this.statusColor,
    required this.lastActiveText,
    this.batteryText,
    required this.onRename,
    this.onRemoteLogout,
    this.onStatusTap,
    this.statusTapHint,
    this.onApprove,
    this.onReject,
    this.showMakeParent = false,
    this.onMakeParent,
    this.onSettings,
    this.awaitingParentHint = false,
  });

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: primary.withValues(alpha: 0.1),
                child: Icon(deviceTypeIcon(device), color: primary, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.displayDeviceName,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    if (device.deviceModel.isNotEmpty)
                      Text(
                        device.deviceModel,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    if (isThisPhone)
                      Text(
                        'This phone',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: primary),
                      ),
                  ],
                ),
              ),
              _StatusChip(
                label: statusLabel,
                color: statusColor,
                onTap: onStatusTap,
              ),
              IconButton(
                onPressed: onRename,
                icon: const Icon(Icons.edit_outlined, size: 20),
                tooltip: 'Rename',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(lastActiveText, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          if (batteryText != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Battery: $batteryText',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ),
          if (statusTapHint != null) ...[
            const SizedBox(height: 6),
            Text(
              statusTapHint!,
              style: TextStyle(fontSize: 12, color: Colors.orange.shade800, fontWeight: FontWeight.w500),
            ),
          ],
          if (awaitingParentHint) ...[
            const SizedBox(height: 8),
            Text(
              'Waiting for the parent device to approve this sign-in.',
              style: TextStyle(fontSize: 12, color: Colors.orange.shade800, height: 1.35),
            ),
          ],
          if (onApprove != null && onReject != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton(onPressed: onApprove, child: const Text('Approve')),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(onPressed: onReject, child: const Text('Reject')),
                ),
              ],
            ),
          ],
          if (showMakeParent) ...[
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Make parent device'),
              value: false,
              onChanged: (_) => onMakeParent?.call(),
            ),
          ],
          if (onSettings != null) ...[
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onSettings,
                icon: const Icon(Icons.settings_outlined, size: 18),
                label: const Text('Device settings'),
              ),
            ),
          ],
          if (onRemoteLogout != null) ...[
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onRemoteLogout,
                icon: Icon(Icons.logout_rounded, size: 18, color: Colors.red.shade700),
                label: Text('Remote logout', style: TextStyle(color: Colors.red.shade700)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool tappable;

  const _StatusChip({
    required this.label,
    required this.color,
    this.onTap,
    this.tappable = false,
  });

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
    if (onTap == null && !tappable) return chip;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: chip,
      ),
    );
  }
}
