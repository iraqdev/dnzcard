import 'package:flutter/services.dart';

abstract final class GenericEscPosPrinter {
  static const _channel = MethodChannel('kushk/generic_escpos_printer');

  static Future<bool> hasUsbPrinter() async {
    return await _channel.invokeMethod<bool>('hasUsbPrinter') ?? false;
  }

  static Future<bool> hasUsbPermission() async {
    return await _channel.invokeMethod<bool>('hasUsbPermission') ?? false;
  }

  static Future<bool> requestUsbPermission() async {
    return await _channel.invokeMethod<bool>('requestUsbPermission') ?? false;
  }

  static Future<void> printUsbPngPages({
    required List<Uint8List> pages,
    required int maxWidthPx,
  }) async {
    await _channel.invokeMethod<bool>('printUsbPng', {
      'pages': pages,
      'maxWidthPx': maxWidthPx,
    });
  }

  static Future<void> printNetworkPngPages({
    required String host,
    int port = 9100,
    required List<Uint8List> pages,
    required int maxWidthPx,
  }) async {
    await _channel.invokeMethod<bool>('printNetworkPng', {
      'host': host,
      'port': port,
      'pages': pages,
      'maxWidthPx': maxWidthPx,
    });
  }
}
