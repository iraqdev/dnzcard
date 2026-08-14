import 'package:cloud_firestore/cloud_firestore.dart';

class PaymentMethodModel {
  const PaymentMethodModel({
    required this.id,
    required this.name,
    required this.key,
    required this.isActive,
    required this.sortOrder,
  });

  final String id;
  final String name;
  final String key;
  final bool isActive;
  final int sortOrder;

  factory PaymentMethodModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? {};
    return PaymentMethodModel(
      id: doc.id,
      name: d['name'] ?? '',
      key: d['key'] ?? '',
      isActive: d['isActive'] ?? true,
      sortOrder: (d['sortOrder'] ?? 0) as int,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'key': key,
        'isActive': isActive,
        'sortOrder': sortOrder,
      };
}
