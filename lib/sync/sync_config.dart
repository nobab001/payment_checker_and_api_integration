import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

enum DeviceMode { none, main, sub }

class SyncConfig {
  final DeviceMode mode;
  final String mainDeviceIp;
  final int port;

  const SyncConfig({
    this.mode = DeviceMode.none,
    this.mainDeviceIp = '',
    this.port = 7890,
  });

  SyncConfig copyWith({
    DeviceMode? mode,
    String? mainDeviceIp,
    int? port,
  }) =>
      SyncConfig(
        mode: mode ?? this.mode,
        mainDeviceIp: mainDeviceIp ?? this.mainDeviceIp,
        port: port ?? this.port,
      );

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'mainDeviceIp': mainDeviceIp,
        'port': port,
      };

  factory SyncConfig.fromJson(Map<String, dynamic> j) => SyncConfig(
        mode: DeviceMode.values.firstWhere(
          (e) => e.name == j['mode'],
          orElse: () => DeviceMode.none,
        ),
        mainDeviceIp: (j['mainDeviceIp'] as String?) ?? '',
        port: (j['port'] as num?)?.toInt() ?? 7890,
      );

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/sync_config.json');
  }

  static Future<SyncConfig> load() async {
    try {
      final f = await _file();
      if (!f.existsSync()) return const SyncConfig();
      final raw = f.readAsStringSync().trim();
      if (raw.isEmpty) return const SyncConfig();
      return SyncConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const SyncConfig();
    }
  }

  Future<void> save() async {
    final f = await _file();
    f.writeAsStringSync(jsonEncode(toJson()));
  }
}
