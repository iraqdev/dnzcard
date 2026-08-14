import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:printing/printing.dart';

/// تحويل PDF إيصال إلى صفحات PNG جاهزة للطباعة الحرارية.
abstract final class ReceiptPdfRaster {
  static Future<List<Uint8List>> rasterToPngPages(
    Uint8List pdfBytes, {
    required double dpi,
    required int maxWidthPx,
  }) async {
    final pages = <Uint8List>[];
    final safeDpi = dpi.clamp(120.0, 203.0);
    await for (final page in Printing.raster(pdfBytes, dpi: safeDpi)) {
      final pngBytes = await page.toPng();
      final prepared = await prepareForThermal(pngBytes, maxWidthPx);
      if (prepared != null) pages.add(prepared);
    }
    return pages;
  }

  /// يعيد صورة بيضاء/سوداء صالحة، أو null إذا كانت الصفحة سوداء تالفة.
  static Future<Uint8List?> prepareForThermal(
    Uint8List pngBytes,
    int maxWidth,
  ) async {
    final decoded = img.decodePng(pngBytes);
    if (decoded == null) return null;

    var work = decoded;
    if (work.width > maxWidth) {
      final h = (work.height * maxWidth / work.width).round().clamp(1, 2500);
      work = img.copyResize(
        work,
        width: maxWidth,
        height: h,
        interpolation: img.Interpolation.linear,
      );
    } else if (work.height > 2500) {
      final w = (work.width * 2500 / work.height).round().clamp(1, maxWidth);
      work = img.copyResize(
        work,
        width: w,
        height: 2500,
        interpolation: img.Interpolation.linear,
      );
    }

    // خلفية بيضاء + تباين حراري؛ الشفافية كانت تخرج أسود على الطابعة.
    var dark = 0;
    final total = work.width * work.height;
    for (var y = 0; y < work.height; y++) {
      for (var x = 0; x < work.width; x++) {
        final p = work.getPixel(x, y);
        final a = p.a.toInt().clamp(0, 255);
        final r = p.r.toInt().clamp(0, 255);
        final g = p.g.toInt().clamp(0, 255);
        final b = p.b.toInt().clamp(0, 255);
        final invA = 255 - a;
        final fr = ((r * a) + (255 * invA)) ~/ 255;
        final fg = ((g * a) + (255 * invA)) ~/ 255;
        final fb = ((b * a) + (255 * invA)) ~/ 255;
        final gray = (0.299 * fr + 0.587 * fg + 0.114 * fb).round();
        final isDark = gray < 160;
        if (isDark) dark++;
        final v = isDark ? 0 : 255;
        work.setPixelRgb(x, y, v, v, v);
      }
    }

    if (total > 0 && dark / total > 0.85) {
      return null;
    }

    return Uint8List.fromList(img.encodePng(work));
  }

  @Deprecated('Use prepareForThermal')
  static Future<Uint8List> fitPngToWidth(
    Uint8List pngBytes,
    int maxWidth,
  ) async {
    return (await prepareForThermal(pngBytes, maxWidth)) ?? pngBytes;
  }
}
