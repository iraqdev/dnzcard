import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

import '../models/bot_settings.dart';
import '../models/catalog_models.dart';

/// خدمة بوت آسيا — نفس منطق CardBotService لكن على /asia/* و asia_bot_maps.
class AsiaBotService {
  AsiaBotService({FirebaseFirestore? db, http.Client? httpClient})
      : _db = db ?? FirebaseFirestore.instance,
        _http = httpClient ?? http.Client();

  final FirebaseFirestore _db;
  final http.Client _http;
  final Map<String, DateTime> _cooldown = {};

  DocumentReference<Map<String, dynamic>> get _settingsRef =>
      _db.collection('app_settings').doc('asia_card_bot');

  CollectionReference<Map<String, dynamic>> get _mapsRef =>
      _db.collection('asia_bot_maps');

  CollectionReference<Map<String, dynamic>> get _logsRef =>
      _db.collection('asia_bot_logs');

  Stream<AsiaBotSettings> watchSettings() {
    return _settingsRef.snapshots().map((doc) {
      if (!doc.exists) return AsiaBotSettings.defaults();
      return AsiaBotSettings.fromMap(doc.data());
    });
  }

  Future<AsiaBotSettings> getSettings() async {
    final doc = await _settingsRef.get();
    if (!doc.exists) return AsiaBotSettings.defaults();
    return AsiaBotSettings.fromMap(doc.data());
  }

  Future<void> saveSettings(AsiaBotSettings settings) {
    return _settingsRef.set(settings.toFirestore(), SetOptions(merge: true));
  }

  Stream<List<AsiaBotProductMap>> watchMaps() {
    return _mapsRef.snapshots().map(
          (s) => s.docs.map(AsiaBotProductMap.fromFirestore).toList(),
        );
  }

  Future<void> saveMap(AsiaBotProductMap map) {
    return _mapsRef.doc(map.productId).set(map.toFirestore(), SetOptions(merge: true));
  }

  Future<void> deleteMap(String productId) {
    return _mapsRef.doc(productId).delete();
  }

