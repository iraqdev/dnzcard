import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:http/http.dart' as http;

import '../models/bot_settings.dart';
import '../models/catalog_models.dart';

class CardBotService {
  CardBotService({FirebaseFirestore? db, http.Client? httpClient})
      : _db = db ?? FirebaseFirestore.instance,
        _http = httpClient ?? http.Client();

  final FirebaseFirestore _db;
  final http.Client _http;
  final Map<String, DateTime> _cooldown = {};

  DocumentReference<Map<String, dynamic>> get _settingsRef =>
      _db.collection('app_settings').doc('card_bot');

  CollectionReference<Map<String, dynamic>> get _mapsRef =>
      _db.collection('bot_maps');

  CollectionReference<Map<String, dynamic>> get _logsRef =>
      _db.collection('bot_logs');

  Future<Map<String, dynamic>> _callCloud(
    String name,
    Map<String, dynamic> data,
  ) async {
    final fn = FirebaseFunctions.instanceFor(region: 'europe-west1');
    final result = await fn.httpsCallable(name).call(data);
    final payload = result.data;
    if (payload is Map) return Map<String, dynamic>.from(payload);
    return {};
  }

  Stream<CardBotSettings> watchSettings() {
    return _settingsRef.snapshots().map((doc) {
      if (!doc.exists) return CardBotSettings.defaults();
      return CardBotSettings.fromMap(doc.data());
    });
  }

  Future<CardBotSettings> getSettings() async {
    final doc = await _settingsRef.get();
    if (!doc.exists) return CardBotSettings.defaults();
    return CardBotSettings.fromMap(doc.data());
  }

  Future<void> saveSettings(CardBotSettings settings) {
    return _settingsRef.set(settings.toFirestore(), SetOptions(merge: true));
  }

  Stream<List<BotProductMap>> watchMaps() {
    return _mapsRef.snapshots().map(
          (s) => s.docs.map(BotProductMap.fromFirestore).toList(),
        );
  }

  Future<void> saveMap(BotProductMap map) {
    return _mapsRef.doc(map.productId).set(map.toFirestore(), SetOptions(merge: true));
  }

  Future<void> deleteMap(String productId) {
    return _mapsRef.doc(productId).delete();
  }

