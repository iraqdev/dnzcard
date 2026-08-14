import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// مسار قديم — الدخول أصبح برقم الهاتف وكلمة المرور.
class OtpVerifyScreen extends StatelessWidget {
  const OtpVerifyScreen({super.key, required this.phone});

  final String phone;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('التحقق')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'تم إلغاء التحقق عبر رسالة SMS.\nاستخدم رقم الهاتف وكلمة المرور للدخول.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            if (phone.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(phone, textAlign: TextAlign.center),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go('/login'),
              child: const Text('الذهاب لتسجيل الدخول'),
            ),
          ],
        ),
      ),
    );
  }
}
