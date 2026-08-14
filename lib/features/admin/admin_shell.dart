import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_logo.dart';

class AdminShell extends StatelessWidget {
  const AdminShell({super.key, required this.child});
  final Widget child;

  static const _items = [
    ('/admin', 'لوحة التحكم', Icons.dashboard),
    ('/admin/users', 'المستخدمون', Icons.people),
    ('/admin/notifications', 'الإشعارات', Icons.notifications_active),
    ('/admin/companies', 'الشركات', Icons.business),
    ('/admin/products', 'فئات الكروت', Icons.sim_card),
    ('/admin/fazer', 'بطاقات فايزر', Icons.card_giftcard),
    ('/admin/inventory', 'المخزون', Icons.inventory_2),
    ('/admin/inventory-scan', 'قراءة صور الكروت', Icons.document_scanner),
    ('/admin/bot', 'تعبئة المخزون', Icons.inventory_2),
    ('/admin/asia-bot', 'تعبئة آسيا', Icons.sim_card_outlined),
    ('/admin/wallets', 'المحافظ', Icons.account_balance_wallet),
    ('/admin/money', 'إدارة الأموال', Icons.attach_money),
    ('/admin/orders', 'الطلبات', Icons.receipt_long),
    ('/admin/shop-locations', 'مواقع الزبائن', Icons.map_outlined),
    ('/admin/settings', 'الإعدادات', Icons.settings),
  ];

  @override
  Widget build(BuildContext context) {
    final loc = GoRouterState.of(context).matchedLocation;
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final nav = ListView(
      children: [
        DrawerHeader(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [AppColors.primary, AppColors.primaryDark],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppLogo(size: 82, borderRadius: 18),
              const SizedBox(height: 8),
              Container(
                width: 42,
                height: 3,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'DNZ card | لوحة التحكم',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        for (final item in _items)
          ListTile(
            selected: loc == item.$1,
            selectedTileColor: AppColors.chipBg,
            leading: Icon(item.$3),
            title: Text(item.$2),
            onTap: () => context.go(item.$1),
          ),
      ],
    );

    if (!wide) {
      return Scaffold(
        appBar: AppBar(title: const AppLogoTitle('لوحة التحكم')),
        drawer: Drawer(child: nav),
        body: child,
      );
    }

    return Scaffold(
      body: Row(
        children: [
          SizedBox(width: 260, child: Material(elevation: 1, child: nav)),
          Expanded(child: child),
        ],
      ),
    );
  }
}
