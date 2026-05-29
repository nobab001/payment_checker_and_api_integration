import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import 'background_payment_api_client.dart';
import 'payment_ingest_queue_service.dart';

/// Flushes offline payment ingest queue when network becomes available.
class PaymentIngestConnectivityWatcher {
  PaymentIngestConnectivityWatcher._();
  static final PaymentIngestConnectivityWatcher instance =
      PaymentIngestConnectivityWatcher._();

  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _wasOffline = true;
  bool _flushing = false;

  void start() {
    if (_sub != null) return;
    _sub = Connectivity().onConnectivityChanged.listen(_onChange);
    unawaited(_maybeFlush('startup'));
  }

  void stop() {
    unawaited(_sub?.cancel());
    _sub = null;
  }

  Future<void> _onChange(List<ConnectivityResult> results) async {
    final online = results.any((r) => r != ConnectivityResult.none);
    if (!online) {
      _wasOffline = true;
      return;
    }
    if (!_wasOffline) return;
    _wasOffline = false;
    await _maybeFlush('connectivity');
  }

  Future<void> _maybeFlush(String reason) async {
    if (_flushing) return;
    final pending = await PaymentIngestQueueService.instance.pendingCount();
    if (pending == 0) return;

    _flushing = true;
    try {
      final n = await BackgroundPaymentApiClient.instance.flushQueue();
      if (kDebugMode && n > 0) {
        debugPrint(
          '[PaymentIngestConnectivity] flushed $n ($reason)',
        );
      }
    } finally {
      _flushing = false;
    }
  }
}
