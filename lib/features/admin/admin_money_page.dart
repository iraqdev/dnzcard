import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/catalog_models.dart';
import '../../models/order_model.dart';

enum _MoneySection { asia, zain, korek, baly }

class AdminMoneyPage extends StatefulWidget {
  const AdminMoneyPage({super.key});

  @override
  State<AdminMoneyPage> createState() => _AdminMoneyPageState();
}

class _AdminMoneyPageState extends State<AdminMoneyPage> {
  final _db = FirebaseFirestore.instance;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _ordersSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _productsSub;

  List<OrderModel> _orders = [];
  Map<String, Product> _productsById = {};

  _MoneySection _section = _MoneySection.asia;
  DateTime? _fromDate;
  DateTime? _toDate;
  bool _loading = true;
  String? _error;

  static const _sections = <(_MoneySection, String)>[
    (_MoneySection.asia, 'اسيا'),
    (_MoneySection.zain, 'زين'),
    (_MoneySection.korek, 'كورك'),
    (_MoneySection.baly, 'بلي'),
  ];

  @override
  void initState() {
    super.initState();
    _listen();
  }

  void _listen() {
    _productsSub = _db.collection('products').snapshots().listen((snap) {
      if (!mounted) return;
      final byId = <String, Product>{};
      for (final doc in snap.docs) {
        try {
          final p = Product.fromFirestore(doc);
          byId[p.id] = p;
        } catch (_) {}
      }
      setState(() => _productsById = byId);
    }, onError: _onError);

    _subscribeOrders();
  }

  /// نُقيّد قراءة الطلبات على الخادم بنطاق التاريخ عند تحديد "من" و"إلى" معاً
  /// لتقليل عدد المستندات المُنزّلة وتكلفة القراءات. الأرقام لا تتغيّر لأن
  /// الفلترة على العميل تطبّق نفس النطاق.
  void _subscribeOrders() {
    _ordersSub?.cancel();
    Query<Map<String, dynamic>> query = _db.collection('orders');
    if (_fromDate != null && _toDate != null) {
      final from = DateTime(_fromDate!.year, _fromDate!.month, _fromDate!.day);
      final toEnd = DateTime(
        _toDate!.year,
        _toDate!.month,
        _toDate!.day,
        23,
        59,
        59,
        999,
      );
      query = query
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
          .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(toEnd));
    }
    _ordersSub = query.snapshots().listen((snap) {
      if (!mounted) return;
      final orders = <OrderModel>[];
      for (final doc in snap.docs) {
        try {
          orders.add(OrderModel.fromFirestore(doc));
        } catch (_) {}
      }
      setState(() {
        _orders = orders;
        _loading = false;
        _error = null;
      });
    }, onError: _onError);
  }

  void _onError(Object e) {
    if (!mounted) return;
    setState(() {
      _error = e.toString();
      _loading = false;
    });
  }

  @override
  void dispose() {
    _ordersSub?.cancel();
    _productsSub?.cancel();
    super.dispose();
  }

  bool _matchesSection(OrderModel order, _MoneySection section) {
    if (order.status == 'failed' || order.status == 'ordering') return false;
    if (order.source == 'fazer') return false;

    final name = order.companyName.trim().toLowerCase().replaceAll(' ', '');
    switch (section) {
      case _MoneySection.asia:
        return name.contains('اسيا') || name.contains('asia');
      case _MoneySection.zain:
        return name.contains('زين') || name.contains('zain');
      case _MoneySection.korek:
        return name.contains('كورك') || name.contains('korek');
      case _MoneySection.baly:
        return name.contains('بلي') ||
            name.contains('baly') ||
            name.contains('play');
    }
  }

  bool _inDateRange(DateTime createdAt) {
    if (_fromDate != null) {
      final from = DateTime(_fromDate!.year, _fromDate!.month, _fromDate!.day);
      if (createdAt.isBefore(from)) return false;
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
      if (createdAt.isAfter(toEnd)) return false;
    }
    return true;
  }

  int _cardCount(OrderModel order) {
    if (order.cardItems.isNotEmpty) return order.cardItems.length;
    return order.quantity < 1 ? 1 : order.quantity;
  }

  double _unitCost(OrderModel order) {
    return _productsById[order.productId]?.costPrice ?? 0;
  }

  _MoneyStats _computeStats() {
    final byDenom = <String, _DenomRow>{};
    var totalCards = 0;
    var totalCost = 0.0;

    for (final order in _orders) {
      if (!_matchesSection(order, _section)) continue;
      if (!_inDateRange(order.createdAt)) continue;

      final cards = _cardCount(order);
      final cost = _unitCost(order) * cards;
      final denom = order.productName.trim().isEmpty
          ? 'غير محدد'
          : order.productName.trim();

      totalCards += cards;
      totalCost += cost;

      final existing = byDenom[denom];
      if (existing == null) {
        byDenom[denom] = _DenomRow(name: denom, cards: cards, cost: cost);
      } else {
        byDenom[denom] = _DenomRow(
          name: denom,
          cards: existing.cards + cards,
          cost: existing.cost + cost,
        );
      }
    }

    final rows = byDenom.values.toList()
      ..sort((a, b) => b.cards.compareTo(a.cards));

    return _MoneyStats(
      totalCards: totalCards,
      totalCost: totalCost,
      denominations: rows,
    );
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
    setState(() => _fromDate = picked);
    _subscribeOrders();
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
    setState(() => _toDate = picked);
    _subscribeOrders();
  }

  @override
  Widget build(BuildContext context) {
    final stats = _computeStats();

    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة الأموال'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'كروت الرصيد المحلية فقط — فايزr في شاشة جعفر',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary.withValues(alpha: 0.95),
              ),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: AppColors.danger),
                    ),
                  ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final item in _sections) ...[
                        _SectionChip(
                          label: item.$2,
                          selected: _section == item.$1,
                          onTap: () => setState(() => _section = item.$1),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
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
                        onPressed: () {
                          setState(() {
                            _fromDate = null;
                            _toDate = null;
                          });
                          _subscribeOrders();
                        },
                        child: const Text('مسح الفلتر'),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _SummaryCard(
                        title: 'عدد الكروت المباعة',
                        value: '${stats.totalCards}',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _SummaryCard(
                        title: 'مجموع التكلفة',
                        value: Formatters.money(stats.totalCost),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  'الفئات',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 10),
                if (stats.denominations.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text(
                        'لا توجد مبيعات لهذا القسم في الفترة المحددة',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  )
                else
                  ...stats.denominations.map(
                    (row) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        width: double.infinity,
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
                              child: Text(
                                row.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            Text(
                              '${row.cards} كرت',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Text(
                              Formatters.money(row.cost),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _MoneyStats {
  const _MoneyStats({
    required this.totalCards,
    required this.totalCost,
    required this.denominations,
  });

  final int totalCards;
  final double totalCost;
  final List<_DenomRow> denominations;
}

class _DenomRow {
  const _DenomRow({
    required this.name,
    required this.cards,
    required this.cost,
  });

  final String name;
  final int cards;
  final double cost;
}

class _SectionChip extends StatelessWidget {
  const _SectionChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primary : AppColors.chipBg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AppColors.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 18,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}
