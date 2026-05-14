/// Payment / wallet model returned from the server.
class PaymentModel {
  final String? paymentId;
  final String? pendingId;
  final double? amount;
  final String? status;
  final DateTime? createdAt;

  const PaymentModel({
    this.paymentId,
    this.pendingId,
    this.amount,
    this.status,
    this.createdAt,
  });

  factory PaymentModel.fromJson(Map<String, dynamic> m) {
    return PaymentModel(
      paymentId: (m['paymentId'] ?? m['payment_id'] ?? m['paymentID'])
          ?.toString(),
      pendingId: (m['pendingId'] ?? m['pending_id'])?.toString(),
      amount: (m['amount'] is num)
          ? (m['amount'] as num).toDouble()
          : double.tryParse('${m['amount']}'),
      status: (m['status'] ?? m['state'])?.toString(),
      createdAt: m['createdAt'] != null || m['created_at'] != null
          ? DateTime.tryParse('${m['createdAt'] ?? m['created_at']}')
          : null,
    );
  }
}
