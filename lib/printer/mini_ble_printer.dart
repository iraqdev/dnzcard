import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:image/image.dart' as img;

import 'installed_printer_store.dart';
import 'printer_access_guard.dart';

/// طابعات الجيب الحرارية (iPrint / Tiny Print / SC03h …) عبر BLE.
/// البروتوكول مبني على هندسة عكسية شائعة (0x5178) وليست ESC/POS.
abstract final class MiniBlePrinter {
  static const printWidth = 384;
  static const _serviceUuid = '0000ae30-0000-1000-8000-00805f9b34fb';
  static const _serviceUuidAlt = '0000ae3a-0000-1000-8000-00805f9b34fb';
  static const _writeUuid = '0000ae01-0000-1000-8000-00805f9b34fb';
  static const _writeUuidAlt = '0000ae3b-0000-1000-8000-00805f9b34fb';

  static final Guid _serviceGuid = Guid(_serviceUuid);
  static final Guid _serviceAltGuid = Guid(_serviceUuidAlt);
  static final Guid _writeGuid = Guid(_writeUuid);
  static final Guid _writeAltGuid = Guid(_writeUuidAlt);

  /// جدول CRC8 كما في تطبيق iPrint (بايتات موقّعة محوّلة إلى 0..255).
  static final List<int> _crcTable = _buildCrcTable();

  static List<int> _buildCrcTable() {
    const signed = <int>[
      0, 7, 14, 9, 28, 27, 18, 21, 56, 63, 54, 49, 36, 35, 42, 45, 112, 119, 126,
      121, 108, 107, 98, 101, 72, 79, 70, 65, 84, 83, 90, 93, -32, -25, -18, -23,
      -4, -5, -14, -11, -40, -33, -42, -47, -60, -61, -54, -51, -112, -105, -98,
      -103, -116, -117, -126, -123, -88, -81, -90, -95, -76, -77, -70, -67, -57,
      -64, -55, -50, -37, -36, -43, -46, -1, -8, -15, -10, -29, -28, -19, -22,
      -73, -80, -71, -66, -85, -84, -91, -94, -113, -120, -127, -122, -109, -108,
      -99, -102, 39, 32, 41, 46, 59, 60, 53, 50, 31, 24, 17, 22, 3, 4, 13, 10, 87,
      80, 89, 94, 75, 76, 69, 66, 111, 104, 97, 102, 115, 116, 125, 122, -119,
      -114, -121, -128, -107, -110, -101, -100, -79, -74, -65, -72, -83, -86,
      -93, -92, -7, -2, -9, -16, -27, -30, -21, -20, -63, -58, -49, -56, -35,
      -38, -45, -44, 105, 110, 103, 96, 117, 114, 123, 124, 81, 86, 95, 88, 77,
      74, 67, 68, 25, 30, 23, 16, 5, 2, 11, 12, 33, 38, 47, 40, 61, 58, 51, 52,
      78, 73, 64, 71, 82, 85, 92, 91, 118, 113, 120, 127, 106, 109, 100, 99, 62,
      57, 48, 55, 34, 37, 44, 43, 6, 1, 8, 15, 26, 29, 20, 19, -82, -87, -96,
      -89, -78, -75, -68, -69, -106, -111, -104, -97, -118, -115, -124, -125,
      -34, -39, -48, -41, -62, -59, -52, -53, -26, -31, -24, -17, -6, -3, -12,
      -13,
    ];
    return signed.map((v) => v & 0xff).toList(growable: false);
  }

  static int _crc8(List<int> data) {
    var crc = 0;
    for (final b in data) {
      crc = _crcTable[(crc ^ (b & 0xff)) & 0xff];
    }
    return crc;
  }

  static Uint8List _packet(int cmd, List<int> payload) {
    final data = payload.map((e) => e & 0xff).toList();
    final out = BytesBuilder();
    out.addByte(0x51);
    out.addByte(0x78);
    out.addByte(cmd & 0xff);
    out.addByte(0x00);
    out.addByte(data.length & 0xff);
    out.addByte((data.length >> 8) & 0xff);
    out.add(data);
    out.addByte(_crc8(data));
    out.addByte(0xff);
    return out.toBytes();
  }

  static bool looksLikeMiniName(String? name) {
    final n = (name ?? '').trim().toLowerCase();
    if (n.isEmpty) return false;
    const prefixes = <String>[
      'sc03',
      'sc04',
      'sc05',
      'gb0',
      'gt0',
      'mx0',
      'pd0',
      'yt0',
      'yhk',
      'mini',
      'iprint',
      'print',
      'cat',
      'mtp-',
      'x5',
      'x6',
      'x7',
      'x8',
    ];
    return prefixes.any(n.startsWith) || n.contains('printer');
  }

