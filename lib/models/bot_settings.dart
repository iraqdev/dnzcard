import 'package:cloud_firestore/cloud_firestore.dart';

/// إعدادات عامة لبوت شراء الكروت (Baqaty).
class CardBotSettings {
  const CardBotSettings({
    required this.enabled,
    required this.autoRefill,
    required this.useCloudMode,
    required this.apiBaseUrl,
    required this.apiToken,
    required this.defaultMinStock,
    required this.defaultRefillQty,
  });

  final bool enabled;
  final bool autoRefill;
  final bool useCloudMode;
  final String apiBaseUrl;
  final String apiToken;
  final int defaultMinStock;
  final int defaultRefillQty;

  factory CardBotSettings.defaults() => const CardBotSettings(
        enabled: true,
        autoRefill: true,
        useCloudMode: false,
        apiBaseUrl: 'http://127.0.0.1:8765',
        apiToken: 'kushk-bot-secret',
        defaultMinStock: 3,
        defaultRefillQty: 5,
      );

  factory CardBotSettings.fromMap(Map<String, dynamic>? d) {
    final m = d ?? {};
    return CardBotSettings(
      enabled: m['enabled'] ?? true,
      autoRefill: m['autoRefill'] ?? true,
      useCloudMode: m['useCloudMode'] ?? false,
      apiBaseUrl: (m['apiBaseUrl'] ?? 'http://127.0.0.1:8765').toString(),
      apiToken: (m['apiToken'] ?? 'kushk-bot-secret').toString(),
      defaultMinStock: (m['defaultMinStock'] ?? 3) as int,
      defaultRefillQty: (m['defaultRefillQty'] ?? 5) as int,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'enabled': enabled,
        'autoRefill': autoRefill,
        'useCloudMode': useCloudMode,
        'apiBaseUrl': apiBaseUrl,
        'apiToken': apiToken,
        'defaultMinStock': defaultMinStock,
        'defaultRefillQty': defaultRefillQty,
        'updatedAt': FieldValue.serverTimestamp(),
      };
}

/// كارت من كتالوج Baqaty (عبر API البوت).
class BaqatyCard {
  const BaqatyCard({
    required this.cardId,
    required this.cardName,
    required this.catId,
    required this.catName,
    this.enabled = true,
    this.kushkProductId = '',
  });

  final String cardId;
  final String cardName;
  final String catId;
  final String catName;
  final bool enabled;
  final String kushkProductId;

  factory BaqatyCard.fromJson(Map<String, dynamic> j) => BaqatyCard(
        cardId: '${j['card_id'] ?? ''}',
        cardName: '${j['card_name'] ?? ''}',
        catId: '${j['cat_id'] ?? ''}',
        catName: '${j['cat_name'] ?? ''}',
        enabled: j['enabled'] != false,
        kushkProductId: '${j['kushk_product_id'] ?? ''}',
      );
}

/// ربط فئة كارت في Kushk بكارت Baqaty للبوت.
class BotProductMap {
  const BotProductMap({
    required this.productId,
    required this.enabled,
    required this.cardId,
    required this.catId,
    required this.minStock,
    required this.refillQty,
    this.productName = '',
    this.companyName = '',
    this.baqatyCardName = '',
    this.baqatyCatName = '',
    this.lastStatus,
    this.lastMessage,
    this.lastRequestAt,
  });

  final String productId;
  final bool enabled;
  final String cardId;
  final String catId;
  final int minStock;
  final int refillQty;
  final String productName;
  final String companyName;
  final String baqatyCardName;
  final String baqatyCatName;
  final String? lastStatus;
  final String? lastMessage;
  final DateTime? lastRequestAt;

