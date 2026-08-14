import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'paper_size.dart';
import 'printer_engine_type.dart';
import 'mini_ble_printer.dart';

abstract final class InstalledPrinterStore {
  static const _engineKey = 'kushk_selected_printer_engine_v1';
  static const _bluetoothDeviceKey = 'kushk_selected_bluetooth_printer_v1';
  static const _miniBleDeviceKey = 'kushk_selected_mini_ble_printer_v1';
  static const _networkHostKey = 'kushk_network_printer_host_v1';
  static const _networkPortKey = 'kushk_network_printer_port_v1';
  static const _discoveryKey = 'kushk_printer_discovery_result_v1';
  static const _manualEngineKey = 'kushk_printer_engine_manual_v1';

  static Future<PrinterEngineType> loadEngineType() async {
    final prefs = await SharedPreferences.getInstance();
    return PrinterEngineTypeLabels.fromId(prefs.getString(_engineKey));
  }

  static Future<void> saveEngineType(PrinterEngineType type) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_engineKey, type.name);
  }

  static Future<bool> isEngineManual() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_manualEngineKey) ?? false;
  }

  static Future<void> setEngineManual(bool manual) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_manualEngineKey, manual);
  }

  static Future<String?> loadBluetoothDeviceJson() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_bluetoothDeviceKey);
  }

  static Future<void> saveBluetoothDeviceJson(String json) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_bluetoothDeviceKey, json);
  }

  static Future<void> clearBluetoothDevice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_bluetoothDeviceKey);
  }

  static Future<MiniBleDeviceInfo?> loadMiniBleDevice() async {
    final prefs = await SharedPreferences.getInstance();
    return MiniBleDeviceInfo.tryParse(prefs.getString(_miniBleDeviceKey));
  }

  static Future<void> saveMiniBleDevice(MiniBleDeviceInfo device) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_miniBleDeviceKey, jsonEncode(device.toJson()));
  }

  static Future<void> clearMiniBleDevice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_miniBleDeviceKey);
  }

  static Future<({String host, int port})> loadNetworkPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      host: prefs.getString(_networkHostKey) ?? '',
      port: prefs.getInt(_networkPortKey) ?? 9100,
    );
  }

  static Future<void> saveNetworkPrinter({
    required String host,
    int port = 9100,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_networkHostKey, host.trim());
    await prefs.setInt(_networkPortKey, port <= 0 ? 9100 : port);
  }

  static Future<void> saveDiscoveryResult(PrinterDiscoveryResult result) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_discoveryKey, jsonEncode(result.toJson()));
  }

  static Future<PrinterDiscoveryResult?> loadDiscoveryResult() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_discoveryKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return PrinterDiscoveryResult.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> syncPaperSize(PaperSizeMm size) async {
    await PaperSizePrefs.save(size);
  }
}

class PrinterDiscoveryResult {
  const PrinterDiscoveryResult({
    required this.recognized,
    required this.displayName,
    required this.manufacturer,
    required this.model,
    required this.engine,
    required this.paperMm,
    this.nativeDriver,
    this.source = 'local',
    this.message,
    this.fingerprint = '',
  });

  final bool recognized;
  final String displayName;
  final String manufacturer;
  final String model;
  final PrinterEngineType engine;
  final int paperMm;
  final String? nativeDriver;
  final String source;
  final String? message;
  final String fingerprint;

  static const unrecognizedMessage = 'لم يتم التعرف على الطابعة';

  factory PrinterDiscoveryResult.unrecognized({
    String manufacturer = '',
    String model = '',
    String fingerprint = '',
  }) {
    return PrinterDiscoveryResult(
      recognized: false,
      displayName: unrecognizedMessage,
      manufacturer: manufacturer,
      model: model,
      engine: PrinterEngineType.kushkNative,
      paperMm: 58,
      source: 'none',
      message: unrecognizedMessage,
      fingerprint: fingerprint,
    );
  }

  Map<String, dynamic> toJson() => {
        'recognized': recognized,
        'displayName': displayName,
        'manufacturer': manufacturer,
        'model': model,
        'engine': engine.name,
        'paperMm': paperMm,
        'nativeDriver': nativeDriver,
        'source': source,
        'message': message,
        'fingerprint': fingerprint,
      };

  factory PrinterDiscoveryResult.fromJson(Map<String, dynamic> json) {
    return PrinterDiscoveryResult(
      recognized: json['recognized'] == true,
      displayName: (json['displayName'] ?? '').toString(),
      manufacturer: (json['manufacturer'] ?? '').toString(),
      model: (json['model'] ?? '').toString(),
      engine: PrinterEngineTypeLabels.fromId(json['engine']?.toString()),
      paperMm: (json['paperMm'] as num?)?.toInt() ?? 58,
      nativeDriver: json['nativeDriver']?.toString(),
      source: (json['source'] ?? 'local').toString(),
      message: json['message']?.toString(),
      fingerprint: (json['fingerprint'] ?? '').toString(),
    );
  }
}
