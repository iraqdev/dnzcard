import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/catalog_models.dart';
import '../../services/catalog_service.dart';

enum _UploadPeriod { all, today, custom }

class AdminStockUploadsPage extends StatefulWidget {
  const AdminStockUploadsPage({super.key});

  @override
  State<AdminStockUploadsPage> createState() => _AdminStockUploadsPageState();
}

class _AdminStockUploadsPageState extends State<AdminStockUploadsPage> {
  final _service = CatalogService();
  _UploadPeriod _period = _UploadPeriod.today;
  DateTime? _fromDate;
  DateTime? _toDate;

  @override
  void initState() {
    super.initState();
    _applyPeriod(_UploadPeriod.today);
  }

  void _applyPeriod(_UploadPeriod period) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      _period = period;
      switch (period) {
        case _UploadPeriod.all:
          _fromDate = null;
          _toDate = null;
        case _UploadPeriod.today:
          _fromDate = today;
          _toDate = today;
        case _UploadPeriod.custom:
          break;
      }
    });
  }

  Future<void> _pickFrom() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _fromDate ?? now,
      firstDate: DateTime(2020),
      lastDate: now,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _fromDate = picked;
      _period = _UploadPeriod.custom;
    });
  }

  Future<void> _pickTo() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _toDate ?? now,
      firstDate: DateTime(2020),
      lastDate: now,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _toDate = picked;
      _period = _UploadPeriod.custom;
    });
  }

  bool _inRange(DateTime at) {
    if (_fromDate != null) {
      final from = DateTime(_fromDate!.year, _fromDate!.month, _fromDate!.day);
      if (at.isBefore(from)) return false;
    }
    if (_toDate != null) {
      final toEnd = DateTime(
        _toDate!.year,
        _toDate!.month,
        _toDate!.day,
        23,
        59,
        59,
        999,
      );
      if (at.isAfter(toEnd)) return false;
    }
    return true;
  }

  String _sourceLabel(String source) {
    switch (source) {
      case 'scan':
        return 'قراءة صور';
      case 'baqaty_bot':
      case 'cloud_function':
      case 'card_buyer_bot':
        return 'بوت باقتي';
      case 'asia_bot':
        return 'بوت آسيا';
      case 'athir_bot':
        return 'بوت أثير';
      case 'bot':
        return 'بوت';
      default:
        return 'يدوي';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الرفع')),
      body: StreamBuilder<List<StockUpload>>(
        stream: _service.watchStockUploads(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '${snapshot.error}',
                  style: const TextStyle(color: AppColors.danger),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final filtered =
              snapshot.data!.where((u) => _inRange(u.createdAt)).toList();

          var totalCount = 0;
          var totalCost = 0.0;
          final byProduct = <String, _ProductAgg>{};
          for (final u in filtered) {
            totalCount += u.count;
            totalCost += u.totalCost;
            final key = u.productId.isEmpty ? u.productName : u.productId;
            final prev = byProduct[key];
            if (prev == null) {
              byProduct[key] = _ProductAgg(
                name: u.productName.isEmpty ? 'غير محدد' : u.productName,
                companyName: u.companyName,
                count: u.count,
                totalCost: u.totalCost,
              );
            } else {
              byProduct[key] = _ProductAgg(
                name: prev.name,
                companyName: prev.companyName.isEmpty
                    ? u.companyName
                    : prev.companyName,
                count: prev.count + u.count,
                totalCost: prev.totalCost + u.totalCost,
              );
            }
          }
          final products = byProduct.values.toList()
            ..sort((a, b) => b.totalCost.compareTo(a.totalCost));

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _chip('الكل', _UploadPeriod.all),
                    _chip('اليوم', _UploadPeriod.today),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickFrom,
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(
                      _fromDate == null
                          ? 'من تاريخ'
                          : 'من ${Formatters.shortDate(_fromDate!)}',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _pickTo,
                    icon: const Icon(Icons.event, size: 16),
                    label: Text(
                      _toDate == null
                          ? 'إلى تاريخ'
                          : 'إلى ${Formatters.shortDate(_toDate!)}',
                    ),
                  ),
                  if (_fromDate != null || _toDate != null)
                    TextButton(
                      onPressed: () => _applyPeriod(_UploadPeriod.all),
                      child: const Text('مسح الفلتر'),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _StatTile(
                    title: 'عدد الكروت المرفوعة',
                    value: '$totalCount',
                    color: Colors.indigo,
                    icon: Icons.sim_card_outlined,
                  ),
                  _StatTile(
                    title: 'إجمالي التكلفة',
                    value: Formatters.money(totalCost),
                    color: Colors.deepOrange.shade700,
                    icon: Icons.payments_outlined,
                  ),
                  _StatTile(
                    title: 'عدد عمليات الرفع',
                    value: '${filtered.length}',
                    color: Colors.teal,
                    icon: Icons.upload_file_outlined,
                  ),
                  _StatTile(
                    title: 'عدد الفئات',
                    value: '${products.length}',
                    color: Colors.purple,
                    icon: Icons.category_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'حسب الفئة',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 10),
              if (products.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'لا توجد عمليات رفع في هذه الفترة',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                )
              else
                ...products.map(
                  (row) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                row.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (row.companyName.isNotEmpty)
                                Text(
                                  row.companyName,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Text('${row.count} كرت'),
                        const SizedBox(width: 16),
                        Text(
                          Formatters.money(row.totalCost),
                          style: TextStyle(
                            color: Colors.deepOrange.shade700,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              const Text(
                'عمليات الرفع',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 10),
              if (filtered.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'لم يُسجَّل رفع بعد في هذه الفترة',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                )
              else
                ...filtered.map(
                  (u) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                u.productName.isEmpty
                                    ? 'منتج غير معروف'
                                    : u.productName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Text(
                              Formatters.date(u.createdAt),
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        if (u.companyName.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            u.companyName,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 12,
                          runSpacing: 6,
                          children: [
                            Text('العدد: ${u.count}'),
                            Text('تكلفة الوحدة: ${Formatters.money(u.unitCost)}'),
                            Text(
                              'الإجمالي: ${Formatters.money(u.totalCost)}',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Colors.deepOrange.shade700,
                              ),
                            ),
                            Text(
                              _sourceLabel(u.source),
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _chip(String label, _UploadPeriod value) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: FilterChip(
        label: Text(label),
        selected: _period == value,
        onSelected: (_) => _applyPeriod(value),
      ),
    );
  }
}

class _ProductAgg {
  const _ProductAgg({
    required this.name,
    required this.companyName,
    required this.count,
    required this.totalCost,
  });

  final String name;
  final String companyName;
  final int count;
  final double totalCost;
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String title;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final cardWidth = width >= 900 ? 220.0 : (width - 44) / 2;
    return Container(
      width: cardWidth,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
