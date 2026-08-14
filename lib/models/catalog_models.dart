import 'package:cloud_firestore/cloud_firestore.dart';

/// شركة فايزر الافتراضية في قائمة الشركات (يُتحكم بترتيبها من الداش).
const kFazerAllCompanyId = 'fazer_all';
const kFazerGameKeysCompanyId = 'fazer_game_keys';
const kFazerWorldCompanyId = 'fazer_world';
const kFazerTopupsCompanyId = 'fazer_topups';
const kFazerGkPrefix = 'fazergk:';
const kFazerWorldPrefix = 'fazerworld:';
const kFazerTopupPrefix = 'fazertop:';

DateTime _asDate(dynamic value) =>
    value is Timestamp ? value.toDate() : DateTime.now();

class Company {
  const Company({
    required this.id,
    required this.name,
    required this.logoUrl,
    required this.colorHex,
    required this.sortOrder,
    required this.isActive,
  });

  final String id;
  final String name;
  final String logoUrl;
  final String colorHex;
  final int sortOrder;
  final bool isActive;

  bool get isFazerAll => id == kFazerAllCompanyId;
  bool get isFazerGameKeys => id == kFazerGameKeysCompanyId;
  bool get isFazerWorld => id == kFazerWorldCompanyId;
  bool get isFazerTopups => id == kFazerTopupsCompanyId;
  bool get isFazerSpecial =>
      isFazerAll || isFazerGameKeys || isFazerWorld || isFazerTopups;

  factory Company.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return Company(
      id: doc.id,
      name: d['name'] ?? '',
      logoUrl: d['logoUrl'] ?? '',
      colorHex: d['colorHex'] ?? '#0B3B4A',
      sortOrder: _asInt(d['sortOrder'], 0),
      isActive: d['isActive'] ?? true,
    );
  }

  static int _asInt(dynamic value, int fallback) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }

  Map<String, dynamic> toFirestore() => {
    'name': name,
    'logoUrl': logoUrl,
    'colorHex': colorHex,
    'sortOrder': sortOrder,
    'isActive': isActive,
  };
}

class Product {
  const Product({
    required this.id,
    required this.companyId,
    required this.name,
    required this.imageUrl,
    required this.price,
    this.costPrice = 0,
    this.hiddenSalePrice,
    required this.hasOffer,
    required this.isActive,
    required this.buttonColorHex,
    required this.buttonText,
    required this.sortOrder,
    required this.stockCount,
  });

  final String id;
  final String companyId;
  final String name;
  final String imageUrl;
  final double price;
  /// سعر التكلفة (للإدارة).
  final double costPrice;
  final double? hiddenSalePrice;
  final bool hasOffer;
  final bool isActive;
  final String buttonColorHex;
  final String buttonText;
  final int sortOrder;
  final int stockCount;

  factory Product.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return Product(
      id: doc.id,
      companyId: d['companyId'] ?? '',
      name: d['name'] ?? '',
      imageUrl: d['imageUrl'] ?? '',
      price: (d['price'] ?? 0).toDouble(),
      costPrice: (d['costPrice'] ?? 0).toDouble(),
      hiddenSalePrice: d['hiddenSalePrice'] == null
          ? null
          : (d['hiddenSalePrice'] as num).toDouble(),
      hasOffer: d['hasOffer'] ?? false,
      isActive: d['isActive'] ?? true,
      buttonColorHex: d['buttonColorHex'] ?? '#1DB954',
      buttonText: d['buttonText'] ?? 'شراء الآن',
      sortOrder: _asInt(d['sortOrder'], 0),
      stockCount: _asInt(d['stockCount'], 0),
    );
  }

  static int _asInt(dynamic value, int fallback) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }

  Map<String, dynamic> toFirestore() => {
    'companyId': companyId,
    'name': name,
    'imageUrl': imageUrl,
    'price': price,
    'costPrice': costPrice,
    'hiddenSalePrice': hiddenSalePrice,
    'hasOffer': hasOffer,
    'isActive': isActive,
    'buttonColorHex': buttonColorHex,
    'buttonText': buttonText,
    'sortOrder': sortOrder,
    'stockCount': stockCount,
    'updatedAt': FieldValue.serverTimestamp(),
  };
}

class CardCode {
  const CardCode({
    required this.id,
    required this.code,
    required this.serialNumber,
    required this.status,
    this.soldTo,
    this.orderId,
    this.soldAt,
  });

  final String id;
  final String code;
  final String serialNumber;
  final String status;
  final String? soldTo;
  final String? orderId;
  final DateTime? soldAt;

  factory CardCode.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return CardCode(
      id: doc.id,
      code: d['code'] ?? '',
      serialNumber: d['serialNumber']?.toString() ?? '',
      status: d['status'] ?? 'available',
      soldTo: d['soldTo'],
      orderId: d['orderId'],
      soldAt: d['soldAt'] is Timestamp ? _asDate(d['soldAt']) : null,
    );
  }
}

/// زوج رمز البطاقة ورقم التسلسل عند الإضافة للمخزون أو البيع.
class CardItem {
  const CardItem({required this.code, required this.serialNumber});

  final String code;
  final String serialNumber;

  Map<String, dynamic> toMap() => {'code': code, 'serialNumber': serialNumber};

  factory CardItem.fromMap(Map<String, dynamic> map) {
    return CardItem(
      code: map['code']?.toString() ?? '',
      serialNumber: map['serialNumber']?.toString() ?? '',
    );
  }
}
