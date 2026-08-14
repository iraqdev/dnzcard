import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract class Printer {
  Future<Map<String, dynamic>> detect();
  Future<String> getStatus();
  Future<void> setDriver(String driver);
  Future<void> setDriverWithDevice({
    required String driver,
    String? address,
    String? id,
  });
  Future<List<Map<String, dynamic>>> listDevices();
  Future<void> setPaperSizeMm(int mm);
  Future<int> getPaperSizeMm();
  Future<void> printText(String text);
  Future<void> printReceipt(List<String> lines, {Uint8List? imageBytes});
  Future<void> printCard(String code);
  Future<void> testPrint();
  Future<void> openDrawer();
  Future<void> cut();
}

class ChannelPrinter implements Printer {
  static const _channel = MethodChannel('kushk/printer');

  Future<dynamic> _invoke(String method, [Map<String, dynamic>? args]) async {
    if (kIsWeb) return null;
    return _channel.invokeMethod(method, args);
  }

  @override
  Future<Map<String, dynamic>> detect() async {
    final result = await _invoke('detect');
    if (result is Map) return Map<String, dynamic>.from(result);
    return {};
  }

  @override
  Future<String> getStatus() async {
    final result = await _invoke('getStatus');
    if (result is Map) {
      return (result['status'] ?? result['driver'] ?? result.toString())
          .toString();
    }
    return result?.toString() ?? 'غير متاح على الويب';
  }

  @override
  Future<void> setDriver(String driver) =>
      _invoke('setDriver', {'driver': driver});

  @override
  Future<void> setDriverWithDevice({
    required String driver,
    String? address,
    String? id,
  }) =>
      _invoke('setDriver', {
        'driver': driver,
        'address': ?address,
        'id': ?id,
      });

  @override
  Future<List<Map<String, dynamic>>> listDevices() async {
    final result = await _invoke('listDevices');
    if (result is List) {
      return result
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [];
  }

  @override
  Future<void> setPaperSizeMm(int mm) =>
      _invoke('setPaperSize', {'mm': mm});

  @override
  Future<int> getPaperSizeMm() async {
    final result = await _invoke('getPaperSize');
    if (result is Map) {
      return (result['mm'] as num?)?.toInt() ?? 58;
    }
    if (result is num) return result.toInt();
    return 58;
  }

  @override
  Future<void> printText(String text) => _invoke('printText', {'text': text});

  @override
  Future<void> printReceipt(List<String> lines, {Uint8List? imageBytes}) =>
      _invoke('printReceipt', {
        'text': lines.join('\n'),
        'lines': lines,
        'image': ?imageBytes,
      });

  @override
  Future<void> printCard(String code) => _invoke('printCard', {
    'code': code,
    'text': code,
    'body': code,
    'title': 'كود البطاقة',
  });

  @override
  Future<void> testPrint() async {
    final result = await _invoke('testPrint');
    if (result is Map && result['success'] == false) {
      throw StateError(
        'تعذر الطباعة. اختر طابعة بلوتوث/USB من الإعدادات أولاً',
      );
    }
  }

  @override
  Future<void> openDrawer() => _invoke('openDrawer');

  @override
  Future<void> cut() => _invoke('cut');
}

final Printer kushkPrinter = ChannelPrinter();