  Stream<List<Map<String, dynamic>>> watchLogs({int limit = 50}) {
    return _logsRef
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  Future<Map<String, dynamic>> healthCheck([CardBotSettings? settings]) async {
    final s = settings ?? await getSettings();
    if (s.useCloudMode) {
      try {
        final body = await _callCloud('baqatyBotStatus', {});
        return {
          'ok': body['ok'] == true,
          'bot_running': body['bot_running'] == true,
          'message': body['message']?.toString() ?? 'cloud',
          'mode': 'cloud',
        };
      } catch (e) {
        return {
          'ok': false,
          'bot_running': false,
          'message': 'فشل البوت السحابي: $e',
          'mode': 'cloud',
        };
      }
    }

    final base = s.apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
    try {
      final res = await _http
          .get(Uri.parse('$base/health'))
          .timeout(const Duration(seconds: 4));
      if (res.statusCode != 200) {
        return {
          'ok': false,
          'message': 'HTTP ${res.statusCode}',
          'bot_running': false,
          'mode': 'local',
        };
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return {
        'ok': body['ok'] == true,
        'bot_running': body['bot_running'] == true,
        'catalog_count': body['catalog_count'],
        'message': body['bot_running'] == true
            ? 'البوت المحلي يعمل'
            : 'السيرفر المحلي يعمل لكن البوت متوقف',
        'mode': 'local',
      };
    } catch (e) {
      return {
        'ok': false,
        'bot_running': false,
        'message': 'لا يمكن الوصول للبوت المحلي: $e',
        'mode': 'local',
      };
    }
  }

  Future<Map<String, dynamic>> saveBaqatyAccount({
    required String userId,
    required String username,
    required String password,
    String imei = '121212',
    String secretKey = '',
  }) async {
    try {
      final body = await _callCloud('baqatySaveAccount', {
        'user_id': userId,
        'username': username,
        'password': password,
        'imei': imei,
        'secret_key': secretKey,
      });
      return {
        'ok': body['ok'] == true,
        'message': body['message']?.toString() ?? 'تم الحفظ',
        'user_id': body['user_id']?.toString(),
      };
    } catch (e) {
      return {'ok': false, 'message': 'فشل حفظ الحساب: $e'};
    }
  }

  Future<List<BaqatyCard>> fetchBaqatyCatalog([CardBotSettings? settings]) async {
    final s = settings ?? await getSettings();
    if (s.useCloudMode) {
      final body = await _callCloud('baqatyFetchCatalog', {});
      return (body['cards'] as List? ?? [])
          .whereType<Map>()
          .map((e) => BaqatyCard.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    final base = s.apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
    final res = await _http
        .get(
          Uri.parse('$base/catalog'),
          headers: {'X-Api-Token': s.apiToken},
        )
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      throw StateError('فشل جلب كتالوج Baqaty: HTTP ${res.statusCode}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return (body['cards'] as List? ?? [])
        .whereType<Map>()
        .map((e) => BaqatyCard.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<Map<String, dynamic>> syncToLocalBot(List<BotProductMap> maps) async {
    final s = await getSettings();
    if (s.useCloudMode) {
      return {'ok': true, 'message': 'وضع السحابة — لا حاجة لمزامنة الجهاز'};
    }
    final base = s.apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
    final cardMap = <String, String>{};
    final enabledIds = <String>[];
    final disabledIds = <String>[];
    for (final m in maps) {
      if (m.cardId.isEmpty) continue;
      cardMap[m.cardId] = m.productId;
      if (m.enabled) {
        enabledIds.add(m.cardId);
      } else {
        disabledIds.add(m.cardId);
      }
    }
    try {
      final res = await _http
          .post(
            Uri.parse('$base/sync_maps'),
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
    } catch (e) {
      return {'ok': false, 'message': '$e'};
    }
  }

  Future<Map<String, dynamic>> requestBuy({
    required String productId,
    required String cardId,
    required String catId,
    required int quantity,
    String source = 'admin',
  }) async {
    final settings = await getSettings();
    if (!settings.enabled) {
      return {'ok': false, 'message': 'البوت معطّل من الإعدادات'};
    }
    if (cardId.trim().isEmpty || catId.trim().isEmpty) {
      return {'ok': false, 'message': 'card_id / cat_id ناقص في الربط'};
    }

    if (settings.useCloudMode) {
      try {
        final body = await _callCloud('baqatyBuyCards', {
          'productId': productId,
          'cardId': cardId,
          'catId': catId,
          'quantity': quantity,
          'source': source,
        });
        return {
          'ok': body['ok'] == true,
          'message': body['message']?.toString() ?? '',
          'response': body,
        };
      } catch (e) {
        return {'ok': false, 'message': 'فشل الشراء السحابي: $e'};
      }
    }

    final base = settings.apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
    try {
      final res = await _http
          .post(
            Uri.parse('$base/buy'),
            headers: {
              'Content-Type': 'application/json',
              'X-Api-Token': settings.apiToken,
            },
            body: jsonEncode({
              'card_id': cardId,
              'cat_id': catId,
              'quantity': quantity,
              'kushk_product_id': productId,
            }),
          )
          .timeout(const Duration(seconds: 20));

      Map<String, dynamic> body = {};
      try {
        body = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {
        body = {'ok': false, 'message': res.body};
      }

      final ok = res.statusCode >= 200 &&
          res.statusCode < 300 &&
          body['ok'] != false;
      final message = (body['message'] ?? body['job_id'] ?? res.body).toString();

      await _mapsRef.doc(productId).set({
        'lastStatus': ok ? 'queued' : 'error',
        'lastMessage': message,
        'lastRequestAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _logsRef.add({
        'productId': productId,
        'cardId': cardId,
        'catId': catId,
        'quantity': quantity,
        'ok': ok,
        'source': source,
        'response': body,
        'httpStatus': res.statusCode,
        'createdAt': FieldValue.serverTimestamp(),
      });

      return {
        'ok': ok,
        'message': ok ? 'تم إرسال طلب الشراء للبوت' : message,
        'response': body,
      };
    } catch (e) {
      await _logsRef.add({
        'productId': productId,
        'cardId': cardId,
        'catId': catId,
        'quantity': quantity,
        'ok': false,
        'source': source,
        'message': e.toString(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      return {'ok': false, 'message': 'فشل الاتصال بالبوت: $e'};
    }
  }

  Future<void> maybeRefillAfterSale(String productId) async {
    try {
      final settings = await getSettings();
      if (!settings.enabled || !settings.autoRefill) return;

      final mapDoc = await _mapsRef.doc(productId).get();
      if (!mapDoc.exists) return;
      final map = BotProductMap.fromFirestore(mapDoc);
      if (!map.enabled || map.cardId.isEmpty || map.catId.isEmpty) return;

      final productSnap =
          await _db.collection('products').doc(productId).get();
      final stock =
          (productSnap.data()?['stockCount'] as num?)?.toInt() ?? 0;
      if (stock > map.minStock) return;

      final last = _cooldown[productId];
      if (last != null &&
          DateTime.now().difference(last) < const Duration(minutes: 2)) {
        return;
      }
      _cooldown[productId] = DateTime.now();

      await requestBuy(
        productId: productId,
        cardId: map.cardId,
        catId: map.catId,
        quantity: map.refillQty,
        source: 'auto_after_sale',
      );
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> scanAndRefill({
    required List<Product> products,
    required List<BotProductMap> maps,
  }) async {
    final settings = await getSettings();
    if (!settings.enabled || !settings.autoRefill) return [];

    final byId = {for (final m in maps) m.productId: m};
    final results = <Map<String, dynamic>>[];

    for (final p in products) {
      final map = byId[p.id];
      if (map == null || !map.enabled) continue;
      if (map.cardId.isEmpty || map.catId.isEmpty) continue;
      if (p.stockCount > map.minStock) continue;

      final last = _cooldown[p.id];
      if (last != null &&
          DateTime.now().difference(last) < const Duration(minutes: 2)) {
        continue;
      }
      _cooldown[p.id] = DateTime.now();

      final r = await requestBuy(
        productId: p.id,
        cardId: map.cardId,
        catId: map.catId,
        quantity: map.refillQty,
        source: 'auto_scan',
      );
      results.add({'productId': p.id, 'name': p.name, ...r});
    }
    return results;
  }
}
