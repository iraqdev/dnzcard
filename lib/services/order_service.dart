import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/order_model.dart';
import 'card_bot_service.dart';
import 'asia_bot_service.dart';
import 'functions_service.dart';

class OrderService {
  OrderService({FirebaseFirestore? db, FunctionsService? functions})
    : _db = db ?? FirebaseFirestore.instance,
      _functions = functions ?? FunctionsService();
  final FirebaseFirestore _db;
  final FunctionsService _functions;

  Stream<List<OrderModel>> ordersForShop(String shopId) {
    return _db
        .collection('orders')
        .where('shopId', isEqualTo: shopId)
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots()
        .map((s) {
          final list = <OrderModel>[];
          for (final doc in s.docs) {
            try {
              list.add(OrderModel.fromFirestore(doc));
            } catch (_) {}
          }
          return list;
        });
  }

  Stream<List<OrderModel>> allOrders() {
    // ترتيب تنازلي ضروري: بدون orderBy يعيد Firestore 200 مستنداً
    // بترتيب غير مضمون وقد تختفي مشتريات اليوم إن تجاوز العدد 200.
    return _db
        .collection('orders')
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots()
        .map((s) {
          final list = <OrderModel>[];
          for (final doc in s.docs) {
            try {
              list.add(OrderModel.fromFirestore(doc));
            } catch (_) {}
          }
          return list;
        });
  }

  /// شراء منتج محلي عبر دالة سحابية ذرية (الخصم والطلب يتمّان على الخادم
  /// بصلاحية آمنة لا يمكن تزويرها من العميل).
  Future<OrderModel> purchaseProductViaServer({
    required String productId,
    int quantity = 1,
    String? pin,
  }) async {
    if (quantity < 1) {
      throw ArgumentError('الكمية غير صحيحة');
    }
    final data = await _functions.purchaseLocalProduct(
      productId: productId,
      quantity: quantity,
      pin: pin,
    );
    final orderId = data['orderId']?.toString() ?? '';
    if (orderId.isEmpty) {
      throw StateError('تعذر إنشاء الطلب');
    }
    final snap = await _db.collection('orders').doc(orderId).get();
    if (!snap.exists) {
      throw StateError('الطلب غير موجود بعد الشراء');
    }
    final order = OrderModel.fromFirestore(snap);
    // تعبئة تلقائية عبر بوت Baqaty / آسيا إن انخفض المخزون.
    unawaited(CardBotService().maybeRefillAfterSale(productId));
    unawaited(AsiaBotService().maybeRefillAfterSale(productId));
    return order;
  }

  Future<void> markPrinted(String orderId) {
    return _db.collection('orders').doc(orderId).update({
      'printed': true,
      'printCount': FieldValue.increment(1),
    });
  }
}
