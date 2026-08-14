import '../../core/widgets/app_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/catalog_models.dart';
import '../../models/fazer_models.dart';
import '../../services/catalog_service.dart';
import '../../services/fazer_service.dart';
import '../../services/storage_service.dart';

class AdminProductsPage extends StatefulWidget {
  const AdminProductsPage({super.key});

  @override
  State<AdminProductsPage> createState() => _AdminProductsPageState();
}

class _AdminProductsPageState extends State<AdminProductsPage> {
  final _service = CatalogService();
  String? _selectedCompanyId;
  bool _reordering = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('فئات الكروت')),
      floatingActionButton: _isFazerCompany(_selectedCompanyId)
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _edit(context, _service),
              icon: const Icon(Icons.add),
              label: const Text('إضافة فئة كارت'),
            ),
      body: StreamBuilder<List<Company>>(
        stream: _service.watchCompanies(activeOnly: false),
        builder: (context, companiesSnapshot) {
          final companies = companiesSnapshot.data ?? [];
          if (companies.isEmpty) {
            return const Center(child: Text('أضف شركة أولاً'));
          }

          if (_selectedCompanyId == null ||
              !companies.any((company) => company.id == _selectedCompanyId)) {
            _selectedCompanyId = companies.first.id;
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
                child: _isFazerCompany(_selectedCompanyId)
                    ? _FazerAdminCategoriesList(
                        mode: _selectedCompanyId == kFazerGameKeysCompanyId
                            ? _FazerAdminMode.gameKeys
                            : _selectedCompanyId == kFazerWorldCompanyId
                                ? _FazerAdminMode.world
                                : _selectedCompanyId == kFazerTopupsCompanyId
                                    ? _FazerAdminMode.topups
                                    : _FazerAdminMode.pricedGifts,
                      )
                    : StreamBuilder<List<Product>>(
                  stream: _service.watchProducts(activeOnly: false),
                  builder: (context, productsSnapshot) {
                    final products = (productsSnapshot.data ?? [])
                        .where(
                          (product) => product.companyId == _selectedCompanyId,
                        )
                        .toList();
                    if (products.isEmpty) {
                      return const Center(
                        child: Text('لا توجد فئات كروت لهذه الشركة'),
                      );
                    }
                    return ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                      buildDefaultDragHandles: false,
                      itemCount: products.length,
                      onReorder: (oldIndex, newIndex) =>
                          _reorder(products, oldIndex, newIndex),
                      itemBuilder: (context, index) {
                        final product = products[index];
                        return Card(
                          key: ValueKey(product.id),
                          child: ListTile(
                            leading: _ProductImage(url: product.imageUrl),
                            title: Text(product.name),
                            subtitle: Text(
                              'بيع: ${Formatters.money(product.price)} | '
                              'تكلفة: ${Formatters.money(product.costPrice)} | '
                              '${product.hiddenSalePrice == null ? '' : 'السعر المخفي: ${Formatters.money(product.hiddenSalePrice!)} | '}'
                              'المخزون: ${product.stockCount}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'تعديل',
                                  icon: const Icon(Icons.edit),
                                  onPressed: () =>
                                      _edit(context, _service, product),
                                ),
                                IconButton(
                                  tooltip: 'حذف فئة الكارت',
                                  color: Colors.red,
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () =>
                                      _delete(context, _service, product),
                                ),
                                ReorderableDragStartListener(
                                  index: index,
                                  child: const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: Icon(Icons.drag_handle),
                                  ),
                                ),
                              ],
                            ),
                          ),
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

  bool _isFazerCompany(String? id) =>
      id == kFazerAllCompanyId ||
      id == kFazerGameKeysCompanyId ||
      id == kFazerWorldCompanyId ||
      id == kFazerTopupsCompanyId;

  Future<void> _reorder(
    List<Product> products,
    int oldIndex,
    int newIndex,
  ) async {
    if (_reordering || oldIndex == newIndex) return;
    if (newIndex > oldIndex) newIndex--;
    final reordered = List<Product>.from(products);
    final product = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, product);

    setState(() => _reordering = true);
    try {
      await _service.updateProductOrder(
        reordered.map((item) => item.id).toList(),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تعذر حفظ ترتيب الفئات: $e')));
    } finally {
      if (mounted) setState(() => _reordering = false);
    }
  }

  Future<void> _edit(
    BuildContext context,
    CatalogService service, [
    Product? existing,
  ]) async {
    final companies = (await service.watchCompanies(activeOnly: false).first)
        .where((company) => !company.isFazerSpecial)
        .toList();
    final products = await service.watchProducts(activeOnly: false).first;
    if (!context.mounted) return;

    if (companies.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أضف شركة أولاً قبل إضافة فئة كارت')),
      );
      return;
    }

    final cardCategory = TextEditingController(text: existing?.name ?? '');
    final price = TextEditingController(
      text: existing?.price.toStringAsFixed(0) ?? '',
    );
    final costPrice = TextEditingController(
      text: existing == null || existing.costPrice <= 0
          ? ''
          : existing.costPrice.toStringAsFixed(0),
    );
    final hiddenSalePrice = TextEditingController(
      text: existing?.hiddenSalePrice?.toStringAsFixed(0) ?? '',
    );
    final buttonText = TextEditingController(
      text: existing?.buttonText ?? 'شراء الآن',
    );
    final buttonColor = TextEditingController(
      text: existing?.buttonColorHex ?? '#1DB954',
    );
    String imageUrl = existing?.imageUrl ?? '';
    String companyId = existing?.companyId.isNotEmpty == true
        ? existing!.companyId
        : (_selectedCompanyId ?? companies.first.id);
    var hasOffer = existing?.hasOffer ?? false;
    var active = existing?.isActive ?? true;
    var uploading = false;
    String? error;

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          Future<void> pickImage() async {
            final result = await FilePicker.pickFiles(
              type: FileType.image,
              withData: true,
            );
            final file = result?.files.single;
            if (file?.bytes == null) return;

            setState(() {
              uploading = true;
              error = null;
            });
            try {
              imageUrl = await StorageService().uploadImage(
                folder: 'products',
                bytes: file!.bytes!,
                fileName: file.name,
                contentType: _contentType(file.extension),
              );
            } catch (e) {
              error = 'تعذر رفع الصورة: $e';
            } finally {
              setState(() => uploading = false);
            }
          }

          return AlertDialog(
            title: Text(existing == null ? 'إضافة فئة كارت' : 'تعديل فئة كارت'),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Builder(
                  builder: (context) {
                    final saleValue = double.tryParse(price.text.trim());
                    final costValue = double.tryParse(costPrice.text.trim());
                    final costWarnsAgainstSale = saleValue != null &&
                        costValue != null &&
                        saleValue > 0 &&
                        costValue > 0 &&
                        costValue >= saleValue;

                    return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: companyId,
                      items: companies
                          .map(
                            (company) => DropdownMenuItem(
                              value: company.id,
                              child: Text(company.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) setState(() => companyId = value);
                      },
                      decoration: const InputDecoration(labelText: 'الشركة'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: cardCategory,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'فئة الكارت',
                        hintText: 'مثال: 5000',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: price,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'سعر البيع',
                        hintText: 'مثال: 5000',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: costPrice,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'سعر التكلفة',
                        hintText: 'مثال: 4500',
                        errorText: costWarnsAgainstSale
                            ? 'تحذير: سعر التكلفة يساوي أو أعلى من سعر البيع'
                            : null,
                      ),
                    ),
                    if (costWarnsAgainstSale) ...[
                      const SizedBox(height: 6),
                      const Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'لا يوجد ربح أو هناك خسارة بهذه الأسعار.',
                          style: TextStyle(
                            color: AppColors.danger,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: hiddenSalePrice,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'سعر البيع المخفي',
                        hintText: 'اختياري — يخصم هذا السعر دون عرضه للزبون',
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: uploading ? null : pickImage,
                      icon: uploading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.upload_file),
                      label: Text(
                        uploading
                            ? 'جاري رفع الصورة...'
                            : 'تصفح الحاسوب ورفع صورة الكارت',
                      ),
                    ),
                    if (imageUrl.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 110,
                        child: AppNetworkImage(url: imageUrl),
                      ),
                    ],
                    if (error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        error!,
                        style: const TextStyle(color: AppColors.danger),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: buttonText,
                      decoration: const InputDecoration(labelText: 'نص الزر'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: buttonColor,
                      decoration: const InputDecoration(labelText: 'لون الزر'),
                    ),
                    SwitchListTile(
                      value: hasOffer,
                      onChanged: (value) => setState(() => hasOffer = value),
                      title: const Text('إظهار علامة عرض'),
                    ),
                    SwitchListTile(
                      value: active,
                      onChanged: (value) => setState(() => active = value),
                      title: const Text('مفعّل'),
                    ),
                  ],
                );
                  },
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: uploading
                    ? null
                    : () => Navigator.pop(dialogContext, false),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed:
                    uploading ||
                        cardCategory.text.trim().isEmpty ||
                        (double.tryParse(price.text) ?? 0) <= 0 ||
                        (double.tryParse(costPrice.text) ?? 0) <= 0 ||
                        (hiddenSalePrice.text.trim().isNotEmpty &&
                            (double.tryParse(hiddenSalePrice.text) ?? 0) <= 0)
                    ? null
                    : () => Navigator.pop(dialogContext, true),
                child: const Text('حفظ'),
              ),
            ],
          );
        },
      ),
    );

    if (saved != true) return;
    var nextSortOrder = 0;
    for (final product in products) {
      if (product.companyId == companyId &&
          product.id != existing?.id &&
          product.sortOrder >= nextSortOrder) {
        nextSortOrder = product.sortOrder + 1;
      }
    }
    await service.saveProduct(
      Product(
        id: existing?.id ?? '',
        companyId: companyId,
        name: cardCategory.text.trim(),
        imageUrl: imageUrl,
        price: double.parse(price.text),
        costPrice: double.parse(costPrice.text),
        hiddenSalePrice: hiddenSalePrice.text.trim().isEmpty
            ? null
            : double.parse(hiddenSalePrice.text),
        hasOffer: hasOffer,
        isActive: active,
        buttonColorHex: buttonColor.text.trim(),
        buttonText: buttonText.text.trim(),
        sortOrder: existing != null && existing.companyId == companyId
            ? existing.sortOrder
            : nextSortOrder,
        stockCount: existing?.stockCount ?? 0,
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    CatalogService service,
    Product product,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف فئة الكارت'),
        content: Text(
          'هل تريد حذف فئة "${product.name}" نهائياً؟\n'
          'سيتم أيضاً حذف جميع رموز المخزون التابعة لها.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حذف نهائي'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await service.deleteProduct(product.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حذف فئة الكارت ومخزونها')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تعذر حذف فئة الكارت: $e')));
    }
  }
}

