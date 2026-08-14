import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../models/wallet_transaction.dart';

class WalletService {
  WalletService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  Stream<List<WalletTransaction>> watchTransactions(String userId) {
    return _db
        .collection('wallet_transactions')
        .where('userId', isEqualTo: userId)
        .limit(100)
        .snapshots()
        .map((s) {
          final list = s.docs.map(WalletTransaction.fromFirestore).toList()
            ..removeWhere((transaction) => !transaction.visibleToUser)
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list;
        });
  }

  /// كل المعاملات بما فيها المخفية — لشاشة إدارة المحافظ.
  Stream<List<WalletTransaction>> watchTransactionsForAdmin(String userId) {
    return _db
        .collection('wallet_transactions')
        .where('userId', isEqualTo: userId)
        .limit(80)
        .snapshots()
        .map((s) {
          final list = s.docs.map(WalletTransaction.fromFirestore).toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list;
        });
  }

  /// مجموع إيداعات «آجل» لكل مستخدم (من بيانات المعاملات الحقيقية).
  Stream<Map<String, double>> watchDeferredDepositTotalsByUser() {
    return _db
        .collection('wallet_transactions')
        .where('type', isEqualTo: 'credit')
        .snapshots()
        .map((s) {
          final totals = <String, double>{};
          for (final doc in s.docs) {
            try {
              final tx = WalletTransaction.fromFirestore(doc);
              if (tx.depositMethod != WalletDepositMethod.deferred) continue;
              if (tx.userId.isEmpty) continue;
              totals[tx.userId] = (totals[tx.userId] ?? 0) + tx.amount;
            } catch (_) {}
          }
          return totals;
        });
  }

  /// مجموع إيداعات «آجل» لمستخدم واحد (ما عليه من دين آجل).
  Stream<double> watchDeferredDepositTotal(String userId) {
    return _db
        .collection('wallet_transactions')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((s) {
          var total = 0.0;
          for (final doc in s.docs) {
            try {
              final tx = WalletTransaction.fromFirestore(doc);
              if (tx.type != 'credit') continue;
              if (tx.depositMethod != WalletDepositMethod.deferred) continue;
              total += tx.amount;
            } catch (_) {}
          }
          return total;
        });
  }

  Future<void> adminAdjust({
    required String userId,
    required double amount,
    required String type,
    required String reason,
    bool hideFromUser = false,
    WalletDepositMethod? depositMethod,
  }) async {
    if (amount <= 0) throw ArgumentError('المبلغ يجب أن يكون أكبر من صفر');
    if (type != 'credit' && type != 'debit') {
      throw ArgumentError('نوع العملية غير صالح');
    }

    final method = type == 'credit'
        ? (depositMethod ?? WalletDepositMethod.cash)
        : null;

    final userRef = _db.collection('users').doc(userId);
    final txRef = _db.collection('wallet_transactions').doc(const Uuid().v4());

    var deferredFallback = 0.0;
    if (type == 'credit' && method == WalletDepositMethod.deferred) {
      final pre = await userRef.get();
      if (pre.data()?['deferredOwed'] == null) {
        deferredFallback = await watchDeferredDepositTotal(userId).first;
      }
    }

    await _db.runTransaction((tx) async {
      final snap = await tx.get(userRef);
      if (!snap.exists) throw StateError('المستخدم غير موجود');
      final balance = (snap.data()?['walletBalance'] ?? 0).toDouble();
      final after = type == 'credit' ? balance + amount : balance - amount;
      if (after < 0) throw StateError('الرصيد غير كافٍ للخصم');

      final updates = <String, dynamic>{'walletBalance': after};
      if (type == 'credit' && method == WalletDepositMethod.deferred) {
        final stored = snap.data()?['deferredOwed'];
        final base = stored == null
            ? deferredFallback
            : (stored as num).toDouble();
        updates['deferredOwed'] = base + amount;
      }
      tx.update(userRef, updates);
      tx.set(
        txRef,
        WalletTransaction(
          id: txRef.id,
          userId: userId,
          type: type,
          amount: amount,
          balanceAfter: after,
          reason: reason,
          createdAt: DateTime.now(),
          visibleToUser: !hideFromUser,
          depositMethod: method,
        ).toFirestore(),
      );
    });
  }
}
