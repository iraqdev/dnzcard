import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/app_settings.dart';
import '../../models/catalog_models.dart';
import '../../models/fazer_models.dart';
import '../../models/order_model.dart';
import '../../models/wallet_transaction.dart';
import '../../services/settings_service.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final _db = FirebaseFirestore.instance;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _usersSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _productsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _companiesSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _ordersSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _txSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _resetSub;
  StreamSubscription<AppSettings>? _settingsSub;
  final _settings = SettingsService();
  double _gameKeyCostRate = kFazerGameKeyCostRate;

  /// وقت آخر تصفير للعدادات — تُحسب المربعات فقط من البيانات بعده.
  /// (لا يُحذف أي شيء من القاعدة؛ مجرد تصفير للعدادات المعروضة.)
  DateTime? _statsResetAt;

  /// رمز التصفية المطلوب لتصفير العدادات.
  static const String _resetCode = '708731';

  int _users = 0;
  int _products = 0;
  int _companies = 0;
  int _soldCardsTotal = 0;
  int _soldCardsToday = 0;
  double _profits = 0;
  /// أرباح مبيعات فايزر فقط (بطاقات / مفاتيح / شحن).
  double _cardProfits = 0;
  /// مجموع سعر البيع للكروت المباعة (تكلفة + ربح).
  double _salesWithProfit = 0;
  /// مجموع سعر التكلفة للكروت المباعة فقط (بدون ربح).
  double _salesCostOnly = 0;
  double _inventoryCost = 0;
  double _depositsToday = 0;
  double _depositsTotal = 0;
  bool _loading = true;
  String? _error;

  Map<String, Product> _productsById = {};

  bool _ordersSubscribed = false;
  DateTime? _appliedOrdersReset;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  void _listen() {
    _resetSub = _db
        .collection('app_settings')
        .doc('dashboard_stats')
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final raw = snap.data()?['statsResetAt'];
      final newReset = raw is Timestamp ? raw.toDate() : null;
      setState(() {
        _statsResetAt = newReset;
        _recomputeOrderStats();
        _recomputeDeposits();
      });
      // نقيّد قراءة الطلبات على الخادم بما بعد التصفير لتقليل عدد المستندات
      // المُنزّلة وتكلفة القراءات (الأرقام المعروضة مُصفّاة أصلاً بعد التصفير).
      if (!_ordersSubscribed || newReset != _appliedOrdersReset) {
        _subscribeOrders();
      }
    }, onError: (_) {});

    _settingsSub = _settings.watch().listen((settings) {
      if (!mounted) return;
      setState(() {
        _gameKeyCostRate = settings.gameKeyCostRate;
        _recomputeOrderStats();
      });
    }, onError: _onError);

    _usersSub = _db.collection('users').snapshots().listen((snap) {
      if (!mounted) return;
      setState(() {
        _users = snap.docs.length;
        _loading = false;
      });
    }, onError: _onError);

    _companiesSub = _db.collection('companies').snapshots().listen((snap) {
      if (!mounted) return;
      setState(() => _companies = snap.docs.length);
    }, onError: _onError);

    _productsSub = _db.collection('products').snapshots().listen((snap) {
      if (!mounted) return;
      final products = <Product>[];
      for (final doc in snap.docs) {
        try {
          products.add(Product.fromFirestore(doc));
        } catch (_) {}
      }
      final byId = {for (final p in products) p.id: p};
      var inventoryCost = 0.0;
      for (final p in products) {
        final stock = p.stockCount < 0 ? 0 : p.stockCount;
        inventoryCost += stock * p.costPrice;
      }
      setState(() {
        _products = products.length;
        _productsById = byId;
        _inventoryCost = inventoryCost;
        _recomputeOrderStats();
      });
    }, onError: _onError);

    _txSub = _db
        .collection('wallet_transactions')
        .where('type', isEqualTo: 'credit')
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final txs = <WalletTransaction>[];
      for (final doc in snap.docs) {
        try {
          txs.add(WalletTransaction.fromFirestore(doc));
        } catch (_) {}
      }
      _creditTxCache = txs;
      setState(() {
        _error = null;
        _recomputeDeposits();
      });
    }, onError: (Object e) {
      // لا نعطّل اللوحة بالكامل إن فشل استعلام الإيداعات فقط.
      if (!mounted) return;
      setState(() {
        _depositsToday = 0;
        _depositsTotal = 0;
        _error = e.toString();
      });
    });
  }

  void _subscribeOrders() {
    _ordersSubscribed = true;
    _appliedOrdersReset = _statsResetAt;
    _ordersSub?.cancel();
    Query<Map<String, dynamic>> query = _db.collection('orders');
    if (_statsResetAt != null) {
      query = query.where(
        'createdAt',
        isGreaterThan: Timestamp.fromDate(_statsResetAt!),
      );
    }
    _ordersSub = query.snapshots().listen((snap) {
      if (!mounted) return;
      final orders = <OrderModel>[];
      for (final doc in snap.docs) {
        try {
          orders.add(OrderModel.fromFirestore(doc));
        } catch (_) {}
      }
      _ordersCache = orders;
      setState(() {
        _error = null;
        _recomputeOrderStats();
      });
    }, onError: _onError);
  }

  List<OrderModel> _ordersCache = [];
  List<WalletTransaction> _creditTxCache = [];

  /// هل يقع هذا التاريخ ضمن نطاق العدّ (بعد وقت التصفير إن وُجد)؟
  bool _countsAfterReset(DateTime at) =>
      _statsResetAt == null || at.isAfter(_statsResetAt!);

  void _recomputeDeposits() {
    final now = DateTime.now();
    var today = 0.0;
    var total = 0.0;
    for (final tx in _creditTxCache) {
      if (!_countsAfterReset(tx.createdAt)) continue;
      total += tx.amount;
      if (_isSameDay(tx.createdAt, now)) {
        today += tx.amount;
      }
    }
    _depositsToday = today;
    _depositsTotal = total;
  }

  void _recomputeOrderStats() {
    final now = DateTime.now();
    var soldTotal = 0;
    var soldToday = 0;
    var profits = 0.0;
    var cardProfits = 0.0;
    var salesWithProfit = 0.0;
    var salesCostOnly = 0.0;

    for (final order in _ordersCache) {
      if (order.status == 'failed' || order.status == 'ordering') continue;
      if (!_countsAfterReset(order.createdAt)) continue;
      final cards = order.cardItems.isNotEmpty
          ? order.cardItems.length
          : (order.quantity < 1 ? 1 : order.quantity);
      soldTotal += cards;
      if (_isSameDay(order.createdAt, now)) {
        soldToday += cards;
      }

      final product = _productsById[order.productId];
      final isFazer = order.source == 'fazer';
      final unitRevenue = isFazer
          ? order.unitPrice
          : product == null
              ? order.unitPrice
              : (product.hiddenSalePrice != null && product.hiddenSalePrice! > 0
                  ? product.hiddenSalePrice!
                  : product.price);
      final unitCost = isFazer
          ? (order.fazerPriceUsd * _gameKeyCostRate).roundToDouble()
          : (product?.costPrice ?? 0);
      final lineProfit = (unitRevenue - unitCost) * cards;
      salesWithProfit += unitRevenue * cards;
      salesCostOnly += unitCost * cards;
      profits += lineProfit;
      if (isFazer) {
        cardProfits += lineProfit;
      }
    }

    _soldCardsTotal = soldTotal;
    _soldCardsToday = soldToday;
    _profits = profits;
    _cardProfits = cardProfits;
    _salesWithProfit = salesWithProfit;
    _salesCostOnly = salesCostOnly;
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _onError(Object e) {
    if (!mounted) return;
    setState(() {
      _error = e.toString();
      _loading = false;
    });
  }

  @override
  void dispose() {
    _usersSub?.cancel();
    _productsSub?.cancel();
    _companiesSub?.cancel();
    _ordersSub?.cancel();
    _txSub?.cancel();
    _resetSub?.cancel();
    _settingsSub?.cancel();
    super.dispose();
  }

  Future<void> _promptReset() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        String? err;
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: const Text('تصفية العدادات'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'أدخل رمز التصفية للمتابعة. لن يُحذف أي شيء من القاعدة — '
                  'فقط تصفير العدادات المعروضة.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  obscureText: true,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'الرمز',
                    errorText: err,
                  ),
                  onChanged: (_) {
                    if (err != null) setLocal(() => err = null);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (controller.text.trim() == _resetCode) {
                    Navigator.pop(ctx, true);
                  } else {
                    setLocal(() => err = 'الرمز غير صحيح');
                  }
                },
                child: const Text('تصفية'),
              ),
            ],
          ),
        );
      },
    );

    if (confirmed != true) return;
    try {
      await _db.collection('app_settings').doc('dashboard_stats').set(
        {'statsResetAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تصفير العدادات')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر التصفية: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة التحكم'),
        actions: [
          if (kIsWeb)
            IconButton(
              onPressed: _promptReset,
              icon: const Icon(Icons.filter_alt_outlined),
              tooltip: 'تصفية',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null) ...[
                  Text(
                    _error!,
                    style: const TextStyle(color: AppColors.danger),
                  ),
                  const SizedBox(height: 12),
                ],
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _StatCard(
                      title: 'المستخدمون',
                      value: '$_users',
                      color: Colors.blue,
                      icon: Icons.people_outline,
                    ),
                    _StatCard(
                      title: 'الكارتات المباعة بالكامل',
                      value: '$_soldCardsTotal',
                      color: AppColors.accent,
                      icon: Icons.sim_card_outlined,
                    ),
                    _StatCard(
                      title: 'المنتجات',
                      value: '$_products',
                      color: AppColors.primary,
                      icon: Icons.category_outlined,
                    ),
                    _StatCard(
                      title: 'الشركات',
                      value: '$_companies',
                      color: Colors.indigo,
                      icon: Icons.business_outlined,
                    ),
                    _StatCard(
                      title: 'الأرباح',
                      value: Formatters.money(_profits),
                      color: Colors.teal,
                      icon: Icons.trending_up,
                      subtitle:
                          'سعر مخفي/بيع − تكلفة × عدد الكروت المباعة',
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  'الملخص المالي والمبيعات',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _StatCard(
                      title: 'مبيعات تساوي التكلفة مع الربح',
                      value: Formatters.money(_salesWithProfit),
                      color: Colors.cyan.shade700,
                      icon: Icons.payments_outlined,
                      subtitle: 'سعر البيع (مخفي/ظاهر) × الكروت المباعة',
                      wide: true,
                    ),
                    _StatCard(
                      title: 'مبيعات التكلفة بدون الربح',
                      value: Formatters.money(_salesCostOnly),
                      color: Colors.brown.shade600,
                      icon: Icons.money_off_outlined,
                      subtitle: 'سعر التكلفة × الكروت المباعة',
                      wide: true,
                    ),
                    _StatCard(
                      title: 'إجمالي تكلفة الأرصدة الحالية',
                      value: Formatters.money(_inventoryCost),
                      color: Colors.deepOrange,
                      icon: Icons.inventory_2_outlined,
                      subtitle: 'المخزون المتاح × سعر التكلفة',
                      wide: true,
                    ),
                    _StatCard(
                      title: 'إيداعات اليوم',
                      value: Formatters.money(_depositsToday),
                      color: Colors.green,
                      icon: Icons.today_outlined,
                      wide: true,
                    ),
                    _StatCard(
                      title: 'إجمالي الإيداعات',
                      value: Formatters.money(_depositsTotal),
                      color: Colors.green.shade800,
                      icon: Icons.account_balance_wallet_outlined,
                    ),
                    _StatCard(
                      title: 'مبيعات اليوم (عدد الكارتات)',
                      value: '$_soldCardsToday',
                      color: Colors.purple,
                      icon: Icons.point_of_sale_outlined,
                    ),
                    _StatCard(
                      title: 'إجمالي المبيعات (عدد كارتات)',
                      value: '$_soldCardsTotal',
                      color: Colors.purple.shade800,
                      icon: Icons.receipt_long_outlined,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  'البطاقات',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _StatCard(
                      title: 'أرباح البطاقات',
                      value: Formatters.money(_cardProfits),
                      color: Colors.teal.shade800,
                      icon: Icons.sim_card_outlined,
                      subtitle:
                          'أرباح مشتريات فايزر فقط (بطاقات / مفاتيح / شحن)',
                      wide: true,
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
    this.subtitle,
    this.wide = false,
  });

  final String title;
  final String value;
  final Color color;
  final IconData icon;
  final String? subtitle;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final cardWidth = wide
        ? (width >= 900 ? 340.0 : width - 32)
        : (width >= 900 ? 220.0 : (width - 44) / 2);

    return Container(
      width: cardWidth,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
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
