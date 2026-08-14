import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_logo.dart';
import '../../core/widgets/notification_bell.dart';
import '../../models/order_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../services/order_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _orderService = OrderService();
  Stream<List<OrderModel>>? _ordersStream;
  String? _ordersUserId;

  Stream<List<OrderModel>>? _ordersFor(String userId) {
    if (_ordersUserId == userId && _ordersStream != null) {
      return _ordersStream;
    }
    _ordersUserId = userId;
    _ordersStream = _orderService.ordersForShop(userId);
    return _ordersStream;
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final wallet = context.watch<WalletProvider>();
    final shopName =
        user?.shopName.isNotEmpty == true ? user!.shopName : 'كشk';

    return Scaffold(
      appBar: AppBar(
        title: AppLogoTitle(shopName),
        actions: const [NotificationBell()],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _KushkBalanceCard(
            name: user?.name ?? '',
            shopName: shopName,
            balance: user?.walletBalance ?? wallet.balance,
            deferredOwed: wallet.deferredOwed,
          ),
          const SizedBox(height: 16),
          if (user != null)
            StreamBuilder<List<OrderModel>>(
              stream: _ordersFor(user.id),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Text(
                    'تعذر تحميل المبيعات',
                    style: TextStyle(color: AppColors.danger),
                  );
                }
                final orders = snapshot.data ?? [];
                final today = DateTime.now();
                final todayCount = orders.where((o) {
                  return o.createdAt.year == today.year &&
                      o.createdAt.month == today.month &&
                      o.createdAt.day == today.day;
                }).length;
                return Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        title: 'مبيعات اليوم',
                        value: '$todayCount',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatCard(
                        title: 'إجمالي الطلبات',
                        value: '${orders.length}',
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _KushkBalanceCard extends StatelessWidget {
  const _KushkBalanceCard({
    required this.name,
    required this.shopName,
    required this.balance,
    required this.deferredOwed,
  });

  final String name;
  final String shopName;
  final double balance;
  final double deferredOwed;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [AppColors.primary, AppColors.primaryDark],
        ),
        boxShadow: AppColors.cardShadow,
      ),
      child: Stack(
        children: [
          Positioned(
            left: -18,
            top: -18,
            child: Opacity(
              opacity: 0.14,
              child: const AppLogo(size: 128, borderRadius: 28),
            ),
          ),
          Positioned(
            right: 0,
            left: 0,
            top: 0,
            child: Container(height: 4, color: AppColors.accent),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? 'مرحباً' : 'مرحباً $name',
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 2),
                Text(
                  shopName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'رصيد المحفظة',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  Formatters.money(balance),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.accent.withValues(alpha: 0.55),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.schedule,
                        color: AppColors.accent,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'الآجل المستحق عليك',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      const Spacer(),
                      Text(
                        Formatters.money(deferredOwed),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
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

class _StatCard extends StatelessWidget {
  const _StatCard({required this.title, required this.value});
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}
