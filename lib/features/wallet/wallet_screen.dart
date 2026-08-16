import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/topup_fee.dart';
import '../../core/widgets/app_logo.dart';
import '../../core/widgets/brief_print_spinner.dart';
import '../../core/widgets/notification_bell.dart';
import '../../features/store/card_receipt_view.dart';
import '../../models/order_model.dart';
import '../../printer/printer_service.dart';
import '../../printer/printer_user_messages.dart';
import '../../providers/auth_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../services/order_service.dart';
import '../../services/wallet_topup_service.dart';
import 'dnz_checkout_screen.dart';
import 'super_key_checkout_screen.dart';
import 'zaincash_checkout_screen.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final _topupService = WalletTopupService();
  final _orderService = OrderService();
  final _printerService = PrinterService();
  bool _reconciling = false;
  bool _creating = false;
  String? _busyOrderId;

  /// نفس رقم الدعم في شاشة الملف الشخصي.
  static const _supportPhoneDisplay = '07878783591';
  static final _whatsappUri = Uri.parse(
    'https://wa.me/9647878783591?text=${Uri.encodeComponent('مرحبا، أحتاج طلب سحب نقدي من تطبيق DNZ card')}',
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reconcilePending());
  }

  Future<void> _reconcilePending() async {
    if (_reconciling) return;
    final user = context.read<AuthProvider>().user;
    if (user == null || !user.isApprovedShop) return;
    setState(() => _reconciling = true);
    try {
      final result = await _topupService.reconcilePending();
      final results = (result['results'] as List?) ?? const [];
      final credited = results.where((e) {
        if (e is Map) return e['credited'] == true;
        return false;
      }).length;
      if (!mounted) return;
      if (credited > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم إضافة $credited عملية شحن معلّقة بنجاح')),
        );
      }
    } catch (_) {
      // لا نقاطع واجهة المحفظة إذا فشل الفحص.
    } finally {
      if (mounted) setState(() => _reconciling = false);
    }
  }

  Future<void> _startTopup() async {
    if (_creating) return;
    final result = await showDialog<(int, _PayMethod)>(
      context: context,
      builder: (context) => const _TopupDialog(),
    );
    if (result == null || !mounted) return;
    final amount = result.$1;
    final method = result.$2;

    setState(() => _creating = true);
    try {
      // سوبر كي تحويل يدوي — لا شحن تلقائي، فقط إرشاد وإرسال الوصل.
      if (method == _PayMethod.superKey) {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => SuperKeyCheckoutScreen(requestedAmount: amount),
          ),
        );
        return;
      }

      final success = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => method == _PayMethod.zainCash
              ? ZainCashCheckoutScreen(requestedAmount: amount)
              : DnzCheckoutScreen(requestedAmount: amount),
        ),
      );
      if (!mounted) return;
      if (success == true) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم تحديث رصيد المحفظة')));
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _openWhatsAppForWithdraw() async {
    try {
      final ok = await launchUrl(
        _whatsappUri,
        mode: LaunchMode.externalApplication,
      );
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر فتح واتساب')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح واتساب')),
      );
    }
  }

  void _contactAdmin() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('طلب سحب نقدي'),
        content: const Text(
          'طلب السحب النقدي يتم عبر الإدارة من لوحة التحكم.\n'
          'أو تواصل معنا عبر واتساب على رقم الدعم.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('حسناً'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _openWhatsAppForWithdraw();
            },
            icon: const Icon(Icons.chat),
            label: const Text('واتساب $_supportPhoneDisplay'),
          ),
        ],
      ),
    );
  }

  Future<void> _showOrderReceipt(OrderModel order) async {
    final shopName = context.read<AuthProvider>().user?.shopName ?? 'DNZ card';
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تفاصيل الكارت'),
        content: SingleChildScrollView(
          child: CardReceiptView(order: order, shopName: shopName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _reprintOrder(order);
            },
            icon: const Icon(Icons.print_outlined, size: 18),
            label: const Text('طباعة'),
          ),
        ],
      ),
    );
  }

  Future<void> _reprintOrder(OrderModel order) async {
    if (_busyOrderId != null) return;
    final user = context.read<AuthProvider>().user;
    if (user == null) return;

    setState(() => _busyOrderId = order.id);
    final dismissSpinner = showBriefPrintSpinner(context);
    try {
      await _printerService.printOrder(
        order,
        shopName: user.shopName,
        context: context,
      );
      await _orderService.markPrinted(order.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تمت إعادة طباعة الكارت')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(PrinterUserMessages.forPrintError(e))),
      );
    } finally {
      dismissSpinner();
      if (mounted) setState(() => _busyOrderId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final wallet = context.watch<WalletProvider>();
    final balance = user?.walletBalance ?? wallet.balance;

    final spendMap = <String, double>{};
    for (final t in wallet.transactions.where((e) => e.type == 'debit')) {
      final key = t.companyName?.isNotEmpty == true ? t.companyName! : t.reason;
      spendMap[key] = (spendMap[key] ?? 0) + t.amount;
    }
    final entries = spendMap.entries.toList();
    final colors = [
      AppColors.primary,
      AppColors.accent,
      Colors.orange,
      Colors.purple,
      Colors.teal,
    ];

    return Scaffold(
      appBar: AppBar(
        title: const AppLogoTitle('المحفظة الرقمية'),
        actions: [
          if (_reconciling)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          const NotificationBell(),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            clipBehavior: Clip.antiAlias,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [AppColors.primary, AppColors.primaryDark],
              ),
              boxShadow: AppColors.cardShadow,
            ),
            child: Column(
              children: [
                Container(
                  height: 4,
                  width: 56,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const Text(
                  'الرصيد الحالي',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 6),
                Text(
                  Formatters.money(balance),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'الآجل المستحق عليك',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 2),
                Text(
                  Formatters.money(wallet.deferredOwed),
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white54),
                        ),
                        onPressed: _contactAdmin,
                        child: const Text('سحب نقدي'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _creating ? null : _startTopup,
                        child: Text(
                          _creating ? 'جاري التجهيز...' : 'إضافة رصيد',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'مشترياتي (الكروت)',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 8),
          if (user == null)
            const Text(
              'سجّل الدخول لعرض المشتريات',
              style: TextStyle(color: AppColors.textSecondary),
            )
          else
            StreamBuilder<List<OrderModel>>(
              stream: _orderService.ordersForShop(user.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final orders = snapshot.data ?? const <OrderModel>[];
                if (orders.isEmpty) {
                  return const Text(
                    'لا توجد كروت مشتراة بعد',
                    style: TextStyle(color: AppColors.textSecondary),
                  );
                }
                return Column(
                  children: [
                    for (final order in orders)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      order.productName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    Formatters.money(order.total),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                Formatters.date(order.createdAt),
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                              if (order.cardItems.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'الرمز: ${order.cardItems.first.code}',
                                  style: const TextStyle(fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _busyOrderId == order.id
                                          ? null
                                          : () => _showOrderReceipt(order),
                                      icon: const Icon(
                                        Icons.visibility_outlined,
                                        size: 18,
                                      ),
                                      label: const Text('إظهار'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: _busyOrderId == order.id
                                          ? null
                                          : () => _reprintOrder(order),
                                      icon: _busyOrderId == order.id
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.print_outlined,
                                              size: 18,
                                            ),
                                      label: const Text('إعادة طباعة'),
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
          const SizedBox(height: 20),
          const Text(
            'تاريخ الأخيرة',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 8),
          ...wallet.transactions.take(8).map((t) {
            final credit = t.isCredit;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: AppColors.chipBg,
                child: Icon(
                  credit ? Icons.add : Icons.remove,
                  color: credit ? AppColors.accent : AppColors.danger,
                ),
              ),
              title: Text(t.reason),
              subtitle: Text(
                [
                  Formatters.date(t.createdAt),
                  if (credit && t.depositMethodLabel != null)
                    t.depositMethodLabel!,
                ].join(' · '),
              ),
              trailing: Text(
                '${credit ? '+' : '-'}${Formatters.money(t.amount)}',
                style: TextStyle(
                  color: credit ? AppColors.accent : AppColors.danger,
                  fontWeight: FontWeight.w800,
                ),
              ),
            );
          }),
          const SizedBox(height: 16),
          const Text(
            'المعاملات الإنفاق',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            const Text('لا توجد بيانات إنفاق بعد')
          else
            SizedBox(
              height: 180,
              child: Row(
                children: [
                  Expanded(
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 36,
                        sections: [
                          for (var i = 0; i < entries.length; i++)
                            PieChartSectionData(
                              value: entries[i].value,
                              color: colors[i % colors.length],
                              title: '',
                              radius: 40,
                            ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < entries.length; i++)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  color: colors[i % colors.length],
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    entries[i].key,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

enum _PayMethod { zainCash, card, superKey }

/// نافذة إضافة رصيد: حقل المبلغ ثم وسائل الدفع أسفله وزر "دفع الآن".
class _TopupDialog extends StatefulWidget {
  const _TopupDialog();

  @override
  State<_TopupDialog> createState() => _TopupDialogState();
}

class _TopupDialogState extends State<_TopupDialog> {
  final _amount = TextEditingController();
  _PayMethod? _method;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  int? get _parsed => int.tryParse(_amount.text.trim().replaceAll(',', ''));

  bool get _amountValid {
    final value = _parsed;
    return value != null && value >= TopupFee.minAmount;
  }

  bool get _superKeyAllowed {
    final value = _parsed;
    return value != null && value >= TopupFee.superKeyMinAmount;
  }

  void _onAmountChanged() {
    setState(() {
      _error = null;
      // إن أصبح المبلغ أقل من حد سوبر كي وكانت مختارة، نلغي الاختيار.
      if (_method == _PayMethod.superKey && !_superKeyAllowed) {
        _method = null;
      }
    });
  }

  void _submit() {
    final value = _parsed;
    if (value == null || value < TopupFee.minAmount) {
      setState(() {
        _error = 'أدخل مبلغاً صحيحاً (${Formatters.money(TopupFee.minAmount)} '
            'فأكثر)';
      });
      return;
    }
    if (_method == null) {
      setState(() => _error = 'اختر وسيلة الدفع');
      return;
    }
    if (_method == _PayMethod.superKey && !_superKeyAllowed) {
      setState(() {
        _error = 'تحويل سوبر كي متاح للمبالغ '
            '${Formatters.money(TopupFee.superKeyMinAmount)} فأكثر';
      });
      return;
    }
    Navigator.pop(context, (value, _method!));
  }

  String _feeSubtitle(double rate) {
    if (!_amountValid) return 'أدخل المبلغ أولاً لعرض العمولة';
    final amount = _parsed!;
    final fee = TopupFee.feeFor(amount, rate: rate);
    final charged = TopupFee.chargedFor(amount, rate: rate);
    final pct = (rate * 100).toStringAsFixed(rate == 0.01 ? 0 : 1);
    return 'عمولة $pct% (${Formatters.money(fee)}) · '
        'تدفع ${Formatters.money(charged)}';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إضافة رصيد'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'أدخل المبلغ الذي تريد إضافته إلى المحفظة بالدينار العراقي.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              autofocus: true,
              onChanged: (_) => _onAmountChanged(),
              decoration: const InputDecoration(
                labelText: 'المبلغ (د.ع)',
                hintText: 'مثال: 15000',
              ),
            ),
            const SizedBox(height: 16),
            const Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                'اختر وسيلة الدفع',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 10),
            _MethodTile(
              title: 'زين كاش',
              subtitle: 'قريباً — غير متاح حالياً',
              icon: Icons.account_balance_wallet_outlined,
              selected: _method == _PayMethod.zainCash,
              enabled: false,
              onTap: () {},
            ),
            const SizedBox(height: 10),
            _MethodTile(
              title: 'ماستركارد / فيزا كارد',
              subtitle: _feeSubtitle(TopupFee.cardRate),
              icon: Icons.credit_card,
              selected: _method == _PayMethod.card,
              onTap: () => setState(() {
                _method = _PayMethod.card;
                _error = null;
              }),
            ),
            const SizedBox(height: 10),
            _MethodTile(
              title: 'تحويل سوبر كي',
              subtitle: _superKeyAllowed
                  ? 'بدون عمولة · تحويل يدوي'
                  : 'متاح للمبالغ ${Formatters.money(TopupFee.superKeyMinAmount)} فأكثر',
              icon: Icons.swap_horiz,
              selected: _method == _PayMethod.superKey,
              enabled: _superKeyAllowed,
              onTap: () => setState(() {
                _method = _PayMethod.superKey;
                _error = null;
              }),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppColors.danger)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: const Text('دفع الآن'),
        ),
      ],
    );
  }
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected ? AppColors.primary : AppColors.border;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: selected
            ? AppColors.primary.withValues(alpha: 0.06)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled ? onTap : null,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: borderColor,
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: AppColors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: selected ? AppColors.primary : AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
