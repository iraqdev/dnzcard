import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/shop_location_service.dart';

/// يطلب صلاحية الموقع بعد 10 ثوانٍ من تشغيل التطبيق للمحلات.
/// عند الرفض يعيد الطلب بعد ساعة. بعد الموافقة لا يظهر مجدداً.
class ShopLocationPromptHost extends StatefulWidget {
  const ShopLocationPromptHost({super.key, required this.child});

  final Widget child;

  @override
  State<ShopLocationPromptHost> createState() => _ShopLocationPromptHostState();
}

class _ShopLocationPromptHostState extends State<ShopLocationPromptHost> {
  final _service = ShopLocationService();
  Timer? _timer;
  var _busy = false;
  String? _startedForUid;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    if (kIsWeb || user == null || !user.isApprovedShop) {
      _timer?.cancel();
      _startedForUid = null;
      return;
    }
    if (_startedForUid == user.id) return;
    _startedForUid = user.id;
    _timer?.cancel();
    _timer = Timer(ShopLocationService.initialDelay, () {
      if (!mounted) return;
      unawaited(_maybePrompt(user.id, user.shopName));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _maybePrompt(String userId, String shopName) async {
    if (_busy || !mounted) return;
    _busy = true;
    try {
      final granted = await _service.isGrantedLocally();
      if (granted) {
        // تحديث صامت للموقع إن كانت الموافقة سابقة.
        await _service.captureAndSave(userId, silent: true);
        return;
      }
      if (!await _service.shouldPromptNow()) return;
      if (!mounted) return;

      final accept = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('صلاحية الموقع'),
          content: Text(
            shopName.trim().isEmpty
                ? 'يحتاج التطبيق إلى موقع المحل لعرضه على خريطة الإدارة.\n\nهل تسمح بالوصول إلى موقعك الحالي؟'
                : 'يحتاج التطبيق إلى موقع محل «$shopName» لعرضه على خريطة الإدارة.\n\nهل تسمح بالوصول إلى موقعك الحالي؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('لاحقاً'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('موافق'),
            ),
          ],
        ),
      );

      if (!mounted) return;
      if (accept != true) {
        await _service.markDenied();
        return;
      }

      final ok = await _service.captureAndSave(userId);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر الحصول على الموقع. سنحاول مرة أخرى لاحقاً.'),
          ),
        );
      }
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
