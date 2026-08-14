import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/app_user.dart';
import '../../models/catalog_models.dart';
import '../../models/user_custom_price.dart';
import '../../services/catalog_service.dart';
import '../../services/custom_price_service.dart';

class AdminUserPricesPage extends StatefulWidget {
  const AdminUserPricesPage({
    super.key,
    required this.userId,
    this.user,
  });

  final String userId;
  final AppUser? user;

  @override
  State<AdminUserPricesPage> createState() => _AdminUserPricesPageState();
}

class _AdminUserPricesPageState extends State<AdminUserPricesPage> {
  final _catalog = CatalogService();
  final _prices = CustomPriceService();
  String? _selectedCompanyId;

  @override
  Widget build(BuildContext context) {
    final titleName = widget.user?.shopName.isNotEmpty == true
        ? widget.user!.shopName
        : (widget.user?.name ?? 'المستخدم');

    return Scaffold(
      appBar: AppBar(
        title: Text('أسعار: $titleName'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_forward),
          onPressed: () => context.go('/admin/users'),
        ),
      ),
      body: StreamBuilder<List<Company>>(
        stream: _catalog.watchCompanies(activeOnly: false),
        builder: (context, companiesSnap) {
          final companies = (companiesSnap.data ?? [])
              .where((c) => !c.isFazerSpecial)
              .toList();
          if (companies.isEmpty) {
            return const Center(child: Text('لا توجد شركات'));
          }

          if (_selectedCompanyId == null ||
              !companies.any((c) => c.id == _selectedCompanyId)) {
            _selectedCompanyId = companies.first.id;
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(
                  'حدد أسعاراً خاصة لهذا المتجر. اترك الحقل فارغاً لاستخدام السعر العام.',
                  style: TextStyle(color: AppColors.textSecondary, height: 1.4),
                ),
              ),
              SizedBox(
                height: 58,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  scrollDirection: Axis.horizontal,
                  itemCount: companies.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final company = companies[index];
                    return ChoiceChip(
                      label: Text(company.name),
                      selected: company.id == _selectedCompanyId,
                      onSelected: (_) {
                        setState(() => _selectedCompanyId = company.id);
                      },
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: StreamBuilder<List<Product>>(
                  stream: _catalog.watchProducts(activeOnly: false),
                  builder: (context, productsSnap) {
                    final products = (productsSnap.data ?? [])
                        .where((p) => p.companyId == _selectedCompanyId)
                        .toList();
                    if (products.isEmpty) {
                      return const Center(
                        child: Text('لا توجد فئات كروت لهذه الشركة'),
                      );
                    }
                    return StreamBuilder<Map<String, UserCustomPrice>>(
                      stream: _prices.watchForUser(widget.userId),
                      builder: (context, pricesSnap) {
                        final customs = pricesSnap.data ?? {};
                        return ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: products.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final product = products[index];
                            final custom = customs[product.id];
                            return _PriceCard(
                              product: product,
                              custom: custom,
                              onEdit: () => _edit(product, custom),
                              onClear: custom == null
                                  ? null
                                  : () => _clear(product),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _clear(Product product) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إزالة السعر الخاص'),
        content: Text(
          'إرجاع فئة «${product.name}» إلى السعر العام لهذا المتجر؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('إزالة'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _prices.clearPrice(userId: widget.userId, productId: product.id);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تم إرجاع السعر العام')));
  }

  Future<void> _edit(Product product, UserCustomPrice? custom) async {
    final priceCtrl = TextEditingController(
      text: custom?.price != null ? custom!.price!.toStringAsFixed(0) : '',
    );
    final hiddenCtrl = TextEditingController(
      text: custom?.hiddenSalePrice != null
          ? custom!.hiddenSalePrice!.toStringAsFixed(0)
          : '',
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('سعر خاص: ${product.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'العام: ${Formatters.money(product.price)}'
              '${product.hiddenSalePrice == null ? '' : ' | مخفي: ${Formatters.money(product.hiddenSalePrice!)}'}',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: priceCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'سعر البيع الظاهر (خاص)',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: hiddenCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'سعر البيع المخفي (خاص)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    double? parseOptional(String raw) {
      final t = raw.trim();
      if (t.isEmpty) return null;
      return double.tryParse(t);
    }

    final price = parseOptional(priceCtrl.text);
    final hidden = parseOptional(hiddenCtrl.text);
    if ((price != null && price <= 0) || (hidden != null && hidden <= 0)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('السعر يجب أن يكون أكبر من صفر')),
      );
      return;
    }
    if (price == null && hidden == null) {
      await _prices.clearPrice(userId: widget.userId, productId: product.id);
    } else {
      await _prices.setPrice(
        userId: widget.userId,
        productId: product.id,
        price: price,
        hiddenSalePrice: hidden,
      );
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تم حفظ السعر الخاص')));
  }
}

class _PriceCard extends StatelessWidget {
  const _PriceCard({
    required this.product,
    required this.custom,
    required this.onEdit,
    required this.onClear,
  });

  final Product product;
  final UserCustomPrice? custom;
  final VoidCallback onEdit;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final hasCustom = custom != null && custom!.hasOverride;
    final resolved = resolveProductPrices(product: product, custom: custom);

    return Card(
      child: ListTile(
        title: Text(product.name),
        subtitle: Text(
          hasCustom
              ? 'خاص: ${Formatters.money(resolved.visible)}'
                    '${resolved.charged != resolved.visible ? ' | مخفي: ${Formatters.money(resolved.charged)}' : ''}\n'
                    'العام: ${Formatters.money(product.price)}'
              : 'يستخدم السعر العام: ${Formatters.money(product.price)}'
                    '${product.hiddenSalePrice == null ? '' : ' | مخفي: ${Formatters.money(product.hiddenSalePrice!)}'}',
        ),
        isThreeLine: hasCustom,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onClear != null)
              IconButton(
                tooltip: 'إزالة السعر الخاص',
                onPressed: onClear,
                icon: const Icon(Icons.clear, color: Colors.red),
              ),
            IconButton(
              tooltip: 'تعديل',
              onPressed: onEdit,
              icon: Icon(
                Icons.edit,
                color: hasCustom ? AppColors.accent : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
