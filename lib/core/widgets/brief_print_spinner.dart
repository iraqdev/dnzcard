import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// أيقونة تحميل شكلية أثناء الطباعة: تدور ثانيتين ثم تختفي.
void showBriefPrintSpinner(BuildContext context) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

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
  Future<void>.delayed(const Duration(seconds: 2), () {
    entry.remove();
  });
}
