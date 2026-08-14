import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/utils/phone_auth.dart';
import '../models/app_user.dart';
import 'device_identity_service.dart';

class AuthService {
  AuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? db,
    DeviceIdentityService? deviceIdentity,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _db = db ?? FirebaseFirestore.instance,
       _deviceIdentity = deviceIdentity ?? DeviceIdentityService();

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final DeviceIdentityService _deviceIdentity;

  String? _pendingPhone;

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentFirebaseUser => _auth.currentUser;
  DeviceIdentityService get deviceIdentity => _deviceIdentity;
  String? get pendingPhone => _pendingPhone;
  bool get hasPendingOtp => false;

  /// دخول الأدمن عبر الهاتف + كلمة المرور (لوحة الويب فقط).
  Future<void> loginAdmin(String phone, String password) async {
    final authEmail = phoneToAuthEmail(normalizePhone(phone));
    await _auth.signInWithEmailAndPassword(
      email: authEmail,
      password: password,
    );
  }

  /// دخول المتجر عبر رقم الهاتف + كلمة المرور (بدون OTP).
  Future<PhoneAuthOutcome> loginShop(String phone, String password) async {
    final normalized = normalizePhone(phone);
    if (normalized.length < 10) {
      throw ArgumentError('رقم الهاتف غير صالح');
    }
    if (password.length < 6) {
      throw ArgumentError('كلمة المرور يجب أن تكون 6 أحرف على الأقل');
    }

    _pendingPhone = normalized;
    final authEmail = phoneToAuthEmail(normalized);
    try {
      await _auth.signInWithEmailAndPassword(
        email: authEmail,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw StateError(_mapPasswordAuthError(e));
    }
    return _afterPasswordSignIn(normalized);
  }

  /// إنشاء حساب متجر برقم الهاتف + كلمة المرور (بدون OTP).
  Future<PhoneAuthOutcome> registerShop(String phone, String password) async {
    final normalized = normalizePhone(phone);
    if (normalized.length < 10) {
      throw ArgumentError('رقم الهاتف غير صالح');
    }
    if (password.length < 6) {
      throw ArgumentError('كلمة المرور يجب أن تكون 6 أحرف على الأقل');
    }

    final existingShop = await _findShopUserDocByPhone(normalized);
    if (existingShop != null) {
      throw StateError('يوجد حساب بهذا الرقم. سجّل الدخول بدل الإنشاء');
    }

    _pendingPhone = normalized;
    final authEmail = phoneToAuthEmail(normalized);
    try {
      await _auth.createUserWithEmailAndPassword(
        email: authEmail,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        throw StateError('يوجد حساب بهذا الرقم. سجّل الدخول بدل الإنشاء');
      }
      throw StateError(_mapPasswordAuthError(e));
    }
    return _afterPasswordSignIn(normalized);
  }

  Future<PhoneAuthOutcome> _afterPasswordSignIn(String phone) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('فشل تسجيل الدخول');

    final current = await _db.collection('users').doc(uid).get();
    if (current.exists) {
      return PhoneAuthOutcome.signedIn;
    }

    // حساب متجر سابق بنفس الرقم (مثلاً بعد ترحيل من OTP).
    final existingShop = await _findShopUserDocByPhone(phone);
    if (existingShop != null) {
      await _migrateUserDoc(from: existingShop, toUid: uid, phone: phone);
      return PhoneAuthOutcome.signedIn;
    }

    return PhoneAuthOutcome.needsProfile;
  }

  Future<QueryDocumentSnapshot<Map<String, dynamic>>?> _findShopUserDocByPhone(
    String phone,
  ) async {
    final candidates = <String>{
      normalizePhone(phone),
      phone.trim(),
      normalizePhone(phone).replaceFirst('+', ''),
      if (normalizePhone(phone).startsWith('+964'))
        '0${normalizePhone(phone).substring(4)}',
    };

    for (final candidate in candidates) {
      final snap = await _db
          .collection('users')
          .where('phone', isEqualTo: candidate)
          .where('role', isEqualTo: 'shop')
          .limit(10)
          .get();
      if (snap.docs.isNotEmpty) return snap.docs.first;
    }
    return null;
  }

  Future<void> _migrateUserDoc({
    required QueryDocumentSnapshot<Map<String, dynamic>> from,
    required String toUid,
    required String phone,
  }) async {
    if (from.id == toUid) return;
    final data = Map<String, dynamic>.from(from.data());
    data['phone'] = normalizePhone(phone);
    data['migratedFrom'] = from.id;
    data['updatedAt'] = FieldValue.serverTimestamp();
    await _db.collection('users').doc(toUid).set(data, SetOptions(merge: true));

    final txs = await _db
        .collection('wallet_transactions')
        .where('userId', isEqualTo: from.id)
        .limit(400)
        .get();
    if (txs.docs.isNotEmpty) {
      final batch = _db.batch();
      for (final doc in txs.docs) {
        batch.update(doc.reference, {'userId': toUid});
      }
      await batch.commit();
    }

    final topups = await _db
        .collection('wallet_topups')
        .where('userId', isEqualTo: from.id)
        .limit(100)
        .get();
    if (topups.docs.isNotEmpty) {
      final batch = _db.batch();
      for (final doc in topups.docs) {
        batch.update(doc.reference, {'userId': toUid});
      }
      await batch.commit();
    }

    await from.reference.delete();
  }

