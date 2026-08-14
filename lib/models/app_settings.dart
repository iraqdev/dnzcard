import 'package:cloud_firestore/cloud_firestore.dart';

class AppSettings {
  const AppSettings({
    required this.primaryColor,
    required this.accentColor,
    required this.storeTitle,
    required this.supportPhone,
    this.gameKeySaleRate = 1470,
    this.gameKeyCostRate = 1400,
    this.minAndroidVersion = '',
    this.playStoreUrl = '',
  });

  final String primaryColor;
  final String accentColor;
  final String storeTitle;
  final String supportPhone;
  final double gameKeySaleRate;
  final double gameKeyCostRate;
  final String minAndroidVersion;
  final String playStoreUrl;

  factory AppSettings.defaults() => const AppSettings(
        primaryColor: '#0B3B4A',
        accentColor: '#1DB954',
        storeTitle: 'DNZ card',
        supportPhone: '',
        playStoreUrl:
            'https://play.google.com/store/apps/details?id=dnz.dnzteam.Kushk',
      );

  factory AppSettings.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return AppSettings(
      primaryColor: d['primaryColor'] ?? '#0B3B4A',
      accentColor: d['accentColor'] ?? '#1DB954',
      storeTitle: d['storeTitle'] ?? 'DNZ card',
      supportPhone: d['supportPhone'] ?? '',
      gameKeySaleRate: _asRate(d['gameKeySaleRate'], 1470),
      gameKeyCostRate: _asRate(d['gameKeyCostRate'], 1400),
      minAndroidVersion: d['minAndroidVersion']?.toString().trim() ?? '',
      playStoreUrl: d['playStoreUrl']?.toString().trim() ?? '',
    );
  }

  static double _asRate(dynamic value, double fallback) {
    final n = value is num ? value.toDouble() : double.tryParse('$value');
    if (n == null || n <= 0) return fallback;
    return n;
  }

  Map<String, dynamic> toFirestore() => {
        'primaryColor': primaryColor,
        'accentColor': accentColor,
        'storeTitle': storeTitle,
        'supportPhone': supportPhone,
        'gameKeySaleRate': gameKeySaleRate,
        'gameKeyCostRate': gameKeyCostRate,
        'minAndroidVersion': minAndroidVersion,
        'playStoreUrl': playStoreUrl,
      };
}
