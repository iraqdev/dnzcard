import 'dart:io';

import 'package:flutter/services.dart';

abstract final class IposBuiltInPrinter {
  static const _channel = MethodChannel('kushk/ipos_built_in_printer');

  static Future<bool> isAvailable() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> probeConnect() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('probeConnect') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>> getDiagnostics() async {
    if (!Platform.isAndroid) {
      return const {'platform': 'non-android'};
    }
    try {
      final raw = await _channel.invokeMethod<Map>('getDiagnostics');
      if (raw == null) return const {};
      return raw.map((k, v) => MapEntry(k.toString(), v));
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  static Future<void> printPngPages({
    required List<Uint8List> pages,
    required int maxWidthPx,
  }) async {
    await _channel.invokeMethod<void>('printPngPages', {
      'pages': pages,
      'maxWidthPx': maxWidthPx,
    });
  }

  static Future<void> printTestText([
    String text = 'اختبار الطابعة - DNZ card',
  ]) async {
    await _channel.invokeMethod<void>('printTestText', {'text': text});
  }
}
