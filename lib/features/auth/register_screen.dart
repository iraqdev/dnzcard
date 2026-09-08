import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/phone_auth.dart';
import '../../core/widgets/app_logo.dart';
import '../../providers/auth_provider.dart';
import '../../services/auth_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_phone.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('أدخل رقم الهاتف')));
      return;
    }
    if (_password.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('كلمة المرور يجب أن تكون 6 أحرف على الأقل')),
      );
      return;
    }
    if (_password.text != _confirm.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تأكيد كلمة المرور غير متطابق')),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final phone = normalizePhone(_phone.text);
      final outcome = await context.read<AuthProvider>().registerShop(
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
      ).showSnackBar(SnackBar(content: Text(err ?? 'تعذر إنشاء الحساب')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إنشاء حساب متجر')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Center(child: AppLogo(size: 120, borderRadius: 24)),
          const SizedBox(height: 20),
          const Text(
            'أدخل رقم هاتفك وكلمة مرور.\n'
            'بعد التسجيل ستكمل بيانات المتجر.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'رقم الهاتف',
              hintText: '07XXXXXXXXX',
              prefixIcon: Icon(Icons.phone_outlined),
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
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirm,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'تأكيد كلمة المرور',
              prefixIcon: Icon(Icons.lock_outline),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _busy ? null : _submit,
            child: Text(_busy ? 'جاري الإنشاء...' : 'إنشاء الحساب'),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () async {
                    await context.read<AuthProvider>().exitGuestMode();
                    if (!context.mounted) return;
                    context.go('/login');
                  },
            child: const Text('لديك حساب؟ ادخل من هنا'),
          ),
        ],
      ),
    );
  }
}
