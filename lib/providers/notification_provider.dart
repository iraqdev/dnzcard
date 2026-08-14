import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/user_notification.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';

class NotificationProvider extends ChangeNotifier {
  NotificationProvider(this._auth, this._notifications) {
    _userSub = _auth.watchCurrentUser().listen((user) {
      _notifSub?.cancel();
      _countSub?.cancel();
      if (user == null) {
        items = [];
        unreadCount = 0;
        notifyListeners();
        return;
      }
      _notifSub = _notifications.watchNotifications(user.id).listen((list) {
        items = list;
        notifyListeners();
      });
      _countSub = _notifications.watchUnreadCount(user.id).listen((count) {
        unreadCount = count;
        notifyListeners();
      });
    });
  }

  final AuthService _auth;
  final NotificationService _notifications;
  StreamSubscription? _userSub;
  StreamSubscription? _notifSub;
  StreamSubscription? _countSub;

  List<UserNotification> items = [];
  int unreadCount = 0;

  Future<void> markAllRead() async {
    await _notifications.markAllRead();
  }

  @override
  void dispose() {
    _userSub?.cancel();
    _notifSub?.cancel();
    _countSub?.cancel();
    super.dispose();
  }
}
