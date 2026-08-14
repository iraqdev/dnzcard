import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../services/wallet_topup_service.dart';

/// شاشة الدفع عبر زين كاش — التوقيع وإنشاء المعاملة يتمّان على الخادم بالكامل.
class ZainCashCheckoutScreen extends StatefulWidget {
  const ZainCashCheckoutScreen({super.key, required this.requestedAmount});

  final int requestedAmount;

  @override
  State<ZainCashCheckoutScreen> createState() => _ZainCashCheckoutScreenState();
}

class _ZainCashCheckoutScreenState extends State<ZainCashCheckoutScreen> {
  final _topups = WalletTopupService();
  late final WebViewController _web;

  bool _starting = true;
  bool _processing = false;
  bool _finished = false;
  String? _error;
  String? _paymentUrl;
  String? _topupId;
  int _requestedAmount = 0;
  int _feeAmount = 0;
  int _chargedAmount = 0;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: _handleUrl,
          onPageFinished: _handleUrl,
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri != null && uri.queryParameters.containsKey('token')) {
              _complete();
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onWebResourceError: (error) {
            if (kDebugMode) {
              debugPrint('[ZainCash] web error: ${error.description}');
            }
          },
        ),
      );
    _start();
  }

  void _handleUrl(String url) {
    final uri = Uri.tryParse(url);
    final token = uri?.queryParameters['token'];
    if (token != null && token.isNotEmpty) {
      _complete();
    }
  }

  Future<void> _start() async {
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      final created = await _topups.createZainCashTopup(widget.requestedAmount);
      final topupId = created.id;
      if (topupId.isEmpty) {
        throw StateError('تعذر إنشاء عملية الشحن');
      }
      _topupId = topupId;
      _requestedAmount = created.requestedAmount.round();
      _feeAmount = created.feeAmount.round();
      _chargedAmount = created.chargedAmount.round();

      final payment = await _topups.startZainCashPayment(topupId: topupId);
      final checkoutUrl = payment['checkoutUrl']?.toString() ?? '';
      if (checkoutUrl.isEmpty) {
        throw StateError('تعذر إنشاء رابط الدفع');
      }

      if (!mounted) return;
      setState(() {
        _paymentUrl = checkoutUrl;
        _starting = false;
      });
      await _web.loadRequest(Uri.parse(checkoutUrl));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  /// تأكيد الدفع عبر الخادم — يتحقق الخادم من الحالة ويضيف الرصيد مرة واحدة.
  Future<void> _complete() async {
    final topupId = _topupId;
    if (topupId == null || _processing || _finished) return;
    _processing = true;
    if (mounted) setState(() {});
    try {
      final result = await _topups.completeZainCashTopup(topupId: topupId);
      final status = result['status']?.toString();
      if (!mounted) return;
      if (status == 'success') {
        _finished = true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم شحن ${Formatters.money(_requestedAmount)} إلى محفظتك',
            ),
          ),
        );
        Navigator.pop(context, true);
        return;
      }
      if (status == 'failed') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فشل الدفع أو تم رفض العملية')),
        );
        Navigator.pop(context, false);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الدفع ما زال معلقاً أو لم يكتمل')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في معالجة الدفع: $e')),
        );
      }
    } finally {
      _processing = false;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الدفع عبر زين كاش'),
        actions: [
          if (_paymentUrl != null)
            TextButton(
              onPressed: _processing ? null : _complete,
              child: const Text('تحقق'),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_starting) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('جاري تجهيز دفع زين كاش...'),
          ],
        ),
      );
    }

    if (_error != null && _paymentUrl == null) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.danger),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _start,
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        if (_chargedAmount > 0)
          Material(
            color: AppColors.chipBg,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'للمحفظة ${Formatters.money(_requestedAmount)} · '
                      'رسم 0.7% ${Formatters.money(_feeAmount)} · '
                      'تدفع ${Formatters.money(_chargedAmount)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: Stack(
            children: [
              WebViewWidget(controller: _web),
              if (_processing)
                const ColoredBox(
                  color: Color(0x66FFFFFF),
                  child: Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
