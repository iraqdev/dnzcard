import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/fazer_models.dart';
import '../models/order_model.dart';
import 'functions_service.dart';

class FazerService {
  FazerService({
    FirebaseFirestore? db,
    FunctionsService? functions,
  })  : _db = db ?? FirebaseFirestore.instance,
        _functions = functions ?? FunctionsService();

  final FirebaseFirestore _db;
  final FunctionsService _functions;

  Stream<List<FazerCategory>>? _categoriesStream;
  Stream<List<FazerCategory>>? _gameKeyCategoriesStream;
  Stream<List<FazerCategory>>? _topupCategoriesStream;
  Stream<List<FazerOffer>>? _pricedOffersStream;

  /// بث مشترك يعيد آخر قيمة للمشتركين الجدد (مثل شاشة مفاتيح الألعاب).
  Stream<T> _shareReplay<T>(Stream<T> source) {
    T? last;
    var hasValue = false;
    StreamSubscription<T>? subscription;
    late final StreamController<T> controller;

    controller = StreamController<T>.broadcast(
      onListen: () {
        subscription ??= source.listen(
          (event) {
            last = event;
            hasValue = true;
            controller.add(event);
          },
          onError: controller.addError,
          onDone: () {
            subscription = null;
            if (!controller.isClosed) controller.close();
          },
        );
        if (hasValue) {
          controller.add(last as T);
        }
      },
    );

    return controller.stream;
  }

  Stream<List<FazerCategory>> watchCategories() {
    return _categoriesStream ??= _shareReplay(
      _db.collection('fazer_categories').snapshots().map((s) {
        final list = s.docs.map(FazerCategory.fromFirestore).toList()
          ..sort((a, b) {
            final byOrder = a.sortOrder.compareTo(b.sortOrder);
            return byOrder != 0 ? byOrder : a.name.compareTo(b.name);
          });
        return list;
      }),
    );
  }

  Stream<List<FazerCategory>> watchGameKeyCategories() {
    return _gameKeyCategoriesStream ??= _shareReplay(
      watchCategories().map(
        (list) => list.where((c) => c.kind == 'game_key').toList(),
      ),
    );
  }

  Stream<List<FazerCategory>> watchGiftCategories() {
    return watchCategories().map(
      (list) => list
          .where((c) => c.kind != 'game_key' && c.kind != 'topup')
          .toList(),
    );
  }

  Stream<List<FazerCategory>> watchTopupCategories() {
    return _topupCategoriesStream ??= _shareReplay(
      watchCategories().map(
        (list) => list.where((c) => c.kind == 'topup').toList(),
      ),
    );
  }

  Future<void> updateCategoryOrder(List<String> categoryIds) async {
    for (var start = 0; start < categoryIds.length; start += 400) {
      final end = start + 400 < categoryIds.length
          ? start + 400
          : categoryIds.length;
      final batch = _db.batch();
      for (var index = start; index < end; index++) {
        batch.set(
          _db.collection('fazer_categories').doc(categoryIds[index]),
          {'sortOrder': index},
          SetOptions(merge: true),
        );
      }
      await batch.commit();
    }
  }

  Future<void> updateCategoryCustomImage({
    required String categoryId,
    required String customImageUrl,
  }) {
    return _db.collection('fazer_categories').doc(categoryId).set({
      'customImageUrl': customImageUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<Set<String>> watchGameKeyFavorites(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('game_key_favorites')
        .snapshots()
        .map((s) => s.docs.map((d) => d.id).toSet());
  }

  Future<void> setGameKeyFavorite({
    required String uid,
    required String gameId,
    required bool favorite,
  }) async {
    final ref = _db
        .collection('users')
        .doc(uid)
        .collection('game_key_favorites')
        .doc(gameId);
    if (favorite) {
      await ref.set({'createdAt': FieldValue.serverTimestamp()});
    } else {
      await ref.delete();
    }
  }

  Stream<Set<String>> watchTopupFavorites(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('topup_favorites')
        .snapshots()
        .map((s) => s.docs.map((d) => d.id).toSet());
  }

  Future<void> setTopupFavorite({
    required String uid,
    required String categoryId,
    required bool favorite,
  }) async {
    final ref = _db
        .collection('users')
        .doc(uid)
        .collection('topup_favorites')
        .doc(categoryId);
    if (favorite) {
      await ref.set({'createdAt': FieldValue.serverTimestamp()});
    } else {
      await ref.delete();
    }
  }

  Future<FazerCategory?> getCategory(String categoryId) async {
    final snap =
        await _db.collection('fazer_categories').doc(categoryId).get();
    if (!snap.exists) return null;
    return FazerCategory.fromFirestore(snap);
  }

  Stream<List<FazerOffer>> watchOffersForCategory(String categoryId) {
    return _db
        .collection('fazer_offers')
        .where('categoryId', isEqualTo: categoryId)
        .snapshots()
        .map((s) {
          final list = s.docs.map(FazerOffer.fromFirestore).toList()
            ..sort((a, b) => a.priceUsd.compareTo(b.priceUsd));
          return list;
        });
  }

  /// العروض المسعّرة للبيع في تطبيق المحل.
  Stream<List<FazerOffer>> watchPricedOffers() {
    return _pricedOffersStream ??= _shareReplay(
      _db
          .collection('fazer_offers')
          .where('kushkPrice', isGreaterThan: 0)
          .snapshots()
          .map((s) {
            final list = s.docs.map(FazerOffer.fromFirestore).toList()
              ..sort((a, b) {
                final byCat = a.categoryName.compareTo(b.categoryName);
                if (byCat != 0) return byCat;
                return a.priceUsd.compareTo(b.priceUsd);
              });
            return list;
          }),
    );
  }

  Future<Map<String, dynamic>> getBalance() => _functions.fazerGetBalance();

  Future<Map<String, dynamic>> syncCategories() =>
      _functions.fazerSyncGiftCategories();

  Future<Map<String, dynamic>> syncGameKeyCategories() =>
      _functions.fazerSyncGameKeyCategories();

  Future<Map<String, dynamic>> syncTopupCategories() =>
      _functions.fazerSyncTopupCategories();

  Future<Map<String, dynamic>> syncTelegramCatalog() =>
      _functions.fazerSyncTelegramCatalog();

  Future<Map<String, dynamic>> syncCategoryOffers(String categoryId) =>
      _functions.fazerSyncCategoryOffers(categoryId: categoryId);

  Future<Map<String, dynamic>> validateTopupId({
    required String categoryId,
    required Map<String, String> fields,
  }) =>
      _functions.fazerValidateTopupId(
        categoryId: categoryId,
        fields: fields,
      );

  Future<void> setKushkPrice({
    required String offerId,
    double? kushkPrice,
  }) {
    return _functions.fazerSetOfferKushkPrice(
      offerId: offerId,
      kushkPrice: kushkPrice,
    );
  }

  Future<OrderModel> purchaseOffer({
    required String offerId,
    int quantity = 1,
    String? telegramUsername,
    Map<String, String>? fields,
    String? pin,
  }) async {
    final data = await _functions.fazerPurchaseGiftCard(
      offerId: offerId,
      quantity: quantity,
      telegramUsername: telegramUsername,
      fields: fields,
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
    return OrderModel.fromFirestore(snap);
  }
}
