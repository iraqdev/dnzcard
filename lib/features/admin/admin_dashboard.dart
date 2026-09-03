import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/catalog_models.dart';
import '../../models/order_model.dart';
import '../../models/wallet_topup.dart';
import '../../models/wallet_transaction.dart';

enum _DashPeriod { all, today, week, month, custom }

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
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _topupsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _uploadsSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _resetSub;

  /// وقت آخر تصفير للعدادات — تُحسب المربعات فقط من البيانات بعده.
  /// (لا يُحذف أي شيء من القاعدة؛ مجرد تصفير للعدادات المعروضة.)
  DateTime? _statsResetAt;

  /// رمز التصفية المطلوب لتصفير العدادات.
  static const String _resetCode = '708731';

  _DashPeriod _period = _DashPeriod.all;
  DateTime? _fromDate;
  DateTime? _toDate;

  int _users = 0;
  int _products = 0;
  int _companies = 0;
  int _soldCardsTotal = 0;
  int _soldCardsToday = 0;
  double _profits = 0;
  /// مجموع سعر البيع للكروت المباعة (تكلفة + ربح).
  double _salesWithProfit = 0;
  /// مجموع سعر التكلفة للكروت المباعة فقط (بدون ربح).
  double _salesCostOnly = 0;
  double _inventoryCost = 0;
  double _depositsToday = 0;
  double _depositsTotal = 0;
  double _depositsCash = 0;
  double _depositsDeferred = 0;
  double _depositsOnline = 0;
  double _onlineFees = 0;
  double _uploadsCost = 0;
  int _uploadsCount = 0;
  double _shopsWalletTotal = 0;
  double _shopsDeferredTotal = 0;
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
        _recomputeOnlineFees();
        _recomputeUploads();
      });
      // نقيّد قراءة الطلبات على الخادم بما بعد التصفير لتقليل عدد المستندات
      // المُنزّلة وتكلفة القراءات (الأرقام المعروضة مُصفّاة أصلاً بعد التصفير).
      if (!_ordersSubscribed || newReset != _appliedOrdersReset) {
        _subscribeOrders();
      }
    }, onError: (_) {});

    _usersSub = _db.collection('users').snapshots().listen((snap) {
      if (!mounted) return;
      var walletTotal = 0.0;
      var deferredTotal = 0.0;
      for (final doc in snap.docs) {
        final data = doc.data();
        if (data['role'] != 'shop') continue;
        walletTotal += (data['walletBalance'] as num?)?.toDouble() ?? 0;
        deferredTotal += (data['deferredOwed'] as num?)?.toDouble() ?? 0;
      }
      setState(() {
        _users = snap.docs.length;
        _shopsWalletTotal = walletTotal;
        _shopsDeferredTotal = deferredTotal;
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
        _depositsCash = 0;
        _depositsDeferred = 0;
        _depositsOnline = 0;
        _error = e.toString();
      });
    });

    _topupsSub = _db.collection('wallet_topups').snapshots().listen((snap) {
      if (!mounted) return;
      final topups = <WalletTopup>[];
      for (final doc in snap.docs) {
        try {
          topups.add(WalletTopup.fromFirestore(doc));
        } catch (_) {}
      }
      _topupsCache = topups;
      setState(() => _recomputeOnlineFees());
    }, onError: (_) {});

    _uploadsSub = _db.collection('stock_uploads').snapshots().listen((snap) {
      if (!mounted) return;
      final uploads = <StockUpload>[];
      for (final doc in snap.docs) {
        try {
          uploads.add(StockUpload.fromFirestore(doc));
        } catch (_) {}
      }
      _uploadsCache = uploads;
      setState(() => _recomputeUploads());
    }, onError: (_) {});
  }

  void _subscribeOrders() {
    _ordersSubscribed = true;
    _appliedOrdersReset = _statsResetAt;
    _ordersSub?.cancel();

    DateTime? effectiveFrom = _statsResetAt;
    if (_fromDate != null) {
      final from = DateTime(_fromDate!.year, _fromDate!.month, _fromDate!.day);
      effectiveFrom =
          effectiveFrom == null || effectiveFrom.isBefore(from)
              ? from
              : effectiveFrom;
    }

    Query<Map<String, dynamic>> query = _db.collection('orders');
    if (effectiveFrom != null) {
      query = query.where(
        'createdAt',
        isGreaterThanOrEqualTo: Timestamp.fromDate(effectiveFrom),
      );
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
      query = query.where(
        'createdAt',
        isLessThanOrEqualTo: Timestamp.fromDate(toEnd),
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
  List<WalletTopup> _topupsCache = [];
  List<StockUpload> _uploadsCache = [];

  /// هل يقع هذا التاريخ ضمن نطاق العدّ (بعد وقت التصفير إن وُجد)؟
  bool _countsAfterReset(DateTime at) =>
      _statsResetAt == null || at.isAfter(_statsResetAt!);

  /// هل يقع هذا التاريخ ضمن نطاق العدّ (بعد وقت التصفير + فلتر التاريخ)؟
  bool _countsInStats(DateTime at) {
    if (!_countsAfterReset(at)) return false;
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

  void _applyPeriod(_DashPeriod period) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime? from;
    DateTime? to = today;
    switch (period) {
      case _DashPeriod.all:
        from = null;
        to = null;
      case _DashPeriod.today:
        from = today;
      case _DashPeriod.week:
        from = today.subtract(const Duration(days: 6));
      case _DashPeriod.month:
        from = DateTime(now.year, now.month, 1);
      case _DashPeriod.custom:
        from = _fromDate;
        to = _toDate;
    }
    setState(() {
      _period = period;
      if (period != _DashPeriod.custom) {
        _fromDate = from;
        _toDate = to;
      }
      _recomputeOrderStats();
      _recomputeDeposits();
      _recomputeOnlineFees();
      _recomputeUploads();
    });
    _subscribeOrders();
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
      _period = _DashPeriod.custom;
      _recomputeOrderStats();
      _recomputeDeposits();
      _recomputeOnlineFees();
      _recomputeUploads();
    });
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
    setState(() {
      _toDate = picked;
      _period = _DashPeriod.custom;
      _recomputeOrderStats();
      _recomputeDeposits();
      _recomputeOnlineFees();
      _recomputeUploads();
    });
    _subscribeOrders();
  }

  bool get _hasDateFilter =>
      _period != _DashPeriod.all &&
      (_fromDate != null || _toDate != null);

  void _recomputeDeposits() {
    final now = DateTime.now();
    var today = 0.0;
    var total = 0.0;
    var cash = 0.0;
    var deferred = 0.0;
    var online = 0.0;
    for (final tx in _creditTxCache) {
      if (!_countsInStats(tx.createdAt)) continue;
      total += tx.amount;
      final method = tx.depositMethod ?? WalletDepositMethod.cash;
      switch (method) {
        case WalletDepositMethod.cash:
          cash += tx.amount;
        case WalletDepositMethod.deferred:
          deferred += tx.amount;
        case WalletDepositMethod.online:
          online += tx.amount;
      }
      if (!_hasDateFilter && _isSameDay(tx.createdAt, now)) {
        today += tx.amount;
      }
    }
    _depositsToday = today;
    _depositsTotal = total;
    _depositsCash = cash;
    _depositsDeferred = deferred;
    _depositsOnline = online;
  }

  void _recomputeOnlineFees() {
    var fees = 0.0;
    for (final topup in _topupsCache) {
      if (!topup.credited && !topup.isSuccess) continue;
      if (!_countsInStats(topup.createdAt)) continue;
      fees += topup.feeAmount;
    }
    _onlineFees = fees;
  }

  void _recomputeUploads() {
    var cost = 0.0;
    var count = 0;
    for (final upload in _uploadsCache) {
      if (!_countsInStats(upload.createdAt)) continue;
      cost += upload.totalCost;
      count += upload.count;
    }
    _uploadsCost = cost;
    _uploadsCount = count;
  }

  void _recomputeOrderStats() {
    final now = DateTime.now();
    var soldTotal = 0;
    var soldToday = 0;
    var profits = 0.0;
    var salesWithProfit = 0.0;
    var salesCostOnly = 0.0;

    for (final order in _ordersCache) {
      if (order.status == 'failed' || order.status == 'ordering') continue;
      if (!_countsInStats(order.createdAt)) continue;
      // أرباح ومبيعات فايزر تُحسب فقط في شاشة جعفر.
      if (order.source == 'fazer') continue;

      final cards = order.cardItems.isNotEmpty
          ? order.cardItems.length
          : (order.quantity < 1 ? 1 : order.quantity);
      soldTotal += cards;
      if (!_hasDateFilter && _isSameDay(order.createdAt, now)) {
        soldToday += cards;
      }

      final product = _productsById[order.productId];
      final unitRevenue = product == null
          ? order.unitPrice
          : (product.hiddenSalePrice != null && product.hiddenSalePrice! > 0
              ? product.hiddenSalePrice!
              : product.price);
      final unitCost = product?.costPrice ?? 0;
      final lineProfit = (unitRevenue - unitCost) * cards;
      salesWithProfit += unitRevenue * cards;
      salesCostOnly += unitCost * cards;
      profits += lineProfit;
    }

    _soldCardsTotal = soldTotal;
    _soldCardsToday = soldToday;
    _profits = profits;
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
    _topupsSub?.cancel();
    _uploadsSub?.cancel();
    _resetSub?.cancel();
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
            title: const Text('تصفير الإحصائيات'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'أدخل رمز التصفير للمتابعة. لن يُحذف أي شيء من القاعدة — '
                  'فقط تصفير العدادات المعروضة من هذه اللحظة فصاعداً.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  obscureText: true,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'رمز التصفير',
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
                child: const Text('تصفير'),
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
            TextButton.icon(
              onPressed: _promptReset,
              icon: const Icon(Icons.restart_alt),
              label: const Text('تصفير الإحصائيات'),
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
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _PeriodChip(
                        label: 'الكل',
                        selected: _period == _DashPeriod.all,
                        onTap: () => _applyPeriod(_DashPeriod.all),
                      ),
                      _PeriodChip(
                        label: 'اليوم',
                        selected: _period == _DashPeriod.today,
                        onTap: () => _applyPeriod(_DashPeriod.today),
                      ),
                      _PeriodChip(
                        label: 'أسبوع',
                        selected: _period == _DashPeriod.week,
                        onTap: () => _applyPeriod(_DashPeriod.week),
                      ),
                      _PeriodChip(
                        label: 'شهر',
                        selected: _period == _DashPeriod.month,
                        onTap: () => _applyPeriod(_DashPeriod.month),
                      ),
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
                        onPressed: () => _applyPeriod(_DashPeriod.all),
                        child: const Text('مسح الفلتر'),
                      ),
                  ],
                ),
                if (_hasDateFilter) ...[
                  const SizedBox(height: 8),
                  Text(
                    'الإحصائيات المالية والمبيعات للفترة المحددة',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary.withValues(alpha: 0.9),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
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
                      subtitle: _hasDateFilter ? 'في الفترة المحددة' : null,
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
                          'كارتات الرصيد فقط — أرباح فايزر في شاشة جعفر',
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  'الملخص المالي — كروت الرصيد',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  'فايزr منفصل بالكامل في شاشة جعفر — لا يدخل هنا',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary.withValues(alpha: 0.9),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _StatCard(
                      title: 'إيداعات نقدية',
                      value: Formatters.money(_depositsCash),
                      color: Colors.green.shade700,
                      icon: Icons.payments_outlined,
                      subtitle: 'فلوس وصلت فعلاً',
                    ),
                    _StatCard(
                      title: 'إيداعات آجل',
                      value: Formatters.money(_depositsDeferred),
                      color: Colors.orange.shade800,
                      icon: Icons.schedule,
                      subtitle: 'دين على المحلات',
                    ),
                    _StatCard(
                      title: 'إيداعات أونلاين',
                      value: Formatters.money(_depositsOnline),
                      color: Colors.blue.shade700,
                      icon: Icons.language,
                      subtitle: 'المبلغ المضاف للمحفظة',
                    ),
                    _StatCard(
                      title: 'عمولات الأونلاين (1%)',
                      value: Formatters.money(_onlineFees),
                      color: Colors.teal.shade800,
                      icon: Icons.percent,
                      subtitle: 'تُأخذ من الزبون عند الإيداع',
                      wide: true,
                    ),
                    _StatCard(
                      title: 'تكلفة الرفع للمخزون',
                      value: Formatters.money(_uploadsCost),
                      color: Colors.deepOrange.shade700,
                      icon: Icons.upload_file_outlined,
                      subtitle: '$_uploadsCount كرت — حسب سعر التكلفة',
                      wide: true,
                    ),
                    _StatCard(
                      title: 'أرصدة المحلات (التزام)',
                      value: Formatters.money(_shopsWalletTotal),
                      color: Colors.indigo.shade700,
                      icon: Icons.account_balance_wallet_outlined,
                      subtitle: 'مجموع محافظ المحلات',
                      wide: true,
                    ),
                    _StatCard(
                      title: 'ديون المحلات (آجل)',
                      value: Formatters.money(_shopsDeferredTotal),
                      color: Colors.brown.shade700,
                      icon: Icons.receipt_long_outlined,
                      subtitle: 'مجموع deferredOwed',
                      wide: true,
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
                    if (!_hasDateFilter) ...[
                      _StatCard(
                        title: 'إيداعات اليوم',
                        value: Formatters.money(_depositsToday),
                        color: Colors.green,
                        icon: Icons.today_outlined,
                        wide: true,
                      ),
                      _StatCard(
                        title: 'مبيعات اليوم (عدد الكارتات)',
                        value: '$_soldCardsToday',
                        color: Colors.purple,
                        icon: Icons.point_of_sale_outlined,
                      ),
                    ],
                    _StatCard(
                      title: _hasDateFilter
                          ? 'إجمالي الإيداعات (الفترة)'
                          : 'إجمالي الإيداعات',
                      value: Formatters.money(_depositsTotal),
                      color: Colors.green.shade800,
                      icon: Icons.account_balance_wallet_outlined,
                    ),
                    _StatCard(
                      title: _hasDateFilter
                          ? 'مبيعات الفترة (عدد كارتات)'
                          : 'إجمالي المبيعات (عدد كارتات)',
                      value: '$_soldCardsTotal',
                      color: Colors.purple.shade800,
                      icon: Icons.receipt_long_outlined,
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
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
