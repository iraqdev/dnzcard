import 'package:cloud_firestore/cloud_firestore.dart';
import 'catalog_models.dart';

class OrderModel {
  const OrderModel({
    required this.id,
    required this.shopId,
    required this.productId,
    required this.productName,
    required this.companyName,
    required this.quantity,
    required this.unitPrice,
    required this.total,
    required this.cardItems,
    required this.paymentMethod,
    required this.status,
    required this.createdAt,
    this.printed = false,
    this.printCount = 0,
    this.source = '',
    this.fazerPriceUsd = 0,
  });

  final String id;
  final String shopId;
  final String productId;
  final String productName;
  final String companyName;
  final int quantity;
  final double unitPrice;
  final double total;
  final List<CardItem> cardItems;
  final String paymentMethod;
  final String status;
  final DateTime createdAt;
  final bool printed;
  /// عدد مرات الطباعة الناجحة لهذا الطلب.
  final int printCount;
  final String source;
  final double fazerPriceUsd;

  /// رقم الطباعة التالي الذي يُظهر على الورقة.
  int get nextPrintNumber => printCount + 1;

  /// للتوافق مع الشاشات القديمة التي تعتمد على قائمة الرموز فقط.
  List<String> get cardCodes =>
      cardItems.map((item) => item.code).toList(growable: false);

  factory OrderModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    final rawItems = d['cardItems'];
    final List<CardItem> items;
    if (rawItems is List && rawItems.isNotEmpty) {
      items = rawItems
          .whereType<Map>()
          .map((item) => CardItem.fromMap(Map<String, dynamic>.from(item)))
          .toList();
    } else {
      // طلبات قديمة: رموز فقط بدون رقم تسلسل.
      items = List<String>.from(
        d['cardCodes'] ?? const [],
      ).map((code) => CardItem(code: code, serialNumber: '')).toList();
    }

    return OrderModel(
      id: doc.id,
      shopId: d['shopId'] ?? '',
      productId: d['productId'] ?? '',
      productName: d['productName'] ?? '',
      companyName: d['companyName'] ?? '',
      quantity: _asInt(d['quantity'], 1),
      unitPrice: (d['unitPrice'] ?? 0).toDouble(),
      total: (d['total'] ?? 0).toDouble(),
      cardItems: items,
      paymentMethod: d['paymentMethod'] ?? 'wallet',
      status: d['status'] ?? 'completed',
      createdAt: d['createdAt'] is Timestamp
          ? (d['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      printed: d['printed'] == true,
      printCount: _asInt(d['printCount'], 0),
      source: d['source']?.toString() ?? '',
      fazerPriceUsd: (d['fazerPriceUsd'] as num?)?.toDouble() ?? 0,
    );
  }

  static int _asInt(dynamic value, int fallback) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }

  Map<String, dynamic> toFirestore() => {
    'shopId': shopId,
    'productId': productId,
    'productName': productName,
    'companyName': companyName,
    'quantity': quantity,
    'unitPrice': unitPrice,
    'total': total,
    'cardItems': cardItems.map((item) => item.toMap()).toList(),
    'cardCodes': cardCodes,
    'paymentMethod': paymentMethod,
    'status': status,
    'createdAt': Timestamp.fromDate(createdAt),
    'printed': printed,
    'printCount': printCount,
  };
}
