import 'package:cloud_firestore/cloud_firestore.dart';

/// سعر مخصص لمستخدم معيّن على فئة كارت.
class UserCustomPrice {
  const UserCustomPrice({
    required this.productId,
    this.price,
    this.hiddenSalePrice,
  });

  final String productId;
  final double? price;
  final double? hiddenSalePrice;

  bool get hasOverride =>
      (price != null && price! > 0) ||
      (hiddenSalePrice != null && hiddenSalePrice! > 0);

  factory UserCustomPrice.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? {};
    return UserCustomPrice(
      productId: doc.id,
      price: d['price'] == null ? null : (d['price'] as num).toDouble(),
      hiddenSalePrice: d['hiddenSalePrice'] == null
          ? null
          : (d['hiddenSalePrice'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    if (price != null) 'price': price,
    if (hiddenSalePrice != null) 'hiddenSalePrice': hiddenSalePrice,
    'updatedAt': FieldValue.serverTimestamp(),
  };
}
