import 'package:android_id/android_id.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import '../services/api_service.dart';
import '../providers/device_approval_provider.dart';

/// Restores parent role on **this phone** using account PIN and/or server recovery key.
Future<String?> recoverParentOnThisDevice({
  String? recoveryKey,
  required String accountPin,
  String? targetDeviceModel,
  int? targetDeviceRowId,
  bool targetThisPhone = true,
}) async {
  final pin = accountPin.trim();
  final key = (recoveryKey ?? '').trim();
  if (pin.isEmpty && key.isEmpty) {
    return 'Account security PIN or recovery key is required';
  }

  final body = <String, dynamic>{};

  if (targetDeviceRowId != null && targetDeviceRowId > 0) {
    body['target_device_id'] = targetDeviceRowId;
  } else if (targetThisPhone && !kIsWeb) {
    body['target_self'] = true;
    var hw = ApiService.instance.hardwareDeviceId;
    if (hw == null || hw.isEmpty) {
      hw = await const AndroidId().getId();
    }
    if (hw != null && hw.isNotEmpty) {
      body['target_hardware_id'] = hw;
      ApiService.instance.setHardwareDeviceId(hw);
      try {
        final android = await DeviceInfoPlugin().androidInfo;
        final brand = android.brand.trim();
        final model = android.model.trim();
        body['device_model'] = brand.isNotEmpty && model.isNotEmpty
            ? '$brand $model'
            : (model.isNotEmpty ? model : android.device.trim());
      } catch (_) {}
    }
  } else {
    final model = (targetDeviceModel ?? '').trim();
    if (model.isEmpty) {
      return 'Could not detect this phone. Enter device model (e.g. MT2111).';
    }
    body['target_device_model'] = model;
  }

  try {
    final res = await ApiService.instance.reassignParentEmergency(
      body: body,
      recoveryKey: key.isEmpty ? null : key,
      accountPin: pin.isEmpty ? null : pin,
    );
    if (res['success'] != true) {
      final msg = res['message']?.toString() ?? 'Recovery failed';
      final devices = res['devices'];
      if (devices is List && devices.isNotEmpty) {
        final lines = devices.take(5).map((d) {
          if (d is Map) {
            return '• id=${d['id']} model=${d['device_model']} status=${d['status']}';
          }
          return '• $d';
        });
        return '$msg\nRegistered devices:\n${lines.join('\n')}';
      }
      return msg;
    }
    return null;
  } catch (e) {
    final msg = ApiService.friendlyErrorMessage(e);
    if (msg.toLowerCase() == 'not found' || msg.contains('Not found')) {
      return 'API not found on server. Deploy latest server code and restart, '
          'or use MySQL: server/scripts/reassign-parent.sql';
    }
    return msg;
  }
}

Future<void> refreshDeviceApprovalAfterRecovery(DeviceApprovalProvider dev) async {
  dev.reset();
  await dev.ensureInitialized();
}
