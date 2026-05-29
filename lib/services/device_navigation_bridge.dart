/// Opens a [HomeScreen] tab without [BuildContext] (e.g. deep link later).
class DeviceNavigationBridge {
  DeviceNavigationBridge._();

  /// `0` = Dashboard, `1` = Profile, `2` = Devices.
  static void Function(int tabIndex)? openTab;

  /// Parent should reload device list (e.g. new pending child).
  static void Function()? refreshDevicesList;
}
