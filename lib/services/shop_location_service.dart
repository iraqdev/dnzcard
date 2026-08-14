import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ShopLocationService {
  ShopLocationService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const _grantedKey = 'kushk_shop_location_granted_v1';
  static const _deniedAtKey = 'kushk_shop_location_denied_at_v1';
  static const retryAfter = Duration(hours: 1);
  static const initialDelay = Duration(seconds: 10);

  Future<bool> isGrantedLocally() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_grantedKey) ?? false;
  }

  Future<bool> shouldPromptNow() async {
    if (kIsWeb) return false;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_grantedKey) == true) return false;
    final deniedAtMs = prefs.getInt(_deniedAtKey);
    if (deniedAtMs == null) return true;
    final deniedAt = DateTime.fromMillisecondsSinceEpoch(deniedAtMs);
    return DateTime.now().difference(deniedAt) >= retryAfter;
  }

  Future<void> markGranted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_grantedKey, true);
    await prefs.remove(_deniedAtKey);
  }

  Future<void> markDenied() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_grantedKey, false);
    await prefs.setInt(_deniedAtKey, DateTime.now().millisecondsSinceEpoch);
  }

  Future<LocationPermission> checkPermission() =>
      Geolocator.checkPermission();

  Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();

  Future<bool> ensureServiceEnabled() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (enabled) return true;
    return Geolocator.openLocationSettings();
  }

  Future<Position?> currentPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> saveShopLocation({
    required String userId,
    required double lat,
    required double lng,
  }) async {
    await _db.collection('users').doc(userId).set(
      {
        'hasShopLocation': true,
        'locationLat': lat,
        'locationLng': lng,
        'locationUpdatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await markGranted();
    return true;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchShopsWithLocation() {
    return _db
        .collection('users')
        .where('hasShopLocation', isEqualTo: true)
        .snapshots();
  }

  Future<bool> captureAndSave(String userId, {bool silent = false}) async {
    final serviceOk = await ensureServiceEnabled();
    if (!serviceOk) {
      if (!silent) await markDenied();
      return false;
    }

    var permission = await checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await requestPermission();
    }
    if (permission == LocationPermission.denied) {
      if (!silent) await markDenied();
      return false;
    }
    if (permission == LocationPermission.deniedForever) {
      if (!silent) {
        await markDenied();
        await Geolocator.openAppSettings();
      }
      return false;
    }

    final position = await currentPosition();
    if (position == null) {
      if (!silent) await markDenied();
      return false;
    }

    await saveShopLocation(
      userId: userId,
      lat: position.latitude,
      lng: position.longitude,
    );
    return true;
  }
}
