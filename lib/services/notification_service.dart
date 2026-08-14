import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/password_reset_request.dart';
import '../models/user_notification.dart';
import 'functions_service.dart';

class NotificationService {
  NotificationService({FirebaseFirestore? db, FunctionsService? functions})
    : _db = db ?? FirebaseFirestore.instance,
      _functions = functions ?? FunctionsService();

  final FirebaseFirestore _db;
  final FunctionsService _functions;

  Stream<List<UserNotification>> watchNotifications(String userId) {
    return _db
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .limit(100)
        .snapshots()
        .map((s) {
          final list =
              s.docs
                  .map(UserNotification.fromFirestore)
                  .where((item) => !item.isDeviceRequest)
                  .toList()
                ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list;
        });
  }

  Stream<int> watchUnreadCount(String userId) {
    return _db
        .collection('user_notification_state')
        .doc(userId)
        .snapshots()
        .map((doc) => (doc.data()?['unreadCount'] as num?)?.toInt() ?? 0);
  }

  Future<void> markAllRead() => _functions.markNotificationsRead();

  Stream<List<PasswordResetRequest>> watchPasswordResetRequests() {
    return _db.collection('password_reset_requests').limit(100).snapshots().map(
      (s) {
        final list = s.docs.map(PasswordResetRequest.fromFirestore).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list;
      },
    );
  }

  Stream<PasswordResetRequest?> watchPasswordResetRequest(String requestId) {
    return _db
        .collection('password_reset_requests')
        .doc(requestId)
        .snapshots()
        .map((doc) {
          if (!doc.exists) return null;
          return PasswordResetRequest.fromFirestore(doc);
        });
  }
}
