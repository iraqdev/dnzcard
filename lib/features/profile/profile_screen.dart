import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_logo.dart';
import '../../core/widgets/auth_confirm_dialogs.dart';
import '../../core/widgets/notification_bell.dart';
import '../../providers/auth_provider.dart';
import '../../services/purchase_pin_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _deleting = false;
  bool _pinBusy = false;

  static const _supportPhoneDisplay = '07878783591';
  static final _whatsappUri = Uri.parse(
    'https://wa.me/9647878783591?text=${Uri.encodeComponent('مرحبا، أحتاج دعم تطبيق DNZ card بخصوص الطابعة')}',
  );

  Future<void> _onPurchasePinSwitch(bool enable) async {
    final user = context.read<AuthProvider>().user;
    if (user == null || _pinBusy) return;

    final service = PurchasePinService();
    setState(() => _pinBusy = true);
    try {
      if (enable) {
        final isFirstSetup = !user.hasPurchasePin;
        final pin = await promptPurchasePin(
          context,
          title: isFirstSetup ? 'تعيين رمز الشراء' : 'تفعيل رمز الشراء',
          subtitle: isFirstSetup
              ? 'أدخل رمزاً من 4 أرقام فقط (أرقام فقط).'
              : 'أدخل الرمز الحالي لتفعيل الحماية.',
          requireConfirm: isFirstSetup,
        );
        if (pin == null || !mounted) return;

        if (isFirstSetup) {
          await service.enableWithPin(userId: user.id, pin: pin);
        } else {
          if (!service.verifyPin(
            pin: pin,
            currentHash: user.purchasePinHash!,
          )) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('الرمز غير صحيح')),
            );
            return;
          }
          await service.enableWithPin(userId: user.id, pin: pin);
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تفعيل رمز شراء الكروت')),
        );
      } else {
        if (!user.hasPurchasePin) {
          await service.adminReset(user.id);
          return;
        }
        final pin = await promptPurchasePin(
          context,
          title: 'إطفاء رمز الشراء',
          subtitle: 'أدخل الرمز الحالي لإيقاف الحماية.',
        );
        if (pin == null || !mounted) return;
        await service.disableWithPin(
          userId: user.id,
          pin: pin,
          currentHash: user.purchasePinHash!,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إيقاف رمز شراء الكروت')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e
                .toString()
                .replaceAll('Exception: ', '')
                .replaceAll('Bad state: ', '')
                .replaceAll('Invalid argument(s): ', ''),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _pinBusy = false);
    }
  }

  Future<void> _openWhatsApp() async {
    try {
      final ok = await launchUrl(
        _whatsappUri,
        mode: LaunchMode.externalApplication,
      );
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر فتح واتساب')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح واتساب')),
      );
    }
  }

  Future<void> _startDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف الحساب'),
        content: const Text(
          'سيتم حذف حسابك نهائياً ولا يمكن استرجاعه.\n'
          'لتأكيد الحذف أدخل كلمة المرور.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('متابعة الحذف'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await _promptDeletePassword();
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _promptDeletePassword() async {
    final passwordController = TextEditingController();
    var busy = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
              if (passwordController.text.length < 6) {
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(content: Text('أدخل كلمة المرور')),
                );
                return;
              }
              final auth = this.context.read<AuthProvider>();
              final messenger = ScaffoldMessenger.of(this.context);
              setDialogState(() => busy = true);
              try {
                await auth.deleteAccountWithPassword(passwordController.text);
                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                messenger.showSnackBar(
                  const SnackBar(content: Text('تم حذف الحساب بنجاح')),
                );
              } catch (_) {
                setDialogState(() => busy = false);
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('تعذر حذف الحساب. تحقق من كلمة المرور'),
                  ),
                );
              }
            }

            return AlertDialog(
              title: const Text('تأكيد الحذف'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('أدخل كلمة المرور لتأكيد حذف الحساب.'),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    enabled: !busy,
                    decoration: const InputDecoration(
                      labelText: 'كلمة المرور',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                    onSubmitted: (_) => busy ? null : submit(),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: busy
                      ? null
                      : () {
                          this.context.read<AuthProvider>().clearOtpFlow();
                          Navigator.pop(dialogContext);
                        },
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: busy ? null : submit,
                  child: busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('حذف نهائي'),
                ),
              ],
            );
          },
        );
      },
    );

    passwordController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;

    return Scaffold(
      appBar: AppBar(
        title: const AppLogoTitle('الملف الشخصي'),
        actions: const [NotificationBell()],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (user?.shopName.isNotEmpty == true)
                      ? user!.shopName
                      : 'بدون اسم محل',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  (user?.name.isNotEmpty == true)
                      ? user!.name
                      : 'بدون اسم المسؤول',
                ),
                Text(user?.phone ?? ''),
                const SizedBox(height: 8),
                Text(
                  'الرصيد: ${Formatters.money(user?.walletBalance ?? 0)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: AppColors.border),
            ),
            secondary: const Icon(Icons.pin_outlined),
            title: const Text('رمز شراء الكروت'),
            subtitle: Text(
              user?.purchasePinEnabled == true
                  ? 'مفعّل — سيُطلب الرمز عند كل شراء'
                  : 'عند التفعيل يُطلب رمز من 4 أرقام قبل الشراء',
            ),
            value: user?.purchasePinEnabled == true,
            onChanged: user == null || _pinBusy
                ? null
                : (value) => _onPurchasePinSwitch(value),
          ),
          const SizedBox(height: 12),
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: AppColors.border),
            ),
            leading: const Icon(Icons.print),
            title: const Text('إعدادات الطابعة'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => context.push('/printer-settings'),
          ),
          const SizedBox(height: 12),
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: AppColors.border),
            ),
            leading: const Icon(Icons.chat, color: Color(0xFF25D366)),
            title: const Text('تواصل عبر واتساب'),
            subtitle: const Text('دعم الشركة · $_supportPhoneDisplay'),
            trailing: const Icon(Icons.open_in_new),
            onTap: _openWhatsApp,
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'في حال كنت تاجر وكيل ولديك مبيعات اكثر من 5 مليون دينار او مايعادل 3000\$ يمكنك التواصل مع الدعم للحصول على اسعار مميزة',
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: _deleting ? null : () => confirmAndLogout(context),
            child: const Text('تسجيل الخروج'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _deleting ? null : _startDeleteAccount,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
            ),
            child: _deleting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('حذف الحساب'),
          ),
        ],
      ),
    );
  }
}