enum _FazerAdminMode { pricedGifts, gameKeys, world, topups }

class _FazerAdminCategoriesList extends StatefulWidget {
  const _FazerAdminCategoriesList({required this.mode});

  final _FazerAdminMode mode;

  @override
  State<_FazerAdminCategoriesList> createState() =>
      _FazerAdminCategoriesListState();
}

class _FazerAdminCategoriesListState extends State<_FazerAdminCategoriesList> {
  final _fazer = FazerService();
  bool _reordering = false;

  Future<void> _reorder(List<FazerCategory> categories, int oldIndex, int newIndex) async {
    if (_reordering || oldIndex == newIndex) return;
    if (newIndex > oldIndex) newIndex--;
    final reordered = List<FazerCategory>.from(categories);
    final item = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, item);
    setState(() => _reordering = true);
    try {
      await _fazer.updateCategoryOrder(reordered.map((c) => c.id).toList());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر حفظ الترتيب: $e')),
      );
    } finally {
      if (mounted) setState(() => _reordering = false);
    }
  }

  Future<void> _editImage(FazerCategory category) async {
    var uploading = false;
    String? error;
    var imageUrl = category.coverUrl;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) {
          Future<void> pick() async {
            final result = await FilePicker.pickFiles(
              type: FileType.image,
              withData: true,
            );
            final file = result?.files.single;
            if (file?.bytes == null) return;
            setLocal(() {
              uploading = true;
              error = null;
            });
            try {
              imageUrl = await StorageService().uploadImage(
                folder: 'fazer_category_images',
                bytes: file!.bytes!,
                fileName: file.name,
                contentType: _contentType(file.extension),
              );
              await _fazer.updateCategoryCustomImage(
                categoryId: category.id,
                customImageUrl: imageUrl,
              );
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            } catch (e) {
              error = 'تعذر رفع الصورة: $e';
            } finally {
              setLocal(() => uploading = false);
            }
          }

          return AlertDialog(
            title: Text(category.name),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: uploading ? null : pick,
                    child: Container(
                      height: 140,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: AppColors.chipBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: uploading
                          ? const Center(child: CircularProgressIndicator())
                          : imageUrl.isEmpty
                              ? const Center(
                                  child: Icon(Icons.add_photo_alternate_outlined),
                                )
                              : AppNetworkImage(
                                  url: imageUrl,
                                  fit: BoxFit.cover,
                                ),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(error!, style: const TextStyle(color: AppColors.danger)),
                  ],
                  const SizedBox(height: 8),
                  const Text('اضغط لتغيير صورة المربع في التطبيق'),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('إغلاق'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FazerCategory>>(
      stream: widget.mode == _FazerAdminMode.gameKeys
          ? _fazer.watchGameKeyCategories()
          : widget.mode == _FazerAdminMode.topups
              ? _fazer.watchTopupCategories()
              : _fazer.watchGiftCategories(),
      builder: (context, snapshot) {
        if (widget.mode == _FazerAdminMode.gameKeys ||
            widget.mode == _FazerAdminMode.topups) {
          return _buildList(
            snapshot.data ?? const <FazerCategory>[],
            loading: snapshot.connectionState == ConnectionState.waiting,
          );
        }
        return StreamBuilder<List<FazerOffer>>(
          stream: _fazer.watchPricedOffers(),
          builder: (context, offersSnap) {
            final cats = snapshot.data ?? const <FazerCategory>[];
            final byId = {for (final cat in cats) cat.id: cat};
            final names = <String, String>{};
            final images = <String, String>{};
            final pricedIds = <String>{};
            for (final offer in offersSnap.data ?? const <FazerOffer>[]) {
              if (offer.isGameKey) continue;
              pricedIds.add(offer.categoryId);
              names.putIfAbsent(
                offer.categoryId,
                () => offer.categoryName.isEmpty
                    ? offer.categoryId
                    : offer.categoryName,
              );
              if ((images[offer.categoryId] ?? '').isEmpty &&
                  offer.imageUrl.isNotEmpty) {
                images[offer.categoryId] = offer.imageUrl;
              }
            }

            final List<FazerCategory> visible;
            if (widget.mode == _FazerAdminMode.world) {
              visible = cats
                  .where((c) => !pricedIds.contains(c.id))
                  .toList()
                ..sort((a, b) {
                  final byOrder = a.sortOrder.compareTo(b.sortOrder);
                  return byOrder != 0 ? byOrder : a.name.compareTo(b.name);
                });
            } else {
              visible = pricedIds.map((id) {
                final cat = byId[id];
                if (cat != null) return cat;
                return FazerCategory(
                  id: id,
                  name: names[id] ?? id,
                  note: '',
                  imageUrl: images[id] ?? '',
                );
              }).toList()
                ..sort((a, b) {
                  final byOrder = a.sortOrder.compareTo(b.sortOrder);
                  return byOrder != 0 ? byOrder : a.name.compareTo(b.name);
                });
            }
            return _buildList(
              visible,
              loading:
                  snapshot.connectionState == ConnectionState.waiting ||
                  offersSnap.connectionState == ConnectionState.waiting,
            );
          },
        );
      },
    );
  }

  Widget _buildList(List<FazerCategory> categories, {required bool loading}) {
    if (loading && categories.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (categories.isEmpty) {
      return Center(
        child: Text(
          widget.mode == _FazerAdminMode.gameKeys
              ? 'لا توجد مفاتيح ألعاب بعد. زامن من شاشة بطاقات فايزر أولاً'
              : widget.mode == _FazerAdminMode.topups
                  ? 'لا توجد ألعاب شحن بعد. زامن الشحن بالاي دي من بطاقات فايزر أولاً'
                  : widget.mode == _FazerAdminMode.world
                      ? 'لا توجد بطاقات عالمية بعد. زامن من شاشة بطاقات فايزر أولاً'
                      : 'لا توجد مربعات ظاهرة في التطبيق. سعّر العروض أولاً من بطاقات فايزر',
        ),
      );
    }
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      buildDefaultDragHandles: false,
      itemCount: categories.length,
      onReorder: (oldIndex, newIndex) =>
          _reorder(categories, oldIndex, newIndex),
      itemBuilder: (context, index) {
        final category = categories[index];
        return Card(
          key: ValueKey(category.id),
          child: ListTile(
            leading: _ProductImage(url: category.coverUrl),
            title: Text(category.name),
            subtitle: Text(category.kindLabel),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'تغيير الصورة',
                  icon: const Icon(Icons.image_outlined),
                  onPressed: () => _editImage(category),
                ),
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Icon(Icons.drag_handle),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ProductImage extends StatelessWidget {
  const _ProductImage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: AppColors.chipBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: AppNetworkImage(
        url: url,
        fallbackIcon: Icons.sim_card,
        fallbackColor: AppColors.primary,
      ),
    );
  }
}

String _contentType(String? extension) {
  switch (extension?.toLowerCase()) {
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    default:
      return 'image/jpeg';
  }
}
