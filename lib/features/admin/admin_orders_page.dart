import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/order_model.dart';
import '../../services/functions_service.dart';
import '../../services/notification_service.dart';
import '../../services/order_service.dart';

class AdminOrdersPage extends StatelessWidget {
  const AdminOrdersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الطلبات'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'مبيعات الكروت'),
              Tab(text: 'استعادة كلمة السر'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [_SalesOrdersTab(), _PasswordResetTab()],
        ),
      ),
    );
  }
}

class _SalesOrdersTab extends StatelessWidget {
  const _SalesOrdersTab();

  Stream<Map<String, String>> _shopNames() {
    return FirebaseFirestore.instance.collection('users').snapshots().map((snap) {
      final map = <String, String>{};
      for (final doc in snap.docs) {
        final d = doc.data();
        final shopName = d['shopName']?.toString().trim() ?? '';
        final name = d['name']?.toString().trim() ?? '';
        final phone = d['phone']?.toString().trim() ?? '';
        map[doc.id] = shopName.isNotEmpty
            ? shopName
            : (name.isNotEmpty ? name : (phone.isNotEmpty ? phone : doc.id));
      }
      return map;
    });
  }

  String _buyerLabel(OrderModel order, Map<String, String> shops) {
    final fromMap = shops[order.shopId];
    if (fromMap != null && fromMap.isNotEmpty) return fromMap;
    if (order.shopId.isEmpty) return 'غير معروف';
    return order.shopId;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, String>>(
      stream: _shopNames(),
      builder: (context, shopsSnap) {
        final shops = shopsSnap.data ?? const <String, String>{};
        return StreamBuilder<List<OrderModel>>(
          stream: OrderService().allOrders(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'تعذر تحميل الطلبات:\n${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.danger),
                  ),
                ),
              );
            }
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final orders = snapshot.data ?? [];
            if (orders.isEmpty) {
              return const Center(child: Text('لا توجد طلبات'));
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: orders.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final o = orders[i];
                final buyer = _buyerLabel(o, shops);
                final codes = o.cardItems
                    .map((item) => item.code)
                    .where((c) => c.isNotEmpty)
                    .join(' · ');
                return Material(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: codes.isEmpty
                        ? null
                        : () {
                            showDialog<void>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('تفاصيل البيع'),
                                content: SingleChildScrollView(
                                  child: Text(
                                    'المشتري: $buyer\n'
                                    'الشركة: ${o.companyName}\n'
                                    'المنتج: ${o.productName}\n'
                                    'المبلغ: ${Formatters.money(o.total)}\n'
                                    'التاريخ: ${Formatters.date(o.createdAt)}\n\n'
                                    '${o.cardItems.map((item) => 'رمز: ${item.code} | تسلسل: ${item.serialNumber}').join('\n')}',
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: const Text('إغلاق'),
                                  ),
                                ],
                              ),
                            );
                          },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minWidth: MediaQuery.sizeOf(context).width - 64,
                          ),
                          child: IntrinsicWidth(
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 180,
                                  child: _StripCell(
                                    label: 'المشتري',
                                    value: buyer,
                                    emphasize: true,
                                  ),
                                ),
                                const _StripDivider(),
                                SizedBox(
                                  width: 140,
                                  child: _StripCell(
                                    label: 'الشركة',
                                    value: o.companyName.isEmpty
                                        ? '—'
                                        : o.companyName,
                                  ),
                                ),
                                const _StripDivider(),
                                SizedBox(
                                  width: 200,
                                  child: _StripCell(
                                    label: 'الفئة',
                                    value: o.productName,
                                  ),
                                ),
                                const _StripDivider(),
                                SizedBox(
                                  width: 120,
                                  child: _StripCell(
                                    label: 'المبلغ',
                                    value: Formatters.money(o.total),
                                    emphasize: true,
                                  ),
                                ),
                                const _StripDivider(),
                                SizedBox(
                                  width: 160,
                                  child: _StripCell(
                                    label: 'التاريخ',
                                    value: Formatters.date(o.createdAt),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _StripDivider extends StatelessWidget {
  const _StripDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 36,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: AppColors.border,
    );
  }
}

class _StripCell extends StatelessWidget {
  const _StripCell({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _PasswordResetTab extends StatelessWidget {
  const _PasswordResetTab();

  @override
  Widget build(BuildContext context) {
    final functions = FunctionsService();
    return StreamBuilder(
      stream: NotificationService().watchPasswordResetRequests(),
      builder: (context, snapshot) {
        final items = snapshot.data ?? [];
        if (items.isEmpty) {
          return const Center(child: Text('لا توجد طلبات استعادة'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return Card(
              child: ListTile(
                title: Text(item.shopName.isEmpty ? item.phone : item.shopName),
                subtitle: Text(
                  'الهاتف: ${item.phone}\n'
                  'الجهاز: ${item.deviceName}\n'
                  'الحالة: ${item.status}\n'
                  '${Formatters.date(item.createdAt)}',
                ),
                isThreeLine: true,
                trailing: item.isPending
                    ? Wrap(
                        children: [
                          IconButton(
                            tooltip: 'موافقة',
                            onPressed: () async {
                              await functions.reviewPasswordResetRequest(
                                requestId: item.id,
                                approve: true,
                              );
                            },
                            icon: const Icon(
                              Icons.check_circle,
                              color: AppColors.accent,
                            ),
                          ),
                          IconButton(
                            tooltip: 'رفض',
                            onPressed: () async {
                              await functions.reviewPasswordResetRequest(
                                requestId: item.id,
                                approve: false,
                              );
                            },
                            icon: const Icon(
                              Icons.cancel,
                              color: AppColors.danger,
                            ),
                          ),
                        ],
                      )
                    : Text(item.status),
              ),
            );
          },
        );
      },
    );
  }
}
