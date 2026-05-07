import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/remote_config.dart';
import 'api_service.dart';

class RemoteConfigService {
  RemoteConfigService._();
  static final instance = RemoteConfigService._();

  static const _pollInterval = Duration(seconds: 90);

  /// Polls [ApiService.fetchRemoteConfig] on an interval (replaces Firestore snapshots).
  Stream<RemoteConfig> configStream() {
    final controller = StreamController<RemoteConfig>.broadcast();

    Future<void> tick() async {
      try {
        final cfg = await ApiService.instance.fetchRemoteConfig();
        controller.add(cfg);
        debugPrint('[RemoteConfig] fetched from VPS');
      } catch (e) {
        debugPrint('[RemoteConfig] fetch error: $e');
        controller.add(const RemoteConfig());
      }
    }

    Timer? timer;
    timer = Timer.periodic(_pollInterval, (_) => tick());
    // ignore: unawaited_futures
    tick();

    controller.onCancel = () {
      timer?.cancel();
      controller.close();
    };

    return controller.stream;
  }
}
