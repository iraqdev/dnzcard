import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/app_settings.dart';
import '../../models/order_model.dart';
import '../../services/fazer_service.dart';
import '../../services/settings_service.dart';

enum _JaafarPeriod { all, today, week, month, custom }

class AdminJaafarPage extends StatefulWidget {
  const AdminJaafarPage({super.key});

  @override
  State<AdminJaafarPage> createState() => _AdminJaafarPageState();
}

class _AdminJaafarPageState extends State<AdminJaafarPage> {
  final _db = FirebaseFirestore.instance;
  final _settings = SettingsService();
  final _fazer = FazerService();

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _ordersSub;
  StreamSubscription<AppSettings>? _settingsSub;

  List<OrderModel> _orders = [];
  double? _fazerBalanceUsd;
  String? _balanceCurrency;
  DateTime? _balanceUpdatedAt;
  _JaafarPeriod _period = _JaafarPeriod.month;
  DateTime? _fromDate;
  DateTime? _toDate;
  bool _loading = true;
  bool _refreshingBalance = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _applyPeriod(_JaafarPeriod.month);
    _listen();
  }

  void _listen() {
    _settingsSub = _settings.watch().listen((s) {
      if (!mounted) return;
      setState(() {
        _fazerBalanceUsd = s.fazerBalanceUsd;
      });
    }, onError: _onError);

    _subscribeOrders();
  }

  void _applyPeriod(_JaafarPeriod period) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime? from;
    DateTime? to = today;
    switch (period) {
      case _JaafarPeriod.all:
        from = null;
        to = null;
      case _JaafarPeriod.today:
        from = today;
      case _JaafarPeriod.week:
        from = today.subtract(const Duration(days: 6));
      case _JaafarPeriod.month:
        from = DateTime(now.year, now.month, 1);
      case _JaafarPeriod.custom:
        from = _fromDate;
        to = _toDate;
    }
    setState(() {
      _period = period;
      if (period != _JaafarPeriod.custom) {
        _fromDate = from;
        _toDate = to;
      }
    });
  }

  void _subscribeOrders() {
    _ordersSub?.cancel();
    final query = _db.collection('orders').where('source', isEqualTo: 'fazer');
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

  Future<void> _refreshBalance() async {
    setState(() => _refreshingBalance = true);
    try {
      final data = await _fazer.getBalance();
      if (!mounted) return;
      setState(() {
        _fazerBalanceUsd = double.tryParse('${data['balance']}');
        _balanceCurrency = data['currency']?.toString() ?? 'USD';
        _balanceUpdatedAt = DateTime.now();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تحديث رصيد فايزr')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _refreshingBalance = false);
    }
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
      _period = _JaafarPeriod.custom;
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
      _period = _JaafarPeriod.custom;
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

  int _items(OrderModel o) =>
      o.cardItems.isNotEmpty ? o.cardItems.length : (o.quantity < 1 ? 1 : o.quantity);

  _JaafarStats _computeStats() {
    var orders = 0;
    var items = 0;
    var revenue = 0.0;
    var cost = 0.0;
    var spentUsd = 0.0;
    var gameKeys = 0;
    var giftCards = 0;
    var topups = 0;
    var telegram = 0;
    final byProduct = <String, _ProductRow>{};

    for (final o in _orders) {
      if (o.status == 'failed' || o.status == 'ordering') continue;
      if (!_inRange(o.createdAt)) continue;
      final n = _items(o);
      orders++;
      items += n;
      revenue += o.unitPrice * n;
      cost += o.fazerOrderUnitCost * n;
      spentUsd += o.fazerPriceUsd * n;

      switch (o.fazerKind) {
        case 'game_key':
          gameKeys += n;
        case 'topup':
          topups += n;
        case 'telegram_stars':
        case 'telegram_premium':
          telegram += n;
        default:
          giftCards += n;
      }

      final key = o.productName.trim().isEmpty ? 'غير محدد' : o.productName.trim();
      final row = byProduct[key];
      if (row == null) {
        byProduct[key] = _ProductRow(
          name: key,
          count: n,
          revenue: o.unitPrice * n,
          profit: (o.unitPrice - o.fazerOrderUnitCost) * n,
        );
      } else {
        byProduct[key] = _ProductRow(
          name: key,
          count: row.count + n,
          revenue: row.revenue + o.unitPrice * n,
          profit: row.profit + (o.unitPrice - o.fazerOrderUnitCost) * n,
        );
      }
    }

    final products = byProduct.values.toList()
      ..sort((a, b) => b.revenue.compareTo(a.revenue));

    return _JaafarStats(
      orderCount: orders,
      itemCount: items,
      revenueIqd: revenue,
      costIqd: cost,
      profitIqd: revenue - cost,
      spentUsd: spentUsd,
      gameKeys: gameKeys,
      giftCards: giftCards,
      topups: topups,
      telegram: telegram,
      topProducts: products.take(15).toList(),
    );
  }

  @override
  void dispose() {
    _ordersSub?.cancel();
    _settingsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stats = _computeStats();
    final balance = _fazerBalanceUsd;

    return Scaffold(
      appBar: AppBar(
        title: const Text('جعفر — فايزr'),
        actions: [
          IconButton(
            tooltip: 'تحديث رصيد فايزr',
            onPressed: _refreshingBalance ? null : _refreshBalance,
            icon: _refreshingBalance
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null) ...[
                  Text(_error!, style: const TextStyle(color: AppColors.danger)),
                  const SizedBox(height: 12),
                ],
                _PeriodBar(
                  period: _period,
                  fromDate: _fromDate,
                  toDate: _toDate,
                  onPeriod: _applyPeriod,
                  onPickFrom: _pickFrom,
                  onPickTo: _pickTo,
                  onClear: () => _applyPeriod(_JaafarPeriod.all),
                ),
                const SizedBox(height: 16),
                const Text(
                  'رصيد فايزr',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _StatTile(
                      title: 'الرصيد الحالي',
                      value: balance == null
                          ? '—'
                          : '\$${balance.toStringAsFixed(2)}',
                      subtitle: _balanceCurrency ?? 'USD',
                      color: Colors.blue.shade700,
                      icon: Icons.account_balance_wallet_outlined,
                    ),
                    if (_balanceUpdatedAt != null)
                      _StatTile(
                        title: 'آخر تحديث مباشر',
                        value: Formatters.shortDate(_balanceUpdatedAt!),
                        subtitle: 'من API فايزr',
                        color: Colors.indigo,
                        icon: Icons.sync,
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  'ملخص الفترة',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _StatTile(
                      title: 'عدد الطلبات',
                      value: '${stats.orderCount}',
                      color: Colors.purple,
                      icon: Icons.receipt_long_outlined,
                    ),
                    _StatTile(
                      title: 'عدد المشتريات',
                      value: '${stats.itemCount}',
                      color: Colors.deepPurple,
                      icon: Icons.shopping_bag_outlined,
                    ),
                    _StatTile(
                      title: 'إجمالي المبيعات',
                      value: Formatters.money(stats.revenueIqd),
                      color: Colors.teal,
                      icon: Icons.payments_outlined,
                    ),
                    _StatTile(
                      title: 'إجمالي التكلفة',
                      value: Formatters.money(stats.costIqd),
                      color: Colors.brown,
                      icon: Icons.money_off_outlined,
                    ),
                    _StatTile(
                      title: 'إجمالي الأرباح',
                      value: Formatters.money(stats.profitIqd),
                      color: Colors.green.shade700,
                      icon: Icons.trending_up,
                    ),
                    _StatTile(
                      title: 'الصرف بالدولار',
                      value: '\$${stats.spentUsd.toStringAsFixed(2)}',
                      subtitle: 'تكلفة فايزr للفترة',
                      color: Colors.orange.shade800,
                      icon: Icons.attach_money,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  'حسب النوع',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _StatTile(
                      title: 'مفاتيح ألعاب',
                      value: '${stats.gameKeys}',
                      color: Colors.blueGrey,
                      icon: Icons.videogame_asset_outlined,
                    ),
                    _StatTile(
                      title: 'بطاقات',
                      value: '${stats.giftCards}',
                      color: Colors.amber.shade800,
                      icon: Icons.card_giftcard,
                    ),
                    _StatTile(
                      title: 'شحن ID',
                      value: '${stats.topups}',
                      color: Colors.cyan.shade700,
                      icon: Icons.person_pin_outlined,
                    ),
                    _StatTile(
                      title: 'تليجرام',
                      value: '${stats.telegram}',
                      color: Colors.lightBlue,
                      icon: Icons.telegram,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  'أكثر المنتجات مبيعاً',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 10),
                if (stats.topProducts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'لا توجد مشتريات فايزr في هذه الفترة',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  )
                else
                  ...stats.topProducts.map(
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
                            child: Text(
                              row.name,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          Text('${row.count}'),
                          const SizedBox(width: 16),
                          Text(Formatters.money(row.revenue)),
                          const SizedBox(width: 12),
                          Text(
                            Formatters.money(row.profit),
                            style: TextStyle(
                              color: Colors.green.shade700,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _JaafarStats {
  const _JaafarStats({
    required this.orderCount,
    required this.itemCount,
    required this.revenueIqd,
    required this.costIqd,
    required this.profitIqd,
    required this.spentUsd,
    required this.gameKeys,
    required this.giftCards,
    required this.topups,
    required this.telegram,
    required this.topProducts,
  });

  final int orderCount;
  final int itemCount;
  final double revenueIqd;
  final double costIqd;
  final double profitIqd;
  final double spentUsd;
  final int gameKeys;
  final int giftCards;
  final int topups;
  final int telegram;
  final List<_ProductRow> topProducts;
}

class _ProductRow {
  const _ProductRow({
    required this.name,
    required this.count,
    required this.revenue,
    required this.profit,
  });

  final String name;
  final int count;
  final double revenue;
  final double profit;
}

class _PeriodBar extends StatelessWidget {
  const _PeriodBar({
    required this.period,
    required this.fromDate,
    required this.toDate,
    required this.onPeriod,
    required this.onPickFrom,
    required this.onPickTo,
    required this.onClear,
  });

  final _JaafarPeriod period;
  final DateTime? fromDate;
  final DateTime? toDate;
  final ValueChanged<_JaafarPeriod> onPeriod;
  final VoidCallback onPickFrom;
  final VoidCallback onPickTo;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _chip('الكل', _JaafarPeriod.all),
              _chip('اليوم', _JaafarPeriod.today),
              _chip('أسبوع', _JaafarPeriod.week),
              _chip('شهر', _JaafarPeriod.month),
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
              onPressed: onPickFrom,
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text(
                fromDate == null
                    ? 'من تاريخ'
                    : 'من ${Formatters.shortDate(fromDate!)}',
              ),
            ),
            OutlinedButton.icon(
              onPressed: onPickTo,
              icon: const Icon(Icons.event, size: 16),
              label: Text(
                toDate == null
                    ? 'إلى تاريخ'
                    : 'إلى ${Formatters.shortDate(toDate!)}',
              ),
            ),
            if (fromDate != null || toDate != null)
              TextButton(onPressed: onClear, child: const Text('مسح الفلتر')),
          ],
        ),
      ],
    );
  }

  Widget _chip(String label, _JaafarPeriod value) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: FilterChip(
        label: Text(label),
        selected: period == value,
        onSelected: (_) => onPeriod(value),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
    this.subtitle,
  });

  final String title;
  final String value;
  final Color color;
  final IconData icon;
  final String? subtitle;

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
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
