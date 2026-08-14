import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'extended_printer_bridge.dart';
import 'generic_escpos_printer.dart';
import 'installed_printer_store.dart';
import 'ipos_built_in_printer.dart';
import 'paper_size.dart';
import 'printer.dart';
import 'printer_engine_type.dart';
import 'printer_service.dart';
import 'senraise_built_in_printer.dart';

/// اكتشاف وتعرف الطابعة: محلي ثم أونلاين، مع ضبط المحرك والورق.
abstract final class PrinterDiscoveryService {
  static List<Map<String, dynamic>>? _localEntries;

  static Future<PrinterDiscoveryResult> discoverAndApply({
    bool respectManualEngine = true,
  }) async {
    if (!Platform.isAndroid) {
      final result = PrinterDiscoveryResult.unrecognized();
      await InstalledPrinterStore.saveDiscoveryResult(result);
      return result;
    }

    final probe = await _collectProbe();
    final fingerprint = probe.fingerprint;

    PrinterDiscoveryResult? match =
        await _matchLocal(probe) ?? await _matchOnline(probe);

    match ??= PrinterDiscoveryResult.unrecognized(
      manufacturer: probe.manufacturer,
      model: probe.model,
      fingerprint: fingerprint,
    );

    // تحسين التعرف عبر خدمات مدمجة حية إن لم يُعرف من الكتالوج.
    if (!match.recognized) {
      match = await _matchLiveServices(probe) ?? match;
    }

    await InstalledPrinterStore.saveDiscoveryResult(match);

    final manual = respectManualEngine &&
        await InstalledPrinterStore.isEngineManual();
    if (match.recognized && !manual) {
      await InstalledPrinterStore.saveEngineType(match.engine);
      final paper = PaperSizeMm.fromMm(match.paperMm);
      await InstalledPrinterStore.syncPaperSize(paper);
      await PrinterService().setPaperSize(paper);
      if (match.nativeDriver != null &&
          match.nativeDriver!.isNotEmpty &&
          match.engine == PrinterEngineType.kushkNative) {
        await PrinterService().setDriver(match.nativeDriver!);
      }
    }

    return match;
  }

