import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_esc_pos_utils/flutter_esc_pos_utils.dart' as esc_pos;
import 'package:image/image.dart' as img;
import 'package:pos_printer_unity/pos_printer_unity.dart';
import 'package:printing/printing.dart' show Printing;
import 'package:sunmi_printer_plus/sunmi_printer_plus.dart';
import 'package:thermal_printer_flutter/thermal_printer_flutter.dart'
    hide CapabilityProfile, Generator, PaperSize;

import 'generic_escpos_printer.dart';
import 'installed_printer_store.dart';
import 'ipos_built_in_printer.dart';
import 'mini_ble_printer.dart';
import 'printer_access_guard.dart';
import 'printer_engine_type.dart';
import 'receipt_paper_profile.dart';
import 'receipt_pdf_raster.dart';
import 'senraise_built_in_printer.dart';

/// مسارات طباعة cartsell الإضافية (PDF → raster → محرك).
abstract final class ExtendedPrinterBridge {
  static final _thermal = ThermalPrinterFlutter();
  static PosPrinterUnity? _switchPosUnity;
  static bool _switchPosReady = false;

  static Future<void> printPdfReceipt({
    required Uint8List pdfBytes,
    required ReceiptPaperProfile profile,
    required PrinterEngineType engine,
  }) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('PRINT_ANDROID_ONLY');
    }

    switch (engine) {
      case PrinterEngineType.kushkNative:
        throw StateError('USE_KUSHK_NATIVE_CHANNEL');
      case PrinterEngineType.switchPos:
        await _printSwitchPos(pdfBytes, profile);
      case PrinterEngineType.sunmi:
        await _printSunmi(pdfBytes, profile);
      case PrinterEngineType.senraise:
        await _printWithOemFallback(
          pdfBytes: pdfBytes,
          profile: profile,
          prefer: PrinterEngineType.senraise,
        );
      case PrinterEngineType.bluetoothV1:
        await _printBluetooth(pdfBytes, profile, autoDiscover: false);
      case PrinterEngineType.bluetoothV2:
        await _printBluetooth(pdfBytes, profile, autoDiscover: true);
      case PrinterEngineType.bluetoothMini:
        await _printMiniBle(pdfBytes, profile);
      case PrinterEngineType.k9:
        await _printWithOemFallback(
          pdfBytes: pdfBytes,
          profile: profile,
          prefer: PrinterEngineType.k9,
        );
      case PrinterEngineType.usb:
        await _printUsb(pdfBytes, profile);
      case PrinterEngineType.network:
        await _printNetwork(pdfBytes, profile);
      case PrinterEngineType.androidPrint:
        await Printing.layoutPdf(
          name: 'receipt',
          onLayout: (_) async => pdfBytes,
        );
    }
  }

  static Future<List<Printer>> scanBluetoothPrinters() async {
    if (!Platform.isAndroid) return const [];
    await PrinterAccessGuard.ensureReady(promptEnable: true);
    return _thermal.getPrinters(printerType: PrinterType.bluetooth);
  }

  static Future<void> printNativeTestText() async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('PRINT_ANDROID_ONLY');
    }
    if (await SenraiseBuiltInPrinter.isAvailable() ||
        await SenraiseBuiltInPrinter.probeConnect()) {
      await SenraiseBuiltInPrinter.printTestText();
      return;
    }
    if (await IposBuiltInPrinter.isAvailable() ||
        await IposBuiltInPrinter.probeConnect()) {
      await IposBuiltInPrinter.printTestText();
      return;
    }
    throw StateError('BUILTIN_PRINTER_NOT_AVAILABLE');
  }

  static Future<Map<String, dynamic>> builtInDiagnostics() async {
    if (!Platform.isAndroid) return const {'platform': 'non-android'};
    return {
      'senraise': await SenraiseBuiltInPrinter.getDiagnostics(),
      'ipos': await IposBuiltInPrinter.getDiagnostics(),
    };
  }

  /// طباعة صفحات PNG جاهزة (نفس صورة المعاينة) بدون إعادة بناء PDF.
  static Future<void> printPreparedPngPages({
    required List<Uint8List> pages,
    required ReceiptPaperProfile profile,
    required PrinterEngineType engine,
  }) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('PRINT_ANDROID_ONLY');
    }
    if (pages.isEmpty) {
      throw StateError('EMPTY_RECEIPT_IMAGE');
    }

    switch (engine) {
      case PrinterEngineType.kushkNative:
        throw StateError('USE_KUSHK_NATIVE_CHANNEL');
      case PrinterEngineType.switchPos:
        await _printSwitchPosPages(pages, profile);
      case PrinterEngineType.sunmi:
        await _printSunmiPages(pages);
      case PrinterEngineType.senraise:
        await _printOemPages(
          pages: pages,
          profile: profile,
          prefer: PrinterEngineType.senraise,
        );
      case PrinterEngineType.bluetoothV1:
        await _printBluetoothPages(
          pages,
          profile,
          autoDiscover: false,
        );
      case PrinterEngineType.bluetoothV2:
        await _printBluetoothPages(
          pages,
          profile,
          autoDiscover: true,
        );
      case PrinterEngineType.bluetoothMini:
        await MiniBlePrinter.printPngPages(pages);
      case PrinterEngineType.k9:
        await _printOemPages(
          pages: pages,
          profile: profile,
          prefer: PrinterEngineType.k9,
        );
      case PrinterEngineType.usb:
        await _printUsbPages(pages, profile);
      case PrinterEngineType.network:
        await _printNetworkPages(pages, profile);
      case PrinterEngineType.androidPrint:
        throw StateError('ANDROID_PRINT_NEEDS_PDF');
    }
  }

  static Future<void> _printUsbPages(
    List<Uint8List> pages,
    ReceiptPaperProfile profile,
  ) async {
    if (!await GenericEscPosPrinter.hasUsbPrinter()) {
      throw StateError('USB_PRINTER_NOT_FOUND');
    }
    if (!await GenericEscPosPrinter.hasUsbPermission()) {
      final granted = await GenericEscPosPrinter.requestUsbPermission();
      if (!granted) throw StateError('USB_PERMISSION_DENIED');
    }
    await GenericEscPosPrinter.printUsbPngPages(
      pages: pages,
      maxWidthPx: profile.printWidthPx,
    );
  }

  static Future<void> _printNetworkPages(
    List<Uint8List> pages,
    ReceiptPaperProfile profile,
  ) async {
    final config = await InstalledPrinterStore.loadNetworkPrinter();
    if (config.host.isEmpty) {
      throw StateError('NETWORK_PRINTER_NOT_CONFIGURED');
    }
    await GenericEscPosPrinter.printNetworkPngPages(
      host: config.host,
      port: config.port,
      pages: pages,
      maxWidthPx: profile.printWidthPx,
    );
  }

  static Future<void> _printSwitchPosPages(
    List<Uint8List> pages,
    ReceiptPaperProfile profile,
  ) async {
    _switchPosUnity ??= PosPrinterUnity();
    if (!_switchPosReady) {
      final init = await _switchPosUnity!.init();
      if (!init.success) {
        await _printOemPages(
          pages: pages,
          profile: profile,
          prefer: PrinterEngineType.senraise,
        );
        return;
      }
      _switchPosReady = true;
    }
    try {
      for (final page in pages) {
        final result = await _switchPosUnity!.printBitmap(page);
        if (!result.success) {
          throw StateError(result.errorMessage ?? 'SWITCH_POS_PRINT_FAILED');
        }
      }
      await _switchPosUnity!.feedPaper(lines: 3);
    } catch (_) {
      await _printOemPages(
        pages: pages,
        profile: profile,
        prefer: PrinterEngineType.senraise,
      );
    }
  }

  static Future<void> _printSunmiPages(List<Uint8List> pages) async {
    final sunmi = SunmiPrinterPlus();
    final bound = await sunmi.rebindPrinter();
    if (!bound) throw StateError('SUNMI_PRINTER_UNAVAILABLE');
    for (final page in pages) {
      await sunmi.printImage(page, align: SunmiPrintAlign.CENTER);
    }
    await sunmi.lineWrap(times: 1);
    await sunmi.cutPaper();
  }

  static Future<void> _printOemPages({
    required List<Uint8List> pages,
    required ReceiptPaperProfile profile,
    required PrinterEngineType prefer,
  }) async {
    final escPosPayload = await _buildEscPosPayload(pages, profile);
    final backends = prefer == PrinterEngineType.k9
        ? [_OemPrintBackend.ipos, _OemPrintBackend.senraise]
        : [_OemPrintBackend.senraise, _OemPrintBackend.ipos];

    Object? lastError;
    for (final backend in backends) {
      if (!await backend.isReachable()) continue;
      try {
        await backend.printReceipt(
          pages: pages,
          maxWidthPx: profile.printWidthPx,
          escPosPayload: escPosPayload,
        );
        return;
      } catch (e) {
        lastError = e;
      }
    }
    if (lastError != null) throw lastError;
    throw StateError(
      prefer == PrinterEngineType.k9
          ? 'IPOS_NOT_AVAILABLE'
          : 'SENRAISE_NOT_AVAILABLE',
    );
  }

  static Future<void> _printBluetoothPages(
    List<Uint8List> pages,
    ReceiptPaperProfile profile, {
    required bool autoDiscover,
  }) async {
    await PrinterAccessGuard.ensureReady(promptEnable: true);

    Printer? device;
    if (autoDiscover) {
      final found =
          await _thermal.getPrinters(printerType: PrinterType.bluetooth);
      if (found.isEmpty) throw StateError('ESC_POS_DEVICE_MISSING');
      device = found.first;
    } else {
      final raw = await InstalledPrinterStore.loadBluetoothDeviceJson();
      if (raw != null && raw.isNotEmpty) {
        try {
          device = Printer.fromJson(raw);
        } catch (_) {}
      }
      if (device == null) {
        throw StateError('BLUETOOTH_DEVICE_NOT_SELECTED');
      }
    }

    if (!await _thermal.isConnected(printer: device)) {
      final connected = await _thermal.connect(printer: device);
      if (!connected) throw StateError('ESC_POS_CONNECT_FAILED');
    }

    final paperSize = profile.paperWidthMm <= 58
        ? esc_pos.PaperSize.mm58
        : esc_pos.PaperSize.mm80;
    final capability = await esc_pos.CapabilityProfile.load();
    final generator = esc_pos.Generator(paperSize, capability);
    final payload = <int>[];
    for (final page in pages) {
      final decoded = img.decodePng(page);
      if (decoded == null) continue;
      payload.addAll(generator.imageRaster(decoded));
      payload.addAll(generator.feed(1));
    }
    payload.addAll(generator.cut());

    try {
      await _thermal.printBytes(bytes: payload, printer: device);
      if (!autoDiscover) {
        await InstalledPrinterStore.saveBluetoothDeviceJson(device.toJson());
      }
    } finally {
      await _thermal.disconnect(printer: device);
    }
  }

  static Future<void> _printUsb(
    Uint8List pdfBytes,
    ReceiptPaperProfile profile,
  ) async {
    final pages = await ReceiptPdfRaster.rasterToPngPages(
      pdfBytes,
      dpi: profile.rasterDpi,
      maxWidthPx: profile.printWidthPx,
    );
    await _printUsbPages(pages, profile);
  }

  static Future<void> _printNetwork(
    Uint8List pdfBytes,
    ReceiptPaperProfile profile,
  ) async {
    final config = await InstalledPrinterStore.loadNetworkPrinter();
    if (config.host.isEmpty) {
      throw StateError('NETWORK_PRINTER_NOT_CONFIGURED');
    }
    final pages = await ReceiptPdfRaster.rasterToPngPages(
      pdfBytes,
      dpi: profile.rasterDpi,
      maxWidthPx: profile.printWidthPx,
    );
    await GenericEscPosPrinter.printNetworkPngPages(
      host: config.host,
      port: config.port,
      pages: pages,
      maxWidthPx: profile.printWidthPx,
    );
  }

  static Future<void> _printSwitchPos(
    Uint8List pdfBytes,
    ReceiptPaperProfile profile,
  ) async {
    _switchPosUnity ??= PosPrinterUnity();
    if (!_switchPosReady) {
      final init = await _switchPosUnity!.init();
      if (!init.success) {
        await _printWithOemFallback(
          pdfBytes: pdfBytes,
          profile: profile,
          prefer: PrinterEngineType.senraise,
        );
        return;
      }
      _switchPosReady = true;
    }

    try {
      final pages = await ReceiptPdfRaster.rasterToPngPages(
        pdfBytes,
        dpi: profile.rasterDpi,
        maxWidthPx: profile.printWidthPx,
      );
      for (final page in pages) {
        final result = await _switchPosUnity!.printBitmap(page);
        if (!result.success) {
          throw StateError(result.errorMessage ?? 'SWITCH_POS_PRINT_FAILED');
        }
      }
      await _switchPosUnity!.feedPaper(lines: 3);
    } catch (_) {
      await _printWithOemFallback(
        pdfBytes: pdfBytes,
        profile: profile,
        prefer: PrinterEngineType.senraise,
      );
    }
  }

  static Future<void> _printSunmi(
    Uint8List pdfBytes,
    ReceiptPaperProfile profile,
  ) async {
    final sunmi = SunmiPrinterPlus();
    final bound = await sunmi.rebindPrinter();
    if (!bound) throw StateError('SUNMI_PRINTER_UNAVAILABLE');

    final pages = await ReceiptPdfRaster.rasterToPngPages(
      pdfBytes,
      dpi: profile.rasterDpi,
      maxWidthPx: profile.printWidthPx,
    );
    for (final page in pages) {
      await sunmi.printImage(page, align: SunmiPrintAlign.CENTER);
    }
    await sunmi.lineWrap(times: 1);
    await sunmi.cutPaper();
  }

  static Future<void> _printWithOemFallback({
    required Uint8List pdfBytes,
    required ReceiptPaperProfile profile,
    required PrinterEngineType prefer,
  }) async {
    final pages = await ReceiptPdfRaster.rasterToPngPages(
      pdfBytes,
      dpi: profile.rasterDpi,
      maxWidthPx: profile.printWidthPx,
    );
    final escPosPayload = await _buildEscPosPayload(pages, profile);
    final backends = prefer == PrinterEngineType.k9
        ? [_OemPrintBackend.ipos, _OemPrintBackend.senraise]
        : [_OemPrintBackend.senraise, _OemPrintBackend.ipos];

    Object? lastError;
    for (final backend in backends) {
      if (!await backend.isReachable()) continue;
      try {
        await backend.printReceipt(
          pages: pages,
          maxWidthPx: profile.printWidthPx,
          escPosPayload: escPosPayload,
        );
        return;
      } catch (e) {
        lastError = e;
      }
    }
    if (lastError != null) throw lastError;
    throw StateError(
      prefer == PrinterEngineType.k9
          ? 'IPOS_NOT_AVAILABLE'
          : 'SENRAISE_NOT_AVAILABLE',
    );
  }

  static Future<Uint8List> _buildEscPosPayload(
    List<Uint8List> pngPages,
    ReceiptPaperProfile profile,
  ) async {
    final paperSize = profile.paperWidthMm <= 58
        ? esc_pos.PaperSize.mm58
        : esc_pos.PaperSize.mm80;
    final capability = await esc_pos.CapabilityProfile.load();
    final generator = esc_pos.Generator(paperSize, capability);
    final payload = <int>[];
    for (final page in pngPages) {
      final decoded = img.decodePng(page);
      if (decoded == null) continue;
      payload.addAll(generator.imageRaster(decoded));
      payload.addAll(generator.feed(1));
    }
    if (payload.isEmpty) return Uint8List(0);
    payload.addAll(generator.cut());
    return Uint8List.fromList(payload);
  }

  static Future<void> _printBluetooth(
    Uint8List pdfBytes,
    ReceiptPaperProfile profile, {
    required bool autoDiscover,
  }) async {
    await PrinterAccessGuard.ensureReady(promptEnable: true);

    Printer? device;
    if (autoDiscover) {
      final found =
          await _thermal.getPrinters(printerType: PrinterType.bluetooth);
      if (found.isEmpty) throw StateError('ESC_POS_DEVICE_MISSING');
      device = found.first;
    } else {
      final raw = await InstalledPrinterStore.loadBluetoothDeviceJson();
      if (raw != null && raw.isNotEmpty) {
        try {
          device = Printer.fromJson(raw);
        } catch (_) {}
      }
      if (device == null) {
        throw StateError('BLUETOOTH_DEVICE_NOT_SELECTED');
      }
    }

    if (!await _thermal.isConnected(printer: device)) {
      final connected = await _thermal.connect(printer: device);
      if (!connected) throw StateError('ESC_POS_CONNECT_FAILED');
    }

    final paperSize = profile.paperWidthMm <= 58
        ? esc_pos.PaperSize.mm58
        : esc_pos.PaperSize.mm80;
    final capability = await esc_pos.CapabilityProfile.load();
    final generator = esc_pos.Generator(paperSize, capability);
    final pages = await ReceiptPdfRaster.rasterToPngPages(
      pdfBytes,
      dpi: profile.rasterDpi,
      maxWidthPx: profile.printWidthPx,
    );
    final payload = <int>[];
    for (final page in pages) {
      final decoded = img.decodePng(page);
      if (decoded == null) continue;
      payload.addAll(generator.imageRaster(decoded));
      payload.addAll(generator.feed(1));
    }
    payload.addAll(generator.cut());

    try {
      await _thermal.printBytes(bytes: payload, printer: device);
      if (!autoDiscover) {
        await InstalledPrinterStore.saveBluetoothDeviceJson(device.toJson());
      }
    } finally {
      await _thermal.disconnect(printer: device);
    }
  }

  static Future<void> _printMiniBle(
    Uint8List pdfBytes,
    ReceiptPaperProfile profile,
  ) async {
    final pages = await ReceiptPdfRaster.rasterToPngPages(
      pdfBytes,
      dpi: profile.rasterDpi,
      maxWidthPx: 384,
    );
    await MiniBlePrinter.printPngPages(pages);
  }
}

