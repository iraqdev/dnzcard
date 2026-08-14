import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/app_user.dart';

class AdminService {
  AdminService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  Stream<List<AppUser>> watchUsers({String? status}) {
    return _db.collection('users').snapshots().map((s) {
      var list = s.docs.map(AppUser.fromFirestore).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (status != null) {
        list = list.where((u) => u.status == status).toList();
      }
      return list;
    });
  }

  Future<void> approveUser(String userId, String adminId) {
    return _db.collection('users').doc(userId).update({
      'status': 'approved',
      'approvedAt': FieldValue.serverTimestamp(),
      'approvedBy': adminId,
    });
  }

  Future<void> rejectUser(String userId, String adminId) {
    return _db.collection('users').doc(userId).update({
      'status': 'rejected',
      'approvedAt': FieldValue.serverTimestamp(),
      'approvedBy': adminId,
    });
  }

  Future<void> suspendUser(String userId) {
    return _db.collection('users').doc(userId).update({
      'status': 'suspended',
    });
  }

  Future<void> makeAdmin(String userId) {
    return _db.collection('users').doc(userId).update({
      'role': 'admin',
      'status': 'approved',
    });
  }
}
