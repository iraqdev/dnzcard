import 'package:flutter/material.dart';
import '../../models/catalog_models.dart';
import '../../services/catalog_service.dart';

class AdminInventoryPage extends StatefulWidget {
  const AdminInventoryPage({super.key});

  @override
  State<AdminInventoryPage> createState() => _AdminInventoryPageState();
}

class _AdminInventoryPageState extends State<AdminInventoryPage> {
  final _service = CatalogService();
  String? _companyId;
  String? _productId;
  final _codes = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _codes.dispose();
    super.dispose();
  }

  Future<void> _addCodes() async {
    if (_productId == null) return;
    setState(() => _busy = true);
    try {
      final items = CatalogService.parseInventoryLines(_codes.text);
      if (items.isEmpty) return;
      final added = await _service.addCardItems(
        _productId!,
        items,
        source: 'manual',
      );
      _codes.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تمت إضافة $added بطاقة')));
    } on FormatException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteCode(CardCode code) async {
    final productId = _productId;
    if (productId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف رمز البطاقة'),
        content: Text('هل تريد حذف الرمز ${code.code} نهائياً من المخزون؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _service.deleteCardCode(productId, code.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم حذف رمز البطاقة')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تعذر حذف الرمز: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('مخزون الأرصدة')),
      body: StreamBuilder<List<Company>>(
        stream: _service.watchCompanies(activeOnly: false),
        builder: (context, companiesSnapshot) {
          final companies = (companiesSnapshot.data ?? [])
              .where((company) => !company.isFazerSpecial)
              .toList();
          if (companies.isEmpty) {
            return const Center(child: Text('أضف شركة أولاً'));
          }
          if (_companyId == null ||
              !companies.any((company) => company.id == _companyId)) {
            _companyId = companies.first.id;
            _productId = null;
          }

          return StreamBuilder<List<Product>>(
            stream: _service.watchProducts(activeOnly: false),
            builder: (context, snapshot) {
              final products = (snapshot.data ?? [])
                  .where((product) => product.companyId == _companyId)
                  .toList();
              if (_productId != null &&
                  !products.any((product) => product.id == _productId)) {
                _productId = null;
              }

              return Column(
                children: [
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
                          selected: company.id == _companyId,
                          onSelected: (_) {
                            setState(() {
                              _companyId = company.id;
                              _productId = null;
                            });
                          },
                        );
                      },
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: products.isEmpty
                        ? const Center(
                            child: Text('لا توجد فئات كروت لهذه الشركة'),
                          )
                        : _buildInventoryBody(products),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildInventoryBody(List<Product> products) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: products.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final product = products[index];
                return ChoiceChip(
                  label: Text('${product.name} (${product.stockCount})'),
                  selected: product.id == _productId,
                  onSelected: (_) {
                    setState(() => _productId = product.id);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          if (_productId == null)
            const Expanded(
              child: Center(child: Text('اختر فئة كارت لإضافة الرموز')),
            )
          else ...[
            TextField(
              controller: _codes,
              minLines: 5,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: 'البطاقات (سطر لكل بطاقة)',
                hintText: 'رمز البطاقة | رقم التسلسل',
                helperText: 'مثال: 12345678901234 | 98765432109876',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _productId == null || _busy ? null : _addCodes,
              child: Text(_busy ? 'جاري الإضافة...' : 'إضافة للمخزون'),
            ),
            const SizedBox(height: 16),
            const Align(
              alignment: Alignment.centerRight,
              child: Text(
                'البطاقات الحالية',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: StreamBuilder(
                stream: _service.watchCodes(_productId!),
                builder: (context, snap) {
                  final codes = snap.data ?? [];
                  final available = codes
                      .where((c) => c.status == 'available')
                      .length;
                  final sold = codes.where((c) => c.status == 'sold').length;
                  return Column(
                    children: [
                      Text('متاح: $available | مباع: $sold'),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView.builder(
                          itemCount: codes.length,
                          itemBuilder: (context, i) {
                            final c = codes[i];
                            return ListTile(
                              dense: true,
                              title: Text(c.code),
                              subtitle: Text(
                                c.serialNumber.isEmpty
                                    ? 'بدون رقم تسلسل'
                                    : 'التسلسل: ${c.serialNumber}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(c.status),
                                  IconButton(
                                    tooltip: 'حذف الرمز',
                                    color: Colors.red,
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: _busy
                                        ? null
                                        : () => _deleteCode(c),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
