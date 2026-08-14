import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/catalog_models.dart';
import '../models/user_custom_price.dart';

class CustomPriceService {
  CustomPriceService({FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _pricesCol(String userId) {
    return _db.collection('users').doc(userId).collection('customPrices');
  }

  Stream<Map<String, UserCustomPrice>> watchForUser(String userId) {
    return _pricesCol(userId).snapshots().map((snap) {
      final map = <String, UserCustomPrice>{};
      for (final doc in snap.docs) {
        final price = UserCustomPrice.fromFirestore(doc);
        if (price.hasOverride) {
          map[doc.id] = price;
        }
      }
      return map;
    });
  }

  Future<void> setPrice({
    required String userId,
    required String productId,
    double? price,
    double? hiddenSalePrice,
  }) async {
    final hasPrice = price != null && price > 0;
    final hasHidden = hiddenSalePrice != null && hiddenSalePrice > 0;
    final ref = _pricesCol(userId).doc(productId);
    if (!hasPrice && !hasHidden) {
      await ref.delete();
      return;
    }
    await ref.set({
      if (hasPrice) 'price': price,
      if (hasHidden) 'hiddenSalePrice': hiddenSalePrice,
      if (!hasPrice) 'price': FieldValue.delete(),
      if (!hasHidden) 'hiddenSalePrice': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> clearPrice({
    required String userId,
    required String productId,
  }) {
    return _pricesCol(userId).doc(productId).delete();
  }
}

/// دمج سعر المنتج العام مع سعر المستخدم المخصص للعرض والخصم.
({double visible, double charged}) resolveProductPrices({
  required Product product,
  UserCustomPrice? custom,
}) {
  final visible = (custom?.price != null && custom!.price! > 0)
      ? custom.price!
      : product.price;

  final customHidden = custom?.hiddenSalePrice;
  if (customHidden != null && customHidden > 0) {
    return (visible: visible, charged: customHidden);
  }
  if (custom?.price != null && custom!.price! > 0) {
    return (visible: visible, charged: custom.price!);
  }
  final productHidden = product.hiddenSalePrice;
  if (productHidden != null && productHidden > 0) {
    return (visible: visible, charged: productHidden);
  }
  return (visible: visible, charged: product.price);
}

Product productWithCustomPrice(Product product, UserCustomPrice? custom) {
  if (custom == null || !custom.hasOverride) return product;
  final prices = resolveProductPrices(product: product, custom: custom);
  return Product(
    id: product.id,
    companyId: product.companyId,
    name: product.name,
    imageUrl: product.imageUrl,
    price: prices.visible,
    costPrice: product.costPrice,
    hiddenSalePrice: prices.charged != prices.visible ? prices.charged : null,
    hasOffer: product.hasOffer,
    isActive: product.isActive,
    buttonColorHex: product.buttonColorHex,
    buttonText: product.buttonText,
    sortOrder: product.sortOrder,
    stockCount: product.stockCount,
  );
}
