import 'dart:async';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/router/app_router.dart';
import 'firebase_options.dart';
import 'providers/auth_provider.dart';
import 'providers/catalog_provider.dart';
import 'providers/notification_provider.dart';
import 'providers/wallet_provider.dart';
import 'services/auth_service.dart';
import 'services/catalog_service.dart';
import 'services/fcm_service.dart';
import 'services/notification_service.dart';
import 'services/wallet_service.dart';

late final GoRouter kushkRouter;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  // App Check قبل أي اتصال Firebase — مطلوب عند enforceAppCheck على السيرفر.
  await _activateAppCheck();

  final authService = AuthService();
  final notificationService = NotificationService();
  final authProvider = AuthProvider(
    authService,
    notifications: notificationService,
  );
  kushkRouter = createAppRouter(authProvider);
  unawaited(FcmService.instance.initialize(router: kushkRouter));

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider(create: (_) => CatalogProvider(CatalogService())),
        ChangeNotifierProvider(
          create: (_) => WalletProvider(authService, WalletService()),
        ),
        ChangeNotifierProvider(
          create: (_) => NotificationProvider(authService, notificationService),
        ),
      ],
      child: const KushkApp(),
    ),
  );
}

Future<void> _activateAppCheck() async {
  // الويب (الداش) بدون App Check — التوكن التجريبي كان يسبب 403 وحلقة تحميل في كروم.
  if (kIsWeb) return;

  try {
    await FirebaseAppCheck.instance.activate(
      providerAndroid: kReleaseMode
          ? const AndroidPlayIntegrityProvider()
          : const AndroidDebugProvider(),
      providerApple: kReleaseMode
          ? const AppleDeviceCheckProvider()
          : const AppleDebugProvider(),
    );
    await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);
  } catch (_) {
    // لا نوقف الإقلاع إذا فشل App Check.
  }
}
