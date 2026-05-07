import 'api_service.dart';

class WalletTopUpStart {
  final String bkashURL;
  final String paymentID;
  final String pendingId;

  const WalletTopUpStart({
    required this.bkashURL,
    required this.paymentID,
    required this.pendingId,
  });
}

/// bKash checkout and wallet / subscription updates via VPS HTTP API.
class PaymentService {
  PaymentService._();
  static final PaymentService instance = PaymentService._();

  Future<WalletTopUpStart> startWalletTopUp(double amount) async {
    final data = await ApiService.instance.startWalletTopUp(amount);
    final url = data['bkashURL'] as String? ??
        data['bkashUrl'] as String? ??
        data['checkoutUrl'] as String? ??
        '';
    if (url.isEmpty) {
      throw Exception('No checkout URL returned');
    }
    return WalletTopUpStart(
      bkashURL: url,
      paymentID: data['paymentID'] as String? ?? data['paymentId'] as String? ?? '',
      pendingId: data['pendingId'] as String? ?? '',
    );
  }

  Future<void> completeWalletTopUp({
    required String pendingId,
    required String paymentID,
  }) async {
    await ApiService.instance.completeWalletTopUp(
      pendingId: pendingId,
      paymentID: paymentID,
    );
  }

  Future<void> purchaseHistorySubscription(String planId) async {
    await ApiService.instance.purchaseHistorySubscription(planId);
  }
}
