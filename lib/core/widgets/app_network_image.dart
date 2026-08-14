import 'package:flutter/material.dart';

/// صورة شبكة موحّدة للتطبيق:
/// - تفكّ الترميز بحجم العرض الفعلي (cacheWidth/Height) لتقليل الذاكرة.
/// - على الويب تسمح للمتصفح بفك ترميز الصور التي يفشل بها محرك Flutter.
/// - تعرض أيقونة بديلة خفيفة أثناء التحميل وعند الفشل.
class AppNetworkImage extends StatelessWidget {
  const AppNetworkImage({
    super.key,
    required this.url,
    this.fit = BoxFit.contain,
    this.fallbackIcon = Icons.image_outlined,
    this.fallbackColor,
    this.memCacheWidth,
    this.memCacheHeight,
  });

  final String url;
  final BoxFit fit;
  final IconData fallbackIcon;
  final Color? fallbackColor;

  /// حد أقصى لعرض فك الترميز بالبكسل المنطقي للجهاز (اختياري).
  final int? memCacheWidth;

  /// حد أقصى لارتفاع فك الترميز بالبكسل المنطقي للجهاز (اختياري).
  final int? memCacheHeight;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return Icon(fallbackIcon, color: fallbackColor);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final cacheW = _resolveCachePx(
          explicit: memCacheWidth,
          extent: constraints.maxWidth,
          dpr: dpr,
        );
        final cacheH = _resolveCachePx(
          explicit: memCacheHeight,
          extent: constraints.maxHeight,
          dpr: dpr,
        );

        return Image.network(
          url,
          fit: fit,
          // عند توفر العرض فقط نمرّر cacheWidth لتجنب تشويه النسبة.
          cacheWidth: cacheW,
          cacheHeight: cacheW == null ? cacheH : null,
          // على الويب نفضّل عنصر HTML لتجنب طلبات XHR التي تفشل بـ CORS.
          webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return Icon(
              fallbackIcon,
              color: (fallbackColor ?? Theme.of(context).disabledColor)
                  .withValues(alpha: 0.35),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return Icon(fallbackIcon, color: fallbackColor);
          },
        );
      },
    );
  }

  static int? _resolveCachePx({
    required int? explicit,
    required double extent,
    required double dpr,
  }) {
    if (explicit != null && explicit > 0) {
      return (explicit * dpr).round().clamp(1, 1024);
    }
    if (extent.isFinite && extent > 0) {
      return (extent * dpr).round().clamp(1, 1024);
    }
    return null;
  }
}
