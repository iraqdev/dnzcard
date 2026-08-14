import 'package:flutter/material.dart';

class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 42, this.borderRadius = 10});

  static const assetPath = 'assets/images/dnz_card_logo.jpeg';

  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cachePx = (size * dpr).round().clamp(1, 512);
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Image.asset(
        assetPath,
        width: size,
        height: size,
        cacheWidth: cachePx,
        fit: BoxFit.cover,
      ),
    );
  }
}

class AppLogoTitle extends StatelessWidget {
  const AppLogoTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const AppLogo(size: 34, borderRadius: 8),
        const SizedBox(width: 9),
        Flexible(child: Text(title, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}
