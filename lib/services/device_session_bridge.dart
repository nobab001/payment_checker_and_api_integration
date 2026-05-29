/// Called from [AuthProvider.signOut] so device/socket state clears without a Provider cycle.
class DeviceSessionBridge {
  static final List<void Function()> _onSignOut = [];

  /// Idempotent per callback reference — safe to call more than once for the same function.
  static void registerOnSignOut(void Function() cb) {
    if (_onSignOut.contains(cb)) return;
    _onSignOut.add(cb);
  }

  static void notifySignedOut() {
    for (final cb in List<void Function()>.from(_onSignOut)) {
      cb();
    }
  }
}
