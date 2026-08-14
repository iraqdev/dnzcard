import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/wallet_topup.dart';
import '../../services/wallet_topup_service.dart';

/// الحد الأدنى لإصدار Chrome/WebView لصفحة دفع Qi الحديثة.
const _kMinChromeMajor = 90;

/// شاشة دفع داخل التطبيق مع كشف WebView القديم.
class DnzCheckoutScreen extends StatefulWidget {
  const DnzCheckoutScreen({super.key, required this.requestedAmount});

  final int requestedAmount;

  @override
  State<DnzCheckoutScreen> createState() => _DnzCheckoutScreenState();
}

class _DnzCheckoutScreenState extends State<DnzCheckoutScreen>
    with WidgetsBindingObserver {
  final _service = WalletTopupService();
  InAppWebViewController? _web;
  Timer? _poll;

  WalletTopup? _topup;
  String? _error;
  bool _creating = true;
  bool _checking = false;
  bool _manualRefresh = false;
  bool _finished = false;
  bool _pollStarted = false;
  bool _checkingWebView = true;
  bool _webViewTooOld = false;
  int? _chromeMajor;
  int _progress = 0;
  String _statusText = 'جاري فحص جاهزية الدفع...';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_finished) {
      if (_webViewTooOld) {
        unawaited(_recheckWebViewAfterUpdate());
      } else if (_topup != null) {
        unawaited(_checkStatus(silent: true));
      }
    }
  }

  Future<void> _bootstrap() async {
    await _detectWebView();
    if (!mounted) return;
    if (_webViewTooOld) {
      setState(() {
        _checkingWebView = false;
        _creating = false;
        _statusText = 'متصفح الجهاز قديم ولا يعرض صفحة الدفع';
      });
      // ننشئ الرابط مسبقاً حتى يبقى جاهزاً بعد تحديث المتصفح.
      unawaited(_createTopup(keepLoadingUi: false));
      return;
    }
    setState(() {
      _checkingWebView = false;
      _statusText = 'جاري تجهيز رابط الدفع...';
    });
    await _createTopup();
  }

  Future<void> _detectWebView() async {
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        final ua = await InAppWebViewController.getDefaultUserAgent();
        _chromeMajor = _parseChromeMajor(ua);
        _webViewTooOld =
            _chromeMajor == null || _chromeMajor! < _kMinChromeMajor;
      } else {
        _webViewTooOld = false;
      }
    } catch (_) {
      // إن فشل الفحص نحاول العرض؛ الأخطاء ستظهر من الصفحة نفسها.
      _webViewTooOld = false;
    }
  }

  Future<void> _recheckWebViewAfterUpdate() async {
    setState(() {
      _checkingWebView = true;
      _statusText = 'جاري إعادة فحص المتصفح...';
    });
    await _detectWebView();
    if (!mounted) return;
    if (_webViewTooOld) {
      setState(() {
        _checkingWebView = false;
        _statusText = 'ما زال المتصفح قديماً — حدّث Chrome ثم ارجع';
      });
      return;
    }
    setState(() {
      _checkingWebView = false;
      _error = null;
      _statusText = 'تم التحديث — جاري فتح صفحة البطاقة...';
    });
    if (_topup == null) {
      await _createTopup();
    } else {
      setState(() {});
      _startPolling();
    }
  }

  int? _parseChromeMajor(String ua) {
    final match = RegExp(r'Chrome/(\d+)').firstMatch(ua);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  Future<void> _createTopup({bool keepLoadingUi = true}) async {
    if (keepLoadingUi) {
      setState(() {
        _creating = true;
        _error = null;
        _statusText = 'جاري تجهيز رابط الدفع...';
      });
    }
    try {
      final topup = await _service.createTopup(widget.requestedAmount);
      if (!mounted) return;
      if (topup.checkoutUrl.isEmpty) {
        throw StateError('تعذر الحصول على رابط الدفع');
      }
      setState(() {
        _topup = topup;
        _creating = false;
        if (!_webViewTooOld) {
          _statusText = 'جاري فتح صفحة البطاقة...';
        }
      });
      if (!_webViewTooOld) _startPolling();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _error = e
            .toString()
            .replaceAll('Exception: ', '')
            .replaceAll('Bad state: ', '')
            .replaceAll('[firebase_functions/', '')
            .split(']')
            .last
            .trim();
        _statusText = 'تعذر تجهيز الدفع';
      });
    }
  }

  void _startPolling() {
    if (_pollStarted) return;
    _pollStarted = true;
    _poll?.cancel();
    _poll = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _checkStatus(silent: true),
    );
    Future<void>.delayed(
      const Duration(seconds: 4),
      () => _checkStatus(silent: true),
    );
  }

  Future<void> _reloadCheckout() async {
    final topup = _topup;
    if (topup == null || _finished || _webViewTooOld) return;
    setState(() {
      _progress = 0;
      _statusText = 'جاري إعادة تحميل صفحة البطاقة...';
      _error = null;
    });
    await _web?.loadUrl(
      urlRequest: URLRequest(url: WebUri(topup.checkoutUrl)),
    );
  }

  Future<void> _openStore(String packageId) async {
    final market = Uri.parse('market://details?id=$packageId');
    final https = Uri.parse(
      'https://play.google.com/store/apps/details?id=$packageId',
    );
    if (await canLaunchUrl(market)) {
      await launchUrl(market, mode: LaunchMode.externalApplication);
      return;
    }
    await launchUrl(https, mode: LaunchMode.externalApplication);
  }

  Future<void> _checkStatus({bool silent = true}) async {
    final topup = _topup;
    if (!mounted || topup == null || _checking || _finished) return;
    setState(() {
      _checking = true;
      if (!silent) _manualRefresh = true;
    });
    try {
      final result = await _service.checkStatus(topup.id);
      final status = result['status']?.toString() ?? 'pending';
      if (!mounted) return;
      if (status == 'success') {
        _finished = true;
        _poll?.cancel();
        setState(() => _statusText = 'تم الدفع وإضافة الرصيد');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم شحن ${Formatters.money(topup.requestedAmount)} إلى محفظتك',
            ),
          ),
        );
        Navigator.pop(context, true);
        return;
      }
      if (status == 'failed') {
        _finished = true;
        _poll?.cancel();
        setState(() => _statusText = 'فشل الدفع');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فشل الدفع. لم يُخصم أي رصيد.')),
        );
        Navigator.pop(context, false);
        return;
      }
      if (!_creating && !_webViewTooOld) {
        setState(() => _statusText = 'أدخل بيانات البطاقة ثم انتظر التأكيد');
      }
    } catch (_) {
      if (!mounted) return;
      if (!silent) {
        setState(() => _statusText = 'تعذر التحقق الآن، حاول مجدداً');
      }
    } finally {
      if (mounted) {
        setState(() {
          _checking = false;
          _manualRefresh = false;
        });
      }
    }
  }

  List<UserScript> get _polyfills => [
        UserScript(
          source: r'''
(function () {
  try {
    if (typeof globalThis === 'undefined') {
      window.globalThis = window;
    }
    if (typeof global === 'undefined') {
      window.global = window;
    }
  } catch (e) {}
})();
''',
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
      ];

  InAppWebViewSettings get _settings => InAppWebViewSettings(
        javaScriptEnabled: true,
        domStorageEnabled: true,
        databaseEnabled: true,
        thirdPartyCookiesEnabled: true,
        supportMultipleWindows: false,
        javaScriptCanOpenWindowsAutomatically: true,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        useHybridComposition: true,
        transparentBackground: false,
        cacheEnabled: true,
        preferredContentMode: UserPreferredContentMode.MOBILE,
        builtInZoomControls: false,
        displayZoomControls: false,
        supportZoom: false,
        horizontalScrollBarEnabled: false,
        verticalScrollBarEnabled: true,
        allowsBackForwardNavigationGestures: true,
        iframeAllow: 'payment *; publickey-credentials-get *',
        iframeAllowFullscreen: true,
      );

  @override
  Widget build(BuildContext context) {
    final topup = _topup;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text('دفع البطاقة'),
        actions: [
          if (topup != null && !_webViewTooOld)
            IconButton(
              tooltip: 'إعادة تحميل',
              onPressed: _finished ? null : _reloadCheckout,
              icon: const Icon(Icons.refresh),
            ),
          IconButton(
            tooltip: 'تحديث الحالة',
            onPressed: _finished || _manualRefresh || topup == null
                ? null
                : () => _checkStatus(silent: false),
            icon: _manualRefresh
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
          ),
        ],
      ),
      body: Column(
        children: [
          _PaymentHeader(
            requestedAmount: widget.requestedAmount.toDouble(),
            chargedAmount: topup?.chargedAmount,
            statusText: _statusText,
            progress: (!_webViewTooOld &&
                    (_creating ||
                        _checkingWebView ||
                        (_progress > 0 && _progress < 100)))
                ? (_progress > 0 ? _progress / 100 : null)
                : null,
          ),
          Expanded(child: _buildBody(topup)),
        ],
      ),
    );
  }

  Widget _buildBody(WalletTopup? topup) {
    if (_checkingWebView) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_webViewTooOld) {
      return _OldWebViewPane(
        chromeMajor: _chromeMajor,
        onUpdateChrome: () => _openStore('com.android.chrome'),
        onUpdateWebView: () => _openStore('com.google.android.webview'),
        onRecheck: _recheckWebViewAfterUpdate,
      );
    }

    if (_error != null && topup == null) {
      return _ErrorPane(message: _error!, onRetry: _createTopup);
    }

    if (_creating || topup == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 14),
            Text(
              'جاري تجهيز الدفع...',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        InAppWebView(
          key: ValueKey(topup.id),
          initialUrlRequest: URLRequest(url: WebUri(topup.checkoutUrl)),
          initialSettings: _settings,
          initialUserScripts: UnmodifiableListView(_polyfills),
          onWebViewCreated: (controller) {
            _web = controller;
          },
          onProgressChanged: (controller, progress) {
            if (!mounted || _finished) return;
            setState(() => _progress = progress);
          },
          onLoadStart: (controller, url) {
            if (!mounted || _finished) return;
            setState(() => _statusText = 'جاري فتح صفحة البطاقة...');
          },
          onConsoleMessage: (controller, message) {
            final text = message.message;
            if (text.contains('globalThis is not defined') && mounted) {
              setState(() {
                _webViewTooOld = true;
                _statusText = 'متصفح الجهاز قديم ولا يعرض صفحة الدفع';
              });
            }
          },
          onLoadStop: (controller, url) async {
            if (!mounted || _finished) return;
            setState(() {
              _progress = 100;
              _statusText = 'أدخل بيانات البطاقة ثم انتظر التأكيد';
            });
          },
          onReceivedError: (controller, request, error) {
            if (request.isForMainFrame != true) return;
            if (!mounted || _finished) return;
            setState(() {
              _error =
                  'تعذر تحميل صفحة الدفع. تحقق من الإنترنت ثم أعد المحاولة.';
              _statusText = 'فشل تحميل الصفحة';
            });
          },
          onReceivedHttpError: (controller, request, response) {
            if (request.isForMainFrame != true) return;
            final code = response.statusCode ?? 0;
            if (code < 400 || !mounted || _finished) return;
            setState(() {
              _error =
                  'صفحة الدفع رجعت خطأ ($code). أعد المحاولة بمبلغ جديد.';
              _statusText = 'رابط الدفع غير صالح';
            });
          },
          shouldOverrideUrlLoading: (controller, action) async {
            return NavigationActionPolicy.ALLOW;
          },
        ),
        if (_error != null)
          ColoredBox(
            color: const Color(0xFFF5F7FB),
            child: _ErrorPane(
              message: _error!,
              onRetry: () {
                setState(() => _error = null);
                unawaited(_reloadCheckout());
              },
              secondaryLabel: 'رابط دفع جديد',
              onSecondary: () {
                setState(() {
                  _topup = null;
                  _pollStarted = false;
                  _poll?.cancel();
                  _error = null;
                });
                unawaited(_createTopup());
              },
            ),
          ),
      ],
    );
  }
}

