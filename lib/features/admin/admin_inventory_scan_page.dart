import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../models/catalog_models.dart';
import '../../services/card_ocr_service.dart';
import '../../services/catalog_service.dart';

class AdminInventoryScanPage extends StatefulWidget {
  const AdminInventoryScanPage({super.key});

  @override
  State<AdminInventoryScanPage> createState() => _AdminInventoryScanPageState();
}

class _AdminInventoryScanPageState extends State<AdminInventoryScanPage> {
  final _catalog = CatalogService();
  final _ocr = CardOcrService();

  String? _companyId;
  String? _productId;
  bool _scanning = false;
  bool _saving = false;
  List<OcrCardResult> _results = [];

  Future<void> _pickAndScan() async {
    if (_productId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اختر فئة الكارت أولاً')),
      );
      return;
    }

    final picked = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;

    final files = <({Uint8List bytes, String fileName, String? mimeType})>[];
    for (final file in picked.files) {
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) continue;
      files.add((
        bytes: bytes,
        fileName: file.name,
        mimeType: file.extension == null
            ? null
            : 'image/${file.extension!.toLowerCase()}',
      ));
    }
    if (files.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر قراءة ملفات الصور')),
      );
      return;
    }

    setState(() {
      _scanning = true;
      _results = [];
    });

    try {
      final results = await _ocr.extractMany(files);
      if (!mounted) return;
      setState(() => _results = results);
      final ok = results.where((r) => r.isValid).length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تمت قراءة $ok من ${results.length} صورة')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تعذر قراءة الصور: $e')));
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _confirmAdd() async {
    final productId = _productId;
    if (productId == null) return;

    final items =
        _results.where((r) => r.isValid).map((r) => r.toCardItem()).toList();
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد نتائج صالحة للإضافة')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الإضافة'),
        content: Text('إضافة ${items.length} بطاقة إلى المخزون؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      final added = await _catalog.addCardItems(productId, items);
      if (!mounted) return;
      setState(() => _results = []);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تمت إضافة $added بطاقة')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تعذر الإضافة: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _removeAt(int index) {
    setState(() => _results.removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    final validCount = _results.where((r) => r.isValid).length;

    return Scaffold(
      appBar: AppBar(title: const Text('قراءة صور الكروت')),
      body: StreamBuilder<List<Company>>(
        stream: _catalog.watchCompanies(activeOnly: false),
        builder: (context, companiesSnap) {
          if (companiesSnap.connectionState == ConnectionState.waiting &&
              !companiesSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final companies = (companiesSnap.data ?? [])
              .where((c) => !c.isFazerSpecial)
              .toList();
          if (companies.isEmpty) {
            return const Center(child: Text('أضف شركة أولاً'));
          }

          final companyId =
              (_companyId != null &&
                  companies.any((c) => c.id == _companyId))
              ? _companyId!
              : companies.first.id;

          return StreamBuilder<List<Product>>(
            stream: _catalog.watchProducts(activeOnly: false),
            builder: (context, productsSnap) {
              final products = (productsSnap.data ?? [])
                  .where((p) => p.companyId == companyId)
                  .toList();
              final productId =
                  (_productId != null &&
                      products.any((p) => p.id == _productId))
                  ? _productId
                  : null;

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    '1) اختر الشركة ثم فئة الكارت\n'
                    '2) اضغط رفع الصور\n'
                    '3) راجع النتائج ثم أضف للمخزون',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'الشركة',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final company in companies)
                        ChoiceChip(
                          label: Text(company.name),
                          selected: company.id == companyId,
                          onSelected: _scanning || _saving
                              ? null
                              : (_) {
                                  setState(() {
                                    _companyId = company.id;
                                    _productId = null;
                                    _results = [];
                                  });
                                },
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'فئة الكارت',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  if (products.isEmpty)
                    const Text(
                      'لا توجد فئات كروت لهذه الشركة',
                      style: TextStyle(color: AppColors.textSecondary),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final product in products)
                          ChoiceChip(
                            label: Text(product.name),
                            selected: product.id == productId,
                            onSelected: _scanning || _saving
                                ? null
                                : (_) {
                                    setState(() {
                                      _companyId = companyId;
                                      _productId = product.id;
                                      _results = [];
                                    });
                                  },
                          ),
                      ],
                    ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _scanning || _saving || productId == null
                          ? null
                          : _pickAndScan,
                      icon: _scanning
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.upload_file),
                      label: Text(
                        productId == null
                            ? 'اختر فئة الكارت أولاً'
                            : (_scanning
                                  ? 'جاري قراءة الصور...'
                                  : 'رفع صور وقراءتها'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: !_scanning && !_saving && validCount > 0
                          ? _confirmAdd
                          : null,
                      icon: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.playlist_add_check),
                      label: Text('إضافة للمخزون ($validCount)'),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 8),
                  if (_results.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Text(
                          _scanning
                              ? 'جاري قراءة الصور...'
                              : 'لا توجد نتائج بعد. ارفع صوراً للبدء.',
                          style: const TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    )
                  else
                    ...List.generate(_results.length, (index) {
                      final item = _results[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _OcrResultCard(
                          result: item,
                          enabled: !_scanning && !_saving,
                          onChanged: () => setState(() {}),
                          onRemove: () => _removeAt(index),
                        ),
                      );
                    }),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _OcrResultCard extends StatelessWidget {
  const _OcrResultCard({
    required this.result,
    required this.enabled,
    required this.onChanged,
    required this.onRemove,
  });

  final OcrCardResult result;
  final bool enabled;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final hasError = result.error != null && !result.isValid;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  hasError ? Icons.warning_amber : Icons.check_circle,
                  color: hasError ? Colors.orange : AppColors.accent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    result.fileName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'حذف',
                  onPressed: enabled ? onRemove : null,
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                ),
              ],
            ),
            if (result.error != null) ...[
              const SizedBox(height: 4),
              Text(
                result.error!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ],
            const SizedBox(height: 8),
            TextFormField(
              initialValue: result.code,
              enabled: enabled,
              decoration: const InputDecoration(
                labelText: 'PIN / كود رمز التعريف الشخصي',
              ),
              onChanged: (v) {
                result.code = v.trim();
                result.error = null;
                onChanged();
              },
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: result.serialNumber,
              enabled: enabled,
              decoration: const InputDecoration(labelText: 'الرقم التسلسلي'),
              onChanged: (v) {
                result.serialNumber = v.trim();
                result.error = null;
                onChanged();
              },
            ),
          ],
        ),
      ),
    );
  }
}
