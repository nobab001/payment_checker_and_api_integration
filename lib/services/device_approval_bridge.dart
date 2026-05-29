/// Callbacks for device approval flow without Provider cycles.
class DeviceApprovalBridge {
  DeviceApprovalBridge._();

  /// Called when VPS reports this handset was rejected — clear session.
  static void Function()? onRejectedMustSignOut;
}
