import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/utils/app_version.dart';
import '../models/app_settings.dart';

const kDefaultPlayStoreUrl =
    'https://play.google.com/store/apps/details?id=dnz.dnzteam.Kushk';
const kPlayStoreMarketUrl = 'market://details?id=dnz.dnzteam.Kushk';

class AppUpdateService {
  Future<String> currentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version.trim();
  }

  bool shouldForceUpdate(AppSettings settings, String currentVersion) {
    if (kIsWeb || !Platform.isAndroid) return false;
    if (kDebugMode) return false;
    return isAppVersionBelowMinimum(currentVersion, settings.minAndroidVersion);
  }

  Future<void> openPlayStore({String? playStoreUrl}) async {
    final customUrl = playStoreUrl?.trim();
    final urls = [
      if (customUrl != null && customUrl.isNotEmpty) customUrl,
      kPlayStoreMarketUrl,
      kDefaultPlayStoreUrl,
    ];

    for (final url in urls) {
      final uri = Uri.tryParse(url);
      if (uri == null) continue;
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        return;
      }
    }
  }
}
