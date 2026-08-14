import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/wallet_transaction.dart';
import '../services/auth_service.dart';
import '../services/wallet_service.dart';

class WalletProvider extends ChangeNotifier {
  WalletProvider(this._auth, this._wallet) {
    _userSub = _auth.watchCurrentUser().listen((user) {
      _txSub?.cancel();
      _deferredSub?.cancel();
      if (user == null) {
        transactions = [];
        balance = 0;
        deferredOwed = 0;
        notifyListeners();
        return;
      }
      balance = user.walletBalance;
      if (user.deferredOwed != null) {
        deferredOwed = user.deferredOwed!;
      } else {
        _deferredSub = _wallet.watchDeferredDepositTotal(user.id).listen((total) {
          deferredOwed = total;
          notifyListeners();
        });
      }
      _txSub = _wallet.watchTransactions(user.id).listen((list) {
        transactions = list;
        notifyListeners();
      });
      notifyListeners();
    });
  }

  final AuthService _auth;
  final WalletService _wallet;
  StreamSubscription? _userSub;
  StreamSubscription? _txSub;
  StreamSubscription? _deferredSub;

  double balance = 0;
  /// مجموع الإيداعات الآجلة المستحقة على المستخدم.
  double deferredOwed = 0;
  List<WalletTransaction> transactions = [];

  @override
  void dispose() {
    _userSub?.cancel();
    _txSub?.cancel();
    _deferredSub?.cancel();
    super.dispose();
  }
}
