import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/auth_confirm_dialogs.dart';
import '../../providers/auth_provider.dart';

class PendingApprovalScreen extends StatelessWidget {
  const PendingApprovalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final status = user?.status ?? 'pending';

    String title;
    String message;
    IconData icon;
    switch (status) {
      case 'rejected':
        title = 'تم رفض الحساب';
        message = 'تم رفض طلب متجرك. تواصل مع الإدارة لإعادة المراجعة.';
        icon = Icons.block;
        break;
      case 'suspended':
        title = 'الحساب موقوف';
        message = 'تم إيقاف حسابك مؤقتاً. تواصل مع الإدارة.';
        icon = Icons.pause_circle_outline;
        break;
      default:
        title = 'الحساب غير متاح';
        message = 'تعذر فتح الحساب حالياً. تواصل مع الإدارة.';
        icon = Icons.info_outline;
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 72, color: AppColors.primary),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 28),
              OutlinedButton(
                onPressed: () => confirmAndLogout(context),
                child: const Text('تسجيل الخروج'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
