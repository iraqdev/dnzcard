import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/app_user.dart';
import '../../models/wallet_transaction.dart';
import '../../services/admin_service.dart';
import '../../services/wallet_service.dart';

class AdminWalletsPage extends StatefulWidget {
  const AdminWalletsPage({super.key});

  @override
  State<AdminWalletsPage> createState() => _AdminWalletsPageState();
}

class _AdminWalletsPageState extends State<AdminWalletsPage> {
  String? _userId;
  final _shopSearch = TextEditingController();
  final _amount = TextEditingController();
  final _reason = TextEditingController(text: 'شحن رصيد من الإدارة');
  String _type = 'credit';
  WalletDepositMethod _depositMethod = WalletDepositMethod.cash;
  bool _hideDebitFromUser = false;
  bool _busy = false;

  @override
  void dispose() {
    _shopSearch.dispose();
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  String _shopLabel(AppUser user) {
    final shop = user.shopName.trim();
    final name = user.name.trim();
    final title = shop.isNotEmpty ? shop : name;
    return '$title · ${user.phone} · ${Formatters.money(user.walletBalance)}';
  }

  bool _matchesShopQuery(AppUser user, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return user.shopName.toLowerCase().contains(q) ||
        user.name.toLowerCase().contains(q) ||
        user.phone.contains(q);
  }

  void _selectShop(AppUser user) {
    setState(() {
      _userId = user.id;
      _shopSearch.text = _shopLabel(user);
    });
  }

  Future<void> _submit() async {
    if (_userId == null) return;
    final amount = double.tryParse(_amount.text);
    if (amount == null || amount <= 0) return;
    setState(() => _busy = true);
    try {
      await WalletService().adminAdjust(
        userId: _userId!,
        amount: amount,
        type: _type,
        reason: _reason.text.trim(),
        hideFromUser: _type == 'debit' && _hideDebitFromUser,
        depositMethod: _type == 'credit' ? _depositMethod : null,
      );
      _amount.clear();
      if (!mounted) return;
      final methodNote = _type == 'credit'
          ? ' (${_depositMethod.labelAr})'
          : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تمت العملية بنجاح$methodNote')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة المحافظ')),
      body: StreamBuilder(
        stream: AdminService().watchUsers(),
        builder: (context, snapshot) {
          final users = (snapshot.data ?? [])
              .where((u) => u.role == 'shop')
              .toList();
          if (_userId == null && users.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || _userId != null) return;
              _selectShop(users.first);
            });
          }
          final selected = users.where((u) => u.id == _userId).firstOrNull;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Autocomplete<AppUser>(
                displayStringForOption: _shopLabel,
                optionsBuilder: (textEditingValue) {
                  final q = textEditingValue.text.trim();
                  final matches =
                      users.where((u) => _matchesShopQuery(u, q)).toList();
                  if (q.isEmpty) return matches.take(12);
                  return matches.take(20);
                },
                onSelected: _selectShop,
                fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                  if (selected != null &&
                      controller.text.isEmpty &&
                      _shopSearch.text.isNotEmpty) {
                    controller.text = _shopSearch.text;
                  }
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    onChanged: (value) {
                      _shopSearch.text = value;
                      if (selected != null &&
                          value.trim() != _shopLabel(selected)) {
                        setState(() => _userId = null);
                      }
                    },
                    decoration: const InputDecoration(
                      labelText: 'المتجر',
                      hintText: 'ابحث باسم المتجر أو رقم الهاتف',
                      prefixIcon: Icon(Icons.search),
                    ),
                  );
                },
                optionsViewBuilder: (context, onSelected, options) {
                  final opts = options.toList();
                  if (opts.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Align(
                    alignment: Alignment.topRight,
                    child: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(12),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxHeight: 280,
                          maxWidth: 520,
                        ),
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: opts.length,
                          itemBuilder: (context, index) {
                            final user = opts[index];
                            return ListTile(
                              dense: true,
                              title: Text(
                                user.shopName.trim().isNotEmpty
                                    ? user.shopName
                                    : user.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                '${user.phone} · ${Formatters.money(user.walletBalance)}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              onTap: () => onSelected(user),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
              if (selected != null) ...[
                const SizedBox(height: 8),
                Text(
                  'الرصيد الحالي: ${Formatters.money(selected.walletBalance)}',
                ),
              ],
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'credit', label: Text('إضافة')),
                  ButtonSegment(value: 'debit', label: Text('خصم')),
                ],
                selected: {_type},
                onSelectionChanged: (s) => setState(() {
                  _type = s.first;
                  if (_type != 'debit') _hideDebitFromUser = false;
                }),
              ),
              if (_type == 'credit') ...[
                const SizedBox(height: 12),
                const Text(
                  'طريقة الإيداع',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                SegmentedButton<WalletDepositMethod>(
                  segments: [
                    for (final method in WalletDepositMethod.values)
                      ButtonSegment(
                        value: method,
                        label: Text(method.labelAr),
                        icon: Icon(switch (method) {
                          WalletDepositMethod.cash => Icons.payments_outlined,
                          WalletDepositMethod.deferred => Icons.schedule,
                          WalletDepositMethod.online => Icons.language,
                        }),
                      ),
                  ],
                  selected: {_depositMethod},
                  onSelectionChanged: (s) =>
                      setState(() => _depositMethod = s.first),
                ),
                const SizedBox(height: 6),
                Text(
                  switch (_depositMethod) {
                    WalletDepositMethod.cash =>
                      'نقدي: استلام المبلغ نقداً من المتجر.',
                    WalletDepositMethod.deferred =>
                      'آجل: يُضاف الرصيد ديناً على المتجر.',
                    WalletDepositMethod.online =>
                      'أونلاين: دفع عبر بوابة الدفع الإلكترونية.',
                  },
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
              if (_type == 'debit') ...[
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: _hideDebitFromUser,
                  onChanged: (value) =>
                      setState(() => _hideDebitFromUser = value ?? false),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('إخفاء عملية الخصم عن الزبون'),
                  subtitle: const Text(
                    'سيُخصم المبلغ من الرصيد دون ظهوره في سجل محفظة الزبون',
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _amount,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'المبلغ'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _reason,
                decoration: const InputDecoration(labelText: 'السبب'),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _busy ? null : _submit,
                child: Text(_busy ? 'جاري التنفيذ...' : 'تنفيذ'),
              ),
              if (_userId != null) ...[
                const SizedBox(height: 24),
                const Text(
                  'سجل عمليات المحفظة',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 8),
                StreamBuilder<List<WalletTransaction>>(
                  stream:
                      WalletService().watchTransactionsForAdmin(_userId!),
                  builder: (context, txSnap) {
                    final txs = txSnap.data ?? const <WalletTransaction>[];
                    if (txSnap.connectionState == ConnectionState.waiting &&
                        txs.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (txs.isEmpty) {
                      return const Text(
                        'لا توجد عمليات بعد',
                        style: TextStyle(color: AppColors.textSecondary),
                      );
                    }
                    return Column(
                      children: [
                        for (final t in txs)
                          Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: AppColors.chipBg,
                                child: Icon(
                                  t.isCredit
                                      ? Icons.add
                                      : Icons.remove,
                                  color: t.isCredit
                                      ? AppColors.accent
                                      : AppColors.danger,
                                ),
                              ),
                              title: Text(t.reason),
                              subtitle: Text(
                                [
                                  Formatters.date(t.createdAt),
                                  if (t.isCredit &&
                                      t.depositMethodLabel != null)
                                    'طريقة الإيداع: ${t.depositMethodLabel}',
                                  if (!t.visibleToUser) 'مخفي عن الزبون',
                                ].join(' · '),
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${t.isCredit ? '+' : '-'}${Formatters.money(t.amount)}',
                                    style: TextStyle(
                                      color: t.isCredit
                                          ? AppColors.accent
                                          : AppColors.danger,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  if (t.isCredit &&
                                      t.depositMethodLabel != null)
                                    Container(
                                      margin: const EdgeInsets.only(top: 4),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.chipBg,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        t.depositMethodLabel!,
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
