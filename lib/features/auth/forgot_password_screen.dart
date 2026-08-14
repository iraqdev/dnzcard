import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _requestId;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_phone.text.trim().isEmpty) {
      _toast('أدخل رقم الهاتف');
      return;
    }
    if (_password.text.length < 6) {
      _toast('كلمة المرور يجب أن تكون 6 أحرف على الأقل');
      return;
    }
    if (_password.text != _confirm.text) {
      _toast('تأكيد كلمة المرور غير متطابق');
      return;
    }

    setState(() => _busy = true);
    try {
      final id = await context.read<AuthProvider>().requestPasswordReset(
        phone: _phone.text,
        newPassword: _password.text,
      );
      if (!mounted) return;
      setState(() => _requestId = id);
      _toast('تم إرسال الطلب للإدارة');
    } catch (e) {
      if (!mounted) return;
      _toast(
        e
            .toString()
            .replaceAll('Exception: ', '')
            .replaceAll('Bad state: ', '')
            .replaceAll('[firebase_functions/', '')
            .split(']')
            .last
            .trim(),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final waiting = _requestId != null;
    if (waiting && auth.isLoggedIn && auth.user != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.go('/store');
      });
    }
    final resetError = waiting ? auth.error : null;

    return Scaffold(
      appBar: AppBar(title: const Text('نسيت كلمة السر')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'أدخل رقم هاتفك وكلمة المرور الجديدة. '
            'سيظهر الطلب لدى الإدارة، وبعد الموافقة يفتح التطبيق تلقائياً على هذا الجهاز.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          if (!waiting) ...[
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'رقم الهاتف',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'كلمة المرور الجديدة',
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
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _busy ? null : _submit,
              child: Text(_busy ? 'جاري الإرسال...' : 'إرسال الطلب'),
            ),
          ] else ...[
            const Icon(Icons.hourglass_top, size: 48, color: AppColors.primary),
            const SizedBox(height: 12),
            const Text(
              'بانتظار موافقة الإدارة...\nسيفتح التطبيق تلقائياً بعد الموافقة.',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            if (resetError != null && resetError.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                resetError,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.danger),
              ),
            ],
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: () => context.go('/login'),
              child: const Text('العودة لتسجيل الدخول'),
            ),
          ],
        ],
      ),
    );
  }
}
