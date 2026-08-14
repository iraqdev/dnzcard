import 'package:cloud_firestore/cloud_firestore.dart';

class PasswordResetRequest {
  const PasswordResetRequest({
    required this.id,
    required this.userId,
    required this.phone,
    required this.shopName,
    required this.deviceId,
    required this.deviceName,
    required this.status,
    required this.serverApproved,
    required this.createdAt,
    this.reviewedAt,
    this.completedAt,
  });

  final String id;
  final String userId;
  final String phone;
  final String shopName;
  final String deviceId;
  final String deviceName;
  final String status;
  final bool serverApproved;
  final DateTime createdAt;
  final DateTime? reviewedAt;
  final DateTime? completedAt;

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved' && serverApproved;
  bool get isCompleted => status == 'completed';

  factory PasswordResetRequest.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? {};
    DateTime date(dynamic v) =>
        v is Timestamp ? v.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
    return PasswordResetRequest(
      id: doc.id,
      userId: d['userId'] ?? '',
      phone: d['phone'] ?? '',
      shopName: d['shopName'] ?? '',
      deviceId: d['deviceId'] ?? '',
      deviceName: d['deviceName'] ?? '',
      status: d['status'] ?? 'pending',
      serverApproved: d['serverApproved'] == true,
      createdAt: date(d['createdAt']),
      reviewedAt: d['reviewedAt'] is Timestamp
          ? (d['reviewedAt'] as Timestamp).toDate()
          : null,
      completedAt: d['completedAt'] is Timestamp
          ? (d['completedAt'] as Timestamp).toDate()
          : null,
    );
  }
}
