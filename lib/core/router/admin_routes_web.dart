import 'package:go_router/go_router.dart';

import '../../features/admin/admin_shell.dart';
import '../../features/admin/admin_dashboard.dart';
import '../../features/admin/admin_users_page.dart';
import '../../features/admin/admin_notifications_page.dart';
import '../../features/admin/admin_user_prices_page.dart';
import '../../features/admin/admin_companies_page.dart';
import '../../features/admin/admin_products_page.dart';
import '../../features/admin/admin_fazer_page.dart';
import '../../features/admin/admin_inventory_page.dart';
import '../../features/admin/admin_inventory_scan_page.dart';
import '../../features/admin/admin_wallets_page.dart';
import '../../features/admin/admin_money_page.dart';
import '../../features/admin/admin_orders_page.dart';
import '../../features/admin/admin_settings_page.dart';
import '../../features/admin/admin_shop_locations_page.dart';
import '../../features/admin/admin_bot_page.dart';
import '../../features/admin/admin_asia_bot_page.dart';
import '../../models/app_user.dart';

/// مسارات لوحة الأدمن — ويب فقط.
List<RouteBase> buildAdminRoutes() {
  return [
    ShellRoute(
      builder: (context, state, child) => AdminShell(child: child),
      routes: [
        GoRoute(path: '/admin', builder: (_, _) => const AdminDashboard()),
        GoRoute(
          path: '/admin/users',
          builder: (_, _) => const AdminUsersPage(),
        ),
        GoRoute(
          path: '/admin/notifications',
          builder: (_, _) => const AdminNotificationsPage(),
        ),
        GoRoute(
          path: '/admin/users/:userId/prices',
          builder: (_, state) {
            final userId = state.pathParameters['userId'] ?? '';
            final user = state.extra is AppUser ? state.extra as AppUser : null;
            return AdminUserPricesPage(userId: userId, user: user);
          },
        ),
        GoRoute(
          path: '/admin/companies',
          builder: (_, _) => const AdminCompaniesPage(),
        ),
        GoRoute(
          path: '/admin/products',
          builder: (_, _) => const AdminProductsPage(),
        ),
        GoRoute(
          path: '/admin/fazer',
          builder: (_, _) => const AdminFazerPage(),
        ),
        GoRoute(
          path: '/admin/inventory',
          builder: (_, _) => const AdminInventoryPage(),
        ),
        GoRoute(
          path: '/admin/inventory-scan',
          builder: (_, _) => const AdminInventoryScanPage(),
        ),
        GoRoute(
          path: '/admin/bot',
          builder: (_, _) => const AdminBotPage(),
        ),
        GoRoute(
          path: '/admin/asia-bot',
          builder: (_, _) => const AdminAsiaBotPage(),
        ),
        GoRoute(
          path: '/admin/wallets',
          builder: (_, _) => const AdminWalletsPage(),
        ),
        GoRoute(
          path: '/admin/money',
          builder: (_, _) => const AdminMoneyPage(),
        ),
        GoRoute(
          path: '/admin/orders',
          builder: (_, _) => const AdminOrdersPage(),
        ),
        GoRoute(
          path: '/admin/shop-locations',
          builder: (_, _) => const AdminShopLocationsPage(),
        ),
        GoRoute(
          path: '/admin/settings',
          builder: (_, _) => const AdminSettingsPage(),
        ),
      ],
    ),
  ];
}