enum _OemPrintBackend { senraise, ipos }

extension on _OemPrintBackend {
  Future<bool> isReachable() async {
    switch (this) {
      case _OemPrintBackend.senraise:
        return await SenraiseBuiltInPrinter.isAvailable() ||
            await SenraiseBuiltInPrinter.probeConnect();
      case _OemPrintBackend.ipos:
        return await IposBuiltInPrinter.isAvailable() ||
            await IposBuiltInPrinter.probeConnect();
    }
  }

  Future<void> printReceipt({
    required List<Uint8List> pages,
    required int maxWidthPx,
    required Uint8List escPosPayload,
  }) async {
    Object? lastError;
    try {
      await printPngPages(pages, maxWidthPx);
      return;
    } catch (e) {
      lastError = e;
    }
    if (this == _OemPrintBackend.senraise && escPosPayload.isNotEmpty) {
      try {
        await SenraiseBuiltInPrinter.printEscPos(escPosPayload);
        return;
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError;
  }

  Future<void> printPngPages(List<Uint8List> pages, int maxWidthPx) async {
    switch (this) {
      case _OemPrintBackend.senraise:
        await SenraiseBuiltInPrinter.printPngPages(
          pages: pages,
          maxWidthPx: maxWidthPx,
        );
      case _OemPrintBackend.ipos:
        await IposBuiltInPrinter.printPngPages(
          pages: pages,
          maxWidthPx: maxWidthPx,
        );
    }
  }
}
