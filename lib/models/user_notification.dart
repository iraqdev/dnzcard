import 'package:cloud_firestore/cloud_firestore.dart';

class UserNotification {
  const UserNotification({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.body,
    required this.badgeEnabled,
    required this.read,
    required this.createdAt,
    this.readAt,
    this.imageUrl,
    this.iconUrl,
    this.meta = const {},
  });

  final String id;
  final String userId;
  final String type;
  final String title;
  final String body;
  final bool badgeEnabled;
  final bool read;
  final DateTime createdAt;
  final DateTime? readAt;
  final String? imageUrl;
  final String? iconUrl;
  final Map<String, dynamic> meta;

  bool get isDeviceRequest => type == 'device_access_request';
  bool get isPasswordChanged => type == 'password_changed';
  bool get isAdminMessage => type == 'admin_message';

  String? get requestId => meta['requestId']?.toString();
  bool get showLocalPassword => meta['showLocalPassword'] == true;

  factory UserNotification.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? {};
    return UserNotification(
      id: doc.id,
      userId: d['userId'] ?? '',
      type: d['type'] ?? 'message',
      title: d['title'] ?? '',
      body: d['body'] ?? '',
      badgeEnabled: d['badgeEnabled'] ?? true,
      read: d['read'] ?? false,
      createdAt: d['createdAt'] is Timestamp
          ? (d['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      readAt: d['readAt'] is Timestamp
          ? (d['readAt'] as Timestamp).toDate()
          : null,
      imageUrl: (d['imageUrl'] ?? (d['meta'] is Map ? (d['meta'] as Map)['imageUrl'] : null))
          ?.toString(),
      iconUrl: (d['iconUrl'] ?? (d['meta'] is Map ? (d['meta'] as Map)['iconUrl'] : null))
          ?.toString(),
      meta: Map<String, dynamic>.from(d['meta'] as Map? ?? const {}),
    );
  }
}