  Future<Map<String, dynamic>> healthCheck([AsiaBotSettings? settings]) async {
    final s = settings ?? await getSettings();
    // البوت المحلي يكتب botLastSeenAt على فايربيس — لا حاجة لـ IP
    try {
      final doc = await _settingsRef.get();
      final d = doc.data() ?? {};
      final last = d['botLastSeenAt'];
      DateTime? seen;
      if (last is Timestamp) {
        seen = last.toDate();
      }
      final online = seen != null &&
          DateTime.now().difference(seen) < const Duration(minutes: 2);
      if (online) {
        return {
          'ok': true,
          'bot_running': true,
          'catalog_count': d['mappedProducts'],
          'message': 'بوت آسيا متصل بفايربيس (حاسوب محلي)',
        };
      }
    } catch (_) {}

    // احتياطي: فحص HTTP إن وُجد على نفس الجهاز
    final base = s.apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
    try {
      final res = await _http
          .get(Uri.parse('$base/asia/health'))
          .timeout(const Duration(seconds: 4));
      if (res.statusCode != 200) {
        return {
          'ok': false,
          'message': 'HTTP ${res.statusCode}',
          'bot_running': false,
        };
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return {
        'ok': body['ok'] == true,
        'bot_running': body['bot_running'] == true,
        'catalog_count': body['catalog_count'],
        'message': body['bot_running'] == true
            ? 'بوت آسيا المحلي يعمل'
            : 'السيرفر يعمل لكن بوت آسيا متوقف',
      };
    } catch (e) {
      return {
        'ok': false,
        'bot_running': false,
        'message':
            'بوت آسيا غير متصل — شغّله على الحاسوب ليظهر عبر فايربيس',
      };
    }
  }

  Future<Map<String, dynamic>> syncToLocalBot(List<AsiaBotProductMap> maps) async {
    final s = await getSettings();
    final base = s.apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
    final cardMap = <String, String>{};
    final enabledIds = <String>[];
    final disabledIds = <String>[];
    for (final m in maps) {
      if (m.asiaProductId.isEmpty) continue;
      cardMap[m.asiaProductId] = m.productId;
      if (m.enabled) {
        enabledIds.add(m.asiaProductId);
      } else {
        disabledIds.add(m.asiaProductId);
      }
    }
    // الربط محفوظ أصلاً في asia_bot_maps — المزامنة HTTP اختيارية
    try {
      final res = await _http
          .post(
            Uri.parse('$base/asia/sync_maps'),
            headers: {
              'Content-Type': 'application/json',
              'X-Api-Token': s.apiToken,
            },
            body: jsonEncode({
              'card_to_kushk_product': cardMap,
              'enabled_card_ids': enabledIds,
              'disabled_card_ids': disabledIds,
            }),
          )
          .timeout(const Duration(seconds: 10));
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return {
        'ok': true,
        'message': 'الربط محفوظ في فايربيس — البوت سيسحبه عند التشغيل',
        'mapped': cardMap.length,
      };
    }
  }

  Future<Map<String, dynamic>> requestBuy({
    required String productId,
    required String asiaProductId,
    required String catId,
    required String provider,
    required int quantity,
    String source = 'admin',
  }) async {
    final settings = await getSettings();
    if (!settings.enabled) {
      return {'ok': false, 'message': 'بوت آسيا معطّل من الإعدادات'};
    }
    if (asiaProductId.trim().isEmpty || catId.trim().isEmpty) {
      return {'ok': false, 'message': 'product_id / cat_id ناقص في الربط'};
    }

    // المسار الأساسي: كتابة الطلب في فايربيس → بوت الحاسوب يسحبه ويرفع للمخزون
    try {
      final doc = await _db.collection('asia_bot_requests').add({
        'productId': productId,
        'asiaProductId': asiaProductId,
        'cardId': asiaProductId,
        'catId': catId,
        'provider': provider,
        'quantity': quantity,
        'status': 'pending',
        'source': source,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await _mapsRef.doc(productId).set({
        'lastStatus': 'queued',
        'lastMessage': 'طلب عبر فايربيس #${doc.id}',
        'lastRequestAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _logsRef.add({
        'productId': productId,
        'asiaProductId': asiaProductId,
        'catId': catId,
        'provider': provider,
        'quantity': quantity,
        'ok': true,
        'source': source,
        'channel': 'firestore',
        'requestId': doc.id,
        'createdAt': FieldValue.serverTimestamp(),
      });

      return {
        'ok': true,
        'message': 'تم إرسال طلب شراء آسيا عبر فايربيس — ينفّذه البوت على الحاسوب',
        'requestId': doc.id,
      };
    } catch (e) {
      await _logsRef.add({
        'productId': productId,
        'asiaProductId': asiaProductId,
        'catId': catId,
        'provider': provider,
        'quantity': quantity,
        'ok': false,
        'source': source,
        'channel': 'firestore',
        'message': e.toString(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      return {'ok': false, 'message': 'فشل كتابة طلب آسيا في فايربيس: $e'};
    }
  }

  Future<void> maybeRefillAfterSale(String productId) async {
    try {
      final settings = await getSettings();
      if (!settings.enabled || !settings.autoRefill) return;

      final mapDoc = await _mapsRef.doc(productId).get();
      if (!mapDoc.exists) return;
      final map = AsiaBotProductMap.fromFirestore(mapDoc);
      if (!map.enabled || map.asiaProductId.isEmpty || map.catId.isEmpty) return;

      final productSnap =
          await _db.collection('products').doc(productId).get();
      final stock =
          (productSnap.data()?['stockCount'] as num?)?.toInt() ?? 0;
      if (stock > map.minStock) return;

      final last = _cooldown[productId];
      if (last != null &&
          DateTime.now().difference(last) < const Duration(seconds: 90)) {
        return;
      }
      _cooldown[productId] = DateTime.now();

      await requestBuy(
        productId: productId,
        asiaProductId: map.asiaProductId,
        catId: map.catId,
        provider: map.provider,
        quantity: map.refillQty,
        source: 'auto_after_sale',
      );
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> scanAndRefill({
    required List<Product> products,
    required List<AsiaBotProductMap> maps,
  }) async {
    final settings = await getSettings();
    if (!settings.enabled || !settings.autoRefill) return [];

    final byId = {for (final m in maps) m.productId: m};
    final results = <Map<String, dynamic>>[];

    for (final p in products) {
      final map = byId[p.id];
      if (map == null || !map.enabled) continue;
      if (map.asiaProductId.isEmpty || map.catId.isEmpty) continue;
      if (p.stockCount > map.minStock) continue;

      final last = _cooldown[p.id];
      if (last != null &&
          DateTime.now().difference(last) < const Duration(seconds: 90)) {
        continue;
      }
      _cooldown[p.id] = DateTime.now();

      final r = await requestBuy(
        productId: p.id,
        asiaProductId: map.asiaProductId,
        catId: map.catId,
        provider: map.provider,
        quantity: map.refillQty,
        source: 'auto_scan',
      );
      results.add({'productId': p.id, 'name': p.name, ...r});
    }
    return results;
  }
}