  static Future<List<MiniBleDeviceInfo>> scan({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (!Platform.isAndroid) return const [];
    await PrinterAccessGuard.ensureReady(promptEnable: true);
    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
      await FlutterBluePlus.turnOn();
    }

    final found = <String, MiniBleDeviceInfo>{};
    late final StreamSubscription sub;
    sub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final name = r.advertisementData.advName.isNotEmpty
            ? r.advertisementData.advName
            : (r.device.platformName);
        final services = r.advertisementData.serviceUuids
            .map((g) => g.str128.toLowerCase())
            .toList();
        final hasService = services.any(
          (s) =>
              s.contains('ae30') ||
              s.contains('ae3a') ||
              s == _serviceUuid ||
              s == _serviceUuidAlt,
        );
        if (!hasService && !looksLikeMiniName(name)) continue;
        final id = r.device.remoteId.str;
        found[id] = MiniBleDeviceInfo(
          remoteId: id,
          name: name.isEmpty ? id : name,
          rssi: r.rssi,
        );
      }
    });

    try {
      await FlutterBluePlus.startScan(
        timeout: timeout,
        androidUsesFineLocation: false,
        androidCheckLocationServices: false,
        withServices: const [],
      );
      await Future<void>.delayed(timeout);
    } finally {
      await FlutterBluePlus.stopScan();
      await sub.cancel();
    }

    final list = found.values.toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));
    return list;
  }

  static Future<void> printPngPages(List<Uint8List> pngPages) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('PRINT_ANDROID_ONLY');
    }
    if (pngPages.isEmpty) {
      throw StateError('EMPTY_RECEIPT_IMAGE');
    }

    await PrinterAccessGuard.ensureReady(promptEnable: true);
    final saved = await InstalledPrinterStore.loadMiniBleDevice();
    if (saved == null) {
      throw StateError('MINI_BLE_DEVICE_NOT_SELECTED');
    }

    final device = BluetoothDevice.fromId(saved.remoteId);
    await device.connect(
      license: License.commercial,
      autoConnect: false,
      mtu: null,
    );
    try {
      try {
        await device.requestMtu(247);
      } catch (_) {}
      final services = await device.discoverServices();
      final writeChar = _findWriteCharacteristic(services);
      if (writeChar == null) {
        throw StateError('MINI_BLE_WRITE_CHAR_MISSING');
      }

      final rows = <List<bool>>[];
      for (final page in pngPages) {
        rows.addAll(_pngToRows(page));
      }
      if (rows.isEmpty) {
        throw StateError('EMPTY_RECEIPT_IMAGE');
      }

      final commands = _buildPrintCommands(rows);
      await _writeChunks(writeChar, commands);
    } finally {
      try {
        await device.disconnect();
      } catch (_) {}
    }
  }

  static BluetoothCharacteristic? _findWriteCharacteristic(
    List<BluetoothService> services,
  ) {
    BluetoothCharacteristic? fallback;
    for (final service in services) {
      final sid = service.uuid.str128.toLowerCase();
      final isTarget = sid.contains('ae30') || sid.contains('ae3a');
      for (final c in service.characteristics) {
        final cid = c.uuid.str128.toLowerCase();
        final canWrite = c.properties.writeWithoutResponse || c.properties.write;
        if (!canWrite) continue;
        if (cid.contains('ae01') || cid.contains('ae3b')) {
          return c;
        }
        if (isTarget && fallback == null) fallback = c;
        if (c.uuid == _writeGuid || c.uuid == _writeAltGuid) return c;
      }
      if (service.uuid == _serviceGuid || service.uuid == _serviceAltGuid) {
        for (final c in service.characteristics) {
          if (c.properties.writeWithoutResponse || c.properties.write) {
            return c;
          }
        }
      }
    }
    return fallback;
  }

  static List<List<bool>> _pngToRows(Uint8List pngBytes) {
    final decoded = img.decodePng(pngBytes);
    if (decoded == null) return const [];

    var work = decoded;
    if (work.width != printWidth) {
      final h = (work.height * printWidth / work.width).round().clamp(1, 4000);
      work = img.copyResize(
        work,
        width: printWidth,
        height: h,
        interpolation: img.Interpolation.linear,
      );
    }

    final rows = <List<bool>>[];
    for (var y = 0; y < work.height; y++) {
      final row = List<bool>.filled(printWidth, false);
      for (var x = 0; x < printWidth; x++) {
        final p = work.getPixel(x, y);
        final gray = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b);
        row[x] = gray < 160;
      }
      rows.add(row);
    }
    return rows;
  }

  static Uint8List _buildPrintCommands(List<List<bool>> rows) {
    final out = BytesBuilder();
    out.add(_packet(0xa3, const [0x00])); // get state
    out.add(_packet(0xa4, const [0x32])); // quality 200dpi
    out.add(_packet(0xaf, const [0xff, 0xff])); // energy
    out.add(_packet(0xbe, const [0x01])); // apply energy / mode
    out.add(
      _packet(0xa6, const [
        0xaa,
        0x55,
        0x17,
        0x38,
        0x44,
        0x5f,
        0x5f,
        0x5f,
        0x44,
        0x38,
        0x2c,
      ]),
    ); // lattice start

    for (final row in rows) {
      out.add(_cmdPrintRow(row));
    }

    out.add(_packet(0xbd, const [0x19])); // feed speed blank
    out.add(_packet(0xa1, const [0x30, 0x00])); // feed
    out.add(_packet(0xa1, const [0x30, 0x00]));
    out.add(_packet(0xa1, const [0x30, 0x00]));
    out.add(
      _packet(0xa6, const [
        0xaa,
        0x55,
        0x17,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x17,
      ]),
    ); // lattice end
    out.add(_packet(0xa3, const [0x00]));
    return out.toBytes();
  }

  static Uint8List _cmdPrintRow(List<bool> row) {
    final bits = row.length >= printWidth
        ? row.sublist(0, printWidth)
        : [...row, ...List<bool>.filled(printWidth - row.length, false)];

    final rle = _runLengthEncode(bits);
    if (rle.length <= printWidth ~/ 8) {
      return _packet(0xbf, rle);
    }
    return _packet(0xa2, _byteEncode(bits));
  }

  static List<int> _byteEncode(List<bool> row) {
    final out = <int>[];
    for (var i = 0; i < row.length; i += 8) {
      var byte = 0;
      for (var bit = 0; bit < 8; bit++) {
        if (i + bit < row.length && row[i + bit]) {
          byte |= 1 << bit;
        }
      }
      out.add(byte);
    }
    return out;
  }

  static List<int> _runLengthEncode(List<bool> row) {
    final out = <int>[];
    var count = 0;
    var last = -1;
    for (final dark in row) {
      final val = dark ? 1 : 0;
      if (val == last) {
        count++;
      } else {
        out.addAll(_encodeRepetition(count, last));
        count = 1;
        last = val;
      }
    }
    out.addAll(_encodeRepetition(count, last));
    return out;
  }

  static List<int> _encodeRepetition(int n, int val) {
    if (n <= 0 || val < 0) return const [];
    final out = <int>[];
    var left = n;
    while (left > 0x7f) {
      out.add(0x7f | (val << 7));
      left -= 0x7f;
    }
    out.add((val << 7) | left);
    return out;
  }

  static Future<void> _writeChunks(
    BluetoothCharacteristic characteristic,
    Uint8List data,
  ) async {
    final withoutResponse = characteristic.properties.writeWithoutResponse;
    // اترك هامشاً عن MTU؛ كثير من الأجهزة تستقر حول 20–180 بايت للحمولة.
    const chunk = 100;
    for (var i = 0; i < data.length; i += chunk) {
      final end = (i + chunk < data.length) ? i + chunk : data.length;
      final slice = data.sublist(i, end);
      await characteristic.write(
        slice,
        withoutResponse: withoutResponse,
      );
      await Future<void>.delayed(const Duration(milliseconds: 15));
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
}

class MiniBleDeviceInfo {
  const MiniBleDeviceInfo({
    required this.remoteId,
    required this.name,
    this.rssi = 0,
  });

  final String remoteId;
  final String name;
  final int rssi;

  Map<String, dynamic> toJson() => {
        'remoteId': remoteId,
        'name': name,
        'rssi': rssi,
      };

  factory MiniBleDeviceInfo.fromJson(Map<String, dynamic> json) {
    return MiniBleDeviceInfo(
      remoteId: (json['remoteId'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      rssi: (json['rssi'] as num?)?.toInt() ?? 0,
    );
  }

  static MiniBleDeviceInfo? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final info = MiniBleDeviceInfo.fromJson(map);
      if (info.remoteId.isEmpty) return null;
      return info;
    } catch (_) {
      return null;
    }
  }
}
