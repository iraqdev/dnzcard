import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../models/app_settings.dart';
import '../../services/app_update_service.dart';
import '../../services/settings_service.dart';
import 'app_logo.dart';

class ForceUpdateGate extends StatefulWidget {
  const ForceUpdateGate({super.key, required this.child});

  final Widget child;

  @override
  State<ForceUpdateGate> createState() => _ForceUpdateGateState();
}

class _ForceUpdateGateState extends State<ForceUpdateGate> {
  final _settingsService = SettingsService();
  final _updateService = AppUpdateService();

  AppSettings _settings = AppSettings.defaults();
  String? _currentVersion;
  var _checking = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final version = await _updateService.currentVersion();
      if (!mounted) return;
      setState(() {
        _currentVersion = version;
        _checking = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _checking = false);
    }
  }

  Future<void> _openStore() {
    return _updateService.openPlayStore(playStoreUrl: _settings.playStoreUrl);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppSettings>(
      stream: _settingsService.watch(),
      builder: (context, snapshot) {
        _settings = snapshot.data ?? AppSettings.defaults();
        final needsUpdate = !_checking &&
            _currentVersion != null &&
            _updateService.shouldForceUpdate(_settings, _currentVersion!);

        if (!needsUpdate) return widget.child;

        return PopScope(
          canPop: false,
          child: Material(
            color: AppColors.background,
            child: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const AppLogo(size: 88, borderRadius: 18),
                        const SizedBox(height: 24),
                        const Text(
                          'يرجى التحديث',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'يوجد إصدار جديد من التطبيق. يرجى التحديث من Google Play للمتابعة.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 28),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _openStore,
                            child: const Text('تحديث الآن'),
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
  }
}
