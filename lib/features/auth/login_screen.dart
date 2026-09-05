import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/phone_auth.dart';
import '../../core/widgets/app_logo.dart';
import '../../providers/auth_provider.dart';
import '../../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.isAdminPortal = false});

  final bool isAdminPortal;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submitAdmin() async {
    if (_phone.text.trim().isEmpty || _password.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل رقم الهاتف وكلمة المرور')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<AuthProvider>().loginAdmin(
        _phone.text,
        _password.text,
      );
    } catch (_) {
      if (!mounted) return;
      final err = context.read<AuthProvider>().error;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(err ?? 'تعذر تسجيل الدخول')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitShop() async {
    if (_phone.text.trim().isEmpty || _password.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل رقم الهاتف وكلمة المرور')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final phone = normalizePhone(_phone.text);
      final outcome = await context.read<AuthProvider>().loginShop(
        phone,
        _password.text,
      );
      if (!mounted) return;
      if (outcome == PhoneAuthOutcome.needsProfile ||
          context.read<AuthProvider>().needsProfileCompletion) {
        context.go('/complete-profile');
        return;
      }
      context.go('/store');
    } catch (_) {
      if (!mounted) return;
      final err = context.read<AuthProvider>().error;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(err ?? 'تعذر تسجيل الدخول')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enterAsGuest() async {
    setState(() => _busy = true);
    try {
      await context.read<AuthProvider>().loginAsGuest();
      if (!mounted) return;
      context.go('/store');
    } catch (_) {
      if (!mounted) return;
      final err = context.read<AuthProvider>().error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err ?? 'تعذر الدخول كضيف')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = widget.isAdminPortal;

    return Scaffold(
      backgroundColor: isAdmin ? const Color(0xFFF0F4F5) : AppColors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 32),
                const Center(child: AppLogo(size: 180, borderRadius: 32)),
                const SizedBox(height: 28),
                Text(
                  isAdmin ? 'لوحة تحكم الإدارة' : 'دخول المتجر',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isAdmin
                      ? 'دخول الإدارة فقط — رقم الهاتف وكلمة المرور'
                      : 'أدخل رقم هاتفك وكلمة المرور للدخول.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 28),
                Card(
                  elevation: isAdmin ? 2 : 0,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        TextField(
                          controller: _phone,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'رقم الهاتف',
                            prefixIcon: Icon(Icons.phone_outlined),
                            hintText: '07XXXXXXXXX',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _password,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'كلمة المرور',
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                          onSubmitted: (_) =>
                              _busy ? null : (isAdmin ? _submitAdmin() : _submitShop()),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _busy
                                ? null
                                : (isAdmin ? _submitAdmin : _submitShop),
                            child: _busy
                                ? const SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.primary,
                                    ),
                                  )
                                : const Text('دخول'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!isAdmin) ...[
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => context.push('/forgot-password'),
                    child: const Text('نسيت كلمة المرور؟'),
                  ),
                  TextButton(
                    onPressed: () => context.push('/register'),
                    child: const Text('إنشاء حساب متجر جديد'),
                  ),
                  const SizedBox(height: 4),
                  OutlinedButton(
                    onPressed: _busy ? null : _enterAsGuest,
                    child: const Text('دخول كضيف'),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'تصفّح المتجر بدون حساب — الأسعار مخفية حتى التسجيل',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
