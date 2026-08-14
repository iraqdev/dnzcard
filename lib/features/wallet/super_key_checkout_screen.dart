import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';

/// شاشة الدفع عبر تحويل سوبر كي (تحويل يدوي — الإيداع من الإدارة بعد استلام الوصل).
class SuperKeyCheckoutScreen extends StatefulWidget {
  const SuperKeyCheckoutScreen({super.key, required this.requestedAmount});

  final int requestedAmount;

  @override
  State<SuperKeyCheckoutScreen> createState() => _SuperKeyCheckoutScreenState();
}

class _SuperKeyCheckoutScreenState extends State<SuperKeyCheckoutScreen> {
  /// حساب سوبر كي المستلم.
  static const _superKeyAccount = '6638735685';

  /// نفس رقم الدعم المستخدم في عملية السحب.
  static const _supportPhoneDisplay = '07878783591';
  static const _supportPhoneWa = '9647878783591';

  bool _receiptSent = false;

  Future<void> _copyAccount() async {
    await Clipboard.setData(const ClipboardData(text: _superKeyAccount));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم نسخ رقم الحساب')),
    );
  }

  Future<void> _sendReceiptOnWhatsApp() async {
    final now = DateTime.now();
    final message =
        'مرحبا، قمت بالدفع وهذا وصل التحويل.\n'
        'المبلغ: ${Formatters.money(widget.requestedAmount)}\n'
        'إلى حساب سوبر كي: $_superKeyAccount\n'
        'وقت التحويل: ${Formatters.date(now)}';
    final uri = Uri.parse(
      'https://wa.me/$_supportPhoneWa?text=${Uri.encodeComponent(message)}',
    );
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!mounted) return;
      if (ok) {
        setState(() => _receiptSent = true);
      } else {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(title: const Text('تحويل سوبر كي')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [AppColors.primary, AppColors.primaryDark],
              ),
            ),
            child: Column(
              children: [
                const Text(
                  'المبلغ المطلوب إضافته',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 6),
                Text(
                  Formatters.money(widget.requestedAmount),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'بدون عمولة',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _StepCard(
            step: '1',
            title: 'حوّل المبلغ إلى حساب سوبر كي',
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
              decoration: BoxDecoration(
                color: AppColors.chipBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _superKeyAccount,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _copyAccount,
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('نسخ'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _StepCard(
            step: '2',
            title: 'بعد إتمام التحويل، أرسل صورة وصل التحويل عبر واتساب',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'سيتم فتح محادثة واتساب مع الدعم ($_supportPhoneDisplay) '
                  'برسالة جاهزة، أرفق صورة وصل التحويل ثم أرسلها.',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _sendReceiptOnWhatsApp,
                  icon: const Icon(Icons.chat),
                  label: const Text('إرسال وصل التحويل عبر واتساب'),
                ),
              ],
            ),
          ),
          if (_receiptSent) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.4),
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.hourglass_bottom, color: AppColors.accent),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'بانتظار الإيداع — سيتم إيداع المبلغ خلال مدة تتراوح '
                      'بين ربع ساعة إلى ساعتين بعد التحقق من الوصل.',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('تم'),
            ),
          ],
        ],
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.step,
    required this.title,
    required this.child,
  });

  final String step;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: AppColors.primary,
                child: Text(
                  step,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