  static Future<_DeviceProbe> _collectProbe() async {
    Map<String, dynamic> detect = {};
    List<Map<String, dynamic>> devices = [];
    try {
      detect = await kushkPrinter.detect();
    } catch (_) {}
    try {
      devices = await kushkPrinter.listDevices();
    } catch (_) {}

    final manufacturer =
        (detect['manufacturer'] ?? detect['brand'] ?? '').toString();
    final model = (detect['model'] ?? detect['device'] ?? '').toString();
    final brand = (detect['brand'] ?? '').toString();
    final device = (detect['device'] ?? '').toString();
    final driver = (detect['driver'] ?? detect['selectedDriver'] ?? '')
        .toString()
        .toUpperCase();

    final deviceHints = devices
        .map((d) =>
            '${d['name'] ?? ''} ${d['driver'] ?? ''} ${d['type'] ?? ''}')
        .join(' ');

    var hasUsb = false;
    try {
      hasUsb = await GenericEscPosPrinter.hasUsbPrinter();
    } catch (_) {}

    Map<String, dynamic> senraise = {};
    Map<String, dynamic> ipos = {};
    try {
      final diag = await ExtendedPrinterBridge.builtInDiagnostics();
      senraise = Map<String, dynamic>.from(
        (diag['senraise'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), v),
            ) ??
            {},
      );
      ipos = Map<String, dynamic>.from(
        (diag['ipos'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), v),
            ) ??
            {},
      );
    } catch (_) {}

    final fingerprint = [
      manufacturer,
      brand,
      model,
      device,
      driver,
      deviceHints,
      if (hasUsb) 'USB',
      if (senraise['canBind'] == true || senraise['available'] == true)
        'SENRAISE',
      if (ipos['canBind'] == true || ipos['available'] == true) 'IPOS',
    ].join(' ').toUpperCase();

    return _DeviceProbe(
      manufacturer: manufacturer,
      brand: brand,
      model: model,
      device: device,
      driver: driver,
      fingerprint: fingerprint,
      hasUsb: hasUsb,
      senraiseReachable: senraise['canBind'] == true ||
          senraise['available'] == true ||
          await SenraiseBuiltInPrinter.isAvailable() ||
          await SenraiseBuiltInPrinter.probeConnect(),
      iposReachable: ipos['canBind'] == true ||
          ipos['available'] == true ||
          await IposBuiltInPrinter.isAvailable() ||
          await IposBuiltInPrinter.probeConnect(),
      devices: devices,
    );
  }

  static Future<List<Map<String, dynamic>>> _loadLocalCatalog() async {
    if (_localEntries != null) return _localEntries!;
    try {
      final raw =
          await rootBundle.loadString('assets/printers/printer_catalog.json');
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final entries = (json['entries'] as List?)
              ?.whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [];
      _localEntries = entries;
      return entries;
    } catch (_) {
      _localEntries = [];
      return [];
    }
  }

  static Future<PrinterDiscoveryResult?> _matchLocal(_DeviceProbe probe) async {
    final entries = await _loadLocalCatalog();
    for (final entry in entries) {
      final keys = (entry['matchAny'] as List?)
              ?.map((e) => e.toString().toUpperCase())
              .toList() ??
          [];
      final hit = keys.any((k) => k.isNotEmpty && probe.fingerprint.contains(k));
      if (!hit) continue;
      return _fromCatalogEntry(entry, probe, source: 'local');
    }
    return null;
  }

  static Future<PrinterDiscoveryResult?> _matchOnline(
    _DeviceProbe probe,
  ) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('printer_catalog')
          .limit(100)
          .get()
          .timeout(const Duration(seconds: 8));
      for (final doc in snap.docs) {
        final entry = doc.data();
        final keys = (entry['matchAny'] as List?)
                ?.map((e) => e.toString().toUpperCase())
                .toList() ??
            [];
        // مطابقة حقول مباشرة أيضاً
        final modelKey = (entry['model'] ?? '').toString().toUpperCase();
        final mfgKey = (entry['manufacturer'] ?? '').toString().toUpperCase();
        final hit = keys.any((k) => k.isNotEmpty && probe.fingerprint.contains(k)) ||
            (modelKey.isNotEmpty &&
                probe.fingerprint.contains(modelKey)) ||
            (mfgKey.isNotEmpty && probe.fingerprint.contains(mfgKey));
        if (!hit) continue;
        return _fromCatalogEntry(entry, probe, source: 'online');
      }
    } catch (_) {
      // انقطاع الشبكة أو صلاحيات — نتجاهل ونكمل محلياً.
    }
    return null;
  }

  static Future<PrinterDiscoveryResult?> _matchLiveServices(
    _DeviceProbe probe,
  ) async {
    if (probe.driver.contains('CENTERM') ||
        probe.fingerprint.contains('CENTERM') ||
        probe.fingerprint.contains('MTHD') ||
        probe.fingerprint.contains('ROVOO')) {
      return PrinterDiscoveryResult(
        recognized: true,
        displayName: 'Centerm / ROVOO (مدمجة)',
        manufacturer: probe.manufacturer,
        model: probe.model,
        engine: PrinterEngineType.kushkNative,
        paperMm: 58,
        nativeDriver: 'CENTERM',
        source: 'live',
        fingerprint: probe.fingerprint,
      );
    }
    if (probe.senraiseReachable) {
      return PrinterDiscoveryResult(
        recognized: true,
        displayName: 'Senraise (مدمجة)',
        manufacturer: probe.manufacturer,
        model: probe.model,
        engine: PrinterEngineType.senraise,
        paperMm: 58,
        source: 'live',
        fingerprint: probe.fingerprint,
      );
    }
    if (probe.iposReachable) {
      return PrinterDiscoveryResult(
        recognized: true,
        displayName: 'iPos / K9 (مدمجة)',
        manufacturer: probe.manufacturer,
        model: probe.model,
        engine: PrinterEngineType.k9,
        paperMm: 58,
        source: 'live',
        fingerprint: probe.fingerprint,
      );
    }
    if (probe.hasUsb) {
      return PrinterDiscoveryResult(
        recognized: true,
        displayName: 'طابعة USB',
        manufacturer: probe.manufacturer,
        model: probe.model,
        engine: PrinterEngineType.usb,
        paperMm: 58,
        source: 'live',
        fingerprint: probe.fingerprint,
      );
    }
    final btDevice = probe.devices.cast<Map<String, dynamic>?>().firstWhere(
          (d) =>
              (d?['type']?.toString().toLowerCase().contains('bluetooth') ??
                  false) ||
              (d?['driver']?.toString().toUpperCase() == 'BLUETOOTH'),
          orElse: () => null,
        );
    if (btDevice != null) {
      return PrinterDiscoveryResult(
        recognized: true,
        displayName: (btDevice['name'] ?? 'طابعة Bluetooth').toString(),
        manufacturer: probe.manufacturer,
        model: probe.model,
        engine: PrinterEngineType.bluetoothV2,
        paperMm: 58,
        source: 'live',
        fingerprint: probe.fingerprint,
      );
    }
    return null;
  }

  static PrinterDiscoveryResult _fromCatalogEntry(
    Map<String, dynamic> entry,
    _DeviceProbe probe, {
    required String source,
  }) {
    return PrinterDiscoveryResult(
      recognized: true,
      displayName: (entry['displayName'] ?? 'طابعة معروفة').toString(),
      manufacturer: probe.manufacturer,
      model: probe.model,
      engine: PrinterEngineTypeLabels.fromId(entry['engine']?.toString()),
      paperMm: (entry['paperMm'] as num?)?.toInt() ?? 58,
      nativeDriver: entry['nativeDriver']?.toString(),
      source: source,
      fingerprint: probe.fingerprint,
    );
  }
}

class _DeviceProbe {
  const _DeviceProbe({
    required this.manufacturer,
    required this.brand,
    required this.model,
    required this.device,
    required this.driver,
    required this.fingerprint,
    required this.hasUsb,
    required this.senraiseReachable,
    required this.iposReachable,
    required this.devices,
  });

  final String manufacturer;
  final String brand;
  final String model;
  final String device;
  final String driver;
  final String fingerprint;
  final bool hasUsb;
  final bool senraiseReachable;
  final bool iposReachable;
  final List<Map<String, dynamic>> devices;
}
