import '../../core/widgets/app_network_image.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/catalog_models.dart';

class ProductCardWidget extends StatelessWidget {
  const ProductCardWidget({
    super.key,
    required this.product,
    required this.onBuy,
    this.companyLogo,
    this.soldOutText,
    this.hidePrice = false,
  });

  final Product product;
  final VoidCallback onBuy;
  final String? companyLogo;
  /// نص زر عدم التوفر (افتراضي: نفد)
  final String? soldOutText;
  final bool hidePrice;

  Color _parse(String hex, Color fallback) {
    try {
      final h = hex.replaceAll('#', '');
      return Color(int.parse('FF$h', radix: 16));
    } catch (_) {
      return fallback;
    }
  }

  @override
  Widget build(BuildContext context) {
    final btnColor = _parse(product.buttonColorHex, AppColors.accent);
    final image = product.imageUrl.isNotEmpty
        ? product.imageUrl
        : (companyLogo ?? '');

    return GestureDetector(
      onTap: product.stockCount > 0 ? onBuy : null,
      child: Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: image.isEmpty
                      ? const Icon(
                          Icons.sim_card,
                          size: 42,
                          color: AppColors.primary,
                        )
                      : AppNetworkImage(
                          url: image,
                          fit: BoxFit.cover,
                          fallbackIcon: Icons.sim_card,
                        ),
                ),
                if (product.hasOffer)
                  Positioned(
                    top: 0,
                    left: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: const BoxDecoration(
                        color: AppColors.offer,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(14),
                          bottomRight: Radius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'عروض',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          if (product.name.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                product.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                ),
              ),
            ),
          if (product.name.trim().isNotEmpty) const SizedBox(height: 4),
          if (!hidePrice)
            Text(
              Formatters.money(product.price),
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          if (!hidePrice) const SizedBox(height: 6),
          if (hidePrice) const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: SizedBox(
              width: double.infinity,
              height: 34,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: btnColor,
                  foregroundColor: AppColors.onAccent,
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: product.stockCount > 0 ? onBuy : null,
                child: Text(
                  product.stockCount > 0
                      ? product.buttonText
                      : (soldOutText ?? 'نفد'),
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
    );
  }
}
