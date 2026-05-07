import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/remote_config.dart';
import '../services/remote_config_service.dart';

class RemoteConfigProvider extends ChangeNotifier {
  RemoteConfig _config = const RemoteConfig();
  StreamSubscription<RemoteConfig>? _sub;

  RemoteConfig get config => _config;

  void startListening() {
    _sub = RemoteConfigService.instance.configStream().listen((cfg) {
      _config = cfg;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
