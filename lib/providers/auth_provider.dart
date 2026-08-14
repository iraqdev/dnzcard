import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/app_user.dart';
import '../services/auth_service.dart';
import '../services/device_identity_service.dart';
import '../services/functions_service.dart';
import '../services/notification_service.dart';

class AuthProvider extends ChangeNotifier {
  AuthProvider(
    this._auth, {
    FunctionsService? functions,
    NotificationService? notifications,
  }) : _functions = functions ?? FunctionsService(),
       _notifications = notifications ?? NotificationService() {
    _sub = _auth.watchCurrentUser().listen(
      (user) {
        _user = user;
        _loading = false;
        notifyListeners();
      },
      onError: (e) {
        _error = e.toString();
        _loading = false;
        notifyListeners();
      },
    );
  }

  final AuthService _auth;
  final FunctionsService _functions;
  final NotificationService _notifications;
  StreamSubscription? _sub;
  StreamSubscription? _resetSub;

  AppUser? _user;
  bool _loading = true;
  String? _error;
  String? _activeResetRequestId;
  bool _otpSent = false;
  bool _awaitingProfile = false;
  String? _verifiedPhone;

  AppUser? get user => _user;
  bool get loading => _loading;
  String? get error => _error;
  bool get isLoggedIn =>
      _auth.currentFirebaseUser != null &&
      !(_auth.currentFirebaseUser!.isAnonymous);
  bool get otpSent => _otpSent;
  bool get awaitingProfile => _awaitingProfile;
  bool get needsProfileCompletion => isLoggedIn && _user == null && !kIsWeb;
  String? get pendingPhone =>
      _verifiedPhone ??
      _auth.pendingPhone ??
      _auth.currentFirebaseUser?.phoneNumber;
  DeviceIdentityService get deviceIdentity => _auth.deviceIdentity;

  /// دخول الأدمن (ويب) برقم هاتف وكلمة مرور.
  Future<void> loginAdmin(String phone, String password) async {
    _error = null;
    _loading = true;
    notifyListeners();
    try {
      await _auth.loginAdmin(phone, password);
    } catch (e) {
      _error = 'فشل تسجيل الدخول. تحقق من رقم الهاتف وكلمة المرور.';
      _loading = false;
      notifyListeners();
      rethrow;
    }
  }

  /// توافق مع الشاشات القديمة التي تستدعي login.
  Future<void> login(String phone, String password) =>
      loginAdmin(phone, password);

  /// دخول المتجر برقم هاتف وكلمة مرور (بدون OTP).
  Future<PhoneAuthOutcome> loginShop(String phone, String password) async {
    _error = null;
    _loading = true;
    _otpSent = false;
    _awaitingProfile = false;
    _verifiedPhone = null;
    notifyListeners();
    try {
      final outcome = await _auth.loginShop(phone, password);
      _verifiedPhone = _auth.pendingPhone;
      _awaitingProfile = outcome == PhoneAuthOutcome.needsProfile;
      _loading = false;
      notifyListeners();
      return outcome;
    } catch (e) {
      _error = _mapOtpError(e);
      _loading = false;
      notifyListeners();
      rethrow;
    }
  }

