import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../models/bot_settings.dart';
import '../../models/catalog_models.dart';
import '../../services/card_bot_service.dart';
import '../../services/catalog_service.dart';

/// شاشة بسيطة: الفئات المربوطة + الحد الأدنى + كمية الشراء.
class AdminBotPage extends StatefulWidget {
  const AdminBotPage({super.key});

  @override
  State<AdminBotPage> createState() => _AdminBotPageState();
}

class _AdminBotPageState extends State<AdminBotPage> {
  final _bot = CardBotService();
  final _catalog = CatalogService();
  bool _settingsLoaded = false;
  bool _enabled = true;
  bool _autoRefill = true;
  bool _savingGlobal = false;

  void _ensureSettings(CardBotSettings s) {
    if (_settingsLoaded) return;
    _enabled = s.enabled;
    _autoRefill = s.autoRefill;
    _settingsLoaded = true;
  }

  Future<void> _saveGlobal(CardBotSettings current) async {
    setState(() => _savingGlobal = true);
    await _bot.saveSettings(
      CardBotSettings(
        enabled: _enabled,
        autoRefill: _autoRefill,
        useCloudMode: false,
        apiBaseUrl: current.apiBaseUrl,
        apiToken: current.apiToken,
        defaultMinStock: current.defaultMinStock,
        defaultRefillQty: current.defaultRefillQty,
      ),
    );
    if (!mounted) return;
    setState(() => _savingGlobal = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حفظ إعداد التعبئة التلقائية')),
    );
  }

