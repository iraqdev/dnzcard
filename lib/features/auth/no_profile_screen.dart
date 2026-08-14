import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/auth_confirm_dialogs.dart';

class NoProfileScreen extends StatelessWidget {
  const NoProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.person_off, size: 64, color: AppColors.danger),
                const SizedBox(height: 16),
                const Text(
                  'الحساب غير مكتمل',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                const Text(
                  'تم تسجيل الدخول لكن لا يوجد ملف مستخدم في النظام.\n'
                  'تأكد من إنشاء مستند في Firestore ضمن users بنفس UID، '
                  'مع role = admin و status = approved.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                OutlinedButton(
                  onPressed: () => confirmAndLogout(context),
                  child: const Text('تسجيل الخروج'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
