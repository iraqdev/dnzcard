import '../../core/widgets/app_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../models/catalog_models.dart';
import '../../services/catalog_service.dart';
import '../../services/storage_service.dart';

class AdminCompaniesPage extends StatefulWidget {
  const AdminCompaniesPage({super.key});

  @override
  State<AdminCompaniesPage> createState() => _AdminCompaniesPageState();
}

class _AdminCompaniesPageState extends State<AdminCompaniesPage> {
  final _service = CatalogService();
  bool _reordering = false;

  @override
  void initState() {
    super.initState();
    _service.ensureFazerAllCompany();
    _service.ensureFazerGameKeysCompany();
    _service.ensureFazerWorldCompany();
    _service.ensureFazerTopupsCompany();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الشركات')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editCompany(context, _service),
        icon: const Icon(Icons.add),
        label: const Text('إضافة شركة'),
      ),
      body: StreamBuilder<List<Company>>(
        stream: _service.watchCompanies(activeOnly: false),
        builder: (context, snapshot) {
          final items = snapshot.data ?? [];
          if (items.isEmpty) {
            return const Center(child: Text('لا توجد شركات بعد'));
          }
          return ReorderableListView.builder(
            padding: const EdgeInsets.all(16),
            buildDefaultDragHandles: false,
            itemCount: items.length,
            onReorder: (oldIndex, newIndex) =>
                _reorder(items, oldIndex, newIndex),
            itemBuilder: (context, index) {
              final company = items[index];
              return Card(
                key: ValueKey(company.id),
                child: ListTile(
                  leading: _CompanyImage(url: company.logoUrl),
                  title: Text(company.name),
                  subtitle: Text(
                    company.isFazerSpecial
                        ? '${company.isActive ? 'ظاهرة في التطبيق' : 'مخفية من التطبيق'} · اسحب لتغيير الترتيب'
                        : (company.isActive
                            ? 'ظاهرة في التطبيق'
                            : 'مخفية من التطبيق'),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: company.isActive
                            ? 'إخفاء من التطبيق'
                            : 'إظهار في التطبيق',
                        icon: Icon(
                          company.isActive
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: company.isActive
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                        onPressed: () =>
                            _toggleCompanyVisibility(context, company),
                      ),
                      IconButton(
                        tooltip: 'تعديل',
                        icon: const Icon(Icons.edit),
                        onPressed: () =>
                            _editCompany(context, _service, company),
                      ),
                      if (!company.isFazerSpecial)
                        IconButton(
                          tooltip: 'حذف الشركة',
                          color: Colors.red,
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () =>
                              _deleteCompany(context, _service, company),
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
    );
  }

  Future<void> _toggleCompanyVisibility(
    BuildContext context,
    Company company,
  ) async {
    final next = !company.isActive;
    try {
      await _service.setCompanyActive(company.id, next);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            next
                ? '«${company.name}» ظاهرة الآن في التطبيق'
                : '«${company.name}» مخفية من التطبيق',
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تحديث ظهور الشركة: $e')),
      );
    }
  }

  Future<void> _reorder(
    List<Company> companies,
    int oldIndex,
    int newIndex,
  ) async {
    if (_reordering || oldIndex == newIndex) return;
    if (newIndex > oldIndex) newIndex--;
    final reordered = List<Company>.from(companies);
    final company = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, company);

    setState(() => _reordering = true);
    try {
      await _service.updateCompanyOrder(
        reordered.map((item) => item.id).toList(),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تعذر حفظ ترتيب الشركات: $e')));
    } finally {
      if (mounted) setState(() => _reordering = false);
    }
  }

  Future<void> _editCompany(
    BuildContext context,
    CatalogService service, [
    Company? existing,
  ]) async {
    final companies = await service.watchCompanies(activeOnly: false).first;
    if (!context.mounted) return;
    final name = TextEditingController(text: existing?.name ?? '');
    final color = TextEditingController(text: existing?.colorHex ?? '#0B3B4A');
    var imageUrl = existing?.logoUrl ?? '';
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
                folder: 'companies',
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
            title: Text(existing == null ? 'إضافة شركة' : 'تعديل شركة'),
            content: SizedBox(
              width: 430,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: name,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'اسم الشركة',
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
                            : 'تصفح الحاسوب ورفع صورة الشركة',
                      ),
                    ),
                    if (imageUrl.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 100,
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
                      controller: color,
                      decoration: const InputDecoration(
                        labelText: 'لون الشركة',
                      ),
                    ),
                    SwitchListTile(
                      value: active,
                      onChanged: (value) => setState(() => active = value),
                      title: const Text('مفعّلة'),
                    ),
                  ],
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
                onPressed: uploading || name.text.trim().isEmpty
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
    for (final company in companies) {
      if (company.id != existing?.id && company.sortOrder >= nextSortOrder) {
        nextSortOrder = company.sortOrder + 1;
      }
    }
    await service.saveCompany(
      Company(
        id: existing?.id ?? '',
        name: name.text.trim(),
        logoUrl: imageUrl,
        colorHex: color.text.trim(),
        sortOrder: existing?.sortOrder ?? nextSortOrder,
        isActive: active,
      ),
    );
  }

  Future<void> _deleteCompany(
    BuildContext context,
    CatalogService service,
    Company company,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف الشركة'),
        content: Text(
          'هل تريد حذف شركة "${company.name}" نهائياً؟\n'
          'سيتم أيضاً حذف جميع فئات الكروت ورموز المخزون التابعة لها.',
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
      await service.deleteCompany(company.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حذف الشركة وجميع بياناتها')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تعذر حذف الشركة: $e')));
    }
  }
}

class _CompanyImage extends StatelessWidget {
  const _CompanyImage({required this.url});

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
        fallbackIcon: Icons.business,
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
