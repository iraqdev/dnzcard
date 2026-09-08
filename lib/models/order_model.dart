import 'package:cloud_firestore/cloud_firestore.dart';
import 'catalog_models.dart';
import 'fazer_models.dart';

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
    this.fazerSaleRate = 0,
    this.fazerCostRate = 0,
    this.fazerUnitCost = 0,
    this.fazerKind = '',
    this.unitCostPrice = 0,
    this.chargedUnitPrice = 0,
    this.chargedTotal = 0,
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
  final double fazerSaleRate;
  final double fazerCostRate;
  final double fazerUnitCost;
  final String fazerKind;
  /// تكلفة الوحدة وقت الشراء — لا تتأثر بتغيير سعر المنتج لاحقاً.
  final double unitCostPrice;
  /// سعر البيع الفعلي المخصوم من المحفظة (مخفي أو ظاهر) وقت الشراء.
  final double chargedUnitPrice;
  final double chargedTotal;

  /// تكلفة الوحدة لفايزr — مُثبتة وقت الشراء ولا تتأثر بتغيير الإعدادات لاحقاً.
  double get fazerOrderUnitCost {
    if (source != 'fazer') return 0;
    if (fazerUnitCost > 0) return fazerUnitCost;
    if (fazerCostRate > 0 && fazerPriceUsd > 0) {
      return (fazerPriceUsd * fazerCostRate).roundToDouble();
    }
    if (fazerPriceUsd > 0 && unitPrice > 0) {
      // طلبات قديمة: تقدير من سعر البيع المحفوظ ونسبة التكلفة/البيع الافتراضية.
      return (unitPrice * (kFazerGameKeyCostRate / kFazerGameKeyIqdRate))
          .roundToDouble();
    }
    return 0;
  }

  /// رقم الطباعة التالي الذي يُظهر على الورقة.
  int get nextPrintNumber => printCount + 1;

  /// سعر البيع للإحصائيات — من الطلب وقت الشراء وليس من المنتج الحالي.
  double saleUnitForStats({double? fallbackProductCost}) {
    if (chargedUnitPrice > 0) return chargedUnitPrice;
    if (chargedTotal > 0 && quantity > 0) return chargedTotal / quantity;
    return unitPrice;
  }

  /// تكلفة الوحدة للإحصائيات — من الطلب وقت الشراء فقط.
  double costUnitForStats() {
    return unitCostPrice > 0 ? unitCostPrice : 0;
  }

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
      fazerSaleRate: (d['fazerSaleRate'] as num?)?.toDouble() ?? 0,
      fazerCostRate: (d['fazerCostRate'] as num?)?.toDouble() ?? 0,
      fazerUnitCost: (d['fazerUnitCost'] as num?)?.toDouble() ?? 0,
      fazerKind: d['fazerKind']?.toString() ?? '',
      unitCostPrice: (d['unitCostPrice'] as num?)?.toDouble() ?? 0,
      chargedUnitPrice: (d['chargedUnitPrice'] as num?)?.toDouble() ?? 0,
      chargedTotal: (d['chargedTotal'] as num?)?.toDouble() ?? 0,
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
