import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../features/store/card_receipt_view.dart';
import '../models/order_model.dart';
import 'paper_size.dart';

/// يلتقط نفس ويدجت المعاينة كصورة PNG للطباعة.
class ReceiptImage {
  static Future<Uint8List?> capture(
    BuildContext context,
    OrderModel order, {
    required String shopName,
    PaperSizeMm? paperSize,
    int? printNumber,
  }) async {
    final overlayState = Overlay.maybeOf(context, rootOverlay: true);
    if (overlayState == null) return null;

    final size = paperSize ?? await PaperSizePrefs.load();
    final key = GlobalKey();
    final overlay = OverlayEntry(
      builder: (_) => Positioned(
        left: -10000,
        top: 0,
        child: Material(
          color: Colors.transparent,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: MediaQuery(
              data: const MediaQueryData(),
              child: RepaintBoundary(
                key: key,
                child: CardReceiptView(
                  order: order,
                  shopName: shopName,
                  compact: true,
                  compactWidth: size.logicalWidth,
                  printNumber: printNumber ?? order.nextPrintNumber,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    overlayState.insert(overlay);

    try {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await WidgetsBinding.instance.endOfFrame;
      return await captureFromKey(key);
    } catch (_) {
      return null;
    } finally {
      overlay.remove();
    }
  }

  static Future<Uint8List?> captureFromKey(GlobalKey key) async {
    try {
      final boundary =
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 2);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }
}
