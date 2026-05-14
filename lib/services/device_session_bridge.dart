/// Called from [AuthProvider.signOut] so device/socket state clears without a Provider cycle.
class DeviceSessionBridge {
  static void Function()? onSignOut;

  static void notifySignedOut() {
    onSignOut?.call();
  }
}
