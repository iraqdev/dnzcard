import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.phone,
    required this.email,
    required this.shopName,
    required this.role,
    required this.status,
    required this.walletBalance,
    this.deferredOwed,
    required this.createdAt,
    this.approvedAt,
    this.approvedBy,
    this.purchasePinEnabled = false,
    this.purchasePinHash,
  });
  final String id, name, phone, email, shopName, role, status;
  final double walletBalance;
  /// الآجل المستحق. null = غير محفوظ بعد (يُحسب من الإيداعات الآجلة).
  final double? deferredOwed;
  final DateTime createdAt;
  final DateTime? approvedAt;
  final String? approvedBy;
  final bool purchasePinEnabled;
  final String? purchasePinHash;

  bool get hasPurchasePin =>
      purchasePinHash != null && purchasePinHash!.isNotEmpty;

  bool get isApprovedShop =>
      role == 'shop' && status != 'suspended' && status != 'rejected';
  bool get isAdmin => role == 'admin';
  factory AppUser.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    DateTime date(dynamic value) =>
        value is Timestamp ? value.toDate() : DateTime.now();
    return AppUser(
      id: doc.id,
      name: d['name'] ?? '',
      phone: d['phone'] ?? '',
      email: d['email'] ?? '',
      shopName: d['shopName'] ?? '',
      role: d['role'] ?? 'shop',
      status: d['status'] ?? 'approved',
      walletBalance: (d['walletBalance'] ?? 0).toDouble(),
      deferredOwed: d['deferredOwed'] == null
          ? null
          : (d['deferredOwed'] as num).toDouble(),
      createdAt: date(d['createdAt']),
      approvedAt: d['approvedAt'] is Timestamp
          ? (d['approvedAt'] as Timestamp).toDate()
          : null,
      approvedBy: d['approvedBy'],
      purchasePinEnabled: d['purchasePinEnabled'] == true,
      purchasePinHash: d['purchasePinHash']?.toString(),
    );
  }
  Map<String, dynamic> toFirestore() => {
    'name': name,
    'phone': phone,
    'email': email,
    'shopName': shopName,
    'role': role,
    'status': status,
    'walletBalance': walletBalance,
    if (deferredOwed != null) 'deferredOwed': deferredOwed,
    'createdAt': Timestamp.fromDate(createdAt),
    if (approvedAt != null) 'approvedAt': Timestamp.fromDate(approvedAt!),
    if (approvedBy != null) 'approvedBy': approvedBy,
    'purchasePinEnabled': purchasePinEnabled,
    if (purchasePinHash != null) 'purchasePinHash': purchasePinHash,
  };
}
