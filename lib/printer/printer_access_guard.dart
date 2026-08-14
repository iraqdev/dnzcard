import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thermal_printer_flutter/thermal_printer_flutter.dart';

/// طلب صلاحيات الوصول للطابعات الخارجية (Bluetooth) على Android.
abstract final class PrinterAccessGuard {
  static final _thermal = ThermalPrinterFlutter();
  static const _explainedKey = 'kushk_printer_permission_explained_v1';

  static Future<bool> requestPermissions() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _thermal.checkBluetoothPermissions();
    } catch (_) {
      return false;
    }
  }

  static Future<bool> requestWithExplanation(BuildContext context) async {
    if (!Platform.isAndroid) return true;

    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('الوصول للطابعات'),
        content: const Text(
          'يحتاج التطبيق إلى صلاحية Bluetooth للبحث عن الطابعات '
          'الخارجية المتصلة بالجهاز وطباعة الإيصالات.\n\n'
          'الطابعات المدمجة (Centerm / Sunmi / Senraise / K9) '
          'قد لا تحتاج هذه الصلاحية، لكنها تساعد على الاكتشاف الكامل.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('لاحقاً'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('السماح'),
          ),
        ],
      ),
    );

    if (proceed != true || !context.mounted) return false;

    final granted = await requestPermissions();
    if (granted) return true;

    if (!context.mounted) return false;

    final retry = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('صلاحية مرفوضة'),
        content: const Text(
          'لم تُمنح صلاحية Bluetooth. بدونها قد لا تُكتشف '
          'طابعات Bluetooth الخارجية.\n\n'
          'يمكنك تفعيلها من: إعدادات الجهاز ← التطبيقات ← DNZ card ← الأذونات.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إغلاق'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );

    if (retry != true) return false;
    return requestPermissions();
  }

  /// شرح مرة واحدة عند أول تشغيل، ثم طلب صامت لاحقاً إن لم تُمنح.
  static Future<bool> requestWithExplanationIfNeeded(
    BuildContext context,
  ) async {
    if (!Platform.isAndroid) return true;
    final prefs = await SharedPreferences.getInstance();
    final explained = prefs.getBool(_explainedKey) ?? false;
    if (!explained) {
      await prefs.setBool(_explainedKey, true);
      if (!context.mounted) return false;
      return requestWithExplanation(context);
    }
    return requestPermissions();
  }

  static Future<bool> ensureReady({bool promptEnable = false}) async {
    if (!Platform.isAndroid) return false;
    try {
      final permitted = await requestPermissions().timeout(
        const Duration(seconds: 8),
        onTimeout: () => false,
      );
      if (!permitted) return false;

      final enabled = await _thermal.isBluetoothEnabled();
      if (enabled) return true;
      if (!promptEnable) return false;

      return await _thermal.enableBluetooth().timeout(
        const Duration(seconds: 15),
        onTimeout: () => false,
      );
    } catch (_) {
      return false;
    }
  }
}