  Future<void> _unlink(BotProductMap map, List<BotProductMap> maps) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('فك الربط'),
        content: Text('فك ربط «${map.productName.isEmpty ? map.productId : map.productName}»؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('فك الربط'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _bot.deleteMap(map.productId);
    final updated = maps.where((m) => m.productId != map.productId).toList();
    await _bot.syncToLocalBot(updated);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم فك الربط')),
    );
  }

  Future<void> _toggleMap(
    BotProductMap map,
    bool enabled,
    List<BotProductMap> maps,
  ) async {
    final next = map.copyWith(enabled: enabled);
    await _bot.saveMap(next);
    final updated =
        maps.map((m) => m.productId == map.productId ? next : m).toList();
    await _bot.syncToLocalBot(updated);
  }

  Future<void> _saveMapFields({
    required BotProductMap map,
    required int minStock,
    required int refillQty,
    required List<BotProductMap> maps,
    int? stock,
  }) async {
    final next = map.copyWith(minStock: minStock, refillQty: refillQty);
    await _bot.saveMap(next);
    final updated =
        maps.map((m) => m.productId == map.productId ? next : m).toList();
    await _bot.syncToLocalBot(updated);

    String extra = '';
    final settings = await _bot.getSettings();
    if (settings.enabled &&
        settings.autoRefill &&
        next.enabled &&
        stock != null &&
        stock <= minStock &&
        next.cardId.isNotEmpty &&
        next.catId.isNotEmpty) {
      final r = await _bot.requestBuy(
        productId: next.productId,
        cardId: next.cardId,
        catId: next.catId,
        quantity: next.refillQty,
        source: 'admin_save',
      );
      extra = r['ok'] == true
          ? ' — أُرسل طلب تعبئة (مخزون $stock ≤ $minStock)'
          : ' — تعبئة: ${r['message']}';
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'تم حفظ «${map.productName.isEmpty ? map.productId : map.productName}»$extra',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6F8),
      appBar: AppBar(
        title: const Text('تعبئة المخزون'),
      ),
      body: StreamBuilder<CardBotSettings>(
        stream: _bot.watchSettings(),
        builder: (context, settingsSnap) {
          final settings = settingsSnap.data ?? CardBotSettings.defaults();
          _ensureSettings(settings);

          return StreamBuilder<List<BotProductMap>>(
            stream: _bot.watchMaps(),
            builder: (context, mapsSnap) {
              final maps = mapsSnap.data ?? [];

              return StreamBuilder<List<Product>>(
                stream: _catalog.watchProducts(),
                builder: (context, productsSnap) {
                  final products = {
                    for (final p in productsSnap.data ?? <Product>[]) p.id: p,
                  };

                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _globalCard(settings),
                      const SizedBox(height: 12),
                      Text(
                        'الفئات المربوطة (${maps.length})',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'الربط يتم من البوت المحلي. هنا فقط الحد الأدنى وكمية الشراء.',
                        style: TextStyle(color: Colors.black54, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      if (mapsSnap.connectionState == ConnectionState.waiting &&
                          maps.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (maps.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Text(
                            'لا توجد فئات مربوطة بعد.\nاربطها من برنامج البوت المحلي (زر ربط المواد).',
                            textAlign: TextAlign.center,
                            style: TextStyle(height: 1.5),
                          ),
                        )
                      else
                        ...maps.map((m) {
                          final stock =
                              products[m.productId]?.stockCount ?? 0;
                          return _LinkedCard(
                            key: ValueKey('${m.productId}-${m.minStock}-${m.refillQty}-${m.enabled}'),
                            map: m,
                            stock: stock,
                            onToggle: (v) => _toggleMap(m, v, maps),
                            onSave: (minStock, refillQty) => _saveMapFields(
                              map: m,
                              minStock: minStock,
                              refillQty: refillQty,
                              maps: maps,
                              stock: stock,
                            ),
                            onUnlink: () => _unlink(m, maps),
                          );
                        }),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _globalCard(CardBotSettings settings) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'التحكم العام',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('تفعيل طلبات التعبئة'),
            subtitle: const Text('عند البيع وDNZ card يطلب من البوت المحلي'),
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('تعبئة تلقائية عند انخفاض المخزون'),
            value: _autoRefill,
            onChanged: (v) => setState(() => _autoRefill = v),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton(
              onPressed: _savingGlobal ? null : () => _saveGlobal(settings),
              child: Text(_savingGlobal ? 'جاري الحفظ...' : 'حفظ'),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkedCard extends StatefulWidget {
  const _LinkedCard({
    super.key,
    required this.map,
    required this.stock,
    required this.onToggle,
    required this.onSave,
    required this.onUnlink,
  });

  final BotProductMap map;
  final int stock;
  final ValueChanged<bool> onToggle;
  final Future<void> Function(int minStock, int refillQty) onSave;
  final VoidCallback onUnlink;

  @override
  State<_LinkedCard> createState() => _LinkedCardState();
}

class _LinkedCardState extends State<_LinkedCard> {
  late final TextEditingController _minStock;
  late final TextEditingController _refillQty;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _minStock = TextEditingController(text: '${widget.map.minStock}');
    _refillQty = TextEditingController(text: '${widget.map.refillQty}');
  }

  @override
  void dispose() {
    _minStock.dispose();
    _refillQty.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.onSave(
      int.tryParse(_minStock.text.trim()) ?? widget.map.minStock,
      int.tryParse(_refillQty.text.trim()) ?? widget.map.refillQty,
    );
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.map;
    final title = m.productName.isEmpty ? m.productId : m.productName;
    final low = widget.stock <= m.minStock;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: low ? AppColors.danger.withValues(alpha: 0.35) : const Color(0xFFE5E7EB),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (m.companyName.isNotEmpty) m.companyName,
                        if (m.baqatyCardName.isNotEmpty)
                          'Baqaty: ${m.baqatyCardName}',
                        'مخزون: ${widget.stock}',
                      ].join(' • '),
                      style: TextStyle(
                        color: low ? AppColors.danger : Colors.black54,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: m.enabled,
                onChanged: widget.onToggle,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _minStock,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'الحد الأدنى للمخزون',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _refillQty,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'كمية الشراء',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined, size: 18),
                label: Text(_saving ? 'جاري الحفظ...' : 'حفظ'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: widget.onUnlink,
                child: const Text(
                  'فك الربط',
                  style: TextStyle(color: AppColors.danger),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
