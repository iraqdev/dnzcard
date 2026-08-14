import 'dart:convert';
import 'dart:typed_data';

import '../models/catalog_models.dart';
import 'functions_service.dart';

class OcrCardResult {
  OcrCardResult({
    required this.fileName,
    required this.code,
    required this.serialNumber,
    this.error,
    this.bytes,
    this.mimeType,
  });

  final String fileName;
  String code;
  String serialNumber;
  String? error;
  final Uint8List? bytes;
  final String? mimeType;

  bool get isValid =>
      error == null && code.trim().isNotEmpty && serialNumber.trim().isNotEmpty;

  CardItem toCardItem() =>
      CardItem(code: code.trim(), serialNumber: serialNumber.trim());
}

/// قراءة صور الكروت عبر Cloud Function (بدون App Check على العميل).
class CardOcrService {
  CardOcrService({FunctionsService? functions})
    : _functions = functions ?? FunctionsService();

  final FunctionsService _functions;

  String _mimeOf(String fileName, String? pickerMime) {
    final fromPicker = pickerMime?.trim().toLowerCase();
    if (fromPicker != null && fromPicker.startsWith('image/')) {
      return fromPicker;
    }
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  Future<OcrCardResult> extractFromImage({
    required Uint8List bytes,
    required String fileName,
    String? mimeType,
  }) async {
    final mime = _mimeOf(fileName, mimeType);
    try {
      final data = await _functions.scanCardImage(
        imageBase64: base64Encode(bytes),
        mimeType: mime,
        fileName: fileName,
      );
      final code = '${data['code'] ?? ''}'.trim();
      final serial = '${data['serialNumber'] ?? ''}'.trim();
      final error = data['error']?.toString();
      final ok = data['ok'] == true;

      if (!ok || code.isEmpty || serial.isEmpty) {
        return OcrCardResult(
          fileName: fileName,
          code: code,
          serialNumber: serial,
          error: (error != null && error.isNotEmpty)
              ? error
              : 'تعذر قراءة PIN أو الرقم التسلسلي من الصورة',
          bytes: bytes,
          mimeType: mime,
        );
      }

      return OcrCardResult(
        fileName: fileName,
        code: code,
        serialNumber: serial,
        bytes: bytes,
        mimeType: mime,
      );
    } catch (e) {
      return OcrCardResult(
        fileName: fileName,
        code: '',
        serialNumber: '',
        error: _mapError(e),
        bytes: bytes,
        mimeType: mime,
      );
    }
  }

  Future<List<OcrCardResult>> extractMany(
    List<({Uint8List bytes, String fileName, String? mimeType})> files,
  ) async {
    final results = <OcrCardResult>[];
    for (final file in files) {
      results.add(
        await extractFromImage(
          bytes: file.bytes,
          fileName: file.fileName,
          mimeType: file.mimeType,
        ),
      );
    }
    return results;
  }

  String _mapError(Object e) {
    return e
        .toString()
        .replaceAll('Exception: ', '')
        .replaceAll('FirebaseFunctionsException: ', '')
        .replaceAll('[firebase_functions/', '[')
        .trim();
  }
}
