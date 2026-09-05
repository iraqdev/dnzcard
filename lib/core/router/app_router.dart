import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/login_screen.dart';
import '../../features/auth/register_screen.dart';
import '../../features/auth/pending_approval_screen.dart';
import '../../features/auth/no_profile_screen.dart';
import '../../features/auth/forgot_password_screen.dart';
import '../../features/auth/otp_verify_screen.dart';
import '../../features/auth/complete_profile_screen.dart';
import '../../features/shell/main_shell.dart';
import '../../features/home/home_screen.dart';
import '../../features/store/store_screen.dart';
import '../../features/wallet/wallet_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/profile/printer_settings_screen.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../providers/auth_provider.dart';
import '../../core/widgets/shell_tab_gate.dart';
import 'admin_routes_stub.dart'
    if (dart.library.html) 'admin_routes_web.dart';

GoRouter createAppRouter(AuthProvider auth) {
  return GoRouter(
    initialLocation: kIsWeb ? '/login' : '/store',
    refreshListenable: auth,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final loggingIn = loc == '/login';
      final forgot = loc == '/forgot-password';
      final otp = loc == '/otp';
      final completeProfile = loc == '/complete-profile';
      final user = auth.user;
      final loading = auth.loading;

      // لوحة الأدمن ويب فقط — تُحظر بالكامل على الموبايل.
      if (!kIsWeb && loc.startsWith('/admin')) {
        return auth.isLoggedIn ? '/store' : '/login';
      }

      if (kIsWeb && loc == '/register') return '/login';
      if (kIsWeb && (forgot || otp || completeProfile)) {
        return '/login';
      }

      if (loading) return null;

      if (auth.isGuest) {
        if (kIsWeb) return '/login';
        if (loggingIn) return '/store';
        if (loc == '/wallet' ||
            loc == '/profile' ||
            loc == '/notifications' ||
            loc == '/printer-settings' ||
            loc == '/complete-profile' ||
            loc == '/forgot-password' ||
            loc == '/otp' ||
            loc == '/pending') {
          return '/register';
        }
        if (loc.startsWith('/admin')) return '/store';
        return null;
      }

      if (!auth.isLoggedIn) {
        if (forgot || loggingIn || otp) return null;
        if (loc == '/register' && !kIsWeb) return null;
        return '/login';
      }

      if (user == null) {
        if (kIsWeb) {
          return loc == '/no-profile' ? null : '/no-profile';
        }
        return completeProfile ? null : '/complete-profile';
      }

      if (user.isAdmin) {
        if (kIsWeb) {
          if (loggingIn || loc == '/no-profile' || forgot) return '/admin';
          if (!loc.startsWith('/admin')) return '/admin';
          return null;
        }
        // حساب أدمن على الموبايل: بدون لوحة تحكم.
        return null;
      }

      if (kIsWeb && !loggingIn) {
        return '/login';
      }

      final blocked = user.status == 'rejected' || user.status == 'suspended';

      if (blocked && loc != '/pending') return '/pending';
      if (!blocked && loc == '/pending') return '/store';

      if (loc.startsWith('/admin')) return '/store';
      if (loggingIn || forgot || otp || completeProfile) return '/store';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (_, _) => LoginScreen(isAdminPortal: kIsWeb),
      ),
      GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
      GoRoute(
        path: '/otp',
        builder: (_, state) {
          final phone = state.extra is String
              ? state.extra as String
              : (auth.pendingPhone ?? '');
          return OtpVerifyScreen(phone: phone);
        },
      ),
      GoRoute(
        path: '/complete-profile',
        builder: (_, _) => const CompleteProfileScreen(),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (_, _) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/pending',
        builder: (_, _) => const PendingApprovalScreen(),
      ),
      GoRoute(path: '/no-profile', builder: (_, _) => const NoProfileScreen()),
      GoRoute(
        path: '/printer-settings',
        builder: (_, _) => const PrinterSettingsScreen(),
      ),
      GoRoute(
        path: '/notifications',
        builder: (_, _) => const NotificationsScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return MainShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (_, _) => const ShellTabGate(
                  tabIndex: 0,
                  child: HomeScreen(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/store', builder: (_, _) => const StoreScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/wallet',
                builder: (_, _) => const ShellTabGate(
                  tabIndex: 2,
                  child: WalletScreen(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (_, _) => const ShellTabGate(
                  tabIndex: 3,
                  child: ProfileScreen(),
                ),
              ),
            ],
          ),
        ],
      ),
      ...buildAdminRoutes(),
    ],
  );
}
