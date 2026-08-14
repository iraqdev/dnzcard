import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// معرّف تثبيت ثابت محلياً + اسم الجهاز للعرض فقط.
class DeviceIdentityService {
  DeviceIdentityService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _deviceIdKey = 'kushk_device_id';
  static const _pendingPasswordPrefix = 'kushk_pending_password_';

  Future<String> getDeviceId() async {
    final existing = await _storage.read(key: _deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = const Uuid().v4();
    await _storage.write(key: _deviceIdKey, value: id);
    return id;
  }

  Future<String> getDeviceName() async {
    try {
      final plugin = DeviceInfoPlugin();
      if (kIsWeb) return 'Web';
      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        final brand = info.brand;
        final model = info.model;
        return '$brand $model'.trim();
      }
      if (Platform.isIOS) {
        final info = await plugin.iosInfo;
        return info.name.isNotEmpty ? info.name : info.utsname.machine;
      }
    } catch (_) {}
    return 'جهاز DNZ card';
  }

  Future<void> savePendingPassword(String requestId, String password) {
    return _storage.write(
      key: '$_pendingPasswordPrefix$requestId',
      value: password,
    );
  }

  Future<String?> readPendingPassword(String requestId) {
    return _storage.read(key: '$_pendingPasswordPrefix$requestId');
  }

  Future<void> clearPendingPassword(String requestId) {
    return _storage.delete(key: '$_pendingPasswordPrefix$requestId');
  }

  /// كلمة المرور التي أدخلها المستخدم للاستعادة — للعرض المحلي فقط.
  Future<void> saveDisplayPassword(String password) {
    return _storage.write(key: 'kushk_last_reset_password_display', value: password);
  }

  Future<String?> readDisplayPassword() {
    return _storage.read(key: 'kushk_last_reset_password_display');
  }

  Future<void> clearDisplayPassword() {
    return _storage.delete(key: 'kushk_last_reset_password_display');
  }
}
