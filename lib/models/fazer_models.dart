import 'package:cloud_firestore/cloud_firestore.dart';

const kFazerGameKeyIqdRate = 1470.0;
const kFazerGameKeyCostRate = 1400.0;

class FazerBuyerField {
  const FazerBuyerField({
    required this.key,
    required this.label,
    this.type = 'text',
    this.options = const [],
  });

  final String key;
  final String label;
  final String type;
  final List<FazerFieldOption> options;

  bool get isSelect =>
      type == 'select' && options.isNotEmpty;

  factory FazerBuyerField.fromMap(Map<String, dynamic> m) {
    final rawOptions = m['options'];
    final options = rawOptions is List
        ? rawOptions
            .whereType<Map>()
            .map(
              (e) => FazerFieldOption.fromMap(Map<String, dynamic>.from(e)),
            )
            .where((o) => o.value.isNotEmpty)
            .toList()
        : const <FazerFieldOption>[];
    return FazerBuyerField(
      key: m['key']?.toString() ?? '',
      label: (m['label']?.toString().trim().isNotEmpty == true)
          ? m['label'].toString()
          : (m['key']?.toString() ?? ''),
      type: m['type']?.toString() ?? 'text',
      options: options,
    );
  }
}

class FazerFieldOption {
  const FazerFieldOption({required this.value, required this.label});

  final String value;
  final String label;

  factory FazerFieldOption.fromMap(Map<String, dynamic> m) {
    final value =
        m['value']?.toString().trim() ??
        m['id']?.toString().trim() ??
        m['key']?.toString().trim() ??
        '';
    final label = m['label']?.toString().trim();
    return FazerFieldOption(
      value: value,
      label: label?.isNotEmpty == true ? label! : value,
    );
  }
}

class FazerCategory {
  const FazerCategory({
    required this.id,
    required this.name,
    required this.note,
    required this.imageUrl,
    this.customImageUrl = '',
    this.sortOrder = 999999,
    this.kind = 'gift_card',
    this.platform = '',
    this.region = '',
    this.appid,
    this.buyerFields = const [],
    this.validateCategoryId = '',
    this.supportsValidateId = false,
  });

  final String id;
  final String name;
  final String note;
  final String imageUrl;
  final String customImageUrl;
  final int sortOrder;
  final String kind;
  final String platform;
  final String region;
  final int? appid;
  final List<FazerBuyerField> buyerFields;
  final String validateCategoryId;
  final bool supportsValidateId;

  String get coverUrl {
    if (customImageUrl.isNotEmpty && customImageUrl != 'null') {
      return customImageUrl;
    }
    if (imageUrl.isNotEmpty && imageUrl != 'null') return imageUrl;
    final id = appid;
    if (id != null && id > 0) {
      return 'https://cdn.cloudflare.steamstatic.com/steam/apps/$id/library_600x900.jpg';
    }
    return '';
  }

  bool get isTelegram =>
      kind == 'telegram_stars' || kind == 'telegram_premium';

  bool get isTopup => kind == 'topup';

  String get kindLabel {
    switch (kind) {
      case 'game_key':
        return 'مفتاح لعبة';
      case 'topup':
        return 'شحن بالاي دي';
      case 'telegram_stars':
        return 'تليجرام Stars';
      case 'telegram_premium':
        return 'تليجرام Premium';
      default:
        return 'بطاقة';
    }
  }

  factory FazerCategory.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? {};
    final rawFields = d['buyerFields'];
    final fields = rawFields is List
        ? rawFields
            .whereType<Map>()
            .map((e) => FazerBuyerField.fromMap(Map<String, dynamic>.from(e)))
            .where((f) => f.key.isNotEmpty)
            .toList()
        : const <FazerBuyerField>[];
    return FazerCategory(
      id: doc.id,
      name: d['name']?.toString() ?? '',
      note: d['note']?.toString() ?? '',
      imageUrl: d['imageUrl']?.toString() ?? '',
      customImageUrl: d['customImageUrl']?.toString() ?? '',
      sortOrder: d['sortOrder'] == null
          ? 999999
          : (d['sortOrder'] as num).toInt(),
      kind: d['kind']?.toString() ?? 'gift_card',
      platform: d['platform']?.toString() ?? '',
      region: d['region']?.toString() ?? '',
      appid: (d['appid'] as num?)?.toInt(),
      buyerFields: fields,
      validateCategoryId: d['validateCategoryId']?.toString() ?? '',
      supportsValidateId: d['supportsValidateId'] == true,
    );
  }
}

class FazerOffer {
  const FazerOffer({
    required this.id,
    required this.categoryId,
    required this.cardId,
    required this.categoryName,
    required this.name,
    required this.priceUsd,
    required this.stock,
    required this.imageUrl,
    this.kushkPrice,
    this.kind = 'gift_card',
  });

  final String id;
  final String categoryId;
  final String cardId;
  final String categoryName;
  final String name;
  final double priceUsd;
  final int stock;
  final String imageUrl;
  final double? kushkPrice;
  final String kind;

  bool get isPriced => kushkPrice != null && kushkPrice! > 0;

  bool get isTelegram =>
      kind == 'telegram_stars' || kind == 'telegram_premium';

  bool get isGameKey => kind == 'game_key';

  bool get isTopup => kind == 'topup';

  double gameKeyIqdPrice([double saleRate = kFazerGameKeyIqdRate]) =>
      (priceUsd * saleRate).roundToDouble();

  /// عنوان العرض كما يأتي من فايزر: اسم الفئة + اسم الفئة (مثل Ludo 68500 Gold).
  String get displayTitle {
    final cat = categoryName.trim();
    final n = name.trim();
    if (cat.isEmpty) return n;
    if (n.isEmpty) return cat;
    final catLower = cat.toLowerCase();
    final nameLower = n.toLowerCase();
    if (nameLower.startsWith(catLower) || nameLower.contains(catLower)) {
      return n;
    }
    return '$cat $n';
  }

  factory FazerOffer.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? {};
    final rawKushk = d['kushkPrice'];
    return FazerOffer(
      id: doc.id,
      categoryId: d['categoryId']?.toString() ?? '',
      cardId: d['cardId']?.toString() ?? '',
      categoryName: d['categoryName']?.toString() ?? '',
      name: d['name']?.toString() ?? '',
      priceUsd: (d['priceUsd'] as num?)?.toDouble() ?? 0,
      stock: (d['stock'] as num?)?.toInt() ?? 0,
      imageUrl: d['imageUrl']?.toString() ?? '',
      kushkPrice: rawKushk == null ? null : (rawKushk as num).toDouble(),
      kind: d['kind']?.toString() ?? 'gift_card',
    );
  }
}