  factory BotProductMap.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? {};
    return BotProductMap(
      productId: doc.id,
      enabled: d['enabled'] ?? false,
      cardId: (d['cardId'] ?? '').toString(),
      catId: (d['catId'] ?? '').toString(),
      minStock: (d['minStock'] ?? 3) as int,
      refillQty: (d['refillQty'] ?? 5) as int,
      productName: (d['productName'] ?? '').toString(),
      companyName: (d['companyName'] ?? '').toString(),
      baqatyCardName: (d['baqatyCardName'] ?? '').toString(),
      baqatyCatName: (d['baqatyCatName'] ?? '').toString(),
      lastStatus: d['lastStatus']?.toString(),
      lastMessage: d['lastMessage']?.toString(),
      lastRequestAt: d['lastRequestAt'] is Timestamp
          ? (d['lastRequestAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'enabled': enabled,
        'cardId': cardId,
        'catId': catId,
        'minStock': minStock,
        'refillQty': refillQty,
        'productName': productName,
        'companyName': companyName,
        'baqatyCardName': baqatyCardName,
        'baqatyCatName': baqatyCatName,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  BotProductMap copyWith({
    bool? enabled,
    String? cardId,
    String? catId,
    int? minStock,
    int? refillQty,
    String? productName,
    String? companyName,
    String? baqatyCardName,
    String? baqatyCatName,
  }) {
    return BotProductMap(
      productId: productId,
      enabled: enabled ?? this.enabled,
      cardId: cardId ?? this.cardId,
      catId: catId ?? this.catId,
      minStock: minStock ?? this.minStock,
      refillQty: refillQty ?? this.refillQty,
      productName: productName ?? this.productName,
      companyName: companyName ?? this.companyName,
      baqatyCardName: baqatyCardName ?? this.baqatyCardName,
      baqatyCatName: baqatyCatName ?? this.baqatyCatName,
      lastStatus: lastStatus,
      lastMessage: lastMessage,
      lastRequestAt: lastRequestAt,
    );
  }
}

/// إعدادات بوت آسيا (Asiaphone / apevd).
class AsiaBotSettings {
  const AsiaBotSettings({
    required this.enabled,
    required this.autoRefill,
    required this.apiBaseUrl,
    required this.apiToken,
    required this.defaultMinStock,
    required this.defaultRefillQty,
  });

  final bool enabled;
  final bool autoRefill;
  final String apiBaseUrl;
  final String apiToken;
  final int defaultMinStock;
  final int defaultRefillQty;

  factory AsiaBotSettings.defaults() => const AsiaBotSettings(
        enabled: true,
        autoRefill: true,
        apiBaseUrl: 'http://127.0.0.1:8765',
        apiToken: 'kushk-bot-secret',
        defaultMinStock: 3,
        defaultRefillQty: 5,
      );

  factory AsiaBotSettings.fromMap(Map<String, dynamic>? d) {
    final m = d ?? {};
    return AsiaBotSettings(
      enabled: m['enabled'] ?? true,
      autoRefill: m['autoRefill'] ?? true,
      apiBaseUrl: (m['apiBaseUrl'] ?? 'http://127.0.0.1:8765').toString(),
      apiToken: (m['apiToken'] ?? 'kushk-bot-secret').toString(),
      defaultMinStock: (m['defaultMinStock'] ?? 3) as int,
      defaultRefillQty: (m['defaultRefillQty'] ?? 5) as int,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'enabled': enabled,
        'autoRefill': autoRefill,
        'apiBaseUrl': apiBaseUrl,
        'apiToken': apiToken,
        'defaultMinStock': defaultMinStock,
        'defaultRefillQty': defaultRefillQty,
        'updatedAt': FieldValue.serverTimestamp(),
      };
}

/// ربط فئة كشك بمنتج آسيا للبوت.
class AsiaBotProductMap {
  const AsiaBotProductMap({
    required this.productId,
    required this.enabled,
    required this.asiaProductId,
    required this.catId,
    required this.provider,
    required this.minStock,
    required this.refillQty,
    this.productName = '',
    this.companyName = '',
    this.asiaProductName = '',
    this.asiaCatName = '',
    this.lastStatus,
    this.lastMessage,
    this.lastRequestAt,
  });

  final String productId;
  final bool enabled;
  final String asiaProductId;
  final String catId;
  final String provider;
  final int minStock;
  final int refillQty;
  final String productName;
  final String companyName;
  final String asiaProductName;
  final String asiaCatName;
  final String? lastStatus;
  final String? lastMessage;
  final DateTime? lastRequestAt;

  factory AsiaBotProductMap.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? {};
    return AsiaBotProductMap(
      productId: doc.id,
      enabled: d['enabled'] ?? false,
      asiaProductId: (d['cardId'] ?? d['asiaProductId'] ?? '').toString(),
      catId: (d['catId'] ?? '').toString(),
      provider: (d['provider'] ?? 'like_card').toString(),
      minStock: (d['minStock'] ?? 3) as int,
      refillQty: (d['refillQty'] ?? 5) as int,
      productName: (d['productName'] ?? '').toString(),
      companyName: (d['companyName'] ?? '').toString(),
      asiaProductName: (d['baqatyCardName'] ?? d['asiaProductName'] ?? '').toString(),
      asiaCatName: (d['baqatyCatName'] ?? d['asiaCatName'] ?? '').toString(),
      lastStatus: d['lastStatus']?.toString(),
      lastMessage: d['lastMessage']?.toString(),
      lastRequestAt: d['lastRequestAt'] is Timestamp
          ? (d['lastRequestAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'enabled': enabled,
        'cardId': asiaProductId,
        'asiaProductId': asiaProductId,
        'catId': catId,
        'provider': provider,
        'minStock': minStock,
        'refillQty': refillQty,
        'productName': productName,
        'companyName': companyName,
        'baqatyCardName': asiaProductName,
        'baqatyCatName': asiaCatName,
        'asiaProductName': asiaProductName,
        'asiaCatName': asiaCatName,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  AsiaBotProductMap copyWith({
    bool? enabled,
    String? asiaProductId,
    String? catId,
    String? provider,
    int? minStock,
    int? refillQty,
    String? productName,
    String? companyName,
    String? asiaProductName,
    String? asiaCatName,
  }) {
    return AsiaBotProductMap(
      productId: productId,
      enabled: enabled ?? this.enabled,
      asiaProductId: asiaProductId ?? this.asiaProductId,
      catId: catId ?? this.catId,
      provider: provider ?? this.provider,
      minStock: minStock ?? this.minStock,
      refillQty: refillQty ?? this.refillQty,
      productName: productName ?? this.productName,
      companyName: companyName ?? this.companyName,
      asiaProductName: asiaProductName ?? this.asiaProductName,
      asiaCatName: asiaCatName ?? this.asiaCatName,
      lastStatus: lastStatus,
      lastMessage: lastMessage,
      lastRequestAt: lastRequestAt,
    );
  }
}
