import 'package:cloud_firestore/cloud_firestore.dart';

class WalletTopup {
  const WalletTopup({
    required this.id,
    required this.userId,
    required this.requestedAmount,
    required this.feeAmount,
    required this.chargedAmount,
    required this.currency,
    required this.dnzPaymentId,
    required this.checkoutUrl,
    required this.status,
    required this.createdAt,
    this.creditedAt,
    this.provider = 'dnz',
    this.zainTransactionId = '',
  });

  final String id;
  final String userId;
  final double requestedAmount;
  final double feeAmount;
  final double chargedAmount;
  final String currency;
  final String dnzPaymentId;
  final String checkoutUrl;
  final String status;
  final DateTime createdAt;
  final DateTime? creditedAt;
  /// `dnz` أو `zaincash`.
  final String provider;
  final String zainTransactionId;

  bool get isPending => status == 'pending';
  bool get isSuccess => status == 'success';
  bool get isFailed => status == 'failed';
  bool get credited => creditedAt != null;
  bool get isZainCash => provider == 'zaincash';

  factory WalletTopup.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? {};
    return WalletTopup(
      id: doc.id,
      userId: d['userId'] ?? '',
      requestedAmount: (d['requestedAmount'] ?? 0).toDouble(),
      feeAmount: (d['feeAmount'] ?? 0).toDouble(),
      chargedAmount: (d['chargedAmount'] ?? 0).toDouble(),
      currency: d['currency'] ?? 'IQD',
      dnzPaymentId: d['dnzPaymentId'] ?? '',
      checkoutUrl: d['checkoutUrl'] ?? '',
      status: d['status'] ?? 'pending',
      createdAt: d['createdAt'] is Timestamp
          ? (d['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      creditedAt: d['creditedAt'] is Timestamp
          ? (d['creditedAt'] as Timestamp).toDate()
          : null,
      provider: d['provider']?.toString() ?? 'dnz',
      zainTransactionId: d['zainTransactionId']?.toString() ?? '',
    );
  }

  factory WalletTopup.fromFunction(Map<String, dynamic> data) {
    return WalletTopup(
      id: data['topupId']?.toString() ?? '',
      userId: '',
      requestedAmount: (data['requestedAmount'] as num?)?.toDouble() ?? 0,
      feeAmount: (data['feeAmount'] as num?)?.toDouble() ?? 0,
      chargedAmount: (data['chargedAmount'] as num?)?.toDouble() ?? 0,
      currency: 'IQD',
      dnzPaymentId: data['dnzPaymentId']?.toString() ?? '',
      checkoutUrl: data['checkoutUrl']?.toString() ?? '',
      status: data['status']?.toString() ?? 'pending',
      createdAt: DateTime.now(),
      provider: data['provider']?.toString() ?? 'dnz',
      zainTransactionId: data['zainTransactionId']?.toString() ?? '',
    );
  }
}
