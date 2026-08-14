import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../models/catalog_models.dart';
import '../models/order_model.dart';
import 'extended_printer_bridge.dart';
import 'installed_printer_store.dart';
import 'order_receipt_pdf.dart';
import 'paper_size.dart';
import 'printer.dart';
import 'printer_discovery_service.dart';
import 'printer_engine_type.dart';
import 'printer_user_messages.dart';
import 'receipt_builder.dart';
import 'receipt_image.dart';
import 'receipt_paper_profile.dart';
import 'receipt_pdf_raster.dart';

class PrinterService {
  PrinterService({Printer? printer}) : _printer = printer ?? kushkPrinter;
  final Printer _printer;

  static Future<void>? _discoveryOnce;

  /// اكتشاف الطابعة عند أول طباعة فقط (لا عند إقلاع التطبيق).
  static Future<void> ensureDiscoveredOnce() {
    return _discoveryOnce ??= () async {
      if (!Platform.isAndroid) return;
      try {
        final existing = await InstalledPrinterStore.loadDiscoveryResult();
        if (existing != null && existing.recognized) return;
        await PrinterDiscoveryService.discoverAndApply().timeout(
          const Duration(seconds: 20),
        );
      } catch (_) {}
    }();
  }

  /// يلتقط نفس ويدجت المعاينة ويعالجها للطباعة الحرارية.
  Future<Uint8List?> _capturePreviewImage({
    required BuildContext context,
    required OrderModel order,
    required String shopName,
    required PaperSizeMm paper,
    required ReceiptPaperProfile profile,
    required int printNumber,
  }) async {
    try {
      final captured = await ReceiptImage.capture(
        context,
        order,
        shopName: shopName,
        paperSize: paper,
        printNumber: printNumber,
      );
      if (captured == null) return null;
      return ReceiptPdfRaster.prepareForThermal(
        captured,
        profile.printWidthPx,
      );
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _imageFromPdf({
    required Uint8List pdfBytes,
    required ReceiptPaperProfile profile,
  }) async {
    try {
      final pages = await ReceiptPdfRaster.rasterToPngPages(
        pdfBytes,
        dpi: profile.rasterDpi,
        maxWidthPx: profile.printWidthPx,
      );
      return pages.isNotEmpty ? pages.first : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _sendToPrinter({
    required PrinterEngineType engine,
    required List<String> lines,
    required Uint8List? imageBytes,
    required Uint8List pdfBytes,
    required ReceiptPaperProfile profile,
  }) async {
    if (engine.usesKushkNativeChannel) {
      await _printer.printReceipt(lines, imageBytes: imageBytes);
      return;
    }

    if (!Platform.isAndroid) {
      throw UnsupportedError(
        PrinterUserMessages.forPrintError('PRINT_ANDROID_ONLY'),
      );
    }

    if (imageBytes != null && engine != PrinterEngineType.androidPrint) {
      await ExtendedPrinterBridge.printPreparedPngPages(
        pages: [imageBytes],
        profile: profile,
        engine: engine,
      );
      return;
    }

    await ExtendedPrinterBridge.printPdfReceipt(
      pdfBytes: pdfBytes,
      profile: profile,
      engine: engine,
    );
  }

  Future<void> printOrder(
    OrderModel order, {
    required String shopName,
    BuildContext? context,
  }) async {
    await ensureDiscoveredOnce();
    final paper = await PaperSizePrefs.load();
    final profile = ReceiptPaperProfile.resolve(paperOverrideMm: paper.mm);
    final engine = await InstalledPrinterStore.loadEngineType();
    final printNumber = order.nextPrintNumber;
    final lines = ReceiptBuilder.forOrder(
      order,
      shopName: shopName,
      printNumber: printNumber,
    );

    Uint8List? imageBytes;
    if (context != null && context.mounted) {
      imageBytes = await _capturePreviewImage(
        context: context,
        order: order,
        shopName: shopName,
        paper: paper,
        profile: profile,
        printNumber: printNumber,
      );
    }

    final pdfBytes = await OrderReceiptPdf.buildForOrder(
      order: order,
      shopName: shopName,
      profile: profile,
      printNumber: printNumber,
    );

    imageBytes ??= await _imageFromPdf(pdfBytes: pdfBytes, profile: profile);

    await _sendToPrinter(
      engine: engine,
      lines: lines,
      imageBytes: imageBytes,
      pdfBytes: pdfBytes,
      profile: profile,
    );
  }

  Future<void> testPrint({BuildContext? context}) async {
    await ensureDiscoveredOnce();
    final paper = await PaperSizePrefs.load();
    final profile = ReceiptPaperProfile.resolve(paperOverrideMm: paper.mm);
    final engine = await InstalledPrinterStore.loadEngineType();
    final testOrder = OrderModel(
      id: 'test',
      shopId: '',
      productId: '',
      productName: '5000',
      companyName: 'اسياسيل',
      quantity: 1,
      unitPrice: 0,
      total: 0,
      cardItems: const [
        CardItem(code: '12345678901234', serialNumber: 'TEST-000001'),
      ],
      paymentMethod: 'wallet',
      status: 'completed',
      createdAt: DateTime.now(),
      printCount: 0,
    );
    const shopName = 'اختبار الطابعة';
    final lines = ReceiptBuilder.forOrder(
      testOrder,
      shopName: shopName,
      printNumber: 1,
    );

    Uint8List? imageBytes;
    if (context != null && context.mounted) {
      imageBytes = await _capturePreviewImage(
        context: context,
        order: testOrder,
        shopName: shopName,
        paper: paper,
        profile: profile,
        printNumber: 1,
      );
    }

    final pdfBytes = await OrderReceiptPdf.buildTest(profile: profile);
    imageBytes ??= await _imageFromPdf(pdfBytes: pdfBytes, profile: profile);

    await _sendToPrinter(
      engine: engine,
      lines: lines,
      imageBytes: imageBytes,
      pdfBytes: pdfBytes,
      profile: profile,
    );
  }

  Future<Map<String, dynamic>> detect() => _printer.detect();
  Future<void> setDriver(String driver) => _printer.setDriver(driver);
  Future<void> setDriverWithDevice({
    required String driver,
    String? address,
    String? id,
  }) =>
      _printer.setDriverWithDevice(
        driver: driver,
        address: address,
        id: id,
      );
  Future<List<Map<String, dynamic>>> listDevices() => _printer.listDevices();
  Future<String> status() => _printer.getStatus();

  Future<PaperSizeMm> loadPaperSize() => PaperSizePrefs.load();

  Future<void> setPaperSize(PaperSizeMm size) async {
    await PaperSizePrefs.save(size);
    await _printer.setPaperSizeMm(size.mm);
  }

  Future<PrinterEngineType> loadEngine() =>
      InstalledPrinterStore.loadEngineType();

  Future<void> setEngine(PrinterEngineType engine, {bool manual = true}) async {
    await InstalledPrinterStore.saveEngineType(engine);
    await InstalledPrinterStore.setEngineManual(manual);
  }
}
