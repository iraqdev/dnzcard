import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/catalog_models.dart';

class CatalogService {
  CatalogService({FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  Stream<List<Company>> watchCompanies({bool activeOnly = true}) {
    return _db.collection('companies').snapshots().map((s) {
      final list = s.docs.map(Company.fromFirestore).toList()
        ..sort((a, b) {
          final byOrder = a.sortOrder.compareTo(b.sortOrder);
          return byOrder != 0 ? byOrder : a.id.compareTo(b.id);
        });
      if (activeOnly) return list.where((e) => e.isActive).toList();
      return list;
    });
  }

  Stream<List<Product>> watchProducts({
    bool activeOnly = true,
    String? companyId,
  }) {
    Query<Map<String, dynamic>> query = _db.collection('products');
    if (companyId != null && companyId.isNotEmpty) {
      query = query.where('companyId', isEqualTo: companyId);
    }
    return query.snapshots().map((s) {
      final list = s.docs.map(Product.fromFirestore).toList()
        ..sort((a, b) {
          final byOrder = a.sortOrder.compareTo(b.sortOrder);
          return byOrder != 0 ? byOrder : a.id.compareTo(b.id);
        });
      if (activeOnly) return list.where((e) => e.isActive).toList();
      return list;
    });
  }

  Future<void> ensureFazerAllCompany() => _ensureSpecialCompany(
        id: kFazerAllCompanyId,
        name: 'جميع البطاقات',
      );

  Future<void> ensureFazerGameKeysCompany() => _ensureSpecialCompany(
        id: kFazerGameKeysCompanyId,
        name: 'مفاتيح العاب',
      );

  Future<void> ensureFazerWorldCompany() => _ensureSpecialCompany(
        id: kFazerWorldCompanyId,
        name: 'جميع البطاقات بالعالم',
      );

  Future<void> ensureFazerTopupsCompany() => _ensureSpecialCompany(
        id: kFazerTopupsCompanyId,
        name: 'شحن بالاي دي',
      );

  static Future<void>? _ensureAllInFlight;

  /// يضمن وجود الشركات الخاصة بفazer دفعة واحدة بدون قراءات مكررة.
  Future<void> ensureAllSpecialCompanies() {
    return _ensureAllInFlight ??= _ensureAllSpecialCompaniesImpl();
  }

  Future<void> _ensureAllSpecialCompaniesImpl() async {
    const entries = [
      (id: kFazerAllCompanyId, name: 'جميع البطاقات'),
      (id: kFazerGameKeysCompanyId, name: 'مفاتيح العاب'),
      (id: kFazerWorldCompanyId, name: 'جميع البطاقات بالعالم'),
      (id: kFazerTopupsCompanyId, name: 'شحن بالاي دي'),
    ];

    final missing = <({String id, String name})>[];
    for (final entry in entries) {
      final snap = await _db.collection('companies').doc(entry.id).get();
      if (!snap.exists) missing.add(entry);
    }
    if (missing.isEmpty) return;

    final existing = await _db.collection('companies').get();
    var nextSortOrder = 0;
    for (final doc in existing.docs) {
      final order = (doc.data()['sortOrder'] as num?)?.toInt() ?? 0;
      if (order >= nextSortOrder) nextSortOrder = order + 1;
    }

    for (final entry in missing) {
      await _db.collection('companies').doc(entry.id).set({
        'name': entry.name,
        'logoUrl': '',
        'colorHex': '#0B3B4A',
        'sortOrder': nextSortOrder,
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
      });
      nextSortOrder++;
    }
  }

  Future<void> _ensureSpecialCompany({
    required String id,
    required String name,
  }) async {
    final ref = _db.collection('companies').doc(id);
    final snap = await ref.get();
    if (snap.exists) return;

    final existing = await _db.collection('companies').get();
    var nextSortOrder = 0;
    for (final doc in existing.docs) {
      final order = (doc.data()['sortOrder'] as num?)?.toInt() ?? 0;
      if (order >= nextSortOrder) nextSortOrder = order + 1;
    }

    await ref.set({
      'name': name,
      'logoUrl': '',
      'colorHex': '#0B3B4A',
      'sortOrder': nextSortOrder,
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> setCompanyActive(String id, bool active) async {
    await _db.collection('companies').doc(id).update({'isActive': active});
  }

  Future<void> saveCompany(Company company) async {
    final ref = company.id.isEmpty
        ? _db.collection('companies').doc()
        : _db.collection('companies').doc(company.id);
    await ref.set({
      ...company.toFirestore(),
      if (company.id.isEmpty) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// يحفظ ترتيب الشركات كما يظهر في الداش والتطبيق.
  Future<void> updateCompanyOrder(List<String> companyIds) async {
    for (var start = 0; start < companyIds.length; start += 400) {
      final end = start + 400 < companyIds.length
          ? start + 400
          : companyIds.length;
      final batch = _db.batch();
      for (var index = start; index < end; index++) {
        batch.update(_db.collection('companies').doc(companyIds[index]), {
          'sortOrder': index,
        });
      }
      await batch.commit();
    }
  }

  Future<void> saveProduct(Product product) async {
    final ref = product.id.isEmpty
        ? _db.collection('products').doc()
        : _db.collection('products').doc(product.id);
    await ref.set({
      ...product.toFirestore(),
      if (product.id.isEmpty) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// يحفظ ترتيب فئات الكروت داخل الشركة كما يظهر في الداش والتطبيق.
  Future<void> updateProductOrder(List<String> productIds) async {
    for (var start = 0; start < productIds.length; start += 400) {
      final end = start + 400 < productIds.length
          ? start + 400
          : productIds.length;
      final batch = _db.batch();
      for (var index = start; index < end; index++) {
        batch.update(_db.collection('products').doc(productIds[index]), {
          'sortOrder': index,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
  }

  /// يحذف الشركة مع جميع فئات الكروت ورموز المخزون التابعة لها.
  Future<void> deleteCompany(String id) async {
    final products = await _db
        .collection('products')
        .where('companyId', isEqualTo: id)
        .get();
    for (final product in products.docs) {
      await deleteProduct(product.id);
    }
    await _db.collection('companies').doc(id).delete();
  }

  /// يحذف فئة الكارت مع جميع رموز المخزون التابعة لها.
  Future<void> deleteProduct(String id) async {
    final productRef = _db.collection('products').doc(id);
    while (true) {
      final codes = await productRef.collection('codes').limit(400).get();
      if (codes.docs.isEmpty) break;
      final batch = _db.batch();
      for (final code in codes.docs) {
        batch.delete(code.reference);
      }
      await batch.commit();
    }
    await productRef.delete();
  }

  /// يحذف رمزاً واحداً، ويحدّث عدد المخزون إذا كان الرمز متاحاً.
  Future<void> deleteCardCode(String productId, String codeId) async {
    final productRef = _db.collection('products').doc(productId);
    final codeRef = productRef.collection('codes').doc(codeId);
    await _db.runTransaction((transaction) async {
      final codeSnapshot = await transaction.get(codeRef);
      if (!codeSnapshot.exists) return;

      if (codeSnapshot.data()?['status'] == 'available') {
        final productSnapshot = await transaction.get(productRef);
        final currentStock =
            (productSnapshot.data()?['stockCount'] as num?)?.toInt() ?? 0;
        transaction.update(productRef, {
          'stockCount': currentStock > 0 ? currentStock - 1 : 0,
        });
      }
      transaction.delete(codeRef);
    });
  }

  Stream<List<CardCode>> watchCodes(String productId) {
    return _db
        .collection('products')
        .doc(productId)
        .collection('codes')
        .snapshots()
        .map((s) => s.docs.map(CardCode.fromFirestore).toList());
  }

  /// يضيف أزواج (رمز البطاقة، رقم التسلسل) للمخزون ويسجّل عملية الرفع.
  Future<int> addCardItems(
    String productId,
    List<CardItem> items, {
    String source = 'manual',
  }) async {
    final productRef = _db.collection('products').doc(productId);
    final productSnap = await productRef.get();
    final productData = productSnap.data() ?? {};
    final productName = (productData['name'] ?? '').toString();
    final companyId = (productData['companyId'] ?? '').toString();
    final unitCost = (productData['costPrice'] as num?)?.toDouble() ?? 0;
    var companyName = '';
    if (companyId.isNotEmpty) {
      final companySnap = await _db.collection('companies').doc(companyId).get();
      companyName = (companySnap.data()?['name'] ?? '').toString();
    }

    final batch = _db.batch();
    var added = 0;
    for (final item in items) {
      final code = item.code.trim();
      final serial = item.serialNumber.trim();
      if (code.isEmpty || serial.isEmpty) continue;
      final ref = productRef.collection('codes').doc();
      batch.set(ref, {
        'code': code,
        'serialNumber': serial,
        'status': 'available',
        'createdAt': FieldValue.serverTimestamp(),
        'source': source,
      });
      added++;
    }
    if (added == 0) return 0;
    batch.update(productRef, {'stockCount': FieldValue.increment(added)});
    batch.set(_db.collection('stock_uploads').doc(), {
      'productId': productId,
      'productName': productName,
      'companyId': companyId,
      'companyName': companyName,
      'count': added,
      'unitCost': unitCost,
      'totalCost': unitCost * added,
      'source': source,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    return added;
  }

  Stream<List<StockUpload>> watchStockUploads() {
    return _db
        .collection('stock_uploads')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(StockUpload.fromFirestore).toList());
  }

  /// يحلّل أسطر الإدخال بصيغة: رمز البطاقة | رقم التسلسل
  static List<CardItem> parseInventoryLines(String raw) {
    final items = <CardItem>[];
    for (final line in raw.split(RegExp(r'\r?\n'))) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final parts = trimmed.split('|').map((e) => e.trim()).toList();
      if (parts.length < 2 || parts[0].isEmpty || parts[1].isEmpty) {
        throw FormatException(
          'السطر غير صالح: "$trimmed" — استخدم: رمز البطاقة | رقم التسلسل',
        );
      }
      items.add(CardItem(code: parts[0], serialNumber: parts[1]));
    }
    return items;
  }
}
