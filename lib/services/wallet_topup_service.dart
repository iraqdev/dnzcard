import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/wallet_topup.dart';
import 'functions_service.dart';

class WalletTopupService {
  WalletTopupService({
    FirebaseFirestore? db,
    FunctionsService? functions,
  })  : _db = db ?? FirebaseFirestore.instance,
        _functions = functions ?? FunctionsService();

  final FirebaseFirestore _db;
  final FunctionsService _functions;

  Future<WalletTopup> createTopup(int amountIqd) async {
    final data = await _functions.createWalletTopup(amount: amountIqd);
    return WalletTopup.fromFunction(data);
  }

  Future<WalletTopup> createZainCashTopup(int amountIqd) async {
    final data = await _functions.createZainCashTopup(amount: amountIqd);
    return WalletTopup.fromFunction(data);
  }

  /// إنشاء معاملة زين كاش على الخادم وإرجاع رابط الدفع.
  Future<Map<String, dynamic>> startZainCashPayment({
    required String topupId,
  }) {
    return _functions.startZainCashPayment(topupId: topupId);
  }

  Future<Map<String, dynamic>> registerZainCashTransaction({
    required String topupId,
    required String zainTransactionId,
    String? checkoutUrl,
  }) {
    return _functions.registerZainCashTransaction(
      topupId: topupId,
      zainTransactionId: zainTransactionId,
      checkoutUrl: checkoutUrl,
    );
  }

  Future<Map<String, dynamic>> completeZainCashTopup({
    required String topupId,
    String? zainTransactionId,
  }) {
    return _functions.completeZainCashTopup(
      topupId: topupId,
      zainTransactionId: zainTransactionId,
    );
  }

  Future<Map<String, dynamic>> checkStatus(String topupId) {
    return _functions.checkWalletTopupStatus(topupId: topupId);
  }

  Future<Map<String, dynamic>> reconcilePending() {
    return _functions.reconcilePendingWalletTopups();
  }

  Stream<List<WalletTopup>> watchRecent(String userId) {
    return _db
        .collection('wallet_topups')
        .where('userId', isEqualTo: userId)
        .limit(30)
        .snapshots()
        .map((s) {
      final list = s.docs.map(WalletTopup.fromFirestore).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }
}
