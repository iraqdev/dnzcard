import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/app_settings.dart';

class SettingsService {
  SettingsService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;
  Stream<AppSettings>? _settingsStream;

  DocumentReference<Map<String, dynamic>> get _ref =>
      _db.collection('app_settings').doc('main');

  /// بث مشترك يعيد آخر قيمة للمشتركين الجدد (مهم لشاشة المتجر بعد فتحها).
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

  Stream<AppSettings> watch() {
    return _settingsStream ??= _shareReplay(
      _ref.snapshots().map((doc) {
        if (!doc.exists) return AppSettings.defaults();
        return AppSettings.fromFirestore(doc);
      }),
    );
  }

  Future<void> save(AppSettings settings) => _ref.set({
        'primaryColor': settings.primaryColor,
        'accentColor': settings.accentColor,
        'storeTitle': settings.storeTitle,
        'supportPhone': settings.supportPhone,
        'minAndroidVersion': settings.minAndroidVersion.trim(),
        'playStoreUrl': settings.playStoreUrl.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  Future<void> saveGameKeyRates({
    required double saleRate,
    required double costRate,
  }) {
    return _ref.set({
      'gameKeySaleRate': saleRate,
      'gameKeyCostRate': costRate,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> saveMinAndroidVersion(String minAndroidVersion) {
    return _ref.set({
      'minAndroidVersion': minAndroidVersion.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> saveFazerEnabled(bool enabled) {
    return _ref.set({
      'fazerEnabled': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
