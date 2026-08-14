import 'package:cloud_firestore/cloud_firestore.dart';

/// طريقة إيداع الرصيد في المحفظة.
enum WalletDepositMethod {
  cash,
  deferred,
  online,
}

extension WalletDepositMethodLabels on WalletDepositMethod {
  String get id => name;

  String get labelAr => switch (this) {
        WalletDepositMethod.cash => 'نقدي',
        WalletDepositMethod.deferred => 'آجل',
        WalletDepositMethod.online => 'أونلاين',
      };

  static WalletDepositMethod? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    for (final value in WalletDepositMethod.values) {
      if (value.name == raw) return value;
    }
    return null;
  }

  static WalletDepositMethod fromId(String? raw) {
    return tryParse(raw) ?? WalletDepositMethod.cash;
  }
}

class WalletTransaction {
  const WalletTransaction({
    required this.id,
    required this.userId,
    required this.type,
    required this.amount,
    required this.balanceAfter,
    required this.reason,
    required this.createdAt,
    this.orderId,
    this.companyName,
    this.visibleToUser = true,
    this.depositMethod,
  });

  final String id;
  final String userId;
  final String type;
  final double amount;
  final double balanceAfter;
  final String reason;
  final DateTime createdAt;
  final String? orderId;
  final String? companyName;
  final bool visibleToUser;
  /// للإيداع فقط: cash | deferred | online
  final WalletDepositMethod? depositMethod;

  bool get isCredit => type == 'credit';

  String? get depositMethodLabel => depositMethod?.labelAr;

  factory WalletTransaction.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? {};
    return WalletTransaction(
      id: doc.id,
      userId: d['userId'] ?? '',
      type: d['type'] ?? 'debit',
      amount: (d['amount'] ?? 0).toDouble(),
      balanceAfter: (d['balanceAfter'] ?? 0).toDouble(),
      reason: d['reason'] ?? '',
      orderId: d['orderId'],
      companyName: d['companyName'],
      visibleToUser: d['visibleToUser'] ?? true,
      depositMethod: WalletDepositMethodLabels.tryParse(
        d['depositMethod']?.toString(),
      ),
      createdAt: d['createdAt'] is Timestamp
          ? (d['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'userId': userId,
        'type': type,
        'amount': amount,
        'balanceAfter': balanceAfter,
        'reason': reason,
        'createdAt': Timestamp.fromDate(createdAt),
        if (orderId != null) 'orderId': orderId,
        if (companyName != null) 'companyName': companyName,
        'visibleToUser': visibleToUser,
        if (depositMethod != null) 'depositMethod': depositMethod!.id,
      };
}
