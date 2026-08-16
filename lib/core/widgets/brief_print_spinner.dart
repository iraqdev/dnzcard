import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// يعرض مؤشّر تحميل أثناء الطباعة، ويُعيد دالة لإخفائه فور انتهاء الطباعة.
///
/// استدعِ الدالة المُعادة عند اكتمال الطباعة (أو فشلها) ليختفي المؤشر مباشرةً
/// بدل مدة ثابتة. يوجد مؤقّت أمان يزيله تلقائياً إن لم يُستدعَ الإخفاء.
VoidCallback showBriefPrintSpinner(BuildContext context) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return () {};

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => IgnorePointer(
      child: ColoredBox(
        color: Colors.black26,
        child: Center(
          child: SizedBox(
            width: 42,
            height: 42,
            child: CircularProgressIndicator(
              strokeWidth: 3.5,
              color: AppColors.primary,
            ),
          ),
        ),
      ),
    ),
  );

  overlay.insert(entry);

  var removed = false;
  Timer? safety;
  void dismiss() {
    if (removed) return;
    removed = true;
    safety?.cancel();
    entry.remove();
  }

  // مؤقّت أمان: يمنع بقاء المؤشر عالقاً إن لم يُستدعَ الإخفاء لأي سبب.
  safety = Timer(const Duration(seconds: 30), dismiss);
  return dismiss;
}