class _OldWebViewPane extends StatelessWidget {
  const _OldWebViewPane({
    required this.chromeMajor,
    required this.onUpdateChrome,
    required this.onUpdateWebView,
    required this.onRecheck,
  });

  final int? chromeMajor;
  final VoidCallback onUpdateChrome;
  final VoidCallback onUpdateWebView;
  final VoidCallback onRecheck;

  @override
  Widget build(BuildContext context) {
    final versionText = chromeMajor == null ? 'غير معروف' : '$chromeMajor';
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.system_update_alt,
              size: 48,
              color: AppColors.primary,
            ),
            const SizedBox(height: 14),
            const Text(
              'لا يمكن عرض حقول البطاقة على هذا الجهاز حالياً',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'سبب المشكلة: متصفح WebView قديم (Chrome $versionText).\n'
              'صفحة الدفع من Qi تحتاج Chrome $_kMinChromeMajor أو أحدث.\n\n'
              'حدّث أحد التطبيقين من Google Play ثم اضغط «فحص مجدداً».',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, height: 1.45),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: onUpdateChrome,
              icon: const Icon(Icons.open_in_new),
              label: const Text('تحديث Google Chrome'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onUpdateWebView,
              icon: const Icon(Icons.open_in_new),
              label: const Text('تحديث Android System WebView'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onRecheck,
              icon: const Icon(Icons.refresh),
              label: const Text('فحص مجدداً بعد التحديث'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentHeader extends StatelessWidget {
  const _PaymentHeader({
    required this.requestedAmount,
    required this.chargedAmount,
    required this.statusText,
    required this.progress,
  });

  final double requestedAmount;
  final double? chargedAmount;
  final String statusText;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 0.5,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'للمحفظة: ${Formatters.money(requestedAmount)}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                if (chargedAmount != null)
                  Text(
                    'الإجمالي: ${Formatters.money(chargedAmount!)}',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              statusText,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
            if (progress != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorPane extends StatelessWidget {
  const _ErrorPane({
    required this.message,
    required this.onRetry,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String message;
  final VoidCallback onRetry;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.credit_card_off_outlined,
              size: 44,
              color: AppColors.danger,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
            if (secondaryLabel != null && onSecondary != null) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: onSecondary,
                child: Text(secondaryLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