  /// إكمال بيانات المتجر بعد أول تسجيل ناجح بدون ملف.
  Future<AppUser> completeShopProfile({
    required String name,
    required String shopName,
  }) async {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) {
      throw StateError('يلزم تسجيل الدخول أولاً');
    }

    final trimmedName = name.trim();
    final trimmedShop = shopName.trim();
    if (trimmedName.isEmpty || trimmedShop.isEmpty) {
      throw ArgumentError('أدخل اسم المحل واسم المسؤول');
    }

    final phone = normalizePhone(
      user.phoneNumber ??
          _pendingPhone ??
          authEmailToPhone(user.email) ??
          '',
    );
    if (phone.isEmpty) {
      throw StateError('تعذر قراءة رقم الهاتف');
    }

    final ref = _db.collection('users').doc(user.uid);
    final existing = await ref.get();
    if (existing.exists) {
      // لا نتخطى الحفظ إذا الاسم فارغ في المستند الحالي.
      final current = AppUser.fromFirestore(existing);
      final patch = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (current.name.trim().isEmpty) patch['name'] = trimmedName;
      if (current.shopName.trim().isEmpty) patch['shopName'] = trimmedShop;
      if (current.phone.trim().isEmpty) patch['phone'] = phone;
      if (patch.length > 1) {
        await ref.set(patch, SetOptions(merge: true));
      }
      final fresh = await ref.get();
      return AppUser.fromFirestore(fresh);
    }

    final appUser = AppUser(
      id: user.uid,
      name: trimmedName,
      phone: phone,
      email: '',
      shopName: trimmedShop,
      role: 'shop',
      status: 'approved',
      walletBalance: 0,
      createdAt: DateTime.now(),
    );
    await ref.set(appUser.toFirestore());
    return appUser;
  }

  Future<void> signInWithCustomToken(String token) {
    return _auth.signInWithCustomToken(token);
  }

  Future<void> ensureAnonymous() async {
    if (_auth.currentUser != null) return;
    await _auth.signInAnonymously();
  }

  Future<void> logout() async {
    clearOtpSession();
    await _auth.signOut();
  }

  /// إعادة التحقق بكلمة المرور ثم حذف مستند المستخدم وحساب Firebase Auth.
  Future<void> deleteAccountWithPassword(String password) async {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) {
      throw StateError('يلزم تسجيل الدخول أولاً');
    }
    if (password.length < 6) {
      throw ArgumentError('أدخل كلمة المرور');
    }

    final email = user.email?.trim().isNotEmpty == true
        ? user.email!.trim()
        : phoneToAuthEmail(
            normalizePhone(
              user.phoneNumber ??
                  _pendingPhone ??
                  authEmailToPhone(user.email) ??
                  '',
            ),
          );
    if (email.isEmpty || !email.contains('@')) {
      throw StateError('تعذر التحقق من الحساب. أعد تسجيل الدخول');
    }

    try {
      final credential = EmailAuthProvider.credential(
        email: email,
        password: password,
      );
      await user.reauthenticateWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      throw StateError(_mapPasswordAuthError(e));
    }

    final uid = user.uid;
    final userDoc = _db.collection('users').doc(uid);
    final snap = await userDoc.get();
    if (snap.exists) {
      await userDoc.delete();
    }

    await user.delete();
    clearOtpSession();
  }

  void clearOtpSession() {
    _pendingPhone = null;
  }

  Stream<AppUser?> userStream(String uid) {
    return _db.collection('users').doc(uid).snapshots().map((doc) {
      if (!doc.exists) return null;
      return AppUser.fromFirestore(doc);
    });
  }

  Stream<AppUser?>? _currentUserStream;

  Stream<AppUser?> watchCurrentUser() {
    return _currentUserStream ??= authStateChanges
        .asyncExpand((user) {
          if (user == null || user.isAnonymous) {
            return Stream<AppUser?>.value(null);
          }
          return userStream(user.uid);
        })
        .asBroadcastStream();
  }

  String _mapPasswordAuthError(FirebaseAuthException error) {
    switch (error.code) {
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
      case 'invalid-login-credentials':
        return 'رقم الهاتف أو كلمة المرور غير صحيحة';
      case 'user-disabled':
        return 'هذا الحساب موقوف';
      case 'too-many-requests':
        return 'محاولات كثيرة. حاول لاحقاً';
      case 'network-request-failed':
        return 'تحقق من الاتصال بالإنترنت';
      case 'weak-password':
        return 'كلمة المرور ضعيفة. استخدم 6 أحرف على الأقل';
      case 'email-already-in-use':
        return 'يوجد حساب بهذا الرقم. سجّل الدخول بدل الإنشاء';
      case 'requires-recent-login':
        return 'أعد إدخال كلمة المرور للتأكيد';
      default:
        return error.message?.trim().isNotEmpty == true
            ? error.message!
            : 'تعذر تسجيل الدخول';
    }
  }
}

enum PhoneAuthOutcome { signedIn, needsProfile }
