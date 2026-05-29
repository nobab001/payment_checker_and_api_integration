import 'device_model.dart';

/// Result of [GET /api/check-device-status] (VPS polling).
class DeviceStatusResult {
  final bool success;
  /// `pending` | `approved` | `rejected` | `unknown`
  final String status;
  final DeviceModel? device;
  final bool serverMaintenance;
  final String? message;

  const DeviceStatusResult({
    required this.success,
    required this.status,
    this.device,
    this.serverMaintenance = false,
    this.message,
  });

  bool get isApproved => status == 'approved' || status == 'active';
  bool get isPending => status == 'pending';
  bool get isRejected => status == 'rejected';
}
