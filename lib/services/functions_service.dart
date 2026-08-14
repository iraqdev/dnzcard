import 'package:cloud_functions/cloud_functions.dart';

class FunctionsService {
  FunctionsService({
    FirebaseFunctions? functions,
    FirebaseFunctions? walletFunctions,
  }) : _functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'europe-west1'),
       _walletFunctions =
           walletFunctions ??
           FirebaseFunctions.instanceFor(region: 'me-west1');

  final FirebaseFunctions _functions;
  /// دوال الشحن عبر DNZ في me-west1 لتقليل مشاكل الوصول الجغرافي.
  final FirebaseFunctions _walletFunctions;

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data, {
    FirebaseFunctions? client,
    Duration? timeout,
  }) async {
    final callable = (client ?? _functions).httpsCallable(
      name,
      options: timeout == null
          ? null
          : HttpsCallableOptions(timeout: timeout),
    );
    final result = await callable.call(data);
    final payload = result.data;
    if (payload is Map) {
      return Map<String, dynamic>.from(payload);
    }
    return {};
  }

  Future<Map<String, dynamic>> createPasswordResetRequest({
    required String phone,
    required String deviceId,
    required String deviceName,
  }) {
    return _call('createPasswordResetRequest', {
      'phone': phone,
      'deviceId': deviceId,
      'deviceName': deviceName,
    });
  }

  Future<void> reviewPasswordResetRequest({
    required String requestId,
    required bool approve,
  }) async {
    await _call('reviewPasswordResetRequest', {
      'requestId': requestId,
      'approve': approve,
    });
  }

  Future<String> completePasswordReset({
    required String requestId,
    required String password,
    required String deviceId,
    required String deviceName,
  }) async {
    final data = await _call('completePasswordReset', {
      'requestId': requestId,
      'password': password,
      'deviceId': deviceId,
      'deviceName': deviceName,
    });
    final token = data['customToken']?.toString();
    if (token == null || token.isEmpty) {
      throw StateError('تعذر الحصول على رمز الدخول');
    }
    return token;
  }

  Future<Map<String, dynamic>> getPasswordResetStatus({
    required String requestId,
    required String deviceId,
  }) {
    return _call('getPasswordResetStatus', {
      'requestId': requestId,
      'deviceId': deviceId,
    });
  }

  Future<void> sendAdminMessage({
    required String userId,
    required String title,
    required String body,
  }) async {
    await _call('sendAdminMessage', {
      'userId': userId,
      'title': title,
      'body': body,
    });
  }

  Future<void> adminDeleteUser({required String userId}) async {
    await _call('adminDeleteUser', {'userId': userId});
  }

  Future<void> adminSetUserPassword({
    required String userId,
    required String password,
  }) async {
    await _call('adminSetUserPassword', {
      'userId': userId,
      'password': password,
    });
  }

  Future<void> adminUpdateUser({
    required String userId,
    required String name,
    required String shopName,
    required String phone,
    required String email,
    required String role,
    required String status,
    required double walletBalance,
    required double deferredOwed,
    double? previousDeferredOwed,
  }) async {
    await _call('adminUpdateUser', {
      'userId': userId,
      'name': name,
      'shopName': shopName,
      'phone': phone,
      'email': email,
      'role': role,
      'status': status,
      'walletBalance': walletBalance,
      'deferredOwed': deferredOwed,
      if (previousDeferredOwed != null)
        'previousDeferredOwed': previousDeferredOwed,
    });
  }

  Future<Map<String, dynamic>> adminSendCampaign({
    required String title,
    required String body,
    String? imageUrl,
    String? iconUrl,
    required String target,
    List<String>? phones,
    double? minBalance,
    List<String>? userIds,
  }) {
    return _call('adminSendCampaign', {
      'title': title,
      'body': body,
      if (imageUrl != null && imageUrl.isNotEmpty) 'imageUrl': imageUrl,
      if (iconUrl != null && iconUrl.isNotEmpty) 'iconUrl': iconUrl,
      'target': target,
      if (phones != null) 'phones': phones,
      if (minBalance != null) 'minBalance': minBalance,
      if (userIds != null) 'userIds': userIds,
    }, timeout: const Duration(seconds: 300));
  }

  Future<Map<String, dynamic>> fazerGetBalance() {
    return _call('fazerGetBalance', {});
  }

  Future<Map<String, dynamic>> fazerSyncGiftCategories() {
    return _call(
      'fazerSyncGiftCategories',
      {},
      timeout: const Duration(seconds: 300),
    );
  }

  Future<Map<String, dynamic>> fazerSyncGameKeyCategories() {
    return _call(
      'fazerSyncGameKeyCategories',
      {},
      timeout: const Duration(seconds: 300),
    );
  }

  Future<Map<String, dynamic>> fazerSyncTopupCategories() {
    return _call(
      'fazerSyncTopupCategories',
      {},
      timeout: const Duration(seconds: 300),
    );
  }

  Future<Map<String, dynamic>> fazerSyncTelegramCatalog() {
    return _call(
      'fazerSyncTelegramCatalog',
      {},
      timeout: const Duration(seconds: 60),
    );
  }

  Future<Map<String, dynamic>> fazerSyncCategoryOffers({
    required String categoryId,
  }) {
    return _call('fazerSyncCategoryOffers', {'categoryId': categoryId});
  }

  Future<Map<String, dynamic>> fazerValidateTopupId({
    required String categoryId,
    required Map<String, String> fields,
  }) {
    return _call('fazerValidateTopupId', {
      'categoryId': categoryId,
      'fields': fields,
    });
  }

  Future<void> fazerSetOfferKushkPrice({
    required String offerId,
    double? kushkPrice,
  }) async {
    await _call('fazerSetOfferKushkPrice', {
      'offerId': offerId,
      'kushkPrice': kushkPrice,
    });
  }

  Future<Map<String, dynamic>> fazerPurchaseGiftCard({
    required String offerId,
    int quantity = 1,
    String? telegramUsername,
    Map<String, String>? fields,
    String? pin,
  }) {
    return _call(
      'fazerPurchaseGiftCard',
      {
        'offerId': offerId,
        'quantity': quantity,
        if (telegramUsername != null && telegramUsername.isNotEmpty)
          'telegramUsername': telegramUsername,
        if (fields != null && fields.isNotEmpty) 'fields': fields,
        if (pin != null && pin.isNotEmpty) 'pin': pin,
      },
      timeout: const Duration(seconds: 120),
    );
  }

  Future<Map<String, dynamic>> purchaseLocalProduct({
    required String productId,
    int quantity = 1,
    String? pin,
  }) {
    return _call(
      'purchaseLocalProduct',
      {
        'productId': productId,
        'quantity': quantity,
        if (pin != null && pin.isNotEmpty) 'pin': pin,
      },
      timeout: const Duration(seconds: 60),
    );
  }

  Future<void> markNotificationsRead() async {
    await _call('markNotificationsRead', {});
  }

  Future<Map<String, dynamic>> createWalletTopup({required int amount}) {
    return _call('createWalletTopup', {
      'amount': amount,
    }, client: _walletFunctions);
  }

  Future<Map<String, dynamic>> createZainCashTopup({required int amount}) {
    return _call('createZainCashTopup', {
      'amount': amount,
    }, client: _walletFunctions);
  }

  Future<Map<String, dynamic>> startZainCashPayment({
    required String topupId,
  }) {
    return _call('startZainCashPayment', {
      'topupId': topupId,
    }, client: _walletFunctions);
  }

  Future<Map<String, dynamic>> registerZainCashTransaction({
    required String topupId,
    required String zainTransactionId,
    String? checkoutUrl,
  }) {
    return _call('registerZainCashTransaction', {
      'topupId': topupId,
      'zainTransactionId': zainTransactionId,
      ?'checkoutUrl': checkoutUrl,
    }, client: _walletFunctions);
  }

  Future<Map<String, dynamic>> completeZainCashTopup({
    required String topupId,
    String? zainTransactionId,
  }) {
    return _call('completeZainCashTopup', {
      'topupId': topupId,
      ?'zainTransactionId': zainTransactionId,
    }, client: _walletFunctions);
  }

  Future<Map<String, dynamic>> checkWalletTopupStatus({
    required String topupId,
  }) {
    return _call('checkWalletTopupStatus', {
      'topupId': topupId,
    }, client: _walletFunctions);
  }

  Future<Map<String, dynamic>> reconcilePendingWalletTopups() {
    return _call('reconcilePendingWalletTopups', {}, client: _walletFunctions);
  }

  Future<Map<String, dynamic>> scanCardImage({
    required String imageBase64,
    required String mimeType,
    required String fileName,
  }) {
    return _call('scanCardImage', {
      'imageBase64': imageBase64,
      'mimeType': mimeType,
      'fileName': fileName,
    });
  }
}