  /// إنشاء حساب متجر برقم هاتف وكلمة مرور (بدون OTP).
  Future<PhoneAuthOutcome> registerShop(String phone, String password) async {
    _error = null;
    _loading = true;
    _otpSent = false;
    _awaitingProfile = false;
    _verifiedPhone = null;
    notifyListeners();
    try {
      final outcome = await _auth.registerShop(phone, password);
      _verifiedPhone = _auth.pendingPhone;
      _awaitingProfile = outcome == PhoneAuthOutcome.needsProfile;
      _loading = false;
      notifyListeners();
      return outcome;
    } catch (e) {
      _error = _mapOtpError(e);
      _loading = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> completeShopProfile({
    required String name,
    required String shopName,
  }) async {
    _error = null;
    _loading = true;
    notifyListeners();
    try {
      await _auth.completeShopProfile(name: name, shopName: shopName);
      _awaitingProfile = false;
      _loading = false;
      notifyListeners();
    } catch (e) {
      _error = _mapOtpError(e);
      _loading = false;
      notifyListeners();
      rethrow;
    }
  }

  void clearOtpFlow() {
    _auth.clearOtpSession();
    _otpSent = false;
    _awaitingProfile = false;
    _verifiedPhone = null;
    _error = null;
    notifyListeners();
  }

  Future<String> requestPasswordReset({
    required String phone,
    required String newPassword,
  }) async {
    final deviceId = await _auth.deviceIdentity.getDeviceId();
    final deviceName = await _auth.deviceIdentity.getDeviceName();
    // لا نستخدم Anonymous Auth هنا — الدالة عامة وتُستدعى قبل تسجيل الدخول.
    final result = await _functions.createPasswordResetRequest(
      phone: phone,
      deviceId: deviceId,
      deviceName: deviceName,
    );
    final requestId = result['requestId']?.toString();
    if (requestId == null || requestId.isEmpty) {
      throw StateError('تعذر إنشاء طلب الاستعادة');
    }
    await _auth.deviceIdentity.savePendingPassword(requestId, newPassword);
    _activeResetRequestId = requestId;
    _listenResetCompletion(requestId);
    return requestId;
  }

  bool _completingReset = false;

  void _listenResetCompletion(String requestId) {
    _resetSub?.cancel();
    _completingReset = false;

    Future<void> tick() async {
      if (_completingReset) return;
      try {
        final deviceId = await _auth.deviceIdentity.getDeviceId();
        final status = await _functions.getPasswordResetStatus(
          requestId: requestId,
          deviceId: deviceId,
        );
        final state = status['status']?.toString() ?? 'pending';
        final approved =
            status['serverApproved'] == true &&
            (state == 'approved' || state == 'completed');
        if (state == 'rejected') {
          await _auth.deviceIdentity.clearPendingPassword(requestId);
          _activeResetRequestId = null;
          await _resetSub?.cancel();
          _resetSub = null;
          _error = 'تم رفض طلب استعادة كلمة المرور';
          notifyListeners();
          return;
        }
        if (!approved) return;

        _completingReset = true;
        final password = await _auth.deviceIdentity.readPendingPassword(
          requestId,
        );
        if (password == null || password.isEmpty) {
          _completingReset = false;
          return;
        }
        final deviceName = await _auth.deviceIdentity.getDeviceName();
        final phone = status['phone']?.toString() ?? '';
        try {
          if (state == 'approved') {
            final token = await _functions.completePasswordReset(
              requestId: requestId,
              password: password,
              deviceId: deviceId,
              deviceName: deviceName,
            );
            await _auth.signInWithCustomToken(token);
          } else {
            // اكتمل مسبقاً — دخول مباشر بكلمة المرور الجديدة.
            await _auth.loginShop(phone, password);
          }
          await _auth.deviceIdentity.clearPendingPassword(requestId);
          _activeResetRequestId = null;
          await _resetSub?.cancel();
          _resetSub = null;
          _error = null;
          _loading = false;
          notifyListeners();
        } catch (e) {
          // إن فشل التوكن بعد اكتمال التغيير، جرّب الدخول العادي.
          try {
            if (phone.isNotEmpty) {
              await _auth.loginShop(phone, password);
              await _auth.deviceIdentity.clearPendingPassword(requestId);
              _activeResetRequestId = null;
              await _resetSub?.cancel();
              _resetSub = null;
              _error = null;
              _loading = false;
              notifyListeners();
              return;
            }
          } catch (_) {}
          _completingReset = false;
          _error = 'تعذر إكمال استعادة كلمة المرور: $e';
          notifyListeners();
        }
      } catch (_) {
        // تجاهل أخطاء الشبكة المؤقتة أثناء الانتظار.
      }
    }

    unawaited(tick());
    _resetSub = Stream<void>.periodic(const Duration(seconds: 2)).listen((_) {
      unawaited(tick());
    });
  }

  void resumePendingPasswordReset(String requestId) {
    _activeResetRequestId = requestId;
    _listenResetCompletion(requestId);
  }

  String? get activeResetRequestId => _activeResetRequestId;

  String _mapOtpError(Object e) {
    final msg = e.toString();
    if (msg.contains('invalid-verification-code') ||
        msg.contains('invalid-verification-id')) {
      return 'رمز التحقق غير صحيح';
    }
    if (msg.contains('session-expired')) {
      return 'انتهت صلاحية الرمز. أعد إرسال الرمز';
    }
    if (msg.contains('too-many-requests')) {
      return 'محاولات كثيرة. حاول لاحقاً';
    }
    if (msg.contains('network-request-failed')) {
      return 'تحقق من الاتصال بالإنترنت';
    }
    return msg
        .replaceAll('Exception: ', '')
        .replaceAll('Bad state: ', '')
        .replaceAll('ArgumentError: ', '')
        .replaceAll('StateError: ', '')
        .trim();
  }

  Future<void> logout() async {
    clearOtpFlow();
    await _auth.logout();
  }

  Future<void> deleteAccountWithPassword(String password) async {
    _error = null;
    _loading = true;
    notifyListeners();
    try {
      await _auth.deleteAccountWithPassword(password);
      clearOtpFlow();
      _user = null;
      _loading = false;
      notifyListeners();
    } catch (e) {
      _error = _mapOtpError(e);
      _loading = false;
      notifyListeners();
      rethrow;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _resetSub?.cancel();
    super.dispose();
  }
}
