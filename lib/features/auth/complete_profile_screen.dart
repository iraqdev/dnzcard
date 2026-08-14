import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_logo.dart';
import '../../core/widgets/auth_confirm_dialogs.dart';
import '../../providers/auth_provider.dart';

class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _shop = TextEditingController();
  final _name = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _shop.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_shop.text.trim().isEmpty || _name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل اسم المتجر واسم المسؤول')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<AuthProvider>().completeShopProfile(
        name: _name.text,
        shopName: _shop.text,
      );
      if (!mounted) return;
      context.go('/store');
    } catch (_) {
      if (!mounted) return;
      final err = context.read<AuthProvider>().error;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(err ?? 'تعذر حفظ البيانات')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone =
        context.watch<AuthProvider>().pendingPhone ??
        context.watch<AuthProvider>().user?.phone ??
        '';

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 24),
            const Center(child: AppLogo(size: 120, borderRadius: 24)),
            const SizedBox(height: 24),
            const Text(
              'إكمال بيانات المتجر',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              phone.isEmpty
                  ? 'أكمل بيانات متجرك للمتابعة.'
                  : 'الرقم: $phone\nأكمل بيانات متجرك للمتابعة.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 28),
            TextField(
              controller: _shop,
              decoration: const InputDecoration(labelText: 'اسم المتجر'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'اسم المسؤول'),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary,
                        ),
                      )
                    : const Text('حفظ ودخول المتجر'),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy ? null : () => confirmAndLogout(context),
              child: const Text('تسجيل الخروج'),
            ),
          ],
        ),
      ),
    );
  }
}
