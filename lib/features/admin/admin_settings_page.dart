import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../models/app_settings.dart';
import '../../services/settings_service.dart';

class AdminSettingsPage extends StatefulWidget {
  const AdminSettingsPage({super.key});

  @override
  State<AdminSettingsPage> createState() => _AdminSettingsPageState();
}

class _AdminSettingsPageState extends State<AdminSettingsPage> {
  final _service = SettingsService();
  final _title = TextEditingController();
  final _phone = TextEditingController();
  final _primary = TextEditingController();
  final _accent = TextEditingController();
  final _minAndroidVersion = TextEditingController();
  final _playStoreUrl = TextEditingController();
  final _saleRate = TextEditingController();
  final _costRate = TextEditingController();
  bool _loaded = false;
  bool _savingRates = false;

  @override
  void dispose() {
    _title.dispose();
    _phone.dispose();
    _primary.dispose();
    _accent.dispose();
    _minAndroidVersion.dispose();
    _playStoreUrl.dispose();
    _saleRate.dispose();
    _costRate.dispose();
    super.dispose();
  }

  void _fillFromSettings(AppSettings s) {
    _title.text = s.storeTitle;
    _phone.text = s.supportPhone;
    _primary.text = s.primaryColor;
    _accent.text = s.accentColor;
    _minAndroidVersion.text = s.minAndroidVersion;
    _playStoreUrl.text = s.playStoreUrl.isNotEmpty
        ? s.playStoreUrl
        : AppSettings.defaults().playStoreUrl;
    _saleRate.text = s.gameKeySaleRate.toStringAsFixed(0);
    _costRate.text = s.gameKeyCostRate.toStringAsFixed(0);
  }

  Future<void> _save() async {
    await _service.save(
      AppSettings(
        primaryColor: _primary.text.trim(),
        accentColor: _accent.text.trim(),
        storeTitle: _title.text.trim(),
        supportPhone: _phone.text.trim(),
        minAndroidVersion: _minAndroidVersion.text.trim(),
        playStoreUrl: _playStoreUrl.text.trim(),
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حفظ الإعدادات')),
    );
  }

  Future<void> _saveRates() async {
    final sale = double.tryParse(_saleRate.text.trim());
    final cost = double.tryParse(_costRate.text.trim());
    if (sale == null || sale <= 0 || cost == null || cost <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل أسعار صرف صحيحة أكبر من صفر')),
      );
      return;
    }
    setState(() => _savingRates = true);
    try {
      await _service.saveGameKeyRates(saleRate: sale, costRate: cost);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ أسعار مفاتيح الألعاب')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر الحفظ: $e')),
      );
    } finally {
      if (mounted) setState(() => _savingRates = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إعدادات التطبيق')),
      body: StreamBuilder<AppSettings>(
        stream: _service.watch(),
        builder: (context, snapshot) {
          final s = snapshot.data ?? AppSettings.defaults();
          if (!_loaded) {
            _fillFromSettings(s);
            if (snapshot.hasData) _loaded = true;
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'عام',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'عنوان المتجر'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phone,
                decoration: const InputDecoration(labelText: 'هاتف الدعم'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _primary,
                decoration: const InputDecoration(labelText: 'اللون الأساسي'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _accent,
                decoration: const InputDecoration(labelText: 'لون الأزرار'),
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'أسعار صرف مفاتيح الألعاب',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'سعر البيع = دولار فايزر × سعر البيع. سعر التكلفة = دولار فايزر × سعر التكلفة.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.end,
                        children: [
                          SizedBox(
                            width: 180,
                            child: TextField(
                              controller: _saleRate,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'سعر البيع للدولار',
                                hintText: '1470',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 180,
                            child: TextField(
                              controller: _costRate,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'سعر التكلفة للدولار',
                                hintText: '1400',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          FilledButton(
                            onPressed: _savingRates ? null : _saveRates,
                            child: _savingRates
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('حفظ'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'إجبار تحديث التطبيق',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'عندما يكون إصدار المستخدم أقل من الرقم أدناه، تظهر له رسالة «يرجى التحديث» ويُحوَّل إلى Google Play.',
                        style: TextStyle(fontSize: 13, height: 1.4),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _minAndroidVersion,
                        decoration: const InputDecoration(
                          labelText: 'أقل إصدار Android مطلوب',
                          hintText: 'مثال: 1.0.4',
                          helperText:
                              'اتركه فارغاً لتعطيل إجبار التحديث',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _playStoreUrl,
                        decoration: const InputDecoration(
                          labelText: 'رابط Google Play',
                          hintText:
                              'https://play.google.com/store/apps/details?id=dnz.dnzteam.Kushk',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.url,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _save,
                child: const Text('حفظ الإعدادات'),
              ),
            ],
          );
        },
      ),
    );
  }
}
