import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

class StorageService {
  StorageService({FirebaseStorage? storage})
      : _storage = storage ?? FirebaseStorage.instance;
  final FirebaseStorage _storage;

  Future<String> uploadImage({
    required String folder,
    required Uint8List bytes,
    String? fileName,
    String contentType = 'image/jpeg',
  }) async {
    final extension = fileName?.split('.').last.toLowerCase() ?? 'jpg';
    final safeExtension = ['jpg', 'jpeg', 'png', 'webp'].contains(extension)
        ? extension
        : 'jpg';
    final name = '${const Uuid().v4()}.$safeExtension';
    final ref = _storage.ref().child('$folder/$name');
    await ref.putData(bytes, SettableMetadata(contentType: contentType));
    return ref.getDownloadURL();
  }
}
