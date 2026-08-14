import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../firebase_options.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // إذا وصلت كـ notification payload يعرضها النظام تلقائياً.
  // هنا نعرض يدوياً فقط لرسائل data حتى لا يضيع الإشعار.
  if (message.notification != null) return;
  await FcmService.instance.showRemoteMessage(message);
}

class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();

  static const _channelId = 'kushk_default';
  static const _channelName = 'إشعارات DNZ card';
  static const _channelDesc = 'تنبيهات الإيداع والرسائل من الإدارة';

  final _messaging = FirebaseMessaging.instance;
  final _local = FlutterLocalNotificationsPlugin();
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  GoRouter? _router;
  String? _currentToken;
  String? _lastUid;
  bool _ready = false;
  bool _localReady = false;

  Future<void> initialize({required GoRouter router}) async {
    if (kIsWeb || _ready) {
      _router = router;
      return;
    }
    _router = router;

    await _ensureLocalReady();

    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
    await _messaging.requestPermission(alert: true, badge: true, sound: true);

    FirebaseMessaging.onMessage.listen(showRemoteMessage);
    FirebaseMessaging.onMessageOpenedApp.listen((_) => _openNotifications());

    final initial = await _messaging.getInitialMessage();
    if (initial != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openNotifications());
    }

    _auth.authStateChanges().listen((user) async {
      if (user == null || user.isAnonymous) {
        await _clearToken();
        return;
      }
      _lastUid = user.uid;
      await _registerToken(user.uid);
    });

    _messaging.onTokenRefresh.listen((token) async {
      _currentToken = token;
      final uid = _auth.currentUser?.uid;
      if (uid == null || _auth.currentUser!.isAnonymous) return;
      await _saveToken(uid, token);
    });

    _ready = true;
  }

  Future<void> _ensureLocalReady() async {
    if (_localReady || kIsWeb) return;
    const androidInit = AndroidInitializationSettings('ic_stat_kushk');
    await _local.initialize(
      settings: const InitializationSettings(android: androidInit),
      onDidReceiveNotificationResponse: (_) => _openNotifications(),
    );

    final android = _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      ),
    );
    await android?.requestNotificationsPermission();
    _localReady = true;
  }

  Future<void> _registerToken(String uid) async {
    try {
      final token = await _messaging.getToken();
      if (token == null || token.isEmpty) return;
      _currentToken = token;
      await _saveToken(uid, token);
    } catch (_) {}
  }

  Future<void> _saveToken(String uid, String token) async {
    await _db.collection('users').doc(uid).set({
      'fcmTokens': FieldValue.arrayUnion([token]),
      'fcmUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _clearToken() async {
    final token = _currentToken;
    final uid = _lastUid;
    _currentToken = null;
    _lastUid = null;
    if (token == null || uid == null) return;
    try {
      await _db.collection('users').doc(uid).update({
        'fcmTokens': FieldValue.arrayRemove([token]),
      });
    } catch (_) {}
  }

  Future<Uint8List?> _downloadBytes(String? url) async {
    final value = url?.trim() ?? '';
    if (value.isEmpty) return null;
    try {
      final response = await http
          .get(Uri.parse(value))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response.bodyBytes;
      }
    } catch (_) {}
    return null;
  }

  /// يعرض إشعار FCM مع الصورة الكبيرة والأيقونة إن وُجدتا.
  Future<void> showRemoteMessage(RemoteMessage message) async {
    if (kIsWeb) return;
    await _ensureLocalReady();

    final notification = message.notification;
    final title = notification?.title ?? message.data['title']?.toString();
    final body = notification?.body ?? message.data['body']?.toString();
    if ((title == null || title.isEmpty) && (body == null || body.isEmpty)) {
      return;
    }

    final imageUrl =
        notification?.android?.imageUrl ??
        message.data['imageUrl']?.toString() ??
        message.data['image']?.toString();
    final iconUrl =
        message.data['iconUrl']?.toString() ??
        message.data['icon']?.toString();

    final imageBytes = await _downloadBytes(imageUrl);
    final iconBytes = await _downloadBytes(iconUrl);

    StyleInformation? style;
    AndroidBitmap<Object>? largeIcon;
    if (iconBytes != null && iconBytes.isNotEmpty) {
      largeIcon = ByteArrayAndroidBitmap(iconBytes);
    }
    if (imageBytes != null && imageBytes.isNotEmpty) {
      style = BigPictureStyleInformation(
        ByteArrayAndroidBitmap(imageBytes),
        largeIcon: largeIcon,
        contentTitle: title,
        summaryText: body,
        htmlFormatContentTitle: false,
        htmlFormatSummaryText: false,
      );
    }

    await _local.show(
      id: message.hashCode & 0x7fffffff,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          icon: 'ic_stat_kushk',
          color: const Color(0xFF0B3B4A),
          largeIcon: largeIcon,
          styleInformation: style,
          playSound: true,
          enableVibration: true,
        ),
      ),
    );
  }

  void _openNotifications() {
    final router = _router;
    if (router == null) return;
    router.go('/notifications');
  }
}
